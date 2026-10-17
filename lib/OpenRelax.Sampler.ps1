# Embedded Fotokapan sampler: CPU spike detection and records without
# administrator rights. Per-process CPU comes from the PDH 'Process' category,
# read in one call (~16 ms CPU for ~400 processes, protected ones such as
# MsMpEng included); process handles would need SYSTEM for those and cost
# ~300 ms per sample. Records keep the JSONL contract read by
# lib\OpenRelax.Trap.ps1. Windows PowerShell 5.1.

# Arguments are kept only when the user opted in (setting
# trapRecordCommandLines). Pattern matching cannot guarantee that arbitrary
# secrets are removed, which the setting says.
function Protect-CommandLine([string]$Cmd, [int]$Max = 300) {
    $record = Get-Variable -Name RecordCommandLines -Scope Script -ValueOnly -ErrorAction SilentlyContinue
    if (-not $record -or -not $Cmd) { return '' }
    # key=value / --key value / "Authorization: Bearer x" forms, URL user info,
    # query parameters (each up to the next &) and curl-style -u user:password.
    $c = $Cmd -replace '(?i)(://[^:/\s]+:)[^@\s]+@', '$1***@'
    $c = $c -replace '(?i)(\s(?:-u|--user)\s+[^:\s]+:)\S+', '$1***'
    $c = $c -replace '(?i)((?:token|api[_-]?key|key|secret|password|passwd|pwd|auth\w*|bearer|sig|signature|cookie|session|credential\w*)\S*?[=:\s]+)((?:bearer|basic|token)\s+)?("[^"]*"|''[^'']*''|[^\s&"]+)', '$1$2***'
    if ($c.Length -gt $Max) { $c = $c.Substring(0, $Max) + '...' }
    return $c
}

# Started by Task Scheduler: COM-handler tasks run under taskhostw.exe, program
# tasks are children of the svchost instance hosting "Schedule". Decided from
# the raw parent command line, which is then discarded unless recording is on.
function Test-ScheduledParent([string]$ParentName, [string]$ParentCmd) {
    if ($ParentName -eq 'taskhostw.exe') { return $true }
    return ($ParentName -eq 'svchost.exe' -and $ParentCmd -match '\s-s\s+Schedule\b')
}

# One PDH read of every process: raw CPU time (100 ns units) keyed by PID.
# Instance names ("chrome#3") shift as processes exit, so PIDs are the key.
function Read-ProcessCpuSample {
    $category = New-Object System.Diagnostics.PerformanceCounterCategory('Process')
    $data = $category.ReadCategory()
    $pids = @{}
    foreach ($i in $data['ID Process'].Values) { $pids[$i.InstanceName] = [int]$i.RawValue }
    $byPid = @{}; $ts = [long]0
    foreach ($i in $data['% Processor Time'].Values) {
        if ($i.InstanceName -eq '_Total') { $ts = [long]$i.Sample.TimeStamp100nSec; continue }
        if (-not $pids.ContainsKey($i.InstanceName)) { continue }
        $id = $pids[$i.InstanceName]
        if ($id -eq 0) { continue }
        $byPid[$id] = @{ Instance = [string]$i.InstanceName; Raw = [long]$i.RawValue }
        if ($ts -eq 0) { $ts = [long]$i.Sample.TimeStamp100nSec }
    }
    return @{ At = (Get-Date); Ts100 = $ts; ByPid = $byPid }
}

# Share of the whole machine (all cores = 100 %) per process between two
# samples. A process missing from the first sample started inside the window
# and is counted from zero; one missing from the second sample has exited.
function Measure-ProcessCpu($Before, $After, [int]$CpuCount) {
    $span = [double]($After.Ts100 - $Before.Ts100)
    if ($span -le 0) { return @() }
    $cores = [Math]::Max(1, $CpuCount)
    $rows = foreach ($id in @($After.ByPid.Keys)) {
        if ([int]$id -eq 0) { continue }
        $now = $After.ByPid[$id]
        $prev = [long]0
        if ($Before.ByPid.ContainsKey($id)) { $prev = [long]$Before.ByPid[$id].Raw }
        $pct = ([double]($now.Raw - $prev)) / $span / $cores * 100
        if ($pct -lt 0) { continue }
        @{ Pid = [int]$id; Instance = [string]$now.Instance; Pct = $pct }
    }
    return @($rows | Sort-Object -Property @{ Expression = { $_.Pct } } -Descending)
}

# Spike state machine (the rules of the former SYSTEM recorder): the first hot
# sample arms the burst snapshot, Needed consecutive hot samples start a spike,
# Needed consecutive samples below Threshold - 15 end it; a long spike is
# re-captured every 120 s.
function New-SpikeTracker([int]$Threshold, [int]$SustainSec, [int]$IntervalSec) {
    $needed = [Math]::Max(2, [int][Math]::Ceiling($SustainSec / [Math]::Max(1, $IntervalSec)))
    return @{ Threshold = $Threshold; Needed = $needed; Interval = $IntervalSec; Above = 0; Below = 0; InSpike = $false
        SpikeStart = $null; Peak = 0.0; LastCapture = [datetime]::MinValue; Spikes = 0 }
}

function Step-SpikeTracker($State, [double]$Cpu, [datetime]$Now) {
    if (-not $State.InSpike) {
        if ($Cpu -lt $State.Threshold) { $State.Above = 0; return '' }
        $State.Above++
        if ($State.Above -lt $State.Needed) { if ($State.Above -eq 1) { return 'arm' }; return '' }
        $State.InSpike = $true; $State.Below = 0; $State.Peak = $Cpu; $State.Spikes++
        $State.SpikeStart = $Now.AddSeconds(-$State.Above * $State.Interval)
        $State.LastCapture = $Now
        return 'start'
    }
    if ($Cpu -gt $State.Peak) { $State.Peak = $Cpu }
    if ($Cpu -lt ($State.Threshold - 15)) { $State.Below++ } else { $State.Below = 0 }
    if ($State.Below -ge $State.Needed) { $State.InSpike = $false; $State.Above = 0; return 'end' }
    if (($Now - $State.LastCapture).TotalSeconds -ge 120) { $State.LastCapture = $Now; return 'ongoing' }
    return ''
}

function Round-Share([double]$Value) { return [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero) }

# A start/ongoing record: the five largest processes (>= 1 %) with parent,
# scheduled-task flag and opt-in masked command lines; dpc/interrupt are the
# measured interrupt and DPC shares of the whole machine.
function New-SpikeRecord([string]$Kind, [datetime]$Start, [double]$WindowSec, [double]$Total, $Rows, $Processes, [double]$Dpc, [double]$Interrupt) {
    $attributed = 0.0
    foreach ($r in $Rows) { $attributed += [double]$r.Pct }
    $top = New-Object System.Collections.Generic.List[object]
    foreach ($r in $Rows) {
        if ($top.Count -ge 5) { break }
        if ([double]$r.Pct -lt 1) { continue }
        $info = $null
        if ($Processes -and $Processes.ContainsKey([int]$r.Pid)) { $info = $Processes[[int]$r.Pid] }
        $name = ([string]$r.Instance -replace '#\d+$', '') + '.exe'
        $parent = ''; $parentCmd = ''; $cmd = ''
        if ($info) {
            $name = [string]$info.Name
            $cmd = [string]$info.CommandLine
            if ($Processes.ContainsKey([int]$info.ParentPid)) {
                $parent = [string]$Processes[[int]$info.ParentPid].Name
                $parentCmd = [string]$Processes[[int]$info.ParentPid].CommandLine
            }
        }
        $top.Add([ordered]@{
            name = $name; pid = [int]$r.Pid; pct = (Round-Share $r.Pct); parent = $parent
            scheduled = [bool](Test-ScheduledParent $parent $parentCmd)
            cmd = (Protect-CommandLine $cmd 200); parentCmd = (Protect-CommandLine $parentCmd 200)
        })
    }
    return [ordered]@{
        t = $Start.ToString('s'); kind = $Kind; window = (Round-Share $WindowSec); total = (Round-Share $Total)
        attributed = (Round-Share $attributed); dpc = (Round-Share $Dpc); interrupt = (Round-Share $Interrupt)
        top = $top.ToArray(); defender = $null   # not @(): PS 5.1 fails on @(List[object]) inside [ordered]
    }
}

# Appends one record to spikes-yyyy-MM.jsonl (month of the record), UTF-8 without BOM.
function Add-TrapRecord([string]$Dir, $Record) {
    [void][IO.Directory]::CreateDirectory($Dir)
    $month = Get-Date
    try { $month = [datetime]::ParseExact([string]$Record.t, 's', [Globalization.CultureInfo]::InvariantCulture) } catch {}
    $path = Join-Path $Dir ('spikes-{0:yyyy-MM}.jsonl' -f $month)
    [IO.File]::AppendAllText($path, (ConvertTo-Json -InputObject $Record -Compress -Depth 5) + "`n", (New-Object System.Text.UTF8Encoding $false))
}

# durum.json, written to a temporary file and swapped in: readers never see a
# half-written heartbeat.
function Set-TrapHeartbeat([string]$Dir, $State) {
    [void][IO.Directory]::CreateDirectory($Dir)
    $path = Join-Path $Dir 'durum.json'
    $tmp = Join-Path $Dir ('durum-' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $State -Compress), (New-Object System.Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

# OpenRelax Fotokapan - CPU spike trap
#
# Watches total CPU and, when it stays above the threshold, records who was
# responsible: per-process CPU during the burst, parent process, command
# line, recently started processes and CPU time not attributed to any process
# (interrupts/DPCs, i.e. drivers). When Microsoft Defender is among the top
# consumers it notes whether an on-demand scan is running and otherwise takes
# a short Defender performance recording showing whose file activity it was
# scanning.
#
# It runs standalone as a SYSTEM scheduled task rather than inside the
# OpenRelax GUI: a WinForms timer on a starved UI thread cannot sample during
# the very spikes it is meant to catch, and only SYSTEM can read every process
# (protected ones such as MsMpEng included).
#
# Output (in $LogDir):
#   fotokapan-YYYY-MM.log    human-readable report
#   spikes-YYYY-MM.jsonl     one JSON record per line - the contract OpenRelax reads:
#                            monitor {t,kind,version,threshold,pid}
#                            start/ongoing {t,kind,window,total,attributed,top[],defender}
#                            end {t,kind,durationSec,peak}
#   durum.json               heartbeat, rewritten atomically every minute
#
#   fotokapan.ps1 -Install     copy to ProgramData, register and start the task (admin)
#   fotokapan.ps1 -Uninstall   remove the task (logs are kept)
#   fotokapan.ps1              run the monitor in the foreground

param(
    [int]$Threshold   = 85,
    [int]$SustainSec  = 4,
    [int]$DurationSec = 0,
    [string]$LogDir   = (Join-Path $env:ProgramData 'OpenRelax\Fotokapan'),
    [switch]$Install,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$FotokapanVersion = '2.1'
$TaskName   = 'OpenRelax Fotokapan'
$InstallDir = Join-Path $env:ProgramData 'OpenRelax\Fotokapan'

#region Install / uninstall
if ($Install -or $Uninstall) {
    $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Bu işlem için PowerShell''i yönetici olarak açın.'
        exit 1
    }
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    if ($Uninstall) {
        Write-Host "Fotokapan kaldırıldı. Loglar yerinde duruyor: $InstallDir"
        exit 0
    }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    # Logged command lines can contain tokens: keep the folder private to
    # SYSTEM, Administrators and the installing user.
    & icacls.exe $InstallDir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "$($env:USERDOMAIN)\$($env:USERNAME):(OI)(CI)F" | Out-Null
    Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $InstallDir 'fotokapan.ps1') -Force

    $ps        = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $action    = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f (Join-Path $InstallDir 'fotokapan.ps1'))
    $trigger   = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    # Task Scheduler defaults to priority 7 (below normal), which would starve
    # the monitor during exactly the spikes it has to record.
    $settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -Priority 3 `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
        -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description 'OpenRelax Fotokapan: CPU sıçramalarında sorumlu süreçleri kaydeder.' | Out-Null
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Fotokapan kuruldu ve çalışıyor. Loglar: $InstallDir"
    exit 0
}
#endregion

#region Output helpers
$Utf8Bom   = New-Object System.Text.UTF8Encoding $true
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
$CpuCount  = [Environment]::ProcessorCount

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -like 'fotokapan-*.log' -or $_.Name -like 'spikes-*.jsonl') -and $_.LastWriteTime -lt (Get-Date).AddDays(-180) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
# A recording interrupted by a reboot leaves its .etl behind; durum.txt is the pre-2.1 heartbeat.
Get-ChildItem -LiteralPath $LogDir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.etl' -or $_.Name -eq 'durum.txt' } |
    Remove-Item -Force -ErrorAction SilentlyContinue

function Write-Trap([string]$Text) {
    $path = Join-Path $LogDir ('fotokapan-{0:yyyy-MM}.log' -f (Get-Date))
    [System.IO.File]::AppendAllText($path, $Text + "`r`n", $Utf8Bom)
}

# One compact JSON object per line; 't' comes first so readers can skip old
# lines by comparing the ISO timestamp prefix without parsing them.
function Write-TrapRecord($Record) {
    $path = Join-Path $LogDir ('spikes-{0:yyyy-MM}.jsonl' -f (Get-Date))
    [System.IO.File]::AppendAllText($path, (ConvertTo-Json -InputObject $Record -Compress -Depth 5) + "`n", $Utf8NoBom)
}

# Written to a temp file and swapped in, so a reader never sees a half-written
# heartbeat. Best effort: if a reader holds the file at that instant the swap
# fails and the next beat (a minute later) simply tries again.
function Write-Heartbeat($State) {
    $dst = Join-Path $LogDir 'durum.json'
    $tmp = $dst + '.tmp'
    try {
        [System.IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $State -Compress), $Utf8NoBom)
        # [NullString]::Value, not $null: PowerShell turns $null into "" for a
        # string argument, and Replace rejects "" as a backup path.
        if (Test-Path -LiteralPath $dst) { [System.IO.File]::Replace($tmp, $dst, [NullString]::Value) }
        else { [System.IO.File]::Move($tmp, $dst) }
    } catch {}
}

function Protect-CommandLine([string]$Cmd, [int]$Max = 300) {
    if (-not $Cmd) { return '' }
    $c = $Cmd -replace '(?i)((?:token|api[_-]?key|secret|password|passwd|pwd|auth)\S*?[=:\s]+)("[^"]*"|\S+)', '$1***'
    if ($c.Length -gt $Max) { $c = $c.Substring(0, $Max) + '...' }
    return $c
}

# Cumulative CPU milliseconds per PID.
function Get-CpuTimes {
    $t = @{}
    foreach ($p in [System.Diagnostics.Process]::GetProcesses()) {
        try {
            if ($p.Id -ne 0) { $t[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds }
        } catch {
            # exited meanwhile, or not openable even as SYSTEM
        } finally {
            $p.Dispose()
        }
    }
    return $t
}
#endregion

#region Capture
# Returns 'scan' (an on-demand scan explains the load) or 'realtime'.
function Invoke-DefenderTrace {
    $lines = New-Object System.Collections.Generic.List[string]
    # On-demand scans (quick/full/custom) log 1000 on start and 1001/1002 on
    # end; a pending 1000 means the load is that scan, not real-time scanning,
    # so the rate-limited recording is saved for a spike that needs it.
    $scan = $null
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1000, 1001, 1002 } -MaxEvents 1
        if ($e.Id -eq 1000) {
            $what = ($e.Message -split "`n" | Where-Object { $_ -match 'Parametre|Kaynak|Parameters|Resources' } | ForEach-Object { $_.Trim() }) -join '; '
            $scan = '{0:HH:mm:ss} başladı; {1}' -f $e.TimeCreated, $what
        }
    } catch {}
    if ($scan) {
        $lines.Add("  Defender: elle/zamanlanmış tarama sürüyor ($scan). Yük bu taramadan; performans kaydı alınmadı.")
        Write-Trap ($lines -join "`r`n")
        return 'scan'
    }
    $lines.Add('  Defender: süren tarama yok, yük gerçek zamanlı taramadan.')
    # A recording costs ~30 s of WPR tracing plus report parsing: rate-limit it.
    if (((Get-Date) - $script:LastDefenderTrace).TotalHours -lt 6) {
        $lines.Add('  (Defender performans kaydı son 6 saat içinde alındı, tekrarlanmadı.)')
    } else {
        $script:LastDefenderTrace = Get-Date
        $etl = Join-Path $LogDir ('defender-{0:yyyyMMdd-HHmmss}.etl' -f (Get-Date))
        try {
            New-MpPerformanceRecording -RecordTo $etl -Seconds 30 | Out-Null
            $report = Get-MpPerformanceReport -Path $etl -TopProcesses 8 -TopFiles 10 -TopExtensions 8 | Out-String -Width 220
            $lines.Add('  Defender 30 sn performans kaydı (en çok tarama yaptıran süreçler / dosyalar):')
            $lines.Add($report.TrimEnd())
        } catch {
            $lines.Add("  Defender performans kaydı alınamadı: $($_.Exception.Message)")
        } finally {
            Remove-Item -LiteralPath $etl -Force -ErrorAction SilentlyContinue
        }
    }
    Write-Trap ($lines -join "`r`n")
    return 'realtime'
}

function Invoke-Capture([string]$Title, [string]$Kind, [switch]$Burst) {
    if ($Burst -and $script:BurstCount -gt 0) {
        # Measure the burst itself, from the snapshot taken at its first hot
        # sample: most spikes are over within ~10 s, so a window opened after
        # the trigger mostly sees the aftermath.
        $start   = $script:BurstAt
        $a       = $script:BurstSnap
        $b       = Get-CpuTimes
        $elapsed = $script:BurstClock.Elapsed.TotalMilliseconds
        $total   = $script:BurstSum / $script:BurstCount
        $window  = '{0:N0} sn sıçrama anı' -f ($elapsed / 1000)
    } else {
        $start = Get-Date
        $a = Get-CpuTimes
        [void]$script:Cpu.NextValue()
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        Start-Sleep -Milliseconds 3000
        $b = Get-CpuTimes
        $elapsed = $sw.Elapsed.TotalMilliseconds
        $total = [Math]::Min(100, $script:Cpu.NextValue())
        $window = '3 sn ölçüm'
    }

    $procs = @{}
    foreach ($w in Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name, CommandLine, CreationDate, WorkingSetSize) {
        $procs[[int]$w.ProcessId] = $w
    }

    $rows = foreach ($id in $b.Keys) {
        if ($a.ContainsKey($id)) { $prev = $a[$id] }
        elseif ($procs.ContainsKey($id) -and $procs[$id].CreationDate -ge $start.AddSeconds(-1)) { $prev = 0 }
        else { continue }   # unreadable in the first snapshot: its delta is unknown
        [pscustomobject]@{ Id = $id; Pct = ($b[$id] - $prev) / $elapsed / $CpuCount * 100 }
    }
    $attributed = ($rows | Measure-Object -Property Pct -Sum).Sum
    if (-not $attributed) { $attributed = 0 }
    $top = @($rows | Where-Object { $_.Pct -ge 1 } | Sort-Object Pct -Descending | Select-Object -First 8)

    $lines = New-Object System.Collections.Generic.List[string]
    $topRecords = New-Object System.Collections.Generic.List[object]
    $lines.Add('')
    $lines.Add(('==== {0:yyyy-MM-dd HH:mm:ss}  {1}' -f $start, $Title))
    $lines.Add(('  {3}: toplam %{0:N0} | süreçlere atanan %{1:N0} | atanmamış (kesme/DPC = sürücüler) %{2:N0}' -f $total, $attributed, [Math]::Max(0, $total - $attributed), $window))
    $lines.Add('   %CPU      PID  Süreç                  Bellek  Ebeveyn                   Komut satırı')
    foreach ($r in $top) {
        $w = $procs[$r.Id]
        $name = '?'; $short = '?'; $mem = 0; $parent = ''; $parentName = ''; $cmd = ''
        if ($w) {
            $name = $w.Name
            $short = $name
            if ($short.Length -gt 20) { $short = $short.Substring(0, 19) + '~' }
            $mem  = [int]($w.WorkingSetSize / 1MB)
            $cmd  = Protect-CommandLine $w.CommandLine
            $ppid = [int]$w.ParentProcessId
            if ($procs.ContainsKey($ppid)) { $parentName = $procs[$ppid].Name; $parent = '{0}({1})' -f $parentName, $ppid }
            else { $parent = "(kapanmış $ppid)" }
        }
        $lines.Add(('  {0,5:N1} {1,8}  {2,-20} {3,6}MB  {4,-24}  {5}' -f $r.Pct, $r.Id, $short, $mem, $parent, $cmd))
        if ($topRecords.Count -lt 5) {
            $topRecords.Add([ordered]@{
                name = $name; pid = $r.Id; pct = [Math]::Round($r.Pct, 1)
                parent = $parentName; cmd = (Protect-CommandLine $w.CommandLine 200)
            })
        }
    }

    # Spikes are often caused by short-lived spawns (agents, updaters, tasks).
    $recent = @($procs.Values |
        Where-Object { $_.CreationDate -and $_.CreationDate -gt $start.AddSeconds(-120) -and $_.ProcessId -ne $PID -and $_.Name -ne 'conhost.exe' } |
        Sort-Object CreationDate -Descending | Select-Object -First 12)
    if ($recent.Count) {
        $lines.Add('  Son 2 dakikada başlayan süreçler:')
        foreach ($w in $recent) {
            $ppid = [int]$w.ParentProcessId
            $pn = '?'
            if ($procs.ContainsKey($ppid)) { $pn = $procs[$ppid].Name }
            $lines.Add(('    {0:HH:mm:ss}  {1,-20} PID {2,-7} <- {3,-20} {4}' -f $w.CreationDate, $w.Name, $w.ProcessId, $pn, (Protect-CommandLine $w.CommandLine)))
        }
    }
    Write-Trap ($lines -join "`r`n")

    $defender = $null
    $busyDefender = $top | Select-Object -First 3 |
        Where-Object { $procs[$_.Id] -and $procs[$_.Id].Name -eq 'MsMpEng.exe' -and $_.Pct -ge 10 }
    if ($busyDefender) { $defender = Invoke-DefenderTrace }

    Write-TrapRecord ([ordered]@{
        t = $start.ToString('s'); kind = $Kind
        window = [Math]::Round($elapsed / 1000, 1); total = [Math]::Round($total, 1); attributed = [Math]::Round($attributed, 1)
        top = $topRecords.ToArray(); defender = $defender   # not @(): PS 5.1 fails on @(List[object]) inside [ordered]
    })
}
#endregion

#region Monitor loop
try {
    $script:Cpu = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
    [void]$script:Cpu.NextValue()
} catch {
    Write-Trap ('{0:yyyy-MM-dd HH:mm:ss}  ! CPU sayacı açılamadı: {1}' -f (Get-Date), $_.Exception.Message)
    exit 1
}
# Above normal on purpose: a below-normal sampler gets no CPU during a spike.
try { [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'AboveNormal' } catch {}

$script:LastDefenderTrace = [datetime]::MinValue
$script:BurstCount = 0
$interval = 2
$needed   = [Math]::Max(1, [int][Math]::Ceiling($SustainSec / $interval))
$above = 0; $below = 0; $inSpike = $false; $spikeStart = $null; $peak = 0; $spikes = 0
$lastCapture = [datetime]::MinValue; $lastBeat = [datetime]::MinValue
$startedAt = Get-Date
$stopAt = [datetime]::MaxValue
if ($DurationSec -gt 0) { $stopAt = (Get-Date).AddSeconds($DurationSec) }

Write-Trap ('---- {0:yyyy-MM-dd HH:mm:ss}  Fotokapan {1} başladı (eşik %{2}, en az {3} sn, PID {4}, {5})' -f $startedAt, $FotokapanVersion, $Threshold, ($needed * $interval), $PID, [Security.Principal.WindowsIdentity]::GetCurrent().Name)
# Marks a restart: readers close any episode that was still open before it.
Write-TrapRecord ([ordered]@{ t = $startedAt.ToString('s'); kind = 'monitor'; version = $FotokapanVersion; threshold = $Threshold; pid = $PID })

while ((Get-Date) -lt $stopAt) {
    try {
        Start-Sleep -Seconds $interval
        $v = [Math]::Min(100, $script:Cpu.NextValue())
        $now = Get-Date
        if (-not $inSpike) {
            if ($v -ge $Threshold) {
                if ($above -eq 0) {
                    $script:BurstSnap  = Get-CpuTimes
                    $script:BurstAt    = Get-Date
                    $script:BurstClock = [System.Diagnostics.Stopwatch]::StartNew()
                    $script:BurstSum   = 0; $script:BurstCount = 0
                } else {
                    $script:BurstSum += $v; $script:BurstCount++
                }
                $above++
            } else { $above = 0 }
            if ($above -ge $needed) {
                $inSpike = $true; $below = 0; $peak = $v; $spikes++
                $spikeStart = $now.AddSeconds(-$above * $interval)
                $lastCapture = $now
                Invoke-Capture ('CPU SIÇRAMASI: %{0:N0} (eşik %{1})' -f $v, $Threshold) -Kind 'start' -Burst
            }
        } else {
            if ($v -gt $peak) { $peak = $v }
            if ($v -lt ($Threshold - 15)) { $below++ } else { $below = 0 }
            if ($below -ge $needed) {
                $inSpike = $false; $above = 0
                $duration = ($now - $spikeStart).TotalSeconds
                Write-Trap ('  Bitti {0:HH:mm:ss}: süre {1:N0} sn, tepe %{2:N0}' -f $now, $duration, $peak)
                Write-TrapRecord ([ordered]@{ t = $now.ToString('s'); kind = 'end'; durationSec = [int]$duration; peak = [int][Math]::Round($peak) })
            } elseif (($now - $lastCapture).TotalSeconds -ge 120) {
                $lastCapture = $now
                Invoke-Capture ('SIÇRAMA SÜRÜYOR ({0:N0} sn): %{1:N0}' -f ($now - $spikeStart).TotalSeconds, $v) -Kind 'ongoing'
            }
        }
        if (($now - $lastBeat).TotalSeconds -ge 60) {
            $lastBeat = $now
            # privateMB lets a long run be checked for leaks without extra tools
            $self = [System.Diagnostics.Process]::GetCurrentProcess()
            $privateMB = [int]($self.PrivateMemorySize64 / 1MB)
            $self.Dispose()
            Write-Heartbeat ([ordered]@{
                t = $now.ToString('s'); cpu = [int]$v; spikes = $spikes; inSpike = $inSpike
                threshold = $Threshold; version = $FotokapanVersion; pid = $PID; started = $startedAt.ToString('s')
                privateMB = $privateMB
            })
        }
    } catch {
        Write-Trap ('{0:yyyy-MM-dd HH:mm:ss}  ! Hata: {1}' -f (Get-Date), $_.Exception.Message)
        Start-Sleep -Seconds 10
    }
}
Write-Trap ('---- {0:yyyy-MM-dd HH:mm:ss}  Fotokapan durdu ({1} sıçrama)' -f (Get-Date), $spikes)
#endregion

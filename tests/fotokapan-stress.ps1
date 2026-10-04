# Fotokapan stress test
#
# Runs a private fotokapan instance (own log folder, low threshold) through a
# storm of CPU bursts, then checks its JSONL contract, its own overhead, and
# that OpenRelax's reader survives damaged or half-written lines. The
# installed SYSTEM instance is not touched (pause it to keep these synthetic
# bursts out of its statistics).
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\fotokapan-stress.ps1
param(
    [string]$Work = (Join-Path $env:TEMP ('openrelax-trap-stress-' + [guid]::NewGuid().ToString('N').Substring(0, 8))),
    [int]$Bursts = 5,
    [int]$BurstSec = 6,
    [int]$GapSec = 10,
    [int]$Workers = 8,
    [int]$Threshold = 0   # 0 = baseline + 20 (an episode ends below threshold - 15, so it must sit above the idle load)
)
$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if (-not $Ok) { $script:failures++ }
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ('[{0}] {1}  {2}' -f $mark, $Name, $Detail)
}

$root = Split-Path -Parent $PSScriptRoot
$trap = Join-Path $root 'fotokapan.ps1'
if ($Threshold -le 0) {
    # On a machine in use the idle load can sit above a fixed low threshold,
    # which would merge the bursts into one long episode.
    $counter = New-Object System.Diagnostics.PerformanceCounter('Processor', '% Processor Time', '_Total')
    [void]$counter.NextValue()
    $base = 0.0
    1..6 | ForEach-Object { Start-Sleep -Seconds 1; $base = [Math]::Max($base, $counter.NextValue()) }
    $counter.Dispose()
    $Threshold = [int][Math]::Min(60, [Math]::Max(30, $base + 20))
    Write-Host ('Baseline CPU peak {0:N0}% -> threshold {1}%' -f $base, $Threshold)
}
$logDir = Join-Path $Work 'trap'
$duration = 10 + $Bursts * ($BurstSec + $GapSec) + 12
$monitor = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $trap),
    '-Threshold', $Threshold, '-SustainSec', '4', '-DurationSec', $duration, '-LogDir', ('"{0}"' -f $logDir)
Start-Sleep -Seconds 10

# --- burst storm, sampling the monitor's own cost ---
$samples = New-Object System.Collections.Generic.List[object]
$burner = '$m=''OPENRELAX-STRESS-BURST''; $e=(Get-Date).AddSeconds({0}); while((Get-Date) -lt $e){{}}' -f $BurstSec
for ($b = 0; $b -lt $Bursts; $b++) {
    1..$Workers | ForEach-Object { [void](Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $burner) }
    $until = (Get-Date).AddSeconds($BurstSec + $GapSec)
    while ((Get-Date) -lt $until) {
        try {
            $mp = Get-Process -Id $monitor.Id
            $samples.Add([pscustomobject]@{ T = Get-Date; Cpu = $mp.TotalProcessorTime.TotalSeconds; Handles = $mp.HandleCount; PrivMB = $mp.PrivateMemorySize64 / 1MB })
            $mp.Dispose()
        } catch {}
        Start-Sleep -Seconds 1
    }
}
$exited = $monitor.WaitForExit(($duration + 90) * 1000)
Check 'monitor ran its full duration and exited' $exited

# --- JSONL contract ---
$jsonl = Get-ChildItem -LiteralPath $logDir -Filter 'spikes-*.jsonl' | Select-Object -First 1
$lines = @(Get-Content -LiteralPath $jsonl.FullName -Encoding UTF8 | Where-Object { $_ })
$records = New-Object System.Collections.Generic.List[object]
$bad = 0
foreach ($l in $lines) { try { $records.Add(($l | ConvertFrom-Json)) } catch { $bad++ } }
Check 'every JSONL line parses' ($bad -eq 0) ('{0} lines, {1} bad' -f $lines.Count, $bad)
Check 'first record marks the monitor start' ($records.Count -gt 0 -and $records[0].kind -eq 'monitor' -and $records[0].version)
$starts = @($records | Where-Object { $_.kind -eq 'start' })
$ends = @($records | Where-Object { $_.kind -eq 'end' })
Check 'bursts were caught' ($starts.Count -ge ($Bursts - 1) -and $starts.Count -le ($Bursts + 2)) ('{0} starts for {1} bursts' -f $starts.Count, $Bursts)
Check 'every spike that ended has an end record' ($ends.Count -ge ($starts.Count - 1)) ('{0} ends' -f $ends.Count)
$marked = @($starts | Where-Object { @($_.top).Count -gt 0 -and [string]$_.top[0].cmd -match 'OPENRELAX-STRESS-BURST' })
Check 'the burst processes are named as top culprit' ($marked.Count -ge [Math]::Ceiling($starts.Count * 0.6)) ('{0}/{1}' -f $marked.Count, $starts.Count)
$attributed = @($starts | Where-Object { [double]$_.total -gt 0 -and ([double]$_.attributed / [double]$_.total) -ge 0.7 })
Check 'burst window attributes most of the CPU to processes' ($attributed.Count -ge [Math]::Ceiling($starts.Count * 0.6)) ('{0}/{1} with >= 70%' -f $attributed.Count, $starts.Count)
$errorLines = @(Get-Content -LiteralPath (Get-ChildItem -LiteralPath $logDir -Filter 'fotokapan-*.log').FullName -Encoding UTF8 | Where-Object { $_ -match '! (Hata|CPU)' })
Check 'no errors in the text log' ($errorLines.Count -eq 0) (($errorLines | Select-Object -First 2) -join ' | ')
$beat = Get-Content -LiteralPath (Join-Path $logDir 'durum.json') -Raw | ConvertFrom-Json
Check 'heartbeat written' ($beat.version -and $beat.t)
# Beats come every 60 s: over this run the file must have been rewritten at least once.
$age = ([datetime]::ParseExact([string]$beat.t, 's', $null) - [datetime]::ParseExact([string]$beat.started, 's', $null)).TotalSeconds
Check 'heartbeat refreshed during the run' ($age -ge 55) ('last beat {0:N0} s after start' -f $age)

# --- monitor overhead ---
if ($samples.Count -ge 2) {
    $first = $samples[0]; $last = $samples[$samples.Count - 1]
    $span = ($last.T - $first.T).TotalSeconds
    $corePct = ($last.Cpu - $first.Cpu) / $span * 100
    Check 'monitor overhead under 10% of one core during the storm' ($corePct -lt 10) ('{0:N1}% of one core over {1:N0} s' -f $corePct, $span)
    Check 'monitor handles stable' (($last.Handles - $first.Handles) -lt 100) ('{0} -> {1}' -f $first.Handles, $last.Handles)
    Check 'monitor memory stable' (($last.PrivMB - $first.PrivMB) -lt 50) ('{0:N0} -> {1:N0} MB' -f $first.PrivMB, $last.PrivMB)
}

# --- OpenRelax reader against damaged input ---
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'openrelax.ps1'), [ref]$null, [ref]$null)
$names = 'Read-SharedText', 'Read-TrapRecords', 'Get-TrapEpisodes', 'Get-TrapCulprit', 'Get-TrapCulprits', 'ConvertFrom-TrapTime'
$reader = ($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $names -contains $n.Name }, $true) |
    ForEach-Object { $_.Extent.Text }) -join "`n"
. ([scriptblock]::Create($reader))
$script:TrapCache = @{}
$clean = Get-TrapEpisodes (Read-TrapRecords -Dir $logDir)
$damaged = Join-Path $Work 'damaged'
New-Item -ItemType Directory -Path $damaged -Force | Out-Null
Copy-Item -LiteralPath $jsonl.FullName -Destination $damaged
$now = (Get-Date).ToString('s')
$junkLines = @('not json at all', ('{"t":"' + $now + '", broken}'), ('{"t":"' + $now + '","kind":"start","total":'), '', '{"t":"2026-')
[System.IO.File]::AppendAllText((Join-Path $damaged $jsonl.Name), (($junkLines -join "`n") + "`n"))
$script:TrapCache = @{}
$dirty = Get-TrapEpisodes (Read-TrapRecords -Dir $damaged)
Check 'reader skips damaged and half-written lines' ($dirty.Count -eq $clean.Count) ('{0} episodes clean, {1} with damage' -f $clean.Count, $dirty.Count)
$culprits = @(Get-TrapCulprits $clean)
Check 'culprit ranking puts the burst process first' ($culprits.Count -gt 0 -and $culprits[0].Name -eq 'powershell.exe') (($culprits | Select-Object -First 3 | ForEach-Object { '{0} x{1}' -f $_.Name, $_.Count }) -join ', ')

[System.IO.Directory]::Delete($Work, $true)
Write-Host ('Fotokapan stress: {0} failure(s)' -f $failures)
exit [int]($failures -gt 0)

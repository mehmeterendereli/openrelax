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
    [int]$Threshold = 0,   # 0 = baseline + 20 (an episode ends below threshold - 15, so it must sit above the idle load)
    [switch]$KeepArtifacts
)
$ErrorActionPreference = 'Stop'
foreach ($value in @($Bursts,$BurstSec,$Workers)) { if ($value -lt 1) { throw 'Burst/worker values must be positive.' } }
if ($Bursts -gt 10 -or $BurstSec -gt 30 -or $GapSec -lt 0 -or $GapSec -gt 60 -or $Workers -gt 64) { throw 'Stress run exceeds bounded limits.' }
$failures = 0
$script:Checks = [Collections.Generic.List[object]]::new()
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    $script:Checks.Add(@{ name = $Name; passed = $Ok; detail = $Detail })
    if (-not $Ok) { $script:failures++ }
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ('[{0}] {1}  {2}' -f $mark, $Name, $Detail)
}

. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
$burnerPids = [Collections.Generic.List[int]]::new()
$ownedProcesses = [Collections.Generic.List[object]]::new()
$monitor = $null
try {
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
$monitor = Start-OwnedTestProcess $Work ('-File "{0}" -Threshold {1} -SustainSec 4 -DurationSec {2} -LogDir "{3}"' -f $trap,$Threshold,$duration,$logDir)
$ownedProcesses.Add($monitor)
Start-Sleep -Seconds 10

# --- burst storm, sampling the monitor's own cost ---
$samples = New-Object System.Collections.Generic.List[object]
$burner = Join-Path $Work 'burner.ps1'
[IO.File]::WriteAllText($burner,'param([int]$Seconds) $end=(Get-Date).AddSeconds($Seconds); while((Get-Date) -lt $end) {}')
for ($b = 0; $b -lt $Bursts; $b++) {
    1..$Workers | ForEach-Object { $burn = Start-OwnedTestProcess $Work ('-File "{0}" -Seconds {1}' -f $burner,$BurstSec); $ownedProcesses.Add($burn); $burnerPids.Add($burn.Id) }
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
$deadline = (Get-Date).AddSeconds($duration + 20)
while (-not $monitor.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
if (-not $monitor.HasExited) { throw 'Owned monitor timed out.' }
$monitor.WaitForExit()
Check 'monitor ran its full duration and exited' ($monitor.ExitCode -eq 0 -and -not $monitor.TestStderr.Result)
if ($monitor.ExitCode -ne 0 -or $monitor.TestStderr.Result) { throw ('Monitor failed: ' + $monitor.TestStderr.Result) }

# --- JSONL contract ---
$jsonl = Get-ChildItem -LiteralPath $logDir -Filter 'spikes-*.jsonl' | Select-Object -First 1
if (-not $jsonl) { throw 'Monitor produced no JSONL.' }
$lines = @(Get-Content -LiteralPath $jsonl.FullName -Encoding UTF8 | Where-Object { $_ })
$records = New-Object System.Collections.Generic.List[object]
$bad = 0
foreach ($l in $lines) { try { $records.Add(($l | ConvertFrom-Json)) } catch { $bad++ } }
Check 'every JSONL line parses' ($bad -eq 0) ('{0} lines, {1} bad' -f $lines.Count, $bad)
Check 'first record marks the monitor start' ($records.Count -gt 0 -and $records[0].kind -eq 'monitor' -and $records[0].version)
$starts = @($records | Where-Object { $_.kind -eq 'start' })
$ends = @($records | Where-Object { $_.kind -eq 'end' })
Check 'bursts were caught' ($starts.Count -ge [Math]::Max(1,($Bursts - 1)) -and $starts.Count -le ($Bursts + 2)) ('{0} starts for {1} bursts' -f $starts.Count, $Bursts)
Check 'every spike that ended has an end record' ($ends.Count -ge ($starts.Count - 1)) ('{0} ends' -f $ends.Count)
$marked = @($starts | Where-Object { @($_.top).Count -gt 0 -and $burnerPids.Contains([int]$_.top[0].pid) })
Check 'the burst processes are named as top culprit' ($marked.Count -ge [Math]::Ceiling($starts.Count * 0.6)) ('{0}/{1}' -f $marked.Count, $starts.Count)
Check 'command arguments are absent from every process record' (@($records | ForEach-Object { @($_.top) + @($_.new) } | Where-Object { $_ -and $_.cmd }).Count -eq 0)
$attributed = @($starts | Where-Object { [double]$_.total -gt 0 -and ([double]$_.attributed / [double]$_.total) -ge 0.7 })
Check 'burst window attributes most of the CPU to processes' ($attributed.Count -ge [Math]::Ceiling($starts.Count * 0.6)) ('{0}/{1} with >= 70%' -f $attributed.Count, $starts.Count)
$errorLines = @(Get-Content -LiteralPath (Get-ChildItem -LiteralPath $logDir -Filter 'fotokapan-*.log').FullName -Encoding UTF8 | Where-Object { $_ -match '! (Hata|CPU)' })
Check 'no errors in the text log' ($errorLines.Count -eq 0) (($errorLines | Select-Object -First 2) -join ' | ')
$beat = Get-Content -LiteralPath (Join-Path $logDir 'durum.json') -Raw | ConvertFrom-Json
Check 'heartbeat written' ($beat.version -and $beat.t)
# Beats come every 60 s: over this run the file must have been rewritten at least once.
$age = ([datetime]::ParseExact([string]$beat.t, 's', $null) - [datetime]::ParseExact([string]$beat.started, 's', $null)).TotalSeconds
Check 'heartbeat refreshed during the run' ($duration -lt 60 -or $age -ge 55) ('last beat {0:N0} s after start' -f $age)

# --- monitor overhead ---
Check 'monitor cost has enough observations' ($samples.Count -ge 2)
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
Check 'culprit ranking accounts for all captured episodes' ($culprits.Count -gt 0 -and ($culprits | ForEach-Object { [int]$_['Count'] } | Measure-Object -Sum).Sum -eq $clean.Count)
# Several burners share the load: the unassigned aggregate can outweigh each
# individual burner. Never force a process diagnosis that the capture cannot prove.
$capturedNames = @($starts | ForEach-Object { @($_.top) | ForEach-Object { $_.name } })
Check 'culprit names come from capture or explicit unassigned CPU' (@($culprits | Where-Object { $_.Name -ne '*unattributed*' -and $_.Name -notin $capturedNames }).Count -eq 0)

} finally {
    # Only processes returned by this invocation are stopped; retained PIDs are
    # never used to discover/kill a possibly unrelated process after PID reuse.
    foreach ($process in $ownedProcesses) {
        try { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() } } finally { $process.Dispose() }
    }
    @{ failures = $failures; checks = @($script:Checks.ToArray()); completedUtc = [datetime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $Work 'stress-report.json') -Encoding UTF8
    if ($KeepArtifacts) { Write-Host "Artifacts: $Work" } else { Remove-TestWorkspace $workspace }
}
Write-Host ('Fotokapan stress: {0} failure(s)' -f $failures)
exit [int]($failures -gt 0)

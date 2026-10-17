# OpenRelax footprint: how much the app itself costs while it sits in the tray
# with the embedded Fotokapan recorder on. Starts the real app minimized on an
# owned fixture (TestMode: nothing is cleaned, no system integration), waits
# for the startup scan, then samples the app process every 10 s: CPU as a
# share of one core, private memory, handles and GDI objects.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\footprint.ps1 [-Minutes 10]
[CmdletBinding()]
param(
    [double]$Minutes = 10,
    [int]$WarmupSec = 30,
    [string]$Work = (Join-Path $env:TEMP ('openrelax-footprint-' + [guid]::NewGuid().ToString('N'))),
    [switch]$KeepArtifacts
)
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
if (-not ('OpenRelax.FootprintApi' -as [type])) {
    Add-Type -Namespace OpenRelax -Name FootprintApi -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetGuiResources(IntPtr hProcess, uint uiFlags);'
}
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
$runSec = [int]($Minutes * 60)
$app = Start-FixtureAppAsync $Work '-StartMinimized' @{ OPENRELAX_SMOKETEST = [string]($WarmupSec + $runSec + 30) }
$samples = New-Object System.Collections.Generic.List[object]
$failed = @()
try {
    Start-Sleep -Seconds $WarmupSec
    if ($app.HasExited) { throw ('The app exited during warm-up: ' + $app.TestStderr.Result) }
    $app.Refresh()
    $lastCpu = $app.TotalProcessorTime.TotalMilliseconds
    $clock = [Diagnostics.Stopwatch]::StartNew(); $lastWall = 0.0
    while ($clock.Elapsed.TotalSeconds -lt $runSec) {
        Start-Sleep -Seconds 10
        if ($app.HasExited) { throw 'The app exited during the measurement.' }
        $app.Refresh()
        $cpu = $app.TotalProcessorTime.TotalMilliseconds; $wall = $clock.Elapsed.TotalMilliseconds
        $samples.Add([ordered]@{
            sec = [Math]::Round($clock.Elapsed.TotalSeconds)
            cpuPct = [Math]::Round(100 * ($cpu - $lastCpu) / ($wall - $lastWall), 3)
            privateMB = [Math]::Round($app.PrivateMemorySize64 / 1MB, 1)
            workingSetMB = [Math]::Round($app.WorkingSet64 / 1MB, 1)
            handles = $app.HandleCount
            gdi = [int][OpenRelax.FootprintApi]::GetGuiResources($app.Handle, 0)
        })
        $lastCpu = $cpu; $lastWall = $wall
    }
} finally {
    if (-not $app.HasExited) { $app.Kill(); [void]$app.WaitForExit(10000) }
}
$trapRecords = @(Get-ChildItem -LiteralPath (Join-Path $Work 'trap') -Filter 'spikes-*.jsonl' -ErrorAction SilentlyContinue | ForEach-Object { Get-Content -LiteralPath $_.FullName } | Where-Object { $_ -match '"mode":"embedded"' })
$avgCpu = [Math]::Round((($samples | ForEach-Object { $_.cpuPct }) | Measure-Object -Average).Average, 3)
$maxCpu = [Math]::Round((($samples | ForEach-Object { $_.cpuPct }) | Measure-Object -Maximum).Maximum, 3)
# .NET memory is a saw-tooth: it climbs between garbage collections and drops
# at the next one, so "last minus first" measures GC timing. A leak raises the
# floor instead: compare the lowest sample of the second half with the lowest
# of the first half.
$half = [int][Math]::Floor($samples.Count / 2)
$firstFloor = (($samples | Select-Object -First ([Math]::Max(1, $half))) | ForEach-Object { $_.privateMB } | Measure-Object -Minimum).Minimum
$secondFloor = (($samples | Select-Object -Skip $half) | ForEach-Object { $_.privateMB } | Measure-Object -Minimum).Minimum
$growth = [Math]::Round($secondFloor - $firstFloor, 1)
$summary = [ordered]@{
    minutes = $Minutes; samples = $samples.Count; averageCpuPctOfOneCore = $avgCpu; maxCpuPctOfOneCore = $maxCpu
    privateMBFirst = $samples[0].privateMB; privateMBLast = $samples[$samples.Count - 1].privateMB; privateMBFloorGrowth = $growth
    workingSetMBLast = $samples[$samples.Count - 1].workingSetMB; handlesLast = $samples[$samples.Count - 1].handles; gdiLast = $samples[$samples.Count - 1].gdi
    embeddedRecorderStarted = ($trapRecords.Count -ge 1); cpuCount = [Environment]::ProcessorCount
    windows = [Environment]::OSVersion.VersionString; samplesDetail = $samples.ToArray()
}
if ($avgCpu -ge 1) { $failed += "average CPU $avgCpu % of one core (limit 1 %)" }
if ($growth -ge 20) { $failed += "the private-memory floor rose $growth MB (limit 20 MB)" }
if (-not $summary.embeddedRecorderStarted) { $failed += 'the embedded Fotokapan recorder did not start' }
ConvertTo-Json -InputObject $summary -Depth 4 | Set-Content -LiteralPath (Join-Path $Work 'footprint.json') -Encoding UTF8
Write-Host ''
Write-Host ('| Measure ({0} min in the tray, Fotokapan on, {1} logical CPUs) | Value |' -f $Minutes, [Environment]::ProcessorCount)
Write-Host '| --- | ---: |'
Write-Host ('| Average CPU (share of one core) | {0:N2} % |' -f $avgCpu)
Write-Host ('| Highest 10-second CPU | {0:N2} % |' -f $maxCpu)
Write-Host ('| Private memory | {0:N0} MB |' -f $summary.privateMBLast)
Write-Host ('| Memory floor growth (leak check) | {0:N1} MB |' -f $growth)
Write-Host ('| Handles / GDI objects | {0} / {1} |' -f $summary.handlesLast, $summary.gdiLast)
Write-Host ''
if ($failed.Count) { Write-Host ('Footprint: FAIL - ' + ($failed -join '; ')) } else { Write-Host 'Footprint: OK' }
if (-not $KeepArtifacts) { Remove-TestWorkspace $workspace } else { Write-Host "Artifacts: $Work" }
if ($failed.Count) { exit 1 }
exit 0

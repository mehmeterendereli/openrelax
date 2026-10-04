# OpenRelax release gate
#
# Runs every test in order and prints a summary. The installed Fotokapan task
# is paused while the tests create synthetic load (file storms, CPU bursts),
# so none of it lands in the real spike statistics, and resumed afterwards.
# Needs an elevated PowerShell (trap-install and the pause need it); the GUI
# test opens the app window for a few minutes.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 [-SkipGui]
param([switch]$SkipGui)
$ErrorActionPreference = 'Stop'
$suite = @('verify', 'unit', 'engine-stress', 'trap-install', 'fotokapan-stress')
if (-not $SkipGui) { $suite += 'gui-stress' }

$taskName = 'OpenRelax Fotokapan'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
$wasRunning = [bool]($task -and [string]$task.State -eq 'Running')
if ($wasRunning) { Stop-ScheduledTask -TaskName $taskName }
$results = New-Object System.Collections.Generic.List[object]
try {
    foreach ($name in $suite) {
        Write-Host ''
        Write-Host ('===== {0}' -f $name)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$name.ps1")
        $results.Add([pscustomobject]@{ Test = $name; Passed = ($LASTEXITCODE -eq 0); Seconds = [int]$sw.Elapsed.TotalSeconds })
    }
} finally {
    if ($wasRunning) { Start-ScheduledTask -TaskName $taskName }
}
Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { -not $_.Passed })
Write-Host ('Release gate: {0}/{1} passed' -f ($results.Count - $failed.Count), $results.Count)
exit [int]($failed.Count -gt 0)

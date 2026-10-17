# OpenRelax release gate
#
# Runs every suite in order and prints a summary. The GUI suites open the app
# window for a few minutes. tests\elevated-fotokapan.ps1 runs only from an
# elevated PowerShell on a disposable machine: it refuses a machine where the
# trap is already installed, and is reported as SKIPPED otherwise.
# tests\fotokapan-stress.ps1 creates real CPU bursts; pass -WithTrapStress to
# include it, after pausing an installed trap (Stop-ScheduledTask 'OpenRelax
# Fotokapan') so the synthetic spikes stay out of its statistics.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all.ps1 [-SkipGui] [-WithTrapStress]
param([switch]$SkipGui, [switch]$WithTrapStress)
$ErrorActionPreference = 'Stop'
$suite = @('verify', 'unit', 'engine-stress')
if (-not $SkipGui) { $suite += @('ui-smoke', 'exit-smoke', 'visual-smoke', 'gui-stress', 'footprint') }
if ($WithTrapStress) { $suite += 'fotokapan-stress' }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$trapInstalled = [bool](Test-Path -LiteralPath (Join-Path $env:ProgramData 'OpenRelax\Fotokapan'))

$results = New-Object System.Collections.Generic.List[object]
foreach ($name in $suite + 'elevated-fotokapan') {
    if ($name -eq 'elevated-fotokapan' -and (-not $elevated -or $trapInstalled)) {
        $why = 'not elevated'
        if ($elevated) { $why = 'a trap is installed here' }
        $results.Add([pscustomobject]@{ Test = $name; Result = "SKIPPED ($why)"; Seconds = 0 })
        continue
    }
    Write-Host ''
    Write-Host ('===== {0}' -f $name)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $extra = @(); if ($name -eq 'footprint') { $extra = @('-Minutes', '3') }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "$name.ps1") @extra
    $outcome = 'FAIL'
    if ($LASTEXITCODE -eq 0) { $outcome = 'PASS' }
    $results.Add([pscustomobject]@{ Test = $name; Result = $outcome; Seconds = [int]$sw.Elapsed.TotalSeconds })
}
Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' })
$ran = @($results | Where-Object { $_.Result -ne 'FAIL' -and $_.Result -ne 'PASS' }).Count
Write-Host ('Release gate: {0} passed, {1} failed, {2} skipped' -f @($results | Where-Object { $_.Result -eq 'PASS' }).Count, $failed.Count, $ran)
exit [int]($failed.Count -gt 0)

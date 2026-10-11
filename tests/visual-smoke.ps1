[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-visual-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$images = Join-Path $workspace.Path 'images'
$result = Start-FixtureApp $workspace.Path ('-VisualReportDir "' + $images + '"')
if ($result.ExitCode -ne 0 -or $result.Stderr) { throw ('Visual app failed: ' + $result.Stderr) }
$report = Get-Content -LiteralPath (Join-Path $images 'visual-report.json') -Raw | ConvertFrom-Json
if (@($report.errors).Count -or $report.screenshots -ne 8) { throw 'Renderer reported errors.' }
Add-Type -AssemblyName System.Drawing
foreach ($language in 'tr','en') {
    foreach ($page in 'dash','settings','disk','trap') {
        $path = Join-Path $images ($language + '-' + $page + '.png')
        $bitmap = [Drawing.Image]::FromFile($path)
        try { if ($bitmap.Width -lt 600 -or $bitmap.Height -lt 500) { throw 'Screenshot dimensions are incomplete.' } }
        finally { $bitmap.Dispose() }
    }
}
Write-Host "Visual smoke OK: 8 actual WinForms captures, no renderer errors. Review $images manually."

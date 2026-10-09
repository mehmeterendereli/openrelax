# Create a current-user desktop shortcut; no administrator rights required.
[CmdletBinding()]
param([string]$DesktopPath = [Environment]::GetFolderPath('DesktopDirectory'))
$ErrorActionPreference = 'Stop'
$app = Join-Path $PSScriptRoot 'openrelax.ps1'
$icon = Join-Path $PSScriptRoot 'docs\openrelax.ico'
foreach ($required in @($app,$icon,(Join-Path $PSScriptRoot 'lib\OpenRelax.Core.ps1'))) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Missing application file: ' + $required) }
}
if ($DesktopPath -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') { throw 'DesktopPath must be an existing absolute directory.' }
$DesktopPath = [IO.Path]::GetFullPath($DesktopPath)
if (-not (Test-Path -LiteralPath $DesktopPath -PathType Container)) { throw 'DesktopPath must be an existing absolute directory.' }
$path = Join-Path $DesktopPath 'OpenRelax.lnk'
$exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "' + $app + '"'
$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $path) {
    $existing = $shell.CreateShortcut($path)
    if ($existing.TargetPath -ine $exe -or $existing.Arguments -cne $arguments -or $existing.IconLocation -ine ($icon + ',0') -or $existing.WorkingDirectory -ine $PSScriptRoot -or $existing.WindowStyle -ne 7) { throw ('An existing shortcut was preserved: ' + $path) }
    Write-Host ('Shortcut already matches this checkout: ' + $path)
    return
}
$shortcut = $shell.CreateShortcut($path)
$shortcut.TargetPath = $exe
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = $icon + ',0'
$shortcut.Description = 'OpenRelax PC Care - source checkout'
$shortcut.WindowStyle = 7
$shortcut.Save()
$verified = $shell.CreateShortcut($path)
if ($verified.TargetPath -ine $exe -or $verified.Arguments -cne $arguments -or $verified.IconLocation -ine ($icon + ',0') -or $verified.WorkingDirectory -ine $PSScriptRoot -or $verified.WindowStyle -ne 7) { throw 'Shortcut verification failed.' }
Write-Host ('Desktop shortcut created and verified: ' + $path)

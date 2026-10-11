# Syntax-only preflight. Never imports or executes the Windows application.
[CmdletBinding()]
param([string]$Root = (Join-Path $PSScriptRoot '../..'))
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)

# Protect against the interpolation error that previously spent two runners.
$tokens = $null; $errors = $null
[void][Management.Automation.Language.Parser]::ParseInput('Write-Output "Unexpected owner on $Path: $owner"', [ref]$tokens, [ref]$errors)
if (@($errors).Count -eq 0) { throw 'Parser regression: invalid interpolation was accepted.' }
[void][Management.Automation.Language.Parser]::ParseInput('Write-Output "Unexpected owner on ${Path}: $owner"', [ref]$tokens, [ref]$errors)
if (@($errors).Count -ne 0) { throw 'Parser regression: valid interpolation was rejected.' }

$tracked = @(git -C $Root ls-files)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate tracked source.' }
$files = @($tracked | Where-Object { [IO.Path]::GetExtension($_) -ieq '.ps1' })
if ($files.Count -eq 0) { throw 'No tracked PowerShell source found.' }
$appAst = $null
foreach ($file in $files) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $Root $file), [ref]$tokens, [ref]$errors)
    if (@($errors).Count) { throw ('PowerShell syntax error in ' + $file + ': ' + ($errors -join '; ')) }
    if ($file -eq 'openrelax.ps1') { $appAst = $ast }
}
if ($null -eq $appAst) { throw 'Application source missing.' }
foreach ($name in 'ScanTaskCode','CleanTaskCode','RamTaskCode','DiskTaskCode') {
    $assignment = $appAst.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $name)}, $true)
    if ($null -eq $assignment) { throw ('Worker missing: ' + $name) }
    $literal = $assignment.Right.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]}, $true)
    if ($null -eq $literal) { throw ('Worker literal missing: ' + $name) }
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($literal.Value, [ref]$tokens, [ref]$errors)
    if (@($errors).Count) { throw ('Worker syntax error in ' + $name + ': ' + ($errors -join '; ')) }
}
Write-Host "Syntax preflight OK: $($files.Count) PowerShell files, four workers and interpolation regression."
Write-Host 'This is syntax-only; Windows PowerShell 5.1 runtime acceptance remains in the Windows jobs.'

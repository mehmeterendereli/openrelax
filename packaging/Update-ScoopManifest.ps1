# Points bucket\openrelax.json at a published release: version, url,
# extract_dir and the SHA256 of the release zip (from the downloaded asset).
# Run after the release workflow has attached OpenRelax-<version>.zip:
#
#   gh release download v2.4.0 -p 'OpenRelax-*.zip' -D $env:TEMP\or
#   .\packaging\Update-ScoopManifest.ps1 -Version 2.4.0 -ZipPath $env:TEMP\or\OpenRelax-2.4.0.zip
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Version, [Parameter(Mandatory)][string]$ZipPath)
$ErrorActionPreference = 'Stop'
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Version must look like 2.4.0.' }
if ((Split-Path -Leaf $ZipPath) -ne "OpenRelax-$Version.zip") { throw "Expected the asset OpenRelax-$Version.zip." }
$manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'bucket\openrelax.json'
$hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
# Replace only the four release values, so the file keeps its layout (Windows
# PowerShell's ConvertTo-Json would re-indent it). autoupdate's '$version'
# templates are left alone.
$text = [IO.File]::ReadAllText($manifestPath)
$replacements = [ordered]@{
    '("version"\s*:\s*")[^"]*(")'                                  = '${1}' + $Version + '${2}'
    '("url"\s*:\s*")https://[^"$]*/OpenRelax-[0-9.]+\.zip(")'     = '${1}' + "https://github.com/mehmeterendereli/openrelax/releases/download/v$Version/OpenRelax-$Version.zip" + '${2}'
    '("hash"\s*:\s*")[0-9a-fA-F]{64}(")'                          = '${1}' + $hash + '${2}'
    '("extract_dir"\s*:\s*")OpenRelax-[0-9.]+(")'                  = '${1}' + "OpenRelax-$Version" + '${2}'
}
foreach ($pattern in $replacements.Keys) {
    $regex = [regex]$pattern
    if (-not $regex.IsMatch($text)) { throw "Manifest field not found: $pattern" }
    $text = $regex.Replace($text, $replacements[$pattern], 1)
}
$check = $text | ConvertFrom-Json
if ($check.version -ne $Version -or $check.hash -ne $hash -or $check.extract_dir -ne "OpenRelax-$Version") { throw 'Manifest update did not take effect.' }
[IO.File]::WriteAllText($manifestPath, $text, (New-Object Text.UTF8Encoding $false))
Write-Host "bucket\openrelax.json -> $Version ($hash)"

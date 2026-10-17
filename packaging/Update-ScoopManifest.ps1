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
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifest.version = $Version
$manifest.url = "https://github.com/mehmeterendereli/openrelax/releases/download/v$Version/OpenRelax-$Version.zip"
$manifest.hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest.extract_dir = "OpenRelax-$Version"
[IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 6) + "`n", (New-Object Text.UTF8Encoding $false))
Write-Host "bucket\openrelax.json -> $Version ($($manifest.hash))"

# OpenRelax unit tests
#
# Fast tests for the pure functions: no GUI, no admin, no system changes (temp
# files only, under $env:TEMP). Functions are extracted from the scripts by
# AST, as the stress tests do. CI runs this on every push.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\unit.ps1
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'openrelax.ps1'
$trap = Join-Path $repo 'fotokapan.ps1'
$failures = 0; $passes = 0

function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { $script:passes++; Write-Host ('[PASS] {0}' -f $Name) }
    else { $script:failures++; Write-Host ('[FAIL] {0}  {1}' -f $Name, $Detail) }
}

# Returns the named functions as one script block; dot-source the result at
# script scope (". (Get-FunctionSource ...)") so the tests can call them.
function Get-FunctionSource([string]$File, [string[]]$Names) {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
    $found = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $Names -contains $n.Name }, $true))
    $missing = @($Names | Where-Object { @($found | ForEach-Object { $_.Name }) -notcontains $_ })
    if ($missing.Count) { throw "Missing in ${File}: $($missing -join ', ')" }
    return [scriptblock]::Create((($found | ForEach-Object { $_.Extent.Text }) -join "`n"))
}

function New-Start([string]$T, [string]$Name, [double]$Pct, [double]$Total = 98, [double]$Attributed = 90,
                   [string]$Defender = $null, [string]$Parent = '', [string]$ParentCmd = '') {
    return [pscustomobject]@{
        t = $T; kind = 'start'; total = $Total; attributed = $Attributed; defender = $Defender
        top = @([pscustomobject]@{ name = $Name; pct = $Pct; parent = $Parent; parentCmd = $ParentCmd })
    }
}
function New-End([string]$T, [int]$Sec = 10, [int]$Peak = 95) {
    return [pscustomobject]@{ t = $T; kind = 'end'; durationSec = $Sec; peak = $Peak }
}

# Localization stub: the key plus its format slots, so tests assert structure, not wording
function T([string]$Key) { return $Key + '|{0}|{1}|{2}|{3}' }

# --- Fotokapan episodes and culprits ---
. (Get-FunctionSource $app 'Get-TrapEpisodes', 'Get-TrapCulprit', 'Get-TrapCulprits', 'ConvertFrom-TrapTime')
$recs = @(
    [pscustomobject]@{ t = '2026-10-01T08:00:00'; kind = 'monitor' },
    (New-Start '2026-10-01T09:00:00' 'codex.exe' 40), (New-End '2026-10-01T09:00:12'),
    (New-Start '2026-10-01T10:00:00' 'MsMpEng.exe' 70),                                   # never ended: cut by the next start
    (New-Start '2026-10-01T11:00:00' 'chrome.exe' 20 -Attributed 30), (New-End '2026-10-01T11:00:09'),
    (New-Start '2026-10-01T12:00:00' 'java.exe' 50),
    [pscustomobject]@{ t = '2026-10-01T13:00:00'; kind = 'monitor' }                      # restart closes it
)
$eps = Get-TrapEpisodes $recs
Check 'four episodes' ($eps.Count -eq 4) "got $($eps.Count)"
Check 'ended episode keeps its duration' ($eps[0].Duration -eq 10 -and -not $eps[0].Cut)
Check 'episode without an end is cut by the next start' ($eps[1].Cut)
Check 'monitor restart cuts the open episode' ($eps[3].Cut)
Check 'unattributed CPU above the top process means drivers' ((Get-TrapCulprit $eps[2].Start).Name -eq '*drivers*')
$c = @(Get-TrapCulprits $eps)
# $_.Count reads the 'Count' key; Measure-Object -Property Count would read Hashtable.Count
Check 'culprit ranking counts every episode once' ((($c | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum -eq 4)

Write-Host ('Unit: {0} passed, {1} failed' -f $passes, $failures)
exit [int]($failures -gt 0)

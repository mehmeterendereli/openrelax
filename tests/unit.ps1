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

# --- engine walker ---
. (Get-FunctionSource $app 'Invoke-JunkWalk')
$w = Join-Path $env:TEMP ('or-unit-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$old = (Get-Date).AddDays(-2)
function New-OldFile([string]$P, [int]$Bytes = 100) {
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $P))
    [System.IO.File]::WriteAllBytes($P, (New-Object byte[] $Bytes))
    [System.IO.File]::SetLastWriteTime($P, $old)
}
New-OldFile "$w\tree\a\f1.tmp" 100
New-OldFile "$w\tree\a\b\f2.tmp" 50
New-OldFile "$w\tree\root.tmp" 10
New-OldFile "$w\tree\ro\readonly.tmp" 5
[System.IO.File]::SetAttributes("$w\tree\ro\readonly.tmp", 'ReadOnly')
[System.IO.File]::WriteAllText("$w\tree\young.tmp", 'new')
New-OldFile "$w\outside\keep.tmp" 7
New-Item -ItemType Junction -Path "$w\tree\link" -Target "$w\outside" | Out-Null
$cut = (Get-Date).AddHours(-24)
$m = Invoke-JunkWalk -Root "$w\tree" -Cutoff $cut -ByTopFolder
Check 'walker counts old files only, not through junctions' ($m.Count -eq 4 -and $m.Size -eq 165) ("$($m.Count) files / $($m.Size) bytes")
Check 'walker totals per first-level folder, root files under the empty key' ($m.Folders['a'] -eq 150 -and $m.Folders[''] -eq 10 -and $m.Folders['ro'] -eq 5)
$Sync = [hashtable]::Synchronized(@{ CleanDone = [long]0; CleanBytes = [long]0 })
$held = [System.IO.File]::Open("$w\tree\a\f1.tmp", 'Open', 'Read', 'None')
try { $rm = Invoke-JunkWalk -Root "$w\tree" -Cutoff $cut -Remove } finally { $held.Dispose() }
Check 'remove skips the held file and deletes read-only ones' ($rm.Count -eq 3 -and (Test-Path "$w\tree\a\f1.tmp") -and -not (Test-Path "$w\tree\ro")) ("$($rm.Count) removed")
Check 'remove drops emptied folders, keeps young files and the junction target' (-not (Test-Path "$w\tree\a\b") -and (Test-Path "$w\tree\young.tmp") -and (Test-Path "$w\outside\keep.tmp") -and (Test-Path "$w\tree\link"))
Check 'remove reports progress through $Sync' ($Sync.CleanDone -eq 3 -and $Sync.CleanBytes -eq $rm.Size -and $Sync.Beat) ("done $($Sync.CleanDone) bytes $($Sync.CleanBytes)")
Remove-Variable Sync
1..400 | ForEach-Object { [void][System.IO.Directory]::CreateDirectory("$w\dirs\d$_\e") }
$b = Invoke-JunkWalk -Root "$w\dirs" -BudgetMs 1
Check 'budget stops a folder-only tree (no files to count)' ($b.Partial -and $b.Dirs -lt 801) ("dirs $($b.Dirs) partial $($b.Partial)")
Check 'missing root is an empty result, not an error' ((Invoke-JunkWalk -Root "$w\nope").Count -eq 0)
[System.IO.Directory]::Delete("$w\tree\link")
[System.IO.Directory]::Delete($w, $true)

# --- categories and settings ---
. (Get-FunctionSource $app 'Get-JunkCategories', 'Get-DefaultSettings')
# No @(): the function returns its array with the unary comma, and @() would
# wrap that whole array as a single element
$cats = Get-JunkCategories
$dev = @($cats | Where-Object { $_.Key -eq 'devcache' })
Check 'devcache category exists and the recycle bin stays last' ($dev.Count -eq 1 -and $cats[$cats.Count - 1].Key -eq 'recycle')
$devPaths = @()
if ($dev.Count) { $devPaths = @($dev[0].Paths | Where-Object { $_ }) }
Check 'devcache lists only existing, user-level folders under the 24 h rule' ($dev.Count -eq 1 -and @($devPaths | Where-Object { -not (Test-Path -LiteralPath $_.Path) -or $_.Admin -or $_.MinAgeHours -ne 24 }).Count -eq 0)
Check 'devcache is off by default' ((Get-DefaultSettings).categories.devcache -eq $false)

# --- RAM trim selection ---
. (Get-FunctionSource $app 'Select-TrimTargets', 'Invoke-RamTrim')
$procs = @(
    @{ Id = 10; Name = 'TFTClient'; WorkingSet = 900MB },   # foreground
    @{ Id = 11; Name = 'java'; WorkingSet = 600MB },        # busy right now
    @{ Id = 12; Name = 'notepad'; WorkingSet = 10MB },      # too small to matter
    @{ Id = 13; Name = 'csrss'; WorkingSet = 80MB },        # critical
    @{ Id = 14; Name = 'powershell'; WorkingSet = 90MB },   # ourselves
    @{ Id = 15; Name = 'Teams'; WorkingSet = 400MB }        # idle and big: the one to trim
)
$before = @{ 10 = 1000.0; 11 = 1000.0; 12 = 0.0; 13 = 0.0; 14 = 0.0; 15 = 500.0 }
$after  = @{ 10 = 1300.0; 11 = 1600.0; 12 = 0.0; 13 = 0.0; 14 = 5.0; 15 = 500.5 }
$sel = @(Select-TrimTargets -Processes $procs -ForegroundPid 10 -CpuBefore $before -CpuAfter $after -IntervalMs 500 -CpuCount 12 -SelfPid 14)
Check 'trim only idle, non-critical, non-foreground, sizeable processes' ($sel.Count -eq 1 -and $sel[0] -eq 15) ($sel -join ',')
# Live processes, nothing trimmed: compile the app's Win32Helper and dry-run
$appAst = [System.Management.Automation.Language.Parser]::ParseFile($app, [ref]$null, [ref]$null)
$api = @($appAst.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$apiSource' }, $true))[0].Right.Expression.Value
if (-not ([System.Management.Automation.PSTypeName]'Win32Helper').Type) { Add-Type -TypeDefinition $api }
$dry = Invoke-RamTrim -DryRun
$fgPid = [int][Win32Helper]::GetForegroundProcessId()
Check 'dry run on live processes never targets the foreground app or itself' ($dry.Success -eq 0 -and @($dry.Targets) -notcontains $PID -and ($fgPid -eq 0 -or @($dry.Targets) -notcontains $fgPid) -and $dry.Skipped -gt 0) ("targets $(@($dry.Targets).Count), skipped $($dry.Skipped), fg $fgPid")

# --- recorder helpers (fotokapan.ps1) ---
. (Get-FunctionSource $trap 'Protect-CommandLine', 'ConvertTo-DefenderTop')
$masked = Protect-CommandLine 'tool.exe --token abc123 --api-key=XYZ password "a b c" --keep me'
Check 'command lines are masked, other arguments kept' ($masked -notmatch 'abc123|XYZ|a b c' -and $masked -match '--keep me') $masked
$fake = [pscustomobject]@{
    TopProcesses = @([pscustomobject]@{ ProcessPath = 'C:\x\codex.exe'; Count = 83; TotalDuration = [TimeSpan]::FromMilliseconds(937) })
    TopFiles = @(
        [pscustomobject]@{ Path = 'C:\u\.codex\sessions\a.jsonl'; Count = 8; TotalDuration = [TimeSpan]::FromMilliseconds(65) },
        [pscustomobject]@{ Path = 'C:\u\.codex\sessions\b.jsonl'; Count = 4; TotalDuration = [TimeSpan]::FromMilliseconds(30) },
        [pscustomobject]@{ Path = 'C:\t\x.tmp'; Count = 1; TotalDuration = [TimeSpan]::FromMilliseconds(12) })
}
$top = ConvertTo-DefenderTop $fake
Check 'Defender top process kept with count and ms' ($top.processes[0].path -eq 'C:\x\codex.exe' -and $top.processes[0].count -eq 83 -and $top.processes[0].ms -eq 937)
Check 'scanned files fold into their folders, heaviest first' ($top.folders[0].path -eq 'C:\u\.codex\sessions' -and $top.folders[0].count -eq 12 -and $top.folders[0].ms -eq 95 -and $top.folders.Count -eq 2)
$empty = ConvertTo-DefenderTop ([pscustomobject]@{ TopProcesses = $null; TopFiles = $null })
Check 'an empty report gives empty lists, not an error' (@($empty.processes).Count -eq 0 -and @($empty.folders).Count -eq 0)
Check 'Defender top serializes as the JSONL contract expects' ((ConvertTo-Json -InputObject $top -Compress -Depth 5) -match '^\{"processes":\[\{"path":"C:\\\\x\\\\codex.exe","count":83,"ms":937\}\],"folders":\[')

Write-Host ('Unit: {0} passed, {1} failed' -f $passes, $failures)
exit [int]($failures -gt 0)

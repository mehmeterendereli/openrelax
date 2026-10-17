[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-unit-' + [guid]::NewGuid().ToString('N'))),[switch]$KeepArtifacts)
# Fast tests for the pure engine and Fotokapan functions: no GUI, no admin and no
# system changes. Files are created and deleted only inside an owned workspace.
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
$script:Cases = [Collections.Generic.List[object]]::new()
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Throws([scriptblock]$Action) { $failed = $false; try { & $Action } catch { $failed = $true }; Assert-True $failed 'Expected refusal did not happen.' }
function Case([string]$Name,[scriptblock]$Action) {
    try { & $Action; $script:Cases.Add(@{ name = $Name; passed = $true }); Write-Host "PASS $Name" }
    catch { $script:Cases.Add(@{ name = $Name; passed = $false; error = $_.Exception.Message }); Write-Host "FAIL $Name`: $($_.Exception.Message)" }
}
. ([scriptblock]::Create((Get-TestFunctionSource @('Test-PathWithin','Assert-NoReparseAncestors','Assert-CleanupPath','Invoke-JunkWalk'))))

#region Engine walker
$tree = Join-Path $Work 'tree'; $outside = Join-Path $Work 'outside'; $link = Join-Path $tree 'link'
$old = (Get-Date).AddDays(-2)
function New-OldFile([string]$Path,[int]$Bytes = 100) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllBytes($Path,(New-Object byte[] $Bytes))
    [IO.File]::SetLastWriteTime($Path,$old)
}
New-OldFile (Join-Path $tree 'a\f1.tmp') 100
New-OldFile (Join-Path $tree 'a\b\f2.tmp') 50
New-OldFile (Join-Path $tree 'root.tmp') 10
New-OldFile (Join-Path $tree 'ro\readonly.tmp') 5
[IO.File]::SetAttributes((Join-Path $tree 'ro\readonly.tmp'),'ReadOnly')
[IO.File]::WriteAllText((Join-Path $tree 'young.tmp'),'new')
New-OldFile (Join-Path $outside 'keep.tmp') 7
New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
$cut = (Get-Date).AddHours(-24)

Case 'walker counts old files only, not through junctions' {
    $m = Invoke-JunkWalk -Root $tree -Cutoff $cut -ByTopFolder
    Assert-True ($m.Count -eq 4 -and $m.Size -eq 165) "Counted $($m.Count) files / $($m.Size) bytes."
    Assert-True ($m.Skipped -ge 1) 'The junction was not reported as skipped.'
}
Case 'walker totals per first-level folder, root files under the empty key' {
    $m = Invoke-JunkWalk -Root $tree -Cutoff $cut -ByTopFolder
    Assert-True ($m.Folders['a'] -eq 150 -and $m.Folders[''] -eq 10 -and $m.Folders['ro'] -eq 5) 'Per-folder totals are wrong.'
}
Case 'remove without ApprovedRoot is refused' {
    Assert-Throws { Invoke-JunkWalk -Root $tree -Cutoff $cut -Remove }
    Assert-True (Test-Path -LiteralPath (Join-Path $tree 'root.tmp')) 'A refused walk deleted a file.'
}
Case 'remove refuses a root outside its approved root' {
    Assert-Throws { Invoke-JunkWalk -Root $outside -ApprovedRoot $tree -Cutoff $cut -Remove }
    Assert-True (Test-Path -LiteralPath (Join-Path $outside 'keep.tmp')) 'A refused walk deleted a file.'
}
Case 'remove skips the held file, deletes read-only ones, keeps the junction target' {
    $Sync = [hashtable]::Synchronized(@{ CleanDone = [long]0; CleanBytes = [long]0; Beat = $null; Step = '' })
    $held = [IO.File]::Open((Join-Path $tree 'a\f1.tmp'),'Open','Read','None')
    try { $rm = Invoke-JunkWalk -Root $tree -ApprovedRoot $Work -Cutoff $cut -Remove } finally { $held.Dispose() }
    Assert-True ($rm.Count -eq 3) "Removed $($rm.Count) files."
    Assert-True ($rm.Skipped -ge 1) 'The held file was not reported as skipped.'
    Assert-True (Test-Path -LiteralPath (Join-Path $tree 'a\f1.tmp')) 'The held file was deleted.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $tree 'ro'))) 'The read-only file or its emptied folder remained.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $tree 'a\b'))) 'An emptied folder remained.'
    Assert-True (Test-Path -LiteralPath (Join-Path $tree 'young.tmp')) 'A young file was deleted.'
    Assert-True ((Test-Path -LiteralPath (Join-Path $outside 'keep.tmp')) -and (Test-Path -LiteralPath $link)) 'The junction or its target was touched.'
    Assert-True ($Sync.CleanDone -eq 3 -and $Sync.CleanBytes -eq $rm.Size -and $Sync.Beat) "Progress: $($Sync.CleanDone) files / $($Sync.CleanBytes) bytes."
}
Case 'remove keeps directories when asked' {
    New-OldFile (Join-Path $tree 'stage\x.tmp') 3
    $rm = Invoke-JunkWalk -Root $tree -ApprovedRoot $Work -Cutoff $cut -Remove -KeepDirectories
    Assert-True ($rm.Count -ge 1 -and (Test-Path -LiteralPath (Join-Path $tree 'stage'))) 'A staging directory was removed.'
}
Case 'budget stops a folder-only tree' {
    1..400 | ForEach-Object { [void][IO.Directory]::CreateDirectory((Join-Path $Work "dirs\d$_\e")) }
    $b = Invoke-JunkWalk -Root (Join-Path $Work 'dirs') -BudgetMs 1
    Assert-True ($b.Partial -and $b.Dirs -lt 801) "Walked $($b.Dirs) folders, partial $($b.Partial)."
}
Case 'missing root is an empty result' {
    $r = Invoke-JunkWalk -Root (Join-Path $Work 'nope')
    Assert-True ($r.Count -eq 0 -and -not $r.Partial) 'A missing root was not an empty result.'
}
Case 'read-only walk accepts the user profile root' {
    $r = Invoke-JunkWalk -Root $env:USERPROFILE -BudgetMs 200 -ByTopFolder
    Assert-True ($r.Dirs -ge 1) 'The profile walk did not start.'
}
if (Test-Path -LiteralPath $link) { [IO.Directory]::Delete($link) }
#endregion

$failed = @($script:Cases | Where-Object { -not $_.passed }).Count
Write-Host ("Unit: {0} cases, {1} failed." -f $script:Cases.Count, $failed)
if (-not $KeepArtifacts) { Remove-TestWorkspace $workspace }
if ($failed) { exit 1 }
exit 0

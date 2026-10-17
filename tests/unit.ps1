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

#region Categories
. ([scriptblock]::Create((Get-TestFunctionSource @('Get-JunkCategories'))))
Case 'devcache category exists before recycle' {
    $keys = @((Get-JunkCategories) | ForEach-Object { $_.Key })
    Assert-True ($keys -contains 'devcache') 'The devcache category is missing.'
    Assert-True ($keys[$keys.Count - 1] -eq 'recycle' -and $keys[$keys.Count - 2] -eq 'devcache') ('Unexpected order: ' + ($keys -join ','))
}
Case 'devcache paths are user-level, existing and under the 24 h rule' {
    $dev = @((Get-JunkCategories) | Where-Object { $_.Key -eq 'devcache' })[0]
    $local = [Environment]::GetFolderPath('LocalApplicationData')
    foreach ($target in $dev.Paths) {
        Assert-True (Test-Path -LiteralPath $target.Path) "Missing path listed: $($target.Path)"
        Assert-True (-not $target.Admin -and $target.MinAgeHours -eq 24 -and $target.ApprovedRoot -eq $target.Path) "Unsafe target: $($target.Path)"
        Assert-True ($target.Path.StartsWith($local + '\', [StringComparison]::OrdinalIgnoreCase)) "Target outside LocalAppData: $($target.Path)"
    }
}
#endregion

#region RAM trim selection
. ([scriptblock]::Create((Get-TestFunctionSource @('Select-TrimTargets','Invoke-RamTrim'))))
Case 'trim only idle, non-critical, non-foreground, sizeable processes' {
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
    Assert-True ($sel.Count -eq 1 -and $sel[0] -eq 15) ('Selected: ' + ($sel -join ','))
}
Case 'dry run on live processes never targets the foreground app or itself' {
    $appAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'openrelax.ps1'),[ref]$null,[ref]$null)
    $api = @($appAst.FindAll({ param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$apiSource' },$true))[0].Right.Expression.Value
    if (-not ([Management.Automation.PSTypeName]'Win32Helper').Type) { Add-Type -TypeDefinition $api }
    $dry = Invoke-RamTrim -DryRun
    $fgPid = [int][Win32Helper]::GetForegroundProcessId()
    Assert-True ($dry.Success -eq 0 -and @($dry.Targets) -notcontains $PID -and $dry.Skipped -gt 0) "Targets $(@($dry.Targets).Count), skipped $($dry.Skipped)."
    Assert-True ($fgPid -eq 0 -or @($dry.Targets) -notcontains $fgPid) 'The foreground process was targeted.'
}
#endregion

#region Worker sources
function Get-WorkerSource([string]$Name) {
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'openrelax.ps1'),[ref]$null,[ref]$null)
    $assignment = $ast.Find({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$script:' + $Name)},$true)
    return $assignment.Right.Find({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true).Value
}
Case 'clean worker exposes live progress and always clears it' {
    foreach ($fails in @($false,$true)) {
        $sync = [hashtable]::Synchronized(@{ Beat = [DateTime]::UtcNow; CleanResult = $null; Cleaning = $null; CleanDone = $null; CleanBytes = $null; Seen = $null; Log = [Collections.Queue]::new() })
        $ps = [powershell]::Create()
        try {
            $stub = 'function Invoke-Maintenance { param($Options) $Sync.Seen = @($Sync.Cleaning,$Sync.CleanDone,$Sync.CleanBytes); if ($Options.Fail) { throw "synthetic" }; return @{ Bytes = 5; Count = 1; Skipped = 0; Errors = @(); Status = "Success"; Ram = $null } }'
            [void]$ps.AddScript('Set-StrictMode -Version 2' + "`n" + $stub)
            [void]$ps.AddStatement().AddScript((Get-WorkerSource 'CleanTaskCode')).AddArgument($sync).AddArgument(@{ Fail = $fails })
            [void]$ps.Invoke()
        } finally { $ps.Dispose() }
        Assert-True ($null -ne $sync.Seen -and $sync.Seen[0] -eq $true -and $sync.Seen[1] -eq 0 -and $sync.Seen[2] -eq 0) 'Progress was not reset and switched on before maintenance.'
        Assert-True ($sync.Cleaning -eq $false -and $null -ne $sync.CleanResult) 'Progress stayed on after the worker ended.'
    }
}
Case 'disk walk reports root files and per-folder totals' {
    $disk = Join-Path $Work 'disk'
    New-OldFile (Join-Path $disk 'a\x.bin') 100; New-OldFile (Join-Path $disk 'a\deep\y.bin') 50
    New-OldFile (Join-Path $disk 'b\z.bin') 20; New-OldFile (Join-Path $disk 'root.bin') 10
    $sync = [hashtable]::Synchronized(@{ Beat = [DateTime]::UtcNow; Step = ''; DiskResult = $null; DiskProgress = $null })
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript('Set-StrictMode -Version 2' + "`n" + (Get-TestFunctionSource @('Test-PathWithin','Assert-NoReparseAncestors','Assert-CleanupPath','Invoke-JunkWalk')))
        [void]$ps.AddStatement().AddScript((Get-WorkerSource 'DiskTaskCode')).AddArgument($sync).AddArgument(@{ Target = $disk })
        [void]$ps.Invoke()
        Assert-True (-not $ps.HadErrors) ('Disk worker errors: ' + ($ps.Streams.Error -join '; '))
    } finally { $ps.Dispose() }
    $r = $sync.DiskResult
    $a = @($r.Rows | Where-Object { $_.Name -eq 'a' })
    $root = @($r.Rows | Where-Object { $_.RootFiles })
    Assert-True ($r.Status -eq 'Success' -and $r.Count -eq 3) "Status $($r.Status), count $($r.Count)."
    Assert-True ($a.Count -eq 1 -and $a[0].Size -eq 150 -and -not $a[0].Partial) 'Folder a was not totalled in one row.'
    Assert-True ($root.Count -eq 1 -and $root[0].Size -eq 10 -and $root[0].Name -eq '') 'Root files have no row of their own.'
    Assert-True ($r.Rows[0].Name -eq 'a') 'Rows are not sorted by size.'
}
#endregion

$failed = @($script:Cases | Where-Object { -not $_.passed }).Count
Write-Host ("Unit: {0} cases, {1} failed." -f $script:Cases.Count, $failed)
if (-not $KeepArtifacts) { Remove-TestWorkspace $workspace }
if ($failed) { exit 1 }
exit 0

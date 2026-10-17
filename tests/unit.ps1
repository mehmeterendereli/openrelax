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
    # The user may switch windows meanwhile: judge only a foreground app that
    # stayed the same around the whole sample.
    $fgBefore = [int][Win32Helper]::GetForegroundProcessId()
    $dry = Invoke-RamTrim -DryRun
    $fgAfter = [int][Win32Helper]::GetForegroundProcessId()
    Assert-True ($dry.Success -eq 0 -and @($dry.Targets) -notcontains $PID -and $dry.Skipped -gt 0) "Targets $(@($dry.Targets).Count), skipped $($dry.Skipped)."
    Assert-True ($fgBefore -ne $fgAfter -or $fgBefore -eq 0 -or @($dry.Targets) -notcontains $fgBefore) 'The foreground process was targeted.'
}
#endregion

#region Fotokapan recorder helpers
. ([scriptblock]::Create((Get-TestFunctionSource @('Assert-SingleLinkFile','ConvertTo-DefenderTop','Test-ScheduledParent','Move-LegacyTrapLogs'))))
$fakeReport = [pscustomobject]@{
    TopProcesses = @([pscustomobject]@{ ProcessPath = 'C:\x\codex.exe'; Count = 83; TotalDuration = [TimeSpan]::FromMilliseconds(937) })
    TopFiles = @(
        [pscustomobject]@{ Path = 'C:\u\.codex\sessions\a.jsonl'; Count = 8; TotalDuration = [TimeSpan]::FromMilliseconds(65) },
        [pscustomobject]@{ Path = 'C:\u\.codex\sessions\b.jsonl'; Count = 4; TotalDuration = [TimeSpan]::FromMilliseconds(30) },
        [pscustomobject]@{ Path = 'C:\t\x.tmp'; Count = 1; TotalDuration = [TimeSpan]::FromMilliseconds(12) })
}
Case 'Defender top process kept with count and ms' {
    $top = ConvertTo-DefenderTop $fakeReport
    Assert-True ($top.processes[0].path -eq 'C:\x\codex.exe' -and $top.processes[0].count -eq 83 -and $top.processes[0].ms -eq 937) 'Top process lost.'
}
Case 'scanned files fold into their folders, heaviest first' {
    $top = ConvertTo-DefenderTop $fakeReport
    Assert-True ($top.folders[0].path -eq 'C:\u\.codex\sessions' -and $top.folders[0].count -eq 12 -and $top.folders[0].ms -eq 95 -and $top.folders.Count -eq 2) 'Folders were not folded.'
}
Case 'an empty Defender report gives empty lists' {
    $empty = ConvertTo-DefenderTop ([pscustomobject]@{ TopProcesses = $null; TopFiles = $null })
    Assert-True (@($empty.processes).Count -eq 0 -and @($empty.folders).Count -eq 0) 'An empty report was not empty.'
}
Case 'rows without a path are skipped, archive members count for the archive folder' {
    $odd = ConvertTo-DefenderTop ([pscustomobject]@{
        TopProcesses = @([pscustomobject]@{ ProcessPath = ''; Count = 1; TotalDuration = [TimeSpan]::FromMilliseconds(6) })
        TopFiles = @(
            [pscustomobject]@{ Path = ''; Count = 3; TotalDuration = [TimeSpan]::FromMilliseconds(9) },
            [pscustomobject]@{ Path = 'C:\d\pack.zip->inner\x.js'; Count = 2; TotalDuration = [TimeSpan]::FromMilliseconds(5) },
            [pscustomobject]@{ Path = 'C:\y.txt'; Count = 1; TotalDuration = [TimeSpan]::FromMilliseconds(1) })
    })
    Assert-True (@($odd.processes).Count -eq 0 -and @($odd.folders).Count -eq 2 -and $odd.folders[0].path -eq 'C:\d' -and $odd.folders[0].count -eq 2 -and $odd.folders[1].path -eq 'C:\') 'Odd rows were mishandled.'
}
Case 'Defender top serializes as the JSONL contract expects' {
    $json = ConvertTo-Json -InputObject (ConvertTo-DefenderTop $fakeReport) -Compress -Depth 5
    Assert-True ($json -match '^\{"processes":\[\{"path":"C:\\\\x\\\\codex.exe","count":83,"ms":937\}\],"folders":\[') $json
}
Case 'scheduled-task parents are recognised from the raw parent command line' {
    Assert-True (Test-ScheduledParent 'taskhostw.exe' '') 'taskhostw was not recognised.'
    Assert-True (Test-ScheduledParent 'svchost.exe' 'C:\WINDOWS\system32\svchost.exe -k netsvcs -p -s Schedule') 'The Schedule service host was not recognised.'
    Assert-True (-not (Test-ScheduledParent 'svchost.exe' 'C:\WINDOWS\system32\svchost.exe -k netsvcs -p -s BITS')) 'Another service host was called scheduled.'
    Assert-True (-not (Test-ScheduledParent 'explorer.exe' '')) 'explorer was called scheduled.'
}
Case '2.2 logs in the trap root move into logs, root lines first' {
    $install = Join-Path $Work 'trap-install'; $logs = Join-Path $install 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    [IO.File]::WriteAllText((Join-Path $install 'spikes-2026-10.jsonl'),"{`"t`":`"r1`"}`n{`"t`":`"r2`"}`n")
    [IO.File]::WriteAllText((Join-Path $install 'spikes-2026-09.jsonl'),"{`"t`":`"s1`"}`n")
    [IO.File]::WriteAllText((Join-Path $install 'fotokapan-2026-10.log'),"old log`n")
    [IO.File]::WriteAllText((Join-Path $install 'durum.json'),'{"t":"old"}')
    [IO.File]::WriteAllText((Join-Path $install 'fotokapan.ps1'),'# 2.2.1')
    [IO.File]::WriteAllText((Join-Path $install 'notes.txt'),'unrelated')
    [IO.File]::WriteAllText((Join-Path $logs 'spikes-2026-10.jsonl'),"{`"t`":`"n1`"}`n")
    [IO.File]::WriteAllText((Join-Path $logs 'durum.json'),'{"t":"new"}')
    Move-LegacyTrapLogs -InstallDir $install -LogsDir $logs
    $merged = @([IO.File]::ReadAllLines((Join-Path $logs 'spikes-2026-10.jsonl')) | Where-Object { $_ })
    Assert-True ($merged.Count -eq 3 -and $merged[0] -match 'r1' -and $merged[1] -match 'r2' -and $merged[2] -match 'n1') ('Merged: ' + ($merged -join '|'))
    Assert-True (Test-Path -LiteralPath (Join-Path $logs 'spikes-2026-09.jsonl')) 'A month only in the root was not moved.'
    Assert-True (Test-Path -LiteralPath (Join-Path $logs 'fotokapan-2026-10.log')) 'The text log was not moved.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $logs 'durum.json')) -match 'new') 'A stale heartbeat replaced the current one.'
    foreach ($name in 'spikes-2026-10.jsonl','spikes-2026-09.jsonl','fotokapan-2026-10.log','durum.json','fotokapan.ps1') {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $install $name))) "Legacy root file remained: $name"
    }
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'notes.txt')) 'An unrelated file was touched.'
    Move-LegacyTrapLogs -InstallDir $install -LogsDir $logs
    Assert-True (@([IO.File]::ReadAllLines((Join-Path $logs 'spikes-2026-10.jsonl')) | Where-Object { $_ }).Count -eq 3) 'A second run duplicated records.'
}
#endregion

#region Fotokapan diagnosis, report and notifications
# Localization stub: the key plus its format slots, so tests assert structure, not wording.
$StubSlots = @{ reportGenerated = 2; reportStatus = 2; trapSec = 1 }
function T([string]$Key) {
    $n = 4
    if ($StubSlots.ContainsKey($Key)) { $n = $StubSlots[$Key] }
    return $Key + (-join (0..($n - 1) | ForEach-Object { '|{' + $_ + '}' }))
}
function New-Start([string]$T,[string]$Name,[double]$Pct,[double]$Total = 98,[double]$Attributed = 90,$Defender = $null,[string]$Parent = '',[bool]$Scheduled = $false) {
    return [pscustomobject]@{ t = $T; kind = 'start'; total = $Total; attributed = $Attributed; defender = $Defender
        top = @([pscustomobject]@{ name = $Name; pct = $Pct; parent = $Parent; scheduled = $Scheduled; cmd = ''; parentCmd = '' }) }
}
function New-End([string]$T,[int]$Sec = 10,[int]$Peak = 95) { return [pscustomobject]@{ t = $T; kind = 'end'; durationSec = $Sec; peak = $Peak } }
. ([scriptblock]::Create((Get-TestFunctionSource @('Get-TrapEpisodes','Get-TrapCulprit','Get-TrapCulprits','ConvertFrom-TrapTime','Get-TrapCulpritText','Get-TrapCategory','Test-TrapScheduled','Get-TrapDiagnosis','Format-TrapFinding','Get-TrapHourHistogram','Format-TrapReport','Save-TrapReport','Get-TrapNotification'))))

Case 'episodes pair starts and ends, restarts and new starts cut open ones' {
    $recs = @(
        [pscustomobject]@{ t = '2026-10-01T08:00:00'; kind = 'monitor' },
        (New-Start '2026-10-01T09:00:00' 'codex.exe' 40), (New-End '2026-10-01T09:00:12'),
        (New-Start '2026-10-01T10:00:00' 'MsMpEng.exe' 70),
        (New-Start '2026-10-01T11:00:00' 'chrome.exe' 20 -Attributed 30), (New-End '2026-10-01T11:00:09'),
        (New-Start '2026-10-01T12:00:00' 'java.exe' 50),
        [pscustomobject]@{ t = '2026-10-01T13:00:00'; kind = 'monitor' })
    $eps = Get-TrapEpisodes $recs
    Assert-True ($eps.Count -eq 4 -and $eps[0].Duration -eq 10 -and -not $eps[0].Cut -and $eps[1].Cut -and $eps[3].Cut) 'Episodes were paired wrongly.'
    Assert-True ((Get-TrapCulprit $eps[2].Start).Name -eq '*unattributed*') 'Residual CPU was not reported as unattributed.'
    $c = @(Get-TrapCulprits $eps)
    Assert-True ((($c | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum -eq 4) 'Culprit ranking miscounted.'
}
Case 'categories by process name' {
    Assert-True ((Get-TrapCategory 'MsMpEng.exe') -eq 'defender' -and (Get-TrapCategory 'TFTClient-Win64-Shipping.exe') -eq 'game' -and (Get-TrapCategory 'codex.exe') -eq 'devtools' -and (Get-TrapCategory 'python.exe') -eq 'devtools') 'Known names were miscategorised.'
    Assert-True ((Get-TrapCategory 'msedge.exe') -eq 'browser' -and (Get-TrapCategory 'TiWorker.exe') -eq 'windows' -and (Get-TrapCategory 'foo.exe') -eq 'other') 'Known names were miscategorised.'
}
Case 'scheduled flag and 2.2 parent command lines are both recognised' {
    Assert-True (Test-TrapScheduled ([pscustomobject]@{ name = 'x.exe'; scheduled = $true })) 'The recorded flag was ignored.'
    Assert-True (-not (Test-TrapScheduled ([pscustomobject]@{ name = 'x.exe'; parent = 'taskhostw.exe'; scheduled = $false }))) 'The recorded flag was overridden.'
    Assert-True (Test-TrapScheduled ([pscustomobject]@{ parent = 'svchost.exe'; parentCmd = 'C:\WINDOWS\system32\svchost.exe -k netsvcs -p -s Schedule' })) 'A 2.2 record was not recognised.'
    Assert-True (Test-TrapScheduled ([pscustomobject]@{ parent = 'taskhostw.exe' })) 'A record without parentCmd failed.'
    Assert-True (-not (Test-TrapScheduled ([pscustomobject]@{ parent = 'explorer.exe' })) -and -not (Test-TrapScheduled $null)) 'A non-task parent was called scheduled.'
}
$diagEpisodes = New-Object System.Collections.Generic.List[object]
$defTop = [pscustomobject]@{ processes = @(); folders = @([pscustomobject]@{ path = 'C:\u\.codex\sessions'; count = 12; ms = 95 }) }
foreach ($i in 0..4) {
    $s = New-Start ('2026-10-01T0{0}:00:00' -f $i) 'MsMpEng.exe' 70 -Defender 'realtime'
    if ($i -eq 4) { $s | Add-Member -NotePropertyName defenderTop -NotePropertyValue $defTop }
    $diagEpisodes.Add(@{ Start = $s; Defender = 'realtime'; Duration = 10; Peak = 95; Cut = $false })
}
foreach ($i in 5..7) { $diagEpisodes.Add(@{ Start = (New-Start ('2026-10-01T{0:D2}:00:00' -f ($i + 9)) 'chrome.exe' 20 -Attributed 30); Defender = $null; Duration = 10; Peak = 95; Cut = $false }) }
$diagEpisodes.Add(@{ Start = (New-Start '2026-10-01T15:00:00' 'codex.exe' 50 -Parent 'taskhostw.exe' -Scheduled $true); Defender = $null; Duration = $null; Peak = $null; Cut = $true })
$diagEpisodes.Add(@{ Start = (New-Start '2026-10-01T15:30:00' 'codex.exe' 40); Defender = $null; Duration = 10; Peak = 95; Cut = $false })
Case 'findings sorted by count with shares; unattributed CPU is its own category' {
    $d = @(Get-TrapDiagnosis $diagEpisodes)
    Assert-True ($d.Count -ge 4 -and $d[0].Category -eq 'defender' -and $d[0].Count -eq 5 -and $d[0].Share -eq 50) (($d | ForEach-Object { '{0}:{1}' -f $_.Category, $_.Count }) -join ' ')
    Assert-True ($d[1].Category -eq 'unattributed' -and $d[1].Key -eq 'diag_unattributed' -and $d[1].Count -eq 3) 'Unattributed CPU was not reported honestly.'
    Assert-True (@($d | Where-Object { $_.Category -eq 'drivers' }).Count -eq 0) 'A drivers category was still produced.'
}
Case 'real-time Defender finding names the most-scanned folder' {
    $d = @(Get-TrapDiagnosis $diagEpisodes)
    Assert-True ($d[0].Key -eq 'diag_defender_rt' -and $d[0].Detail -eq 'C:\u\.codex\sessions') 'The scanned folder was lost.'
    Assert-True ((Format-TrapFinding $d[0]) -eq 'diag_defender_rt|50|MsMpEng.exe|C:\u\.codex\sessions|5') (Format-TrapFinding $d[0])
}
Case 'scheduled finding counts task-started spikes' {
    $d = @(Get-TrapDiagnosis $diagEpisodes)
    Assert-True (@($d | Where-Object { $_.Category -eq 'scheduled' -and $_.Count -eq 1 -and $_.Top -eq 'codex.exe' }).Count -eq 1) 'Scheduled spikes were miscounted.'
}
Case 'scan-dominated Defender finding advises moving scans' {
    $scanEp = New-Object System.Collections.Generic.List[object]
    $scanEp.Add(@{ Start = (New-Start '2026-10-02T10:00:00' 'MsMpEng.exe' 80 -Defender 'scan'); Defender = 'scan' })
    Assert-True ((@(Get-TrapDiagnosis $scanEp))[0].Key -eq 'diag_defender_scan') 'Scan advice missing.'
}
Case '2.2.1 records with parentCmd and *drivers* still diagnose' {
    $legacy = [pscustomobject]@{ t = '2026-10-03T10:00:00'; kind = 'start'; total = 90; attributed = 10; defender = $null
        top = @([pscustomobject]@{ name = 'python.exe'; pid = 1; pct = 8; parent = 'svchost.exe'; cmd = ''; parentCmd = 'svchost.exe -k netsvcs -s Schedule' }) }
    $legacyDrivers = [pscustomobject]@{ t = '2026-10-03T11:00:00'; kind = 'start'; total = 90; attributed = 85; defender = $null
        top = @([pscustomobject]@{ name = '*drivers*'; pid = 0; pct = 60; parent = ''; cmd = '' }) }
    $eps = New-Object System.Collections.Generic.List[object]
    $eps.Add(@{ Start = $legacy; Defender = $null }); $eps.Add(@{ Start = $legacyDrivers; Defender = $null })
    $d = @(Get-TrapDiagnosis $eps)
    Assert-True (@($d | Where-Object { $_.Category -eq 'unattributed' }).Count -eq 1 -and @($d | Where-Object { $_.Category -eq 'unattributed' })[0].Count -eq 2) (($d | ForEach-Object { '{0}:{1}' -f $_.Category, $_.Count }) -join ' ')
    Assert-True ((Get-TrapCulpritText '*drivers*') -eq (Get-TrapCulpritText '*unattributed*')) 'Legacy and new unattributed names read differently.'
}
Case 'measured DPC load is diagnosed as drivers' {
    $start = [pscustomobject]@{ t = '2026-10-04T10:00:00'; kind = 'start'; total = 95; attributed = 30; dpc = 20; interrupt = 5; defender = $null
        top = @([pscustomobject]@{ name = 'x.exe'; pct = 15; parent = ''; scheduled = $false }) }
    $c = Get-TrapCulprit $start
    Assert-True ($c.Name -eq '*dpc*' -and $c.Pct -eq 25) "Culprit: $($c.Name) $($c.Pct)"
    $eps = New-Object System.Collections.Generic.List[object]; $eps.Add(@{ Start = $start; Defender = $null })
    $d = @(Get-TrapDiagnosis $eps)
    Assert-True ($d[0].Category -eq 'drivers' -and $d[0].Key -eq 'diag_drivers') ('Finding: ' + $d[0].Category)
    Assert-True ((Get-TrapCulpritText '*dpc*') -match '^trapDpc') 'The measured driver culprit has no own text.'
}
Case 'small or unmeasured DPC load does not become a driver finding' {
    $small = [pscustomobject]@{ t = '2026-10-04T10:00:00'; kind = 'start'; total = 95; attributed = 85; dpc = 6; interrupt = 2
        top = @([pscustomobject]@{ name = 'x.exe'; pct = 70 }) }
    Assert-True ((Get-TrapCulprit $small).Name -eq 'x.exe') 'A small DPC share displaced the top process.'
    $legacy = @{ total = 95; attributed = 10; top = @(@{ name = 'demo.exe'; pct = 8 }) }
    Assert-True ((Get-TrapCulprit $legacy).Name -eq '*unattributed*') 'A record without dpc was called a driver.'
}
Case 'hour histogram has 24 buckets counting starts' {
    $h = Get-TrapHourHistogram $diagEpisodes
    Assert-True ($h.Count -eq 24 -and $h[0] -eq 1 -and $h[15] -eq 3 -and (($h | Measure-Object -Sum).Sum) -eq 10) ($h -join ',')
}
Case 'no episodes, no findings' {
    Assert-True (@(Get-TrapDiagnosis (New-Object System.Collections.Generic.List[object])).Count -eq 0) 'Findings from nothing.'
}
Case 'records of a not yet migrated 2.2 install are read from the legacy root' {
    . ([scriptblock]::Create((Get-TestFunctionSource @('Read-SharedText','Read-TrapRecords'))))
    $script:TrapCache = @{}
    $root = Join-Path $Work 'trap-legacy'; $logs = Join-Path $root 'logs'
    [void][IO.Directory]::CreateDirectory($logs)
    $now = (Get-Date).AddMinutes(-5).ToString('s'); $month = 'spikes-{0:yyyy-MM}.jsonl' -f (Get-Date)
    [IO.File]::WriteAllText((Join-Path $root $month),('{"t":"' + $now + '","kind":"start","total":90,"attributed":80,"top":[]}' + "`n"))
    [IO.File]::WriteAllText((Join-Path $logs $month),('{"t":"' + $now + '","kind":"end","durationSec":5,"peak":91}' + "`n"))
    $records = Read-TrapRecords -Dir $logs -LegacyDir $root
    Assert-True ($records.Count -eq 2 -and [string]$records[0].kind -eq 'start') "Read $($records.Count) records."
    Assert-True ((Read-TrapRecords -Dir $logs).Count -eq 1) 'Without a legacy folder only logs\ is read.'
}
$script:AppVersion = '2.3.0'
$trapState = @{ Installed = $true; Running = $true; Outdated = $false; Threshold = 85; Beat = (Get-Date '2026-10-01T16:00:00') }
Case 'report has title, diagnosis, culprit and spike sections, every episode once' {
    $md = Format-TrapReport $trapState $diagEpisodes
    Assert-True ($md -match '(?m)^# reportTitle' -and $md -match '(?m)^## reportDiagnosis' -and $md -match '(?m)^## reportTop' -and $md -match '(?m)^## reportRecent') 'A report section is missing.'
    Assert-True (([regex]::Matches($md,'(?m)^\| 01\.10 ')).Count -eq 10) 'Episodes are not listed once each.'
    Assert-True ($md -match 'reportStatus\|trapStRunning\S*\|85') 'The trap status is missing.'
}
Case 'report states an outdated trap' {
    $outdated = @{ Installed = $true; Running = $true; Outdated = $true; Threshold = 85 }
    Assert-True ((Format-TrapReport $outdated $diagEpisodes) -match 'reportStatus\|trapStOutdated') 'An outdated trap was reported as current.'
}
Case 'pipes in process names cannot break table rows' {
    $pipeEp = New-Object System.Collections.Generic.List[object]
    $pipeEp.Add(@{ Start = (New-Start '2026-10-03T10:00:00' 'a|b.exe' 50); Defender = $null; Duration = 5; Peak = 90 })
    Assert-True ((Format-TrapReport $trapState $pipeEp) -match 'a\\\|b\.exe') 'A pipe broke the table.'
}
Case 'report saved as UTF-8 markdown, content unchanged' {
    $md = Format-TrapReport $trapState $diagEpisodes
    $path = Save-TrapReport $md (Join-Path $Work 'reports')
    Assert-True ((Test-Path -LiteralPath $path) -and $path -like '*.md' -and [IO.File]::ReadAllText($path) -eq $md) 'The saved report differs.'
}
Case 'notifications: baseline, new spike once, at most one per 15 minutes' {
    $nr = New-Object System.Collections.Generic.List[object]
    $nr.Add((New-Start '2026-10-01T09:00:00' 'codex.exe' 40))
    $now = Get-Date '2026-10-01T09:01:00'
    $n1 = Get-TrapNotification $nr $null ([datetime]::MinValue) $now
    Assert-True (-not $n1.Show -and $n1.LastT -eq '2026-10-01T09:00:00') 'History was announced on the first look.'
    $nr.Add((New-Start '2026-10-01T09:05:00' 'java.exe' 50)); $nr.Add((New-End '2026-10-01T09:05:10'))
    $n2 = Get-TrapNotification $nr $n1.LastT ([datetime]::MinValue) $now
    Assert-True ($n2.Show -and $n2.Record.top[0].name -eq 'java.exe' -and $n2.LastT -eq '2026-10-01T09:05:00') 'A new spike was not announced.'
    Assert-True (-not (Get-TrapNotification $nr $n2.LastT ([datetime]::MinValue) $now).Show) 'A spike was announced twice.'
    $nr.Add((New-Start '2026-10-01T09:07:00' 'node.exe' 30))
    $n4 = Get-TrapNotification $nr $n2.LastT $now.AddMinutes(-5) $now
    Assert-True (-not $n4.Show -and $n4.LastT -eq '2026-10-01T09:07:00') 'The 15-minute limit was not kept.'
    $n5 = Get-TrapNotification (New-Object System.Collections.Generic.List[object]) $null ([datetime]::MinValue) $now
    Assert-True (-not $n5.Show -and $null -eq $n5.LastT) 'Nothing was announced from no records.'
}
#endregion

#region Integration path repair
. ([scriptblock]::Create((Get-TestFunctionSource @('Test-IntegrationCommand','Get-IntegrationScriptPath'))))
. ([scriptblock]::Create((Get-TestFunctionSource @('Test-IntegrationNeedsRepair'))))
Case 'only a missing or dead registration is repaired' {
    $expected = '"C:\ps.exe" -File "C:\Apps\OpenRelax\openrelax.ps1" -StartMinimized'
    $other = Join-Path $Work 'other-copy\openrelax.ps1'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $other)); [IO.File]::WriteAllText($other,'# another copy')
    Assert-True (Test-IntegrationNeedsRepair '' $expected) 'A missing registration was not repaired.'
    Assert-True (-not (Test-IntegrationNeedsRepair $expected $expected)) 'A current registration was rewritten.'
    Assert-True (Test-IntegrationNeedsRepair ('"C:\ps.exe" -File "' + (Join-Path $Work 'moved-away\openrelax.ps1') + '" -StartMinimized') $expected) 'A registration of a deleted folder was kept.'
    Assert-True (-not (Test-IntegrationNeedsRepair ('"C:\ps.exe" -File "' + $other + '" -StartMinimized') $expected)) 'A working registration of another copy was taken over.'
}
Case 'the script a registered command starts is extracted' {
    Assert-True ((Get-IntegrationScriptPath '"C:\ps.exe" -STA -File "C:\Old Folder\openrelax.ps1" -StartMinimized') -eq 'C:\Old Folder\openrelax.ps1') 'The quoted script path was not found.'
    Assert-True ((Get-IntegrationScriptPath '-NoProfile -File C:\x\openrelax.ps1 -AutoClean') -eq 'C:\x\openrelax.ps1') 'An unquoted script path was not found.'
    Assert-True ((Get-IntegrationScriptPath 'notepad.exe') -eq '') 'A command without -File produced a path.'
}
Case 'integration commands compare ignoring case and spacing' {
    $expected = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -STA -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "C:\Apps\OpenRelax\openrelax.ps1" -StartMinimized'
    Assert-True (Test-IntegrationCommand $expected $expected) 'An identical command was a mismatch.'
    Assert-True (Test-IntegrationCommand ('  ' + $expected.ToLowerInvariant().Replace(' -nop', '  -nop') + ' ') $expected) 'Case or spacing made a mismatch.'
    $moved = $expected -replace 'C:\\Apps\\OpenRelax', 'C:\Users\x\Desktop\old'
    Assert-True (-not (Test-IntegrationCommand $moved $expected)) 'A different folder was accepted.'
    Assert-True (-not (Test-IntegrationCommand '' $expected) -and -not (Test-IntegrationCommand $null $expected)) 'A missing command was accepted.'
}
#endregion

#region Embedded spike sampler
. ([scriptblock]::Create((Get-TestFunctionSource @('Read-ProcessCpuSample','Measure-ProcessCpu','New-SpikeTracker','Step-SpikeTracker','Round-Share','New-SpikeRecord','Add-TrapRecord','Set-TrapHeartbeat','Protect-CommandLine','Test-ScheduledParent'))))
Case 'process CPU is matched by PID, not by instance name' {
    # chrome#3 (pid 11) became chrome#2 after pid 10 exited; pid 12 started in between.
    $before = @{ At = (Get-Date); Ts100 = [long]0; ByPid = @{ 10 = @{ Instance = 'chrome#2'; Raw = [long]0 }; 11 = @{ Instance = 'chrome#3'; Raw = [long]1000000 } } }
    $after  = @{ At = (Get-Date); Ts100 = [long]20000000; ByPid = @{ 11 = @{ Instance = 'chrome#2'; Raw = [long]9000000 }; 12 = @{ Instance = 'python'; Raw = [long]4000000 } } }
    $rows = @(Measure-ProcessCpu $before $after 4)
    $chrome = @($rows | Where-Object { $_.Pid -eq 11 })
    Assert-True ($chrome.Count -eq 1 -and [Math]::Abs($chrome[0].Pct - 10) -lt 0.01) ('chrome: ' + ($rows | ForEach-Object { '{0}:{1}' -f $_.Pid, $_.Pct }))
    Assert-True (@($rows | Where-Object { $_.Pid -eq 12 })[0].Pct -eq 5) 'A process started during the window was not counted from zero.'
    Assert-True (@($rows | Where-Object { $_.Pid -eq 10 }).Count -eq 0) 'An exited process was reported.'
    Assert-True ($rows[0].Pid -eq 11) 'Rows are not sorted by share.'
}
Case 'idle and total are excluded' {
    $before = @{ At = (Get-Date); Ts100 = [long]0; ByPid = @{ 0 = @{ Instance = 'Idle'; Raw = [long]0 }; 4 = @{ Instance = 'System'; Raw = [long]0 } } }
    $after  = @{ At = (Get-Date); Ts100 = [long]10000000; ByPid = @{ 0 = @{ Instance = 'Idle'; Raw = [long]9000000 }; 4 = @{ Instance = 'System'; Raw = [long]100000 } } }
    $rows = @(Measure-ProcessCpu $before $after 1)
    Assert-True ($rows.Count -eq 1 -and $rows[0].Instance -eq 'System') ('Rows: ' + ($rows | ForEach-Object { $_.Instance }))
}
Case 'tracker arms, starts after the sustain window and ends after cooling' {
    $state = New-SpikeTracker 85 4 2
    $t = Get-Date '2026-10-17T10:00:00'
    $actions = foreach ($cpu in 90,90,90,40,40) { $t = $t.AddSeconds(2); Step-SpikeTracker $state $cpu $t }
    Assert-True (($actions -join ',') -eq 'arm,start,,,end') ('Actions: ' + ($actions -join ','))
    Assert-True ($state.Spikes -eq 1 -and $state.Peak -eq 90 -and -not $state.InSpike) 'Tracker state is wrong after the spike.'
    $again = foreach ($cpu in 90,40,90) { $t = $t.AddSeconds(2); Step-SpikeTracker $state $cpu $t }
    Assert-True (($again -join ',') -eq 'arm,,arm') ('A single hot sample started a spike: ' + ($again -join ','))
}
Case 'tracker reports ongoing every 120 s' {
    $state = New-SpikeTracker 85 4 2
    $t = Get-Date '2026-10-17T10:00:00'
    $actions = foreach ($i in 1..70) { $t = $t.AddSeconds(2); Step-SpikeTracker $state 95 $t }
    Assert-True (@($actions | Where-Object { $_ -eq 'start' }).Count -eq 1 -and @($actions | Where-Object { $_ -eq 'ongoing' }).Count -eq 1) ('Actions: ' + (($actions | Where-Object { $_ }) -join ','))
}
$recordProcesses = @{
    40 = @{ Name = 'python.exe'; ParentPid = 30; CommandLine = 'python C:\work\train.py --api-key=SECRET' }
    30 = @{ Name = 'svchost.exe'; ParentPid = 4; CommandLine = 'C:\WINDOWS\system32\svchost.exe -k netsvcs -p -s Schedule' }
}
$recordRows = @(
    @{ Pid = 40; Instance = 'python'; Pct = 61.234 }, @{ Pid = 77; Instance = 'chrome#2'; Pct = 12 }, @{ Pid = 78; Instance = 'a'; Pct = 3 },
    @{ Pid = 79; Instance = 'b'; Pct = 2 }, @{ Pid = 80; Instance = 'c'; Pct = 1.5 }, @{ Pid = 81; Instance = 'd'; Pct = 1.2 }, @{ Pid = 82; Instance = 'e'; Pct = 0.4 })
Case 'record keeps the 2.3 contract and adds dpc/interrupt' {
    $script:RecordCommandLines = $false
    $record = New-SpikeRecord 'start' (Get-Date '2026-10-17T21:40:00') 4.2 96.5 $recordRows $recordProcesses 3.25 1.5
    Assert-True ((@($record.Keys) -join ',') -eq 't,kind,window,total,attributed,dpc,interrupt,top,defender') ('Keys: ' + (@($record.Keys) -join ','))
    Assert-True ($record.t -eq '2026-10-17T21:40:00' -and $record.dpc -eq 3.3 -and $record.interrupt -eq 1.5 -and $record.attributed -eq 81.3) 'Header fields are wrong.'
    $top = @($record.top)
    Assert-True ($top.Count -eq 5 -and $top[0].name -eq 'python.exe' -and $top[0].pct -eq 61.2 -and $top[0].parent -eq 'svchost.exe' -and $top[0].scheduled) 'Top process fields are wrong.'
    Assert-True ($top[1].name -eq 'chrome.exe' -and $top[1].parent -eq '') 'Unknown processes fall back to the instance name.'
    $json = ConvertTo-Json -InputObject $record -Compress -Depth 5
    Assert-True ($json.StartsWith('{"t":"2026-10-17T21:40:00","kind":"start"')) $json
}
Case 'record omits command lines unless recording is on' {
    $script:RecordCommandLines = $false
    $off = New-SpikeRecord 'start' (Get-Date) 2 90 $recordRows $recordProcesses 0 0
    Assert-True (@($off.top)[0].cmd -eq '' -and @($off.top)[0].parentCmd -eq '') 'A command line was recorded while off.'
    $script:RecordCommandLines = $true
    try { $on = New-SpikeRecord 'start' (Get-Date) 2 90 $recordRows $recordProcesses 0 0 } finally { $script:RecordCommandLines = $false }
    $cmd = [string]@($on.top)[0].cmd
    Assert-True ($cmd -match 'train\.py' -and $cmd -notmatch 'SECRET') "Recorded: $cmd"
}
Case 'records append as one JSON line each, heartbeat replaces atomically' {
    $dir = Join-Path $Work 'sampler-out'
    $script:RecordCommandLines = $false
    Add-TrapRecord $dir ([ordered]@{ t = '2026-10-17T10:00:00'; kind = 'monitor'; version = 'test' })
    Add-TrapRecord $dir (New-SpikeRecord 'start' (Get-Date '2026-10-17T10:00:10') 2 90 $recordRows $recordProcesses 0 0)
    $lines = @([IO.File]::ReadAllLines((Join-Path $dir 'spikes-2026-10.jsonl')) | Where-Object { $_ })
    Assert-True ($lines.Count -eq 2 -and $lines[1].StartsWith('{"t":"2026-10-17T10:00:10"')) "Lines: $($lines.Count)"
    $bytes = [IO.File]::ReadAllBytes((Join-Path $dir 'spikes-2026-10.jsonl'))
    Assert-True ($bytes[0] -eq [byte][char]'{') 'The record file starts with a BOM.'
    Set-TrapHeartbeat $dir ([ordered]@{ t = '2026-10-17T10:01:00'; threshold = 85; spikes = 1 })
    Set-TrapHeartbeat $dir ([ordered]@{ t = '2026-10-17T10:02:00'; threshold = 85; spikes = 2 })
    $beat = Get-Content -LiteralPath (Join-Path $dir 'durum.json') -Raw | ConvertFrom-Json
    Assert-True ($beat.spikes -eq 2 -and @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp').Count -eq 0) 'Heartbeat was not replaced cleanly.'
}
Case 'a live PDH read sees more than 10 processes and includes this process' {
    $sample = Read-ProcessCpuSample
    Assert-True ($sample.ByPid.Count -gt 10 -and $sample.ByPid.ContainsKey($PID) -and $sample.Ts100 -gt 0) "Processes: $($sample.ByPid.Count)"
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
Case 'the sampler worker records a synthetic spike and stops on request' {
    $dir = Join-Path $Work 'sampler-worker'
    $sync = [hashtable]::Synchronized(@{ TrapStop = $false; TrapBeat = $null; TrapError = ''; TrapRecordCmd = $false })
    # One busy thread is far above a 1 % threshold on any machine.
    $burner = [powershell]::Create(); [void]$burner.AddScript('$end = [DateTime]::UtcNow.AddSeconds(14); while ([DateTime]::UtcNow -lt $end) { $x = 1 }')
    $burnHandle = $burner.BeginInvoke()
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript((Get-TestFunctionSource @('Read-ProcessCpuSample','Measure-ProcessCpu','New-SpikeTracker','Step-SpikeTracker','Round-Share','New-SpikeRecord','Add-TrapRecord','Set-TrapHeartbeat','Protect-CommandLine','Test-ScheduledParent')))
        [void]$ps.AddStatement().AddScript((Get-WorkerSource 'TrapSamplerCode')).AddArgument($sync).AddArgument(@{ Dir = $dir; Threshold = 1; SustainSec = 2; IntervalSec = 1; Version = 'test' })
        $handle = $ps.BeginInvoke()
        Start-Sleep -Seconds 9
        $sync.TrapStop = $true
        $clock = [Diagnostics.Stopwatch]::StartNew()
        Assert-True ($handle.AsyncWaitHandle.WaitOne(3000)) 'The sampler did not stop within 3 s.'
        [void]$ps.EndInvoke($handle)
        Assert-True (-not $ps.HadErrors -and -not $sync.TrapError) ('Sampler errors: ' + ($ps.Streams.Error -join '; ') + $sync.TrapError)
    } finally { $ps.Dispose(); [void]$burner.EndInvoke($burnHandle); $burner.Dispose() }
    $records = @(Get-Content -LiteralPath (Get-ChildItem -LiteralPath $dir -Filter 'spikes-*.jsonl').FullName | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
    $kinds = @($records | ForEach-Object { $_.kind })
    Assert-True ($kinds[0] -eq 'monitor' -and $kinds -contains 'start' -and $kinds[$kinds.Count - 1] -eq 'end') ('Kinds: ' + ($kinds -join ','))
    $start = @($records | Where-Object { $_.kind -eq 'start' })[0]
    Assert-True ($start.PSObject.Properties['dpc'] -and @($start.top).Count -ge 1 -and $start.top[0].name -like '*.exe') 'The start record lacks the embedded fields.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $dir 'durum.json') -Raw | ConvertFrom-Json).mode -eq 'embedded') 'No embedded heartbeat was written.'
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

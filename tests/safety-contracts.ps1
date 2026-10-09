[CmdletBinding()]
param([string]$Work = (Join-Path $env:TEMP ('openrelax-contracts-' + [guid]::NewGuid().ToString('N'))),[switch]$KeepArtifacts)
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
$engineNames = @('Test-PathWithin','Assert-NoReparseAncestors','Assert-CleanupPath','Get-SafeTreeEntries','Get-JunkCategories','Remove-JunkPaths','Measure-JunkPaths','Wait-ServiceState','Invoke-WindowsUpdateCacheCleanup','Invoke-Maintenance','Protect-CommandLine','New-ProtectedTrapAcl','Resolve-TrapReaderSid','Assert-SingleLinkFile','Invoke-DefenderTrace','Get-TrapCulprit')
. ([scriptblock]::Create((Get-TestFunctionSource $engineNames)))

Case 'safe defaults and strict settings types' {
    $defaults = Get-DefaultSettings
    foreach ($key in 'recycle','wu','shader','wer','gpusetup') { Assert-True (-not $defaults.categories[$key]) "Unsafe default: $key" }
    $path = Join-Path $Work 'settings.json'
    Write-SettingsAtomic $defaults $path
    Assert-True (Read-SettingsDocument $path).Valid 'Valid settings rejected.'
    [IO.File]::WriteAllText($path,'{"language":')
    Assert-True (-not (Read-SettingsDocument $path).Valid) 'Truncated settings accepted.'
    $defaults.categories.recycle = 'false'
    Write-SettingsAtomic $defaults $path
    Assert-True (-not (Read-SettingsDocument $path).Valid) 'String boolean accepted.'
    foreach ($bad in @('null','[]','{"language":"en"}')) { [IO.File]::WriteAllText($path,$bad); Assert-True (-not (Read-SettingsDocument $path).Valid) 'Non-settings document accepted.' }
    $defaults = Get-DefaultSettings; $defaults.schemaVersion = 99; Write-SettingsAtomic $defaults $path; Assert-True (-not (Read-SettingsDocument $path).Valid) 'Unsupported schema accepted.'
    foreach ($schema in @('2',$true)) { $defaults = Get-DefaultSettings; $defaults.schemaVersion = $schema; Write-SettingsAtomic $defaults $path; Assert-True (-not (Read-SettingsDocument $path).Valid) 'Wrong schema type accepted.' }
    $defaults = Get-DefaultSettings; $defaults.language = @('tr'); Write-SettingsAtomic $defaults $path; Assert-True (-not (Read-SettingsDocument $path).Valid) 'Language array accepted.'
    $legacy = Get-DefaultSettings; $legacy.Remove('schemaVersion'); $legacy.Remove('trimRam'); $legacy.Remove('clearDns'); Write-SettingsAtomic $legacy $path
    $loaded = Read-SettingsDocument $path; Assert-True ($loaded.Valid -and -not $loaded.Settings.trimRam -and -not $loaded.Settings.clearDns) 'Legacy migration changed opt-in defaults.'
    $defaults = Get-DefaultSettings; $defaults.categories.Remove('recycle')
    Write-SettingsAtomic $defaults $path
    Assert-True (-not (Read-SettingsDocument $path).Valid) 'Missing category accepted.'
    Assert-True (-not (Read-SettingsDocument (Join-Path $Work 'missing.json')).Valid) 'Missing settings accepted.'
}
Case 'atomic save preserves the old file after replace failure' {
    $path = Join-Path $Work 'atomic.json'
    Write-SettingsAtomic (Get-DefaultSettings) $path
    $before = (Get-FileHash -LiteralPath $path).Hash
    $held = [IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { Assert-Throws { Write-SettingsAtomic (Get-DefaultSettings) $path } } finally { $held.Dispose() }
    Assert-True ((Get-FileHash -LiteralPath $path).Hash -eq $before) 'Old settings were changed.'
}
Case 'global state mutex restricts principals and excludes another worker' {
    $path = Join-Path $Work 'mutex-settings.json'
    $mutex = Get-SettingsMutex $path
    $owned = $false; $worker = [powershell]::Create()
    try {
        $owned = $mutex.WaitOne(0)
        Assert-True $owned 'Could not own the test mutex.'
        $acl = $mutex.GetAccessControl()
        Assert-True $acl.AreAccessRulesProtected 'State mutex permissions inherit.'
        $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value,'S-1-5-18','S-1-5-32-544')
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) { Assert-True ($rule.IdentityReference.Value -in $allowed) 'Untrusted mutex principal.' }
        $mutexSource = 'param($Path)' + "`nfunction Get-SettingsMutex {`n" + (Get-Command Get-SettingsMutex).Definition + "`n}`n" + '$other = Get-SettingsMutex $Path; try { $owned = $other.WaitOne(0); if ($owned) { $other.ReleaseMutex() }; return $owned } finally { $other.Dispose() }'
        [void]$worker.AddScript($mutexSource).AddArgument($path)
        $answer = @($worker.Invoke())
        Assert-True (-not $worker.HadErrors -and $answer.Count -eq 1 -and $answer[0] -eq $false) ('Mutex exclusion failed: ' + ($worker.Streams.Error -join '; '))
    } finally { $worker.Dispose(); if ($owned) { $mutex.ReleaseMutex() }; $mutex.Dispose() }
}
Case 'preference save preserves current statistics and fails without truncation' {
    $script:SettingsFile = Join-Path $Work 'preferences.json'; $script:Settings = Get-DefaultSettings
    $latest = Get-DefaultSettings; $latest.stats.totalRuns = 7; $latest.stats.totalCleanedBytes = 40
    Write-SettingsAtomic $latest $script:SettingsFile
    $script:Settings.language = 'en'
    Assert-True (Save-Settings) 'Preference save failed.'
    $saved = Read-SettingsDocument $script:SettingsFile
    Assert-True ($saved.Settings.language -eq 'en' -and $saved.Settings.stats.totalRuns -eq 7) 'Save lost latest statistics.'
    $before = (Get-FileHash -LiteralPath $script:SettingsFile).Hash
    $script:SaveLog = @()
    function Write-Log { param($Message,$Type) $script:SaveLog += $Message }
    $held = [IO.File]::Open($script:SettingsFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try { Assert-True (-not (Save-Settings)) 'Locked settings overwrite reported success.' } finally { $held.Dispose() }
    Assert-True ($script:SaveLog.Count -eq 1 -and (Get-FileHash -LiteralPath $script:SettingsFile).Hash -eq $before) 'Write failure was hidden or old file changed.'
}
Case 'statistics read-modify-write preserves preferences and refuses overflow' {
    $script:Settings = Get-DefaultSettings; $script:SettingsFile = Join-Path $Work 'stats.json'
    Write-SettingsAtomic $script:Settings $script:SettingsFile
    $diskSettings = Get-DefaultSettings; $diskSettings.language = 'en'; $diskSettings.categories.browser = $false
    Write-SettingsAtomic $diskSettings $script:SettingsFile
    Update-MaintenanceStats 12; Update-MaintenanceStats 20
    $loaded = Read-SettingsDocument $script:SettingsFile
    Assert-True ($loaded.Settings.stats.totalCleanedBytes -eq 32 -and $loaded.Settings.stats.totalRuns -eq 2) 'Statistics updates were lost.'
    Assert-True ($loaded.Settings.language -eq 'en' -and -not $loaded.Settings.categories.browser) 'Preferences were overwritten by stale state.'
    $loaded.Settings.stats.totalRuns = [int]::MaxValue
    Write-SettingsAtomic $loaded.Settings $script:SettingsFile
    Assert-Throws { Update-MaintenanceStats 1 }
}
Case 'root, relative and prefix-confusion cleanup paths are refused' {
    Assert-Throws { Assert-CleanupPath ([IO.Path]::GetPathRoot($Work)) $Work }
    Assert-Throws { Assert-CleanupPath '.\relative' $Work }
    Assert-Throws { Assert-CleanupPath ($Work + '-outside') $Work }
    Assert-Throws { Assert-CleanupPath ([Environment]::GetFolderPath('UserProfile')) ([Environment]::GetFolderPath('UserProfile')) }
    Assert-CleanupPath $Work $Work
}
Case 'test workspace refuses existing data and invalid ownership' {
    $existing = Join-Path $Work 'existing'; [void][IO.Directory]::CreateDirectory($existing)
    $sentinel = Join-Path $existing 'keep.txt'; [IO.File]::WriteAllText($sentinel,'keep')
    Assert-Throws { New-TestWorkspace $existing }
    Assert-Throws { Remove-TestWorkspace @{ Path = $existing; Owner = 'not-the-owner' } }
    $owned = New-TestWorkspace (Join-Path $Work 'ownership')
    [IO.File]::WriteAllText((Join-Path $owned.Path 'keep.txt'),'keep')
    Assert-Throws { Remove-TestWorkspace @{ Path = $owned.Path; Owner = 'wrong' } }
    Assert-True ([IO.File]::ReadAllText((Join-Path $owned.Path 'keep.txt')) -eq 'keep') 'Wrong owner removed data.'
    Remove-TestWorkspace $owned
    Assert-True ([IO.File]::ReadAllText($sentinel) -eq 'keep') 'Existing data changed.'
}
Case 'command arguments cannot leak through supported or positional formats' {
    foreach ($input in @('curl -H "Authorization: Bearer FAKE_BEARER"','tool --password ''FAKE SECRET''','tool --token=FAKE_TOKEN','curl -u demo:FAKE_PASSWORD','https://demo:FAKE_PASSWORD@example.invalid/?key=FAKE_KEY','{"password":"FAKE_PASSWORD"}')) {
        Assert-True ((Protect-CommandLine $input) -eq '') 'Command argument was retained.'
    }
}
Case 'SYSTEM tree ACL grants readers no write and assigns administrative ownership' {
    $reader = 'S-1-5-21-111-222-333-1001'
    foreach ($isFile in @($false,$true)) {
        $acl = New-ProtectedTrapAcl $reader $isFile
        Assert-True $acl.AreAccessRulesProtected 'ACL inherits external permissions.'
        Assert-True ($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') 'User retains ownership.'
        $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $reader })
        Assert-True ($rules.Count -eq 1) 'Reader rule missing.'
        $all = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
        Assert-True ($all.Count -eq 3) 'Unexpected ACL principal.'
        foreach ($sid in 'S-1-5-18','S-1-5-32-544') {
            $admin = @($all | Where-Object { $_.IdentityReference.Value -eq $sid })
            Assert-True ($admin.Count -eq 1 -and $admin[0].FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl) 'SYSTEM/admin cannot maintain the tree.'
        }
        $writes = [Security.AccessControl.FileSystemRights]'Write,Delete,DeleteSubdirectoriesAndFiles,ChangePermissions,TakeOwnership'
        Assert-True (-not ($rules[0].FileSystemRights -band $writes)) 'Reader can write or replace task files.'
    }
}
Case 'cross-account installation preserves the requesting reader identity' {
    $requester = 'S-1-5-21-1-2-3-1001'
    Assert-True ((Resolve-TrapReaderSid $requester) -eq $requester) 'Requesting account was replaced by the elevated account.'
    Assert-True ((Resolve-TrapReaderSid '') -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) 'Standalone installation reader changed.'
    Assert-Throws { Resolve-TrapReaderSid 'not-a-sid' }
    foreach ($group in 'S-1-1-0','S-1-5-32-545','S-1-5-32-544','S-1-5-18') { Assert-Throws { Resolve-TrapReaderSid $group } }
    $acl = New-ProtectedTrapAcl (Resolve-TrapReaderSid $requester) $true
    $rule = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $requester })
    Assert-True ($rule.Count -eq 1 -and $rule[0].FileSystemRights -eq [Security.AccessControl.FileSystemRights]'ReadAndExecute,Synchronize') 'Requesting account did not retain read-only access.'
}
Case 'hardlinks are refused before task-file ACL changes' {
    $file = Join-Path $Work 'single-link.txt'; [IO.File]::WriteAllText($file,'keep')
    Assert-SingleLinkFile $file
    $link = Join-Path $Work 'hardlink.txt'; New-Item -ItemType HardLink -Path $link -Target $file | Out-Null
    Assert-Throws { Assert-SingleLinkFile $link }
    Assert-True ([IO.File]::ReadAllText($file) -eq 'keep') 'Hardlink target was modified.'
}
Case 'default Defender classification omits raw event resources and tracing' {
    $script:RecordDefenderTrace = $false; $script:TraceCalls = 0; $script:DefenderLog = ''
    function Get-WinEvent { param($FilterHashtable,$MaxEvents) return @{ Id = 1000; TimeCreated = Get-Date; Message = 'Resources: C:\FAKE_PRIVATE_SCAN\document.txt' } }
    function Write-Trap { param($Text) $script:DefenderLog = $Text }
    function New-MpPerformanceRecording { $script:TraceCalls++; throw 'Unexpected tracing' }
    Assert-True ((Invoke-DefenderTrace) -eq 'scan') 'Scan event was not classified.'
    Assert-True ($script:TraceCalls -eq 0 -and $script:DefenderLog -notmatch 'FAKE_PRIVATE_SCAN|Resources|document') 'Default Defender path disclosed raw details.'
    function Get-WinEvent { throw 'simulated unavailable event log' }
    Assert-True ((Invoke-DefenderTrace) -eq 'realtime' -and $script:TraceCalls -eq 0) 'Missing event triggered a performance trace.'
}
Case 'unattributed CPU is not diagnosed as a driver' {
    $culprit = Get-TrapCulprit @{ total = 95; attributed = 10; top = @(@{ name = 'demo.exe'; pct = 8 }) }
    Assert-True ($culprit.Name -eq '*unattributed*') 'Residual CPU was called a driver.'
    $assigned = Get-TrapCulprit @{ total = 95; attributed = 90; top = @(@{ name = 'synthetic.exe'; pct = 80 }) }
    Assert-True ($assigned.Name -eq 'synthetic.exe' -and $assigned.Pct -eq 80) 'A dominant captured process was hidden by a small residual.'
}
Case 'interactive confirmation and opt-in RAM/DNS are enforced' {
    $script:TrimCalls = 0; $script:DnsCalls = 0; $script:RemoveCalls = 0
    function Get-JunkCategories { return , @(@{ Key = 'temp'; Paths = @() }) }
    function Remove-JunkPaths { param($Paths,[bool]$IsAdmin) $script:RemoveCalls++; return @{ Bytes = 12; Count = 1; Skipped = 0; Errors = @() } }
    function Invoke-RamTrim { $script:TrimCalls++; return @{ Saved = 0; Success = 1; Fail = 0 } }
    function Clear-DnsClientCache { param($ErrorAction) $script:DnsCalls++ }
    Assert-Throws { Invoke-Maintenance @{ Keys = @('temp') } }
    $result = Invoke-Maintenance @{ Keys = @('temp'); Confirmed = $true }
    Assert-True ($result.Status -eq 'Success' -and $script:RemoveCalls -eq 1) 'Confirmed cleanup failed.'
    Assert-True ($script:TrimCalls -eq 0 -and $script:DnsCalls -eq 0) 'Unselected RAM/DNS was performed.'
    $enabled = Invoke-Maintenance @{ Keys = @(); Confirmed = $true; TrimRam = $true; ClearDns = $true }
    Assert-True ($enabled.Status -eq 'Success' -and $script:TrimCalls -eq 1 -and $script:DnsCalls -eq 1 -and $enabled.Ram.Success -eq 1) 'Confirmed opt-in operation did not run.'
}
Case 'headless maintenance skips interactive-only categories and propagates errors' {
    $script:RemoveCalls = 0
    function Get-JunkCategories { return , @(@{ Key = 'recycle'; Paths = @() },@{ Key = 'wu'; Paths = @() },@{ Key = 'temp'; Paths = @() }) }
    function Clear-RecycleBin { throw 'Unexpected recycle operation.' }
    function Invoke-WindowsUpdateCacheCleanup { throw 'Unexpected service operation.' }
    function Remove-JunkPaths { param($Paths,[bool]$IsAdmin) $script:RemoveCalls++; throw 'simulated file error' }
    $script:RemoveCalls = 0
    $result = Invoke-Maintenance @{ Keys = @('recycle','wu','temp'); Headless = $true }
    Assert-True ($script:RemoveCalls -eq 1 -and $result.Errors[0] -match 'simulated file error') 'Maintenance failed for an unrelated reason.'
    Assert-True ($result.Status -eq 'Failed' -and $result.Skipped -eq 2 -and $result.Errors.Count -eq 1) 'Headless failure hidden.'
}
Case 'Windows Update restores states and refuses stop/restart failures' {
    foreach ($scenario in 'normal','stopped','stop-first','stop-second','delete','restart','non-admin','paused','pending','stop-noop','stop-after-change','restart-noop') {
        $script:ServiceStates = @{ wuauserv = 'Running'; bits = 'Running' }; $script:Removed = 0; $script:Violations = 0
        if ($scenario -eq 'stopped') { $script:ServiceStates = @{ wuauserv = 'Stopped'; bits = 'Stopped' } }
        if ($scenario -eq 'paused') { $script:ServiceStates.bits = 'Paused' }
        if ($scenario -eq 'pending') { $script:ServiceStates.bits = 'StartPending' }
        $initial = $script:ServiceStates.Clone()
        function Wait-ServiceState { param($Name,$State) if ([string]$script:ServiceStates[$Name] -ne $State) { throw 'simulated state did not transition' } }
        function Get-Service { param($Name,$ErrorAction) return @{ Status = $script:ServiceStates[$Name] } }
        function Stop-Service { param($Name,[switch]$Force,$ErrorAction) if (($scenario -eq 'stop-first' -and $Name -eq 'wuauserv') -or ($scenario -eq 'stop-second' -and $Name -eq 'bits')) { throw 'simulated stop error' }; if ($scenario -ne 'stop-noop') { $script:ServiceStates[$Name] = 'Stopped' }; if ($scenario -eq 'stop-after-change') { throw 'simulated error after stop' } }
        function Start-Service { param($Name,$ErrorAction) if ($scenario -eq 'restart') { throw 'simulated restart error' }; if ($scenario -ne 'restart-noop') { $script:ServiceStates[$Name] = 'Running' } }
        function Remove-JunkPaths { param($Paths,[bool]$IsAdmin) $script:Removed++; if ($script:ServiceStates.wuauserv -ne 'Stopped' -or $script:ServiceStates.bits -ne 'Stopped') { $script:Violations++ }; if ($scenario -eq 'delete') { throw 'simulated delete error' }; return @{ Bytes = 12; Count = 1; Skipped = 0; Errors = @() } }
        $threw = $false
        try { [void](Invoke-WindowsUpdateCacheCleanup @() ($scenario -ne 'non-admin')) } catch { $threw = $true }
        Assert-True ($threw -eq ($scenario -notin @('normal','stopped'))) "Wrong outcome for $scenario"
        Assert-True ($script:Violations -eq 0) 'Deletion happened before service stop.'
        if ($scenario -in @('normal','stopped','delete','restart','restart-noop')) { Assert-True ($script:Removed -eq 1) 'Cleanup was not invoked exactly once.' }
        if ($scenario -eq 'stopped') { Assert-True ($script:ServiceStates.wuauserv -eq 'Stopped' -and $script:ServiceStates.bits -eq 'Stopped') 'Initially stopped services were started.' }
        if ($scenario -in @('stop-first','stop-second','non-admin','paused','pending','stop-noop','stop-after-change')) { Assert-True ($script:Removed -eq 0) 'Cleanup continued after guard failure.' }
        if ($scenario -notin @('restart','restart-noop')) { Assert-True ($script:ServiceStates.wuauserv -eq $initial.wuauserv -and $script:ServiceStates.bits -eq $initial.bits) 'Original service states were not restored.' }
        if ($scenario -eq 'restart') {
            $script:ServiceStates = @{ wuauserv = 'Running'; bits = 'Running' }
            function Get-JunkCategories { return , @(@{ Key = 'wu'; Paths = @() }) }
            $partial = Invoke-Maintenance @{ Keys = @('wu'); Confirmed = $true; IsAdmin = $true }
            Assert-True ($partial.Status -eq 'Partial' -and $partial.Bytes -eq 12 -and $partial.Count -eq 1 -and $partial.Errors[0] -match 'restored') 'Restoration failure lost completed deletion counts.'
        }
    }
}
Case 'real synthetic engine preserves links, fresh staging and locked files' {
    $junk = Join-Path $Work 'junk'; $outside = Join-Path $Work 'outside'
    [void][IO.Directory]::CreateDirectory($junk); [void][IO.Directory]::CreateDirectory($outside)
    [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'keep')
    foreach ($name in @('old.tmp','br[a]cket.tmp','Turkish-çöp.tmp','locked.tmp')) { $path = Join-Path $junk $name; [IO.File]::WriteAllText($path,'junk'); [IO.File]::SetLastWriteTime($path,(Get-Date).AddDays(-3)) }
    [IO.File]::WriteAllText((Join-Path $junk 'new.tmp'),'new')
    [void][IO.Directory]::CreateDirectory((Join-Path $junk 'new-staging'))
    $link = Join-Path $junk 'escape'; New-Item -ItemType Junction -Path $link -Target $outside | Out-Null
    Assert-Throws { Assert-CleanupPath $link $Work }
    $held = [IO.File]::Open((Join-Path $junk 'locked.tmp'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
    try { $result = Remove-JunkPaths @(@{ Path = $junk; ApprovedRoot = $Work; Admin = $false; MinAgeHours = 24 }) $false }
    finally { $held.Dispose() }
    foreach ($name in @('old.tmp','br[a]cket.tmp','Turkish-çöp.tmp')) { Assert-True (-not (Test-Path -LiteralPath (Join-Path $junk $name))) 'Reported file was not deleted.' }
    Assert-True ($result.Count -eq 3) 'Old unlocked files were not correctly removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $junk 'new.tmp')) 'Fresh file was removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $junk 'new-staging')) 'Fresh staging directory was removed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $junk 'locked.tmp')) 'Locked file was removed.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq 'keep') 'Junction target was modified.'
    $before = $result.Count
    $adminResult = Remove-JunkPaths @(@{ Path = $outside; ApprovedRoot = $Work; Admin = $true; MinAgeHours = 24 }) $false
    Assert-True ($adminResult.Count -eq 0 -and $adminResult.Skipped -eq 1) 'Non-admin target was deleted.'
    $old2 = Join-Path $junk 'second-old.tmp'; [IO.File]::WriteAllText($old2,'done'); [IO.File]::SetLastWriteTime($old2,(Get-Date).AddDays(-3))
    $partial = Remove-JunkPaths @(@{ Path = $junk; ApprovedRoot = $Work; Admin = $false; MinAgeHours = 24 },@{ Path = $outside; ApprovedRoot = $junk; Admin = $false; MinAgeHours = 24 }) $false
    Assert-True ($partial.Count -eq 2 -and $partial.Errors.Count -eq 1 -and -not (Test-Path -LiteralPath $old2)) 'Rejected later target hid completed deletions.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq 'keep') 'Non-admin cleanup changed sentinel.'
    Assert-True (Test-Path -LiteralPath $link) 'Junction was removed.'
    [IO.Directory]::Delete($link)
}
$summary = @{ cases = $script:Cases.ToArray(); failed = @($script:Cases | Where-Object { -not $_.passed }).Count }
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Work 'contracts.json') -Encoding UTF8
if (-not $KeepArtifacts) { Remove-TestWorkspace $workspace }
Write-Host ('Safety contracts: {0} cases, {1} failed.' -f $script:Cases.Count,$summary.failed)
exit [int]($summary.failed -gt 0)

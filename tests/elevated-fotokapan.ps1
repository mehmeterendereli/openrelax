# Elevated disposable-runner acceptance for the real Fotokapan installer.
# This script intentionally changes only the fixed OpenRelax task/tree on an
# ephemeral Windows host. It is not a Windows Update, RDP, Narrator or DPI test.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TaskName = 'OpenRelax Fotokapan'
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SourceScript = Join-Path $RepositoryRoot 'fotokapan.ps1'
$SourceCore = Join-Path $RepositoryRoot 'lib\OpenRelax.Core.ps1'
$InstallDir = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'OpenRelax\Fotokapan'))
$ExpectedInstallDir = [IO.Path]::GetFullPath((Join-Path $env:ProgramData 'OpenRelax\Fotokapan'))
$InstalledScript = Join-Path $InstallDir 'bin\fotokapan.ps1'
$InstalledCore = Join-Path $InstallDir 'bin\lib\OpenRelax.Core.ps1'
$LogsDir = Join-Path $InstallDir 'logs'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$TempUserName = 'OpenRelaxCI' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$ProbeScript = Join-Path $env:ProgramData ('OpenRelax-AclProbe-' + [Guid]::NewGuid().ToString('N') + '.ps1')
$PasswordText = [Guid]::NewGuid().ToString('N') + 'aA1!'
$SecurePassword = ConvertTo-SecureString $PasswordText -AsPlainText -Force
$Credential = [Management.Automation.PSCredential]::new(("$env:COMPUTERNAME\$TempUserName"),$SecurePassword)
$CreatedTestUser = $false
$ReaderSid = $null
$AdminSid = 'S-1-5-32-544'
$SystemSid = 'S-1-5-18'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TrapTask {
    $tasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop |
        Where-Object { $_.TaskName -eq $TaskName } |
        Select-Object -First 1)
    if ($tasks.Count) { return $tasks[0] }
    return $null
}

function Wait-TrapTaskRunning {
    $deadline = (Get-Date).AddSeconds(20)
    $task = $null
    do {
        $task = Get-TrapTask
        if ($task -and $task.State -eq 'Running') { return $task }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    $state = if ($task) { [string]$task.State } else { 'missing' }
    throw "Fotokapan task did not reach Running state; state=$state"
}

function Invoke-Installer {
    param([ValidateSet('Install','Uninstall')][string]$Mode, [switch]$RecordCommandLines)
    $arguments = @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',$SourceScript,('-' + $Mode)
    )
    if ($Mode -eq 'Install') {
        $arguments += @('-ReaderSid',$ReaderSid)
    }
    if ($RecordCommandLines) { $arguments += '-RecordCommandLines' }
    & $PowerShellExe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Fotokapan $Mode exited $LASTEXITCODE." }
}

function Invoke-ReaderProbe {
    param(
        [ValidateSet('Read','Write','Delete')][string]$Mode,
        [string]$ExpectedSha = ''
    )
    $arguments = @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',$ProbeScript,'-Mode',$Mode,'-Target',$InstalledScript
    )
    if ($ExpectedSha) { $arguments += @('-ExpectedSha',$ExpectedSha) }
    $process = Start-Process -FilePath $PowerShellExe -Credential $Credential -LoadUserProfile `
        -ArgumentList $arguments -PassThru -Wait -WindowStyle Hidden
    Assert-True ($process.ExitCode -eq 0) "Cross-account $Mode probe exited $($process.ExitCode)."
}

function Assert-ProtectedAcl {
    param([string]$Path, [bool]$IsFile = $false)
    Assert-True (Test-Path -LiteralPath $Path) "Protected path missing: $Path"
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    Assert-True ($owner -eq $AdminSid) "Unexpected owner on ${Path}: $owner"
    Assert-True $acl.AreAccessRulesProtected "Inherited ACL remains enabled on $Path"

    $rules = @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
    $unexpected = @($rules | Where-Object {
        $_.IdentityReference.Value -notin @($SystemSid,$AdminSid,$ReaderSid)
    })
    Assert-True ($unexpected.Count -eq 0) "Unexpected principal on $Path"

    $readerRules = @($rules | Where-Object {
        $_.IdentityReference.Value -eq $ReaderSid -and
        $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow
    })
    Assert-True ($readerRules.Count -ge 1) "Reader SID is absent on $Path"

    $readExecute = [Security.AccessControl.FileSystemRights]::ReadAndExecute
    Assert-True (@($readerRules | Where-Object {
        ($_.FileSystemRights -band $readExecute) -eq $readExecute
    }).Count -ge 1) "Reader SID lacks ReadAndExecute on $Path"

    $forbidden = [Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    Assert-True (@($readerRules | Where-Object {
        ($_.FileSystemRights -band $forbidden) -ne 0
    }).Count -eq 0) "Reader SID received write/delete/ownership rights on $Path"
}

$principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
Assert-True $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) 'Elevated Fotokapan acceptance requires an administrator runner.'
Assert-True ($InstallDir.Equals($ExpectedInstallDir,[StringComparison]::OrdinalIgnoreCase)) 'Install cleanup target did not resolve to the fixed OpenRelax path.'
Assert-True (Test-Path -LiteralPath $SourceScript -PathType Leaf) 'Source Fotokapan script is missing.'
Assert-True (Test-Path -LiteralPath $SourceCore -PathType Leaf) 'Source core library is missing.'

$preexistingTask = Get-TrapTask
Assert-True (-not $preexistingTask) 'Refusing to replace a pre-existing OpenRelax Fotokapan task.'
Assert-True (-not (Test-Path -LiteralPath $InstallDir)) 'Refusing to replace a pre-existing Fotokapan tree.'

try {
    $testUser = New-LocalUser -Name $TempUserName -Password $SecurePassword `
        -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword `
        -Description 'Disposable OpenRelax ACL acceptance identity'
    $CreatedTestUser = $true
    $ReaderSid = $testUser.Sid.Value
    Assert-True ($ReaderSid -match '^S-1-5-21-') 'Disposable reader SID is not a local account SID.'
    $adminMembers = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop)
    Assert-True (@($adminMembers | Where-Object { $_.Sid.Value -eq $ReaderSid }).Count -eq 0) 'Disposable reader unexpectedly belongs to Administrators.'

    $probe = @'
param(
    [ValidateSet('Read','Write','Delete')][string]$Mode,
    [string]$Target,
    [string]$ExpectedSha = ''
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Read') {
    if (-not (Test-Path -LiteralPath $Target -PathType Leaf)) { exit 20 }
    if ((Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $ExpectedSha) { exit 21 }
    exit 0
}
if ($Mode -eq 'Write') {
    try {
        $stream = [IO.File]::Open($Target,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $stream.Dispose()
        exit 31
    } catch [UnauthorizedAccessException] {
        exit 0
    } catch {
        exit 32
    }
}
if ($Mode -eq 'Delete') {
    try {
        [IO.File]::Delete($Target)
        exit 41
    } catch [UnauthorizedAccessException] {
        exit 0
    } catch {
        exit 42
    }
}
exit 98
'@
    [IO.File]::WriteAllText($ProbeScript,$probe,[Text.UTF8Encoding]::new($false))

    # A 2.2.x install kept records, log, heartbeat and script in the trap root.
    [void][IO.Directory]::CreateDirectory($LogsDir)
    [IO.File]::WriteAllText((Join-Path $InstallDir 'spikes-2026-10.jsonl'),"{`"t`":`"legacy-1`"}`n{`"t`":`"legacy-2`"}`n")
    [IO.File]::WriteAllText((Join-Path $InstallDir 'durum.json'),'{"t":"legacy"}')
    [IO.File]::WriteAllText((Join-Path $InstallDir 'fotokapan.ps1'),'# 2.2.1 script')
    [IO.File]::WriteAllText((Join-Path $LogsDir 'spikes-2026-10.jsonl'),"{`"t`":`"current-1`"}`n")

    Invoke-Installer Install
    $task = Wait-TrapTaskRunning
    $migrated = @([IO.File]::ReadAllLines((Join-Path $LogsDir 'spikes-2026-10.jsonl')) | Where-Object { $_ -match 'legacy-|current-' })
    Assert-True ($migrated.Count -eq 3 -and $migrated[0] -match 'legacy-1' -and $migrated[2] -match 'current-1') ('Legacy records were not merged: ' + ($migrated -join '|'))
    foreach ($name in 'spikes-2026-10.jsonl','durum.json','fotokapan.ps1') {
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $InstallDir $name))) "Legacy root file remained: $name"
    }
    Assert-ProtectedAcl (Join-Path $LogsDir 'spikes-2026-10.jsonl') $true
    Assert-True ([string]$task.Actions[0].Arguments -notmatch 'RecordCommandLines') 'Command-line recording was enabled without opt-in.'

    $principalId = [string]$task.Principal.UserId
    Assert-True ($principalId -eq $SystemSid -or $principalId -eq 'SYSTEM' -or $principalId -like '*\SYSTEM') "Task principal is not SYSTEM: $principalId"
    Assert-True ([string]$task.Principal.LogonType -eq 'ServiceAccount') 'Task logon type is not ServiceAccount.'
    Assert-True ([string]$task.Principal.RunLevel -eq 'Highest') 'Task does not request Highest run level.'
    Assert-True ($task.Actions.Count -eq 1) 'Task must have exactly one action.'
    $actualExecutable = [IO.Path]::GetFullPath([string]$task.Actions[0].Execute)
    $expectedExecutable = [IO.Path]::GetFullPath($PowerShellExe)
    Assert-True ($actualExecutable.Equals($expectedExecutable,[StringComparison]::OrdinalIgnoreCase)) 'Task action does not use Windows PowerShell 5.1.'
    Assert-True ([string]$task.Actions[0].Arguments -like ('*"' + $InstalledScript + '"*')) 'Task action does not point at the protected installed source.'

    foreach ($directory in @(
        (Split-Path -Parent $InstallDir),$InstallDir,
        (Join-Path $InstallDir 'bin'),(Join-Path $InstallDir 'bin\lib'),$LogsDir
    )) {
        Assert-ProtectedAcl $directory
    }
    Assert-ProtectedAcl $InstalledScript $true
    Assert-ProtectedAcl $InstalledCore $true

    $sourceHash = (Get-FileHash -LiteralPath $SourceScript -Algorithm SHA256).Hash
    $coreHash = (Get-FileHash -LiteralPath $SourceCore -Algorithm SHA256).Hash
    Assert-True ((Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash -eq $sourceHash) 'Installed Fotokapan source differs from the reviewed source.'
    Assert-True ((Get-FileHash -LiteralPath $InstalledCore -Algorithm SHA256).Hash -eq $coreHash) 'Installed core library differs from the reviewed source.'

    # Prove the granted SID from a separate standard-user logon: it can read
    # reviewed source, but Windows itself denies write and delete attempts.
    Invoke-ReaderProbe Read $sourceHash
    Invoke-ReaderProbe Write
    Assert-True ((Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash -eq $sourceHash) 'Cross-account write probe changed protected source.'
    Invoke-ReaderProbe Delete
    Assert-True (Test-Path -LiteralPath $InstalledScript -PathType Leaf) 'Cross-account delete probe removed protected source.'
    Assert-True ((Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash -eq $sourceHash) 'Cross-account delete probe changed protected source.'

    # Exercise the real upgrade path: the existing task must be disabled/stopped,
    # sources replaced atomically, and a fresh SYSTEM task started.
    Invoke-Installer Install -RecordCommandLines
    $task = Wait-TrapTaskRunning
    Assert-True ([string]$task.Actions[0].Arguments -match '\s-RecordCommandLines$') 'The command-line opt-in did not reach the task.'
    Assert-True ((Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash -eq $sourceHash) 'Upgrade changed the installed Fotokapan source.'
    Assert-True ((Get-FileHash -LiteralPath $InstalledCore -Algorithm SHA256).Hash -eq $coreHash) 'Upgrade changed the installed core library.'

    $marker = Join-Path $LogsDir 'acceptance-marker.txt'
    [IO.File]::WriteAllText($marker,'retained')
    Invoke-Installer Uninstall
    Assert-True (-not (Get-TrapTask)) 'Fotokapan task remained registered after uninstall.'
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'Uninstall did not preserve existing logs.'
    Assert-True (Test-Path -LiteralPath $InstalledScript -PathType Leaf) 'Uninstall unexpectedly deleted the retained diagnostic tree.'

    Write-Host 'Elevated Fotokapan acceptance passed: install, SYSTEM task, protected ACL, standard-user enforcement, upgrade and uninstall.'
}
finally {
    $task = Get-TrapTask
    if ($task) {
        Stop-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction Stop
    }
    if (Test-Path -LiteralPath $ProbeScript) {
        Remove-Item -LiteralPath $ProbeScript -Force -ErrorAction Stop
    }
    if ($CreatedTestUser -and (Get-LocalUser -Name $TempUserName -ErrorAction SilentlyContinue)) {
        Remove-LocalUser -Name $TempUserName -ErrorAction Stop
    }
}

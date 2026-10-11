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
$ReaderSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$AdminSid = 'S-1-5-32-544'
$SystemSid = 'S-1-5-18'

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Get-TrapTask {
    @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop |
        Where-Object { $_.TaskName -eq $TaskName } |
        Select-Object -First 1)[0]
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
    param([ValidateSet('Install','Uninstall')][string]$Mode)
    $arguments = @(
        '-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass',
        '-File',$SourceScript,('-' + $Mode),'-ReaderSid',$ReaderSid
    )
    & $PowerShellExe @arguments
    if ($LASTEXITCODE -ne 0) { throw "Fotokapan $Mode exited $LASTEXITCODE." }
}

function Assert-ProtectedAcl {
    param([string]$Path, [bool]$IsFile = $false)
    Assert-True (Test-Path -LiteralPath $Path) "Protected path missing: $Path"
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    Assert-True ($owner -eq $AdminSid) "Unexpected owner on $Path: $owner"
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
    Invoke-Installer Install
    $task = Wait-TrapTaskRunning

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

    # Exercise the real upgrade path: the existing task must be disabled/stopped,
    # sources replaced atomically, and a fresh SYSTEM task started.
    Invoke-Installer Install
    $task = Wait-TrapTaskRunning
    Assert-True ((Get-FileHash -LiteralPath $InstalledScript -Algorithm SHA256).Hash -eq $sourceHash) 'Upgrade changed the installed Fotokapan source.'
    Assert-True ((Get-FileHash -LiteralPath $InstalledCore -Algorithm SHA256).Hash -eq $coreHash) 'Upgrade changed the installed core library.'

    $marker = Join-Path $LogsDir 'acceptance-marker.txt'
    [IO.File]::WriteAllText($marker,'retained')
    Invoke-Installer Uninstall
    Assert-True (-not (Get-TrapTask)) 'Fotokapan task remained registered after uninstall.'
    Assert-True (Test-Path -LiteralPath $marker -PathType Leaf) 'Uninstall did not preserve existing logs.'
    Assert-True (Test-Path -LiteralPath $InstalledScript -PathType Leaf) 'Uninstall unexpectedly deleted the retained diagnostic tree.'

    Write-Host 'Elevated Fotokapan acceptance passed: install, SYSTEM task, protected ACL, upgrade and uninstall.'
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
}

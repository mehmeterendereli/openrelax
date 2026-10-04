# Fotokapan install test
#
# Installs the trap into a throw-away root under a test task name and checks
# that only SYSTEM and Administrators can change what the SYSTEM task runs -
# including an upgrade over the 2.1 layout, where the installing user had Full
# Control - then uninstalls and removes everything. Needs an elevated
# PowerShell.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\trap-install.ps1
param([string]$Root = (Join-Path $env:TEMP ('or-install-' + [guid]::NewGuid().ToString('N').Substring(0, 8))))
$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if (-not $Ok) { $script:failures++ }
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ('[{0}] {1}  {2}' -f $mark, $Name, $Detail)
}
$repo = Split-Path -Parent $PSScriptRoot
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'openrelax.ps1'), [ref]$null, [ref]$null)
$fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-TrapAclWritableByUsers' }, $true))
if (-not $fn.Count) { throw 'Test-TrapAclWritableByUsers was not found in openrelax.ps1' }
. ([scriptblock]::Create($fn[0].Extent.Text))

$installRoot = Join-Path $Root 'OpenRelax'
$dir = Join-Path $installRoot 'Fotokapan'
$task = 'OpenRelax Fotokapan TEST ' + [guid]::NewGuid().ToString('N').Substring(0, 6)
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$trap = Join-Path $repo 'fotokapan.ps1'

# The 2.1 layout: the installing user had Full Control on the folder and its files
New-Item -ItemType Directory -Force -Path $dir | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dir 'fotokapan-2026-01.log'), 'old log')
& icacls.exe $dir /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' "*$($me):(OI)(CI)F" | Out-Null
Check 'precondition: the 2.1 layout is writable by the user' (Test-TrapAclWritableByUsers $dir)

try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $trap -Install -InstallRoot $installRoot -TaskName $task | Out-Null
    Check 'install exits 0' ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
    $t = Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
    Check 'task registered as SYSTEM / Highest / priority 3 / no time limit' ($t -and $t.Principal.UserId -eq 'SYSTEM' -and [string]$t.Principal.RunLevel -eq 'Highest' -and $t.Settings.Priority -eq 3 -and $t.Settings.ExecutionTimeLimit -eq 'PT0S')
    Check 'task logs into its own folder' ($t -and $t.Actions[0].Arguments -match [regex]::Escape($dir)) ($(if ($t) { $t.Actions[0].Arguments }))
    foreach ($p in $installRoot, $dir, (Join-Path $dir 'fotokapan.ps1'), (Join-Path $dir 'fotokapan-2026-01.log')) {
        Check ('not writable by users: ' + $p.Substring($Root.Length)) ((Test-Path -LiteralPath $p) -and -not (Test-TrapAclWritableByUsers $p))
    }
    $userAce = @((Get-Acl -LiteralPath $dir).Access | Where-Object { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $me })
    $rx = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    Check 'installing user can still read the logs' ($userAce.Count -gt 0 -and ($userAce[0].FileSystemRights -band $rx) -eq $rx)
} finally {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $trap -Uninstall -InstallRoot $installRoot -TaskName $task | Out-Null
    Check 'uninstall removes the task' (-not (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue))
    Remove-Item -LiteralPath $Root -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ('Trap install: {0} failure(s)' -f $failures)
exit [int]($failures -gt 0)

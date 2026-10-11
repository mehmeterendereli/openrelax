# OpenRelax engine stress test
#
# Runs the real cleaning engine (functions extracted from openrelax.ps1) in a
# worker runspace, exactly as the GUI does, against a synthetic junk tree full
# of traps: junctions (a loop, and one pointing at a sentinel outside the
# tree), a file held open, files younger than the 24 h temp rule, read-only
# and hidden/system files, bracket and Turkish names, deep nesting and an
# over-long path. Only the synthetic tree under -Work is ever deleted.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\engine-stress.ps1
param(
    [string]$Work = (Join-Path $env:TEMP ('openrelax-engine-stress-' + [guid]::NewGuid().ToString('N').Substring(0, 8))),
    [int]$Dirs = 3000,
    [int]$FilesPerDir = 10
)
$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if (-not $Ok) { $script:failures++ }
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ('[{0}] {1}  {2}' -f $mark, $Name, $Detail)
}

# --- the engine, as injected into GUI workers ---
 . (Join-Path $PSScriptRoot 'test-support.ps1')
$workspace = New-TestWorkspace $Work
$Work = $workspace.Path
$names = 'Test-PathWithin','Assert-NoReparseAncestors','Assert-CleanupPath','Get-SafeTreeEntries','Format-Bytes','Measure-JunkPaths','Remove-JunkPaths'
$engine = Get-TestFunctionSource $names
. ([scriptblock]::Create($engine))

# --- synthetic tree ---
$junk = Join-Path $Work 'junk'
$sentinelDir = Join-Path $Work 'sentinel'
$old = (Get-Date).AddDays(-3)
function New-OldFile([string]$Path) {
    [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [System.IO.File]::WriteAllText($Path, 'junk')
    [System.IO.File]::SetLastWriteTime($Path, $old)
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$payload = New-Object byte[] 512
$grid = 0
for ($d = 0; $d -lt $Dirs; $d++) {
    $dir = Join-Path $junk ('d{0:D2}\s{1:D4}' -f ($d % 50), $d)
    [void][System.IO.Directory]::CreateDirectory($dir)
    for ($f = 0; $f -lt $FilesPerDir; $f++) {
        $p = Join-Path $dir ('f{0}.tmp' -f $f)
        [System.IO.File]::WriteAllBytes($p, $payload)
        [System.IO.File]::SetLastWriteTime($p, $old)
        $grid++
    }
}
New-OldFile (Join-Path $sentinelDir 'keep.txt')
New-Item -ItemType Junction -Path (Join-Path $junk 'escape') -Target $sentinelDir | Out-Null
New-Item -ItemType Junction -Path (Join-Path $junk 'd00\loop') -Target $junk | Out-Null
$youngDir = [System.IO.Directory]::CreateDirectory((Join-Path $junk 'young')).FullName
1..20 | ForEach-Object { [System.IO.File]::WriteAllText((Join-Path $youngDir "y$_.txt"), 'new') }
New-OldFile (Join-Path $junk 'attrs\readonly.txt')
[System.IO.File]::SetAttributes((Join-Path $junk 'attrs\readonly.txt'), 'ReadOnly')
New-OldFile (Join-Path $junk 'attrs\hidden.txt')
[System.IO.File]::SetAttributes((Join-Path $junk 'attrs\hidden.txt'), 'Hidden, System')
New-OldFile (Join-Path $junk 'br[a]cket\file[1].txt')
New-OldFile (Join-Path $junk 'Türkçe çöp\ğüşıöç İ.txt')
$deep = $junk
1..60 | ForEach-Object { $deep = Join-Path $deep "n$_" }
New-OldFile (Join-Path $deep 'deep.txt')
New-OldFile (Join-Path $junk 'locked\held.bin')
$specials = 6   # readonly, hidden, bracket, Turkish, deep, locked
# Over-long path (> 260 chars): created through the \\?\ prefix
$longDir = '\\?\' + (Join-Path $junk ('long\' + ((('x' * 60) + '\') * 5)))
$longOk = $true
try {
    [void][System.IO.Directory]::CreateDirectory($longDir)
    [System.IO.File]::WriteAllText($longDir + 'long.txt', 'junk')
    [System.IO.File]::SetLastWriteTime($longDir + 'long.txt', $old)
} catch { $longOk = $false }
Write-Host ('Tree: {0:N0} grid files + {1} specials, built in {2:N1} s (long path: {3})' -f $grid, $specials, $sw.Elapsed.TotalSeconds, $longOk)

# --- measure: unbounded and budgeted ---
$sw.Restart()
$m = Measure-JunkPaths -Paths @(@{ Path = $junk; ApprovedRoot = $Work; Admin = $false; MinAgeHours = 24 }) -IsAdmin:$true
$measureSec = $sw.Elapsed.TotalSeconds
Check 'measure counts every old file, skips young files and junction targets' (($m.Count -eq ($grid + $specials)) -or ($m.Count -eq ($grid + $specials + 1))) ('{0:N0} counted, {1:N0}(+1 long) expected, {2:N1} s' -f $m.Count, ($grid + $specials), $measureSec)
Check 'unbounded measure is not partial' (-not $m.Partial)
$sw.Restart()
$mb = Measure-JunkPaths -Paths @(@{ Path = $junk; ApprovedRoot = $Work; Admin = $false; MinAgeHours = 24 }) -IsAdmin:$true -BudgetSec 1
Check 'budgeted measure stops on time or completes the small fixture' (($mb.Partial -or $mb.Count -eq $m.Count) -and $sw.Elapsed.TotalSeconds -lt 4) ('{0:N1} s, {1:N0} files seen' -f $sw.Elapsed.TotalSeconds, $mb.Count)

# --- remove in a worker runspace, with a file held open ---
$held = [System.IO.File]::Open((Join-Path $junk 'locked\held.bin'), 'Open', 'Read', 'None')
$Sync = [hashtable]::Synchronized(@{})
$Sync.Beat = [DateTime]::UtcNow
$rs = [runspacefactory]::CreateRunspace(); $rs.ApartmentState = 'MTA'; $rs.Open()
$ps = [powershell]::Create(); $ps.Runspace = $rs
[void]$ps.AddScript($engine)
[void]$ps.AddStatement().AddScript('param($Sync, $Paths) $Sync.Result = Remove-JunkPaths -Paths $Paths -IsAdmin:$true').
    AddArgument($Sync).AddArgument(@(@{ Path = $junk; ApprovedRoot = $Work; Admin = $false; MinAgeHours = 24 }))
$me = [System.Diagnostics.Process]::GetCurrentProcess()
$memBefore = $me.PrivateMemorySize64
$memPeak = $memBefore
$maxGap = 0.0
$sw.Restart()
$h = $ps.BeginInvoke()
while (-not $h.IsCompleted -and $sw.Elapsed.TotalMinutes -lt 10) {
    Start-Sleep -Milliseconds 250
    $gap = ([DateTime]::UtcNow - [DateTime]$Sync.Beat).TotalSeconds
    if ($gap -gt $maxGap) { $maxGap = $gap }
    $me.Refresh()
    if ($me.PrivateMemorySize64 -gt $memPeak) { $memPeak = $me.PrivateMemorySize64 }
}
$removeSec = $sw.Elapsed.TotalSeconds
$completed = $h.IsCompleted
if ($completed) { [void]$ps.EndInvoke($h) }
$held.Dispose()
Check 'worker finished' $completed ('{0:N1} s' -f $removeSec)
Check 'worker raised no errors' (-not $ps.HadErrors) (($ps.Streams.Error | Select-Object -First 2) -join '; ')
$r = $Sync.Result
Check 'deleted every old unlocked file' ($r.Count -ge ($grid + $specials - 1)) ('{0:N0} deleted, {1:N0} expected' -f $r.Count, ($grid + $specials - 1))
Check 'progress beats never paused > 10 s (watchdog allows 60 s)' ($maxGap -lt 10) ('longest gap {0:N1} s' -f $maxGap)
Check 'memory stays bounded while streaming' (($memPeak - $memBefore) -lt 150MB) ('peak +{0:N0} MB' -f (($memPeak - $memBefore) / 1MB))
Check 'sentinel behind a junction survived' (Test-Path -LiteralPath (Join-Path $sentinelDir 'keep.txt'))
Check 'junctions left in place' ((Test-Path -LiteralPath (Join-Path $junk 'escape')) -and (Test-Path -LiteralPath (Join-Path $junk 'd00\loop')))
Check 'young files kept (24 h rule)' (@(Get-ChildItem -LiteralPath $youngDir -File).Count -eq 20)
Check 'locked file skipped, not crashed on' (Test-Path -LiteralPath (Join-Path $junk 'locked\held.bin'))
Check 'read-only and hidden/system files deleted' (-not (Test-Path -LiteralPath (Join-Path $junk 'attrs\readonly.txt')) -and -not (Test-Path -LiteralPath (Join-Path $junk 'attrs\hidden.txt')))
Check 'bracket and Turkish files deleted' (-not (Test-Path -LiteralPath (Join-Path $junk 'br[a]cket\file[1].txt')) -and -not (Test-Path -LiteralPath (Join-Path $junk 'Türkçe çöp\ğüşıöç İ.txt')))
Check 'temporary staging directories retained' ((Test-Path -LiteralPath (Join-Path $junk 'n1')) -and (Test-Path -LiteralPath (Join-Path $junk 'br[a]cket')))
if ($longOk) {
    $longLeft = [System.IO.File]::Exists($longDir + 'long.txt')
    $outcome = 'reached and deleted'
    if ($longLeft) { $outcome = 'not reachable here (no long-path support), left in place without aborting the run' }
    Write-Host ('[INFO] over-long path (> 260 chars): {0}' -f $outcome)
}
$ps.Dispose(); $rs.Dispose()

# --- cleanup: drop the junctions first so nothing can be followed ---
foreach ($j in (Join-Path $junk 'escape'), (Join-Path $junk 'd00\loop')) {
    if (Test-Path -LiteralPath $j) { [System.IO.Directory]::Delete($j) }
}
Assert-TestFixture $Work
Assert-NoReparseAncestors $Work
$marker = Get-Content -LiteralPath (Join-Path $Work '.openrelax-test-workspace') -Raw -Encoding UTF8 | ConvertFrom-Json
if ($marker.owner -ne $workspace.Owner) { throw 'Extended-path workspace ownership changed.' }
$walk = @{ Partial = $false; Skipped = 0; ErrorCount = 0; Errors = @() }
[void]@(Get-SafeTreeEntries $Work $walk)
if ($walk.Skipped -or $walk.ErrorCount) { throw 'Unsafe/unreadable extended workspace; cleanup refused.' }
# Explicitly created junctions were removed above; this extended path reaches test-created long entries.
[System.IO.Directory]::Delete('\\?\' + $Work, $true)

Write-Host ('Engine stress: {0} failure(s); measure {1:N1} s, remove {2:N1} s for {3:N0} files' -f $failures, $measureSec, $removeSec, $grid)
exit [int]($failures -gt 0)

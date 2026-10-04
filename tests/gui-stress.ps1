# OpenRelax GUI stress test
#
# 1. Stress run: starts the app with OPENRELAX_STRESS so it drives its own
#    click handlers for -Cycles cycles (see "GUI stress support" in
#    openrelax.ps1), then checks the report for errors, handle/GDI/USER and
#    memory leaks, and a clean self-exit.
# 2. Launch storm: starts and auto-closes the app -Launches times in a row.
# Nothing is cleaned and no setting is saved. The window shows while it runs.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\gui-stress.ps1
param(
    [int]$Cycles = 60,
    [int]$Launches = 5,
    [string]$Work = (Join-Path $env:TEMP ('openrelax-gui-stress-' + [guid]::NewGuid().ToString('N').Substring(0, 8)))
)
$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if (-not $Ok) { $script:failures++ }
    $mark = 'PASS'
    if (-not $Ok) { $mark = 'FAIL' }
    Write-Host ('[{0}] {1}  {2}' -f $mark, $Name, $Detail)
}

$app = Join-Path (Split-Path -Parent $PSScriptRoot) 'openrelax.ps1'
New-Item -ItemType Directory -Path $Work -Force | Out-Null
$report = Join-Path $Work 'gui-report.json'
$appArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"{0}"' -f $app))

# --- synthetic Fotokapan data: 300 episodes over 6 days (drivers, Defender
# scan/real-time, cut-off episodes) so the view re-renders full lists every cycle ---
$trapDir = Join-Path $Work 'trap'
New-Item -ItemType Directory -Path $trapDir -Force | Out-Null
$procNames = 'MsMpEng.exe', 'codex.exe', 'python.exe', 'chrome.exe', 'java.exe', 'TFTClient-Win64-Shipping.exe'
$sb = New-Object System.Text.StringBuilder
$t0 = (Get-Date).AddDays(-6)
[void]$sb.Append((ConvertTo-Json -Compress -InputObject ([ordered]@{ t = $t0.ToString('s'); kind = 'monitor'; version = '2.1'; threshold = 85; pid = 1 }))).Append("`n")
for ($i = 0; $i -lt 300; $i++) {
    $t = $t0.AddMinutes($i * 28)
    $name = $procNames[$i % $procNames.Count]
    $attributed = 90
    if (($i % 17) -eq 0) { $attributed = 30 }   # mostly interrupts/DPC -> "drivers"
    $defender = $null
    if ($name -eq 'MsMpEng.exe') { $defender = @('scan', 'realtime')[$i % 2] }
    $top = @([ordered]@{ name = $name; pid = 1000 + $i; pct = 40 + ($i % 50); parent = 'services.exe'; cmd = "$name --synthetic" })
    [void]$sb.Append((ConvertTo-Json -Compress -Depth 5 -InputObject ([ordered]@{ t = $t.ToString('s'); kind = 'start'; window = 2.0; total = 98; attributed = $attributed; top = $top; defender = $defender }))).Append("`n")
    if (($i % 23) -ne 0) {   # every 23rd episode never ends -> shown as cut off
        [void]$sb.Append((ConvertTo-Json -Compress -InputObject ([ordered]@{ t = $t.AddSeconds(12).ToString('s'); kind = 'end'; durationSec = 12 + ($i % 40); peak = 90 + ($i % 10) }))).Append("`n")
    }
}
[System.IO.File]::WriteAllText((Join-Path $trapDir ('spikes-{0:yyyy-MM}.jsonl' -f (Get-Date))), $sb.ToString())
[System.IO.File]::WriteAllText((Join-Path $trapDir 'durum.json'), (ConvertTo-Json -Compress -InputObject ([ordered]@{ t = (Get-Date).ToString('s'); cpu = 12; spikes = 3; inSpike = $false; threshold = 85; version = '2.1'; pid = 1; started = $t0.ToString('s') })))

# --- 1. stress run ---
$env:OPENRELAX_STRESS = [string]$Cycles
$env:OPENRELAX_STRESS_REPORT = $report
$env:OPENRELAX_TRAP_DIR = $trapDir
try {
    $p = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList $appArgs `
        -RedirectStandardError (Join-Path $Work 'stderr.txt') -RedirectStandardOutput (Join-Path $Work 'stdout.txt')
} finally {
    Remove-Item Env:\OPENRELAX_STRESS, Env:\OPENRELAX_STRESS_REPORT, Env:\OPENRELAX_TRAP_DIR -ErrorAction SilentlyContinue
}
$exited = $p.WaitForExit(15 * 60 * 1000)
if (-not $exited) { try { $p.Kill() } catch {} }
Check 'app finished the stress run and closed itself' $exited
Check 'report written' (Test-Path -LiteralPath $report)
function Read-Text([string]$Path) {
    $t = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    if ($null -eq $t) { return '' }   # -Raw yields nothing at all for an empty file
    return ([string]$t).Trim()
}
$stderr = Read-Text (Join-Path $Work 'stderr.txt')
Check 'nothing on stderr' ($stderr.Length -eq 0) $stderr
if (Test-Path -LiteralPath $report) {
    $r = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
    Check 'no handler exceptions' (@($r.errors).Count -eq 0) ((@($r.errors) | Select-Object -First 3) -join ' | ')
    Check 'no error lines logged' ($r.logErrors -eq 0 -and -not $r.tickError) ('logErrors={0} tickError={1}' -f $r.logErrors, $r.tickError)
    if ($Cycles -ge 30) {   # shorter runs end before the startup scan frees the worker
        Check 'junk scans ran in the worker alongside the UI' ($r.scans -ge 2) ('{0} scans' -f $r.scans)
    }
    Check 'no worker left running at exit' (-not $r.busyAtEnd)
    $samples = @($r.samples)
    $warm = @($samples | Where-Object { $_.cycle -ge 10 })
    if ($warm.Count -ge 2) {
        $a = $warm[0]; $z = $warm[$warm.Count - 1]
        Check 'GDI objects do not leak' (($z.gdi - $a.gdi) -le 25) ('{0} -> {1}' -f $a.gdi, $z.gdi)
        Check 'USER objects do not leak' (($z.user - $a.user) -le 25) ('{0} -> {1}' -f $a.user, $z.user)
        Check 'handles do not leak' (($z.handles - $a.handles) -le 200) ('{0} -> {1}' -f $a.handles, $z.handles)
        Check 'memory does not grow unbounded' (($z.privateMB - $a.privateMB) -le 80) ('{0:N0} -> {1:N0} MB' -f $a.privateMB, $z.privateMB)
    }
    Write-Host ('Stress run: {0} cycles, {1} scans in {2:N0} s' -f $r.cycles, $r.scans, $r.seconds)
    Get-ChildItem -LiteralPath $Work -Filter 'stress-trap-*.png' | ForEach-Object { Write-Host ('Snapshot: {0}' -f $_.FullName) }
}

# --- 2. launch storm ---
$env:OPENRELAX_SMOKETEST = '1'
try {
    for ($i = 1; $i -le $Launches; $i++) {
        $err = Join-Path $Work "launch-$i-stderr.txt"
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $q = Start-Process powershell -PassThru -WindowStyle Hidden -ArgumentList $appArgs -RedirectStandardError $err -RedirectStandardOutput (Join-Path $Work "launch-$i-stdout.txt")
        $ok = $q.WaitForExit(60000)
        if (-not $ok) { try { $q.Kill() } catch {} }
        $e = Read-Text $err
        Check ('launch {0}: starts, auto-closes, clean stderr' -f $i) ($ok -and $e.Length -eq 0) ('{0:N1} s {1}' -f $sw.Elapsed.TotalSeconds, $e)
    }
} finally {
    Remove-Item Env:\OPENRELAX_SMOKETEST -ErrorAction SilentlyContinue
}

Write-Host ('GUI stress: {0} failure(s); artifacts in {1}' -f $failures, $Work)
exit [int]($failures -gt 0)

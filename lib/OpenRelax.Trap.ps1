# Fotokapan (CPU spike trap) records: reading, episodes, culprits, diagnosis,
# report and notification rules. Pure functions apart from file reads; the
# GUI strings come from T in openrelax.ps1. Windows PowerShell 5.1.

# The trap appends to / swaps these files while we read them: share everything.
function Read-SharedText([string]$Path) {
    $fs = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]'ReadWrite, Delete')
    try {
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
        return $sr.ReadToEnd()
    } finally {
        $fs.Dispose()
    }
}

# Records of the last $Days days, oldest first. Parsed files are cached by
# length, so a refresh with no new spikes costs a stat call per file.
function Read-TrapRecords {
    # -LegacyDir: a 2.2.x trap wrote to its root until an install moves the
    # files into logs\; its records are older, so they are read first.
    param([string]$Dir = $script:TrapDir, [int]$Days = 7, [string]$LegacyDir = '')
    $cutoff = (Get-Date).AddDays(-$Days).ToString('s')
    $all = New-Object System.Collections.Generic.List[object]
    $dirs = @($Dir)
    if ($LegacyDir -and -not $LegacyDir.TrimEnd('\').Equals($Dir.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) { $dirs = @($LegacyDir, $Dir) }
    foreach ($month in @((Get-Date).AddMonths(-1), (Get-Date))) { foreach ($monthDir in $dirs) {
        $path = Join-Path $monthDir ('spikes-{0:yyyy-MM}.jsonl' -f $month)
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $len = (Get-Item -LiteralPath $path).Length
        $c = $script:TrapCache[$path]
        if (-not $c -or $c.Length -ne $len) {
            $items = New-Object System.Collections.Generic.List[object]
            # Old lines are skipped by their ISO timestamp prefix without being
            # parsed; a line still being appended has no closing brace yet.
            $lines = @((Read-SharedText $path) -split "`n" | Where-Object {
                $_.Length -gt 25 -and $_.StartsWith('{"t":"') -and $_.TrimEnd().EndsWith('}') -and $_.Substring(6, 19) -ge $cutoff })
            if ($lines.Count) {
                try {
                    foreach ($r in ('[' + ($lines -join ',') + ']' | ConvertFrom-Json)) { $items.Add($r) }
                } catch {
                    # A damaged line spoils the batch parse: fall back to line by line.
                    $items.Clear()
                    foreach ($l in $lines) { try { $items.Add(($l | ConvertFrom-Json)) } catch {} }
                }
            }
            $c = @{ Length = $len; Items = $items }
            $script:TrapCache[$path] = $c
        }
        foreach ($r in $c.Items) { if ([string]$r.t -ge $cutoff) { $all.Add($r) } }
    } }
    return , $all
}

# Pairs start/end records into episodes. A 'monitor' record (trap restarted)
# or a new start closes an episode whose end was never written.
function Get-TrapEpisodes {
    param($Records)
    $episodes = New-Object System.Collections.Generic.List[object]
    $open = $null
    foreach ($r in $Records) {
        switch ([string]$r.kind) {
            'start' {
                if ($open) { $open.Cut = $true }
                $open = @{ Start = $r; Duration = $null; Peak = $null; Cut = $false; Defender = $r.defender }
                $episodes.Add($open)
            }
            'ongoing' { if ($open -and -not $open.Defender) { $open.Defender = $r.defender } }
            'end'     { if ($open) { $open.Duration = $r.durationSec; $open.Peak = $r.peak; $open = $null } }
            'monitor' { if ($open) { $open.Cut = $true; $open = $null } }
        }
    }
    return , $episodes
}

# The main culprit of an episode: its top process, unless CPU time that no
# process accounts for (exited/unreadable processes or interrupts/DPCs) outweighs it.
function Get-TrapCulprit($Start) {
    $top = @($Start.top | Where-Object { $_ })
    # Embedded records (2.4+) measure interrupt and DPC time: a share of at
    # least 10 % that outweighs the top process is driver load, with evidence.
    $driver = 0.0
    foreach ($field in 'dpc','interrupt') {
        $has = if ($Start -is [System.Collections.IDictionary]) { $Start.Contains($field) } else { [bool]$Start.PSObject.Properties[$field] }
        if ($has) { $driver += [double]$Start.$field }
    }
    $topPct = 0.0
    if ($top.Count) { $topPct = [double]$top[0].pct }
    if ($driver -ge 10 -and $driver -ge $topPct) { return @{ Name = '*dpc*'; Pct = $driver } }
    $unattributed = [double]$Start.total - [double]$Start.attributed
    if ($top.Count -eq 0 -or $unattributed -gt [double]$top[0].pct) {
        return @{ Name = '*unattributed*'; Pct = [Math]::Max(0, $unattributed) }
    }
    return @{ Name = [string]$top[0].name; Pct = [double]$top[0].pct }
}

function Get-TrapCulprits {
    param($Episodes)
    $by = @{}
    foreach ($ep in $Episodes) {
        $c = Get-TrapCulprit $ep.Start
        $e = $by[$c.Name]
        if (-not $e) { $e = @{ Name = $c.Name; Count = 0; Sum = 0.0; Last = '' }; $by[$c.Name] = $e }
        $e.Count++
        $e.Sum += $c.Pct
        if ([string]$ep.Start.t -gt $e.Last) { $e.Last = [string]$ep.Start.t }
    }
    return @($by.Values | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Sum }; Descending = $true })
}

function ConvertFrom-TrapTime([string]$Iso) {
    return [datetime]::ParseExact($Iso, 's', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Display name of a culprit. Unattributed CPU (interrupts/DPC, exited or
# unreadable processes) was recorded as '*drivers*' before 2.3.
function Get-TrapCulpritText([string]$Name) {
    if ($Name -eq '*dpc*') { return (T 'trapDpc') }
    if ($Name -in @('*drivers*','*unattributed*')) { return (T 'trapDrivers') }
    return $Name
}

# Coarse category of a culprit process, matched by name (wildcards allowed).
# The lists stay short on purpose: unknown names are simply 'other'.
function Get-TrapCategory([string]$Name) {
    $map = [ordered]@{
        defender = 'MsMpEng.exe', 'MpDefenderCoreService.exe', 'NisSrv.exe', 'MsSense.exe', 'MpCmdRun.exe', 'SecurityHealthService.exe'
        game     = '*Shipping.exe', 'League of Legends.exe', 'LeagueClient*.exe', 'TFTClient*.exe', 'Riot*.exe', 'vgc.exe', 'VALORANT*.exe',
                   'steam.exe', 'steamwebhelper.exe', 'EpicGamesLauncher.exe', 'cs2.exe', 'dota2.exe', 'HD-Player.exe', 'Bluestacks*.exe'
        devtools = 'node.exe', 'python*.exe', 'py.exe', 'java.exe', 'javaw.exe', 'gradle*.exe', 'dotnet.exe', 'MSBuild.exe', 'VBCSCompiler.exe',
                   'cl.exe', 'link.exe', 'rustc.exe', 'cargo.exe', 'go.exe', 'git.exe', 'pwsh.exe', 'powershell.exe', 'codex*.exe', 'claude.exe',
                   'ChatGPT.exe', 'Code.exe', 'devenv.exe', 'idea64.exe', 'studio64.exe', 'Docker*.exe', 'com.docker*.exe', 'vmmem*', 'wsl*.exe',
                   'bun.exe', 'deno.exe', 'esbuild.exe', 'tsc.exe'
        browser  = 'chrome.exe', 'msedge.exe', 'msedgewebview2.exe', 'firefox.exe', 'brave.exe', 'opera.exe', 'vivaldi.exe'
        windows  = 'System', 'Registry', 'MemCompression', 'svchost.exe', 'TiWorker.exe', 'TrustedInstaller.exe', 'MoUsoCoreWorker.exe',
                   'wuauclt.exe', 'SearchIndexer.exe', 'SearchProtocolHost.exe', 'SearchFilterHost.exe', 'CompatTelRunner.exe', 'WmiPrvSE.exe',
                   'dwm.exe', 'explorer.exe', 'sihost.exe', 'RuntimeBroker.exe', 'audiodg.exe', 'lsass.exe', 'csrss.exe', 'services.exe',
                   'dllhost.exe', 'taskhostw.exe', 'msiexec.exe'
    }
    foreach ($cat in $map.Keys) {
        foreach ($pattern in $map[$cat]) { if ($Name -like $pattern) { return $cat } }
    }
    return 'other'
}

# Started by Task Scheduler. 2.3 records carry the recorder's decision as
# 'scheduled'; 2.2 records carry the parent and its command line instead.
function Test-TrapScheduled($Top) {
    if (-not $Top) { return $false }
    if ($Top.PSObject.Properties['scheduled']) { return [bool]$Top.scheduled }
    $parent = ''; $parentCmd = ''
    if ($Top.PSObject.Properties['parent']) { $parent = [string]$Top.parent }
    if ($Top.PSObject.Properties['parentCmd']) { $parentCmd = [string]$Top.parentCmd }
    if ($parent -eq 'taskhostw.exe') { return $true }
    return ($parent -eq 'svchost.exe' -and $parentCmd -match '\s-s\s+Schedule\b')
}

# Turns episodes into findings: one per culprit category (count, share of all
# spikes, most frequent process) plus one for spikes started by scheduled
# tasks. A Defender finding says whether on-demand scans or real-time
# scanning dominate and names the folder Defender scanned most. CPU that no
# recorded process accounts for is reported as such, never as "a driver".
function Get-TrapDiagnosis {
    param($Episodes)
    $findings = New-Object System.Collections.Generic.List[object]
    # .Count, not @($Episodes).Count: PS 5.1 throws "Argument types do not
    # match" for @() around a List[object] variable
    $total = 0
    if ($Episodes) { $total = $Episodes.Count }
    if ($total -eq 0) { return }   # findings go to the pipeline: callers collect with @()
    $groups = @{}; $scheduled = @{}; $scheduledCount = 0; $defScan = 0; $defFolder = ''
    foreach ($ep in $Episodes) {
        $c = Get-TrapCulprit $ep.Start
        if ($c.Name -eq '*dpc*') { $cat = 'drivers' }
        elseif ($c.Name -in @('*unattributed*','*drivers*')) { $cat = 'unattributed' }
        else { $cat = Get-TrapCategory $c.Name }
        if (-not $groups.ContainsKey($cat)) { $groups[$cat] = @{ Count = 0; Names = @{} } }
        $groups[$cat].Count++
        $groups[$cat].Names[$c.Name] = 1 + [int]$groups[$cat].Names[$c.Name]
        $top0 = @($ep.Start.top | Where-Object { $_ }) | Select-Object -First 1
        if (Test-TrapScheduled $top0) {
            $scheduledCount++
            $scheduled[[string]$top0.name] = 1 + [int]$scheduled[[string]$top0.name]
        }
        if ($cat -eq 'defender') {
            if ($ep.Defender -eq 'scan') { $defScan++ }
            if ($ep.Start.PSObject.Properties['defenderTop'] -and $ep.Start.defenderTop -and @($ep.Start.defenderTop.folders).Count) {
                $defFolder = [string]@($ep.Start.defenderTop.folders)[0].path
            }
        }
    }
    foreach ($cat in $groups.Keys) {
        $g = $groups[$cat]
        $key = 'diag_' + $cat; $detail = ''
        if ($cat -eq 'defender') {
            if ($defScan * 2 -ge $g.Count) { $key = 'diag_defender_scan' } else { $key = 'diag_defender_rt'; $detail = $defFolder }
        }
        $findings.Add(@{ Category = $cat; Key = $key; Count = $g.Count; Share = [int][Math]::Round(100.0 * $g.Count / $total)
            Top = ($g.Names.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key; Detail = $detail })
    }
    if ($scheduledCount -gt 0) {
        $findings.Add(@{ Category = 'scheduled'; Key = 'diag_scheduled'; Count = $scheduledCount; Share = [int][Math]::Round(100.0 * $scheduledCount / $total)
            Top = ($scheduled.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key; Detail = '' })
    }
    return $findings | Sort-Object -Property @{ Expression = { $_.Count }; Descending = $true }, @{ Expression = { $_.Category } }
}

function Format-TrapFinding($Finding) {
    $detail = [string]$Finding.Detail
    if (-not $detail) { $detail = (T 'diagUnknownFolder') }
    return [string]::Format((T $Finding.Key), $Finding.Share, (Get-TrapCulpritText $Finding.Top), $detail, $Finding.Count)
}

# Spike starts per hour of the day (local time) - periodic jobs stand out.
function Get-TrapHourHistogram {
    param($Episodes)
    $h = New-Object int[] 24
    foreach ($ep in $Episodes) { $h[(ConvertFrom-TrapTime ([string]$ep.Start.t)).Hour]++ }
    return , $h
}

# Markdown summary of the last 7 days for sharing: status, diagnosis, the
# culprit table and every spike. Cells escape '|' so names cannot break rows.
function Format-TrapReport($State, $Episodes) {
    $esc = { param($s) ([string]$s) -replace '\|', '\|' }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# ' + (T 'reportTitle'))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine([string]::Format((T 'reportGenerated'), (Get-Date).ToString('yyyy-MM-dd HH:mm'), $script:AppVersion))
    $stateKey = 'trapStMissing'
    if ($State.Installed) {
        if ($State.Outdated) { $stateKey = 'trapStOutdated' }
        elseif ($State.Running) { $stateKey = 'trapStRunning' }
        else { $stateKey = 'trapStStopped' }
    }
    [void]$sb.AppendLine([string]::Format((T 'reportStatus'), (T $stateKey), $State.Threshold))
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## ' + (T 'reportDiagnosis'))
    $findings = @(Get-TrapDiagnosis $Episodes)
    if (-not $findings.Count) { [void]$sb.AppendLine('- ' + (T 'diag_none')) }
    foreach ($f in $findings) { [void]$sb.AppendLine('- ' + (Format-TrapFinding $f)) }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## ' + (T 'reportTop'))
    [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f (T 'colProcess'), (T 'colSpikes'), (T 'colAvg'), (T 'colLast')))
    [void]$sb.AppendLine('|---|---:|---:|---|')
    foreach ($c in (Get-TrapCulprits $Episodes)) {
        [void]$sb.AppendLine(('| {0} | {1} | {2:N0}% | {3} |' -f (& $esc (Get-TrapCulpritText $c.Name)), $c.Count, ($c.Sum / $c.Count), (ConvertFrom-TrapTime $c.Last).ToString('dd.MM HH:mm')))
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('## ' + (T 'reportRecent'))
    [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} |' -f (T 'colTime'), (T 'colDur'), (T 'colPeak'), (T 'colCulprit')))
    [void]$sb.AppendLine('|---|---:|---:|---|')
    $n = 0
    if ($Episodes) { $n = $Episodes.Count }
    for ($i = $n - 1; $i -ge 0; $i--) {
        $ep = $Episodes[$i]
        $c = Get-TrapCulprit $ep.Start
        $dur = (T 'trapCut')
        if ($ep.ContainsKey('Duration') -and $null -ne $ep.Duration) { $dur = [string]::Format((T 'trapSec'), $ep.Duration) }
        $peak = ''
        if ($ep.ContainsKey('Peak') -and $null -ne $ep.Peak) { $peak = '{0}%' -f $ep.Peak }
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} {4:N0}% |' -f (ConvertFrom-TrapTime $ep.Start.t).ToString('dd.MM HH:mm'), $dur, $peak, (& $esc (Get-TrapCulpritText $c.Name)), $c.Pct))
    }
    return $sb.ToString()
}

function Save-TrapReport([string]$Text, [string]$Folder = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'OpenRelax')) {
    [void][IO.Directory]::CreateDirectory($Folder)
    $path = Join-Path $Folder ('fotokapan-rapor-{0:yyyyMMdd-HHmmss}.md' -f (Get-Date))
    [System.IO.File]::WriteAllText($path, $Text, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

# Decides whether the newest spike should be announced: never the history
# found on the first look, never the same spike twice, at most one balloon
# per 15 minutes (the baseline still advances, so nothing queues up).
function Get-TrapNotification {
    param($Records, $LastT, [datetime]$LastAt, [datetime]$Now)
    $last = $null
    $n = 0
    if ($Records) { $n = $Records.Count }
    for ($i = $n - 1; $i -ge 0; $i--) {
        if ([string]$Records[$i].kind -eq 'start') { $last = $Records[$i]; break }
    }
    if (-not $last) { return @{ Show = $false; LastT = $LastT; Record = $null } }
    $t = [string]$last.t
    if ($null -eq $LastT) { return @{ Show = $false; LastT = $t; Record = $null } }
    if ($t -le [string]$LastT) { return @{ Show = $false; LastT = $LastT; Record = $null } }
    return @{ Show = (($Now - $LastAt).TotalMinutes -ge 15); LastT = $t; Record = $last }
}

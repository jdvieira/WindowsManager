# Windows Manager - Worker (part of src\; see Windows_Manager.ps1)

# Runs in its own runspace and talks to the window only through $Sync.Events (a thread-safe queue the window drains
# on a timer), so the UI never blocks on winget. 'scan' lists the upgrades; 'upgrade' works through $Sync.Jobs.
$WorkerScript = @'
param($Sync, $Op, $Winget, $Arg)
$ErrorActionPreference = 'Stop'

function Send($Ev) { $Sync.Events.Enqueue($Ev) }
function Write-Log([string]$Text) {
    Send @{ T = 'log'; Text = $Text }
    try { [IO.File]::AppendAllText($Sync.LogFile, ('{0:HH:mm:ss}  {1}{2}' -f (Get-Date), $Text, "`r`n")) } catch { }
}
function Get-Hex([int]$Code) { '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes($Code), 0) }

# winget redraws spinners and progress bars with carriage returns; ReadLine turns each frame into its own line.
function Test-Noise([string]$Line) {
    $t = $Line.Trim()
    return (-not $t) -or ($t -match '^[-\\|/]$') -or ($Line -match '[\u2588\u2592]')
}

function Invoke-Winget {
    param([string[]]$ArgumentList, [scriptblock]$OnLine, [switch]$Quiet)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Winget
    $psi.Arguments = ($ArgumentList | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    if (-not $Quiet) { Write-Log "> winget $($psi.Arguments)" }
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Close()
        $stderr = $p.StandardError.ReadToEndAsync()
        while ($null -ne ($line = $p.StandardOutput.ReadLine())) { $null = & $OnLine $line }
        $p.WaitForExit()
        foreach ($line in ($stderr.Result -split "`r?`n")) { if ($line.Trim()) { $null = & $OnLine $line } }
        return $p.ExitCode
    }
    finally { $p.Dispose() }
}

# winget pads its table by display width, so East Asian wide characters count as two cells and combining marks as none.
function Get-CharWidth([int]$c) {
    if ($c -ge 0x0300 -and $c -le 0x036F) { return 0 }
    if (($c -ge 0x1100 -and $c -le 0x115F) -or ($c -ge 0x2E80 -and $c -le 0xA4CF) -or ($c -ge 0xAC00 -and $c -le 0xD7A3) -or
        ($c -ge 0xF900 -and $c -le 0xFAFF) -or ($c -ge 0xFE30 -and $c -le 0xFE4F) -or ($c -ge 0xFF00 -and $c -le 0xFF60) -or
        ($c -ge 0xFFE0 -and $c -le 0xFFE6)) { return 2 }
    return 1
}

# Splits a line into columns that start at the given display positions. Returns the cells, the line's display width
# and whether every column boundary fell on whitespace (winget always separates columns with a space).
function Split-Columns([string]$Line, [int[]]$Starts) {
    $cells = New-Object string[] $Starts.Count
    $sb = New-Object Text.StringBuilder
    $col = 0; $pos = 0; $i = 0; $clean = $true
    while ($i -lt $Line.Length) {
        $c = [int]$Line[$i]
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and $i + 1 -lt $Line.Length) { $chunk = $Line.Substring($i, 2); $w = 2; $i += 2 }
        else { $chunk = [string]$Line[$i]; $w = Get-CharWidth $c; $i++ }
        while ($col + 1 -lt $Starts.Count -and $pos -ge $Starts[$col + 1]) {
            if ($sb.Length -and -not [char]::IsWhiteSpace($sb[$sb.Length - 1])) { $clean = $false }
            $cells[$col] = $sb.ToString().Trim(); [void]$sb.Clear(); $col++
        }
        [void]$sb.Append($chunk); $pos += $w
    }
    $cells[$col] = $sb.ToString().Trim()
    for ($k = 0; $k -lt $cells.Count; $k++) { if ($null -eq $cells[$k]) { $cells[$k] = '' } }
    return @{ Cells = $cells; Width = $pos; Clean = $clean }
}

function Get-ColumnStarts([string]$Header) {
    $starts = New-Object Collections.Generic.List[int]
    $pos = 0; $prevSpace = $true
    foreach ($ch in $Header.ToCharArray()) {
        $space = [char]::IsWhiteSpace($ch)
        if (-not $space -and $prevSpace) { $starts.Add($pos) }
        $prevSpace = $space
        $pos += Get-CharWidth ([int]$ch)
    }
    return ,$starts.ToArray()
}

# Tables are found by their dashed separator line, so localized headers still work. Column order by table kind:
#   upgrade: Name, Id, Version, Available, Source   (a later table, or one after a line ending in a colon, lists
#            packages that are pinned or need explicit targeting)
#   search:  Name, Id, Version, [Match], Source     (Match only appears when some result matched by tag or moniker)
#   list:    Name, Id, Version, [Available], Source (Available only appears when something can be upgraded; Source is
#            empty for apps winget did not install, and their IDs, such as ARP\Machine\X64\..., can contain spaces)
function ConvertFrom-WingetTable($Lines, [string]$Kind = 'upgrade') {
    $rows = New-Object Collections.Generic.List[object]
    $found = $false; $tableIndex = 0
    for ($i = 0; $i -lt $Lines.Count - 1; $i++) {
        if ($Lines[$i + 1].Trim() -notmatch '^-{8,}$' -or -not $Lines[$i].Trim()) { continue }
        $starts = Get-ColumnStarts $Lines[$i]
        $n = $starts.Count
        if ($n -lt 4) { continue }
        $found = $true
        $prev = ''
        for ($k = $i - 1; $k -ge 0; $k--) { if ($Lines[$k].Trim()) { $prev = $Lines[$k].Trim(); break } }
        $explicit = ($tableIndex -gt 0) -or ($prev -match '[:\uFF1A]$')
        $tableIndex++
        $j = $i + 2
        for (; $j -lt $Lines.Count; $j++) {
            $line = $Lines[$j].TrimEnd()
            if (-not $line.Trim()) { break }
            $r = Split-Columns $line $starts
            $c = $r.Cells
            # Summary lines ("7 upgrades available.") end the table: they cut through words or miss columns
            if (-not $r.Clean -or $r.Width -le $starts[2] -or -not $c[0] -or -not $c[1]) { break }
            $row = $null
            if ($Kind -eq 'list') {
                $row = @{ Name = $c[0]; Id = $c[1]; Version = $c[2]; Available = $(if ($n -ge 5) { $c[3] } else { '' }); Source = $c[$n - 1] }
            }
            elseif ($c[1] -notmatch '\s') {
                if ($Kind -eq 'search') {
                    if ($c[$n - 1]) { $row = @{ Name = $c[0]; Id = $c[1]; Version = $c[2]; Match = $(if ($n -ge 5) { $c[3] } else { '' }); Source = $c[$n - 1] } }
                }
                elseif ($c[3] -and ($n -le 4 -or $c[4])) {
                    $row = @{ Name = $c[0]; Id = $c[1]; Version = $c[2]; Available = $c[3]; Source = $(if ($n -gt 4) { $c[4] } else { '' }); Explicit = $explicit }
                }
            }
            if (-not $row) { break }
            $row.Truncated = $c[1].EndsWith([string][char]0x2026)
            $rows.Add($row)
        }
        $i = $j - 1
    }
    return @{ Rows = $rows.ToArray(); Found = $found }
}
function ConvertFrom-UpgradeTable($Lines) { return ConvertFrom-WingetTable $Lines 'upgrade' }

# Installed sizes come from Windows' uninstall entries (EstimatedSize, in KB), since winget reports none. winget list
# names apps it didn't install ARP\<Machine|User>\<X64|X86>\<entry key>, which points straight at the entry; other
# rows are matched by display name (and version, when the name appears more than once). Store (MSIX) apps have no
# such entry: their install folders are measured afterwards ('msixsizes').
function Get-ArpSizes {
    $byKey = @{}; $byName = @{}
    $views = @(
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; View = [Microsoft.Win32.RegistryView]::Registry64; Scope = 'Machine'; Arch = 'X64' },
        @{ Hive = [Microsoft.Win32.RegistryHive]::LocalMachine; View = [Microsoft.Win32.RegistryView]::Registry32; Scope = 'Machine'; Arch = 'X86' },
        @{ Hive = [Microsoft.Win32.RegistryHive]::CurrentUser; View = [Microsoft.Win32.RegistryView]::Registry64; Scope = 'User'; Arch = 'X64' }
    )
    foreach ($v in $views) {
        $base = $null; $u = $null
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($v.Hive, $v.View)
            $u = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if (-not $u) { continue }
            foreach ($k in $u.GetSubKeyNames()) {
                $s = $null
                try {
                    $s = $u.OpenSubKey($k)
                    if (-not $s) { continue }
                    $kb = $s.GetValue('EstimatedSize')
                    if (-not $kb) { continue }
                    $e = @{ KB = [long]$kb; Name = [string]$s.GetValue('DisplayName'); Version = [string]$s.GetValue('DisplayVersion') }
                    $byKey["$($v.Scope)\$($v.Arch)\$k"] = $e
                    if (-not $byKey.ContainsKey("$($v.Scope)\*\$k")) { $byKey["$($v.Scope)\*\$k"] = $e }
                    if ($e.Name) { if (-not $byName.ContainsKey($e.Name)) { $byName[$e.Name] = New-Object Collections.Generic.List[object] }; $byName[$e.Name].Add($e) }
                }
                catch { }
                finally { if ($s) { $s.Close() } }
            }
        }
        catch { }
        finally { if ($u) { $u.Close() }; if ($base) { $base.Close() } }
    }
    return @{ ByKey = $byKey; ByName = $byName }
}

function Get-RowSize($Row, $Arp) {
    $e = $null
    if ($Row.Id -match '^ARP\\(Machine|User)\\(X64|X86|Arm64)\\(.+)$') {
        $e = $Arp.ByKey["$($Matches[1])\$($Matches[2])\$($Matches[3])"]
        if (-not $e) { $e = $Arp.ByKey["$($Matches[1])\*\$($Matches[3])"] }
    }
    if (-not $e -and $Row.Name -and $Row.Id -notlike 'MSIX\*') {
        $cands = $Arp.ByName[$Row.Name]
        if (-not $cands -and $Row.Name.EndsWith([string][char]0x2026)) {
            $prefix = $Row.Name.TrimEnd([char]0x2026)
            foreach ($n in $Arp.ByName.Keys) { if ($n.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $cands = $Arp.ByName[$n]; break } }
        }
        if ($cands) { $e = @($cands | Where-Object { $_.Version -eq $Row.Version }) | Select-Object -First 1; if (-not $e) { $e = $cands[0] } }
    }
    if ($e) { return $e.KB } else { return 0 }
}

# winget pin list: package ID -> pin type. The last header ("Pin type") is two words, so everything from the fifth
# column on is the type.
function Get-Pins {
    $pins = @{}
    $lines = New-Object Collections.Generic.List[string]
    try { $null = Invoke-Winget -ArgumentList @('pin', 'list', '--disable-interactivity') -Quiet -OnLine { param($l) if (-not (Test-Noise $l)) { $lines.Add($l) } } }
    catch { return $pins }
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i + 1].Trim() -notmatch '^-{8,}$' -or -not $lines[$i].Trim()) { continue }
        $starts = Get-ColumnStarts $lines[$i]
        if ($starts.Count -lt 5) { break }
        $starts = [int[]]($starts[0..4])
        for ($j = $i + 2; $j -lt $lines.Count; $j++) {
            $line = $lines[$j].TrimEnd()
            if (-not $line.Trim()) { break }
            $c = (Split-Columns $line $starts).Cells
            if ($c[1] -and $c[1] -notmatch '\s') { $pins[$c[1]] = $(if ($c[4]) { $c[4] } else { 'Pinning' }) }
        }
        break
    }
    return $pins
}

function Get-Percent([string]$Line) {
    $m = [regex]::Match($Line, '([\d.,]+)\s*(B|KB|MB|GB|TB)\s*/\s*([\d.,]+)\s*(B|KB|MB|GB|TB)')
    if ($m.Success) {
        $unit = @{ B = 1; KB = 1KB; MB = 1MB; GB = 1GB; TB = 1TB }
        $inv = [Globalization.CultureInfo]::InvariantCulture
        try {
            $done = [double]::Parse(($m.Groups[1].Value -replace ',', '.'), $inv) * $unit[$m.Groups[2].Value]
            $total = [double]::Parse(($m.Groups[3].Value -replace ',', '.'), $inv) * $unit[$m.Groups[4].Value]
            if ($total -gt 0) { return [Math]::Min(100, 100 * $done / $total) }
        }
        catch { }
    }
    $m = [regex]::Match($Line, '(\d{1,3})\s*%')
    if ($m.Success) { return [Math]::Min(100, [double]$m.Groups[1].Value) }
    return -1
}

# Maps winget's result to a row state. Unknown failures show winget's own last relevant line.
function Get-Outcome([int]$Code, $Recent, [string]$Action = 'update') {
    $done = @{ update = 'Updated'; install = 'Installed'; uninstall = 'Uninstalled' }[$Action]
    # The installed copy came from a different installer (Edge, WebView2, Teams, ...): Windows or the app updates it
    if ($Action -eq 'update' -and ($Recent -join "`n") -match 'install technology (is )?different') {
        return @{ State = 'skipped'; Detail = 'Updated by Windows or by the app itself, not winget'; SelfUpdating = $true }
    }
    switch (Get-Hex $Code) {
        '0x00000000' { return @{ State = 'ok'; Detail = $done } }
        '0x8A15002B' { if ($Action -eq 'install') { return @{ State = 'ok'; Detail = 'Already installed and up to date' } } else { return @{ State = 'skipped'; Detail = 'No applicable update found' } } }
        '0x8A15010D' { return @{ State = 'ok'; Detail = $(if ($Action -eq 'install') { 'Already installed' } else { 'Already up to date' }) } }
        '0x8A150014' { if ($Action -eq 'uninstall') { return @{ State = 'error'; Detail = "winget couldn't find this app installed" } } }
        '0x8A150109' { return @{ State = 'reboot'; Detail = "$done, restart required" } }
        '0x8A15010B' { return @{ State = 'reboot'; Detail = "$done, restart started" } }
        '0x8A15010A' { return @{ State = 'error'; Detail = 'Restart Windows, then try again' } }
        '0x8A15010C' { return @{ State = 'cancelled'; Detail = 'Cancelled in the installer' } }
        '0x8A150101' { return @{ State = 'error'; Detail = 'The app is in use: close it and retry' } }
        '0x8A150103' { return @{ State = 'error'; Detail = 'A file is in use: close the app and retry' } }
        '0x8A150111' { return @{ State = 'error'; Detail = 'The app is in use: close it and retry' } }
        '0x8A150102' { return @{ State = 'error'; Detail = 'Another installation is in progress' } }
        '0x8A150104' { return @{ State = 'error'; Detail = 'A required dependency is missing' } }
        '0x8A150105' { return @{ State = 'error'; Detail = 'Not enough disk space' } }
        '0x8A150107' { return @{ State = 'error'; Detail = 'No network connection' } }
        '0x8A15010F' { return @{ State = 'error'; Detail = 'Blocked by policy' } }
    }
    $text = ($Recent -join "`n")
    if ($text -match 'exit code:?\s*1223\b') { return @{ State = 'error'; Detail = 'Administrator approval was declined' } }
    if ($text -match 'exit code:?\s*1602\b') { return @{ State = 'cancelled'; Detail = 'Cancelled in the installer' } }
    $reason = @($Recent | Where-Object { $_ -match '(?i)fail|error|exit code|denied|cancel|unable|cannot|not ' }) | Select-Object -Last 1
    if (-not $reason) { $reason = @($Recent) | Select-Object -Last 1 }
    if (-not $reason) { $reason = "winget exited with $(Get-Hex $Code)" }
    return @{ State = 'error'; Detail = $reason }
}

if ($Op -eq 'scan') {
    $lines = New-Object Collections.Generic.List[string]
    # Pinned apps are listed too (--include-pinned) and marked, so held updates stay visible instead of vanishing
    $pins = Get-Pins
    $wingetArgs = @('upgrade', '--include-pinned', '--accept-source-agreements', '--disable-interactivity')
    if ($Arg.IncludeUnknown) { $wingetArgs += '--include-unknown' }
    if ($Arg.Source) { $wingetArgs += '--source', $Arg.Source }
    if ($Arg.Verbose) { $wingetArgs += '--verbose-logs' }
    try {
        $code = Invoke-Winget -ArgumentList $wingetArgs -OnLine { param($l) if (-not (Test-Noise $l)) { $lines.Add($l); Write-Log $l } }
        $table = ConvertFrom-UpgradeTable $lines
        $hex = Get-Hex $code
        Write-Log "Exit code $hex"
        # No table: nothing to upgrade (0, NO_APPLICATIONS_FOUND, UPDATE_NOT_APPLICABLE) or a real failure
        if (-not $table.Found -and $hex -notin '0x00000000', '0x8A150014', '0x8A15002B') {
            $msg = @($lines | Where-Object { $_.Trim() }) | Select-Object -Last 3
            Send @{ T = 'scan'; Rows = @(); Error = "winget exited with $hex.`n$($msg -join "`n")".Trim() }
        }
        else {
            foreach ($row in $table.Rows) { $row.Pin = [string]$pins[$row.Id] }
            Send @{ T = 'scan'; Rows = $table.Rows; Error = $null; Pins = $pins }
        }
    }
    catch { Send @{ T = 'scan'; Rows = @(); Error = "winget could not be started: $($_.Exception.Message)" } }
}
elseif ($Op -in 'search', 'list') {
    # Discover (winget search) and Installed (winget list) use the same table reader with their own column rules
    $lines = New-Object Collections.Generic.List[string]
    $wingetArgs = if ($Op -eq 'search') { @('search', $Arg.Query, '--count', "$($Arg.Count)", '--accept-source-agreements', '--disable-interactivity') }
    else { @('list', '--accept-source-agreements', '--disable-interactivity') }
    if ($Arg.Source) { $wingetArgs += '--source', $Arg.Source }
    try {
        $code = Invoke-Winget -ArgumentList $wingetArgs -OnLine { param($l) if (-not (Test-Noise $l)) { $lines.Add($l); Write-Log $l } }
        $table = ConvertFrom-WingetTable $lines $Op
        $hex = Get-Hex $code
        Write-Log "Exit code $hex"
        if (-not $table.Found -and $hex -notin '0x00000000', '0x8A150014') {
            $msg = @($lines | Where-Object { $_.Trim() }) | Select-Object -Last 3
            Send @{ T = $Op; Query = $Arg.Query; Rows = @(); Error = "winget exited with $hex.`n$($msg -join "`n")".Trim() }
        }
        else {
            $pins = if ($Op -eq 'list') { Get-Pins } else { $null }
            if ($Op -eq 'list') { $arp = Get-ArpSizes; foreach ($row in $table.Rows) { $row.SizeKB = Get-RowSize $row $arp } }
            Send @{ T = $Op; Query = $Arg.Query; Rows = $table.Rows; Error = $null; Pins = $pins }
        }
    }
    catch { Send @{ T = $Op; Query = $Arg.Query; Rows = @(); Error = "winget could not be started: $($_.Exception.Message)" } }
}
elseif ($Op -eq 'versions') {
    # The starter list is built in, so its versions come from one search of the whole winget catalog (under a second).
    # Only lines naming one of the wanted IDs are split into columns, which keeps the ~15,000-line output cheap.
    $want = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($id in @($Arg.Ids)) { [void]$want.Add([string]$id) }
    $lines = New-Object Collections.Generic.List[string]
    $found = @{}
    try {
        $null = Invoke-Winget -ArgumentList @('search', '--id', '.', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') -Quiet -OnLine { param($l) $lines.Add($l) }
        $starts = $null
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if (-not $starts) {
                if ($i + 1 -lt $lines.Count -and $lines[$i].Trim() -and $lines[$i + 1].Trim() -match '^-{8,}$') { $starts = Get-ColumnStarts $lines[$i]; $i++ }
                continue
            }
            $line = $lines[$i]
            $hit = $false
            foreach ($tok in $line.Split([char[]]' ', [StringSplitOptions]::RemoveEmptyEntries)) { if ($want.Contains($tok)) { $hit = $true; break } }
            if (-not $hit) { continue }
            $r = Split-Columns $line.TrimEnd() $starts
            if ($want.Contains($r.Cells[1]) -and $r.Cells[2]) { $found[$r.Cells[1]] = $r.Cells[2] }
        }
    }
    catch { }
    Send @{ T = 'versions'; Versions = $found }
}
elseif ($Op -eq 'show') {
    # Package details for the Details panel (winget show): the raw lines, parsed in the window
    $lines = New-Object Collections.Generic.List[string]
    $wingetArgs = @('show', '--id', $Arg.Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
    if ($Arg.Source) { $wingetArgs += '--source', $Arg.Source }
    if ($Arg.Versions) { $wingetArgs += '--versions' }
    try {
        $code = Invoke-Winget -ArgumentList $wingetArgs -Quiet -OnLine { param($l) if (-not (Test-Noise $l)) { $lines.Add($l.TrimEnd()) } }
        Send @{ T = 'show'; Key = $Arg.Key; Purpose = $Arg.Purpose; Ok = ($code -eq 0); Lines = $lines.ToArray() }
    }
    catch { Send @{ T = 'show'; Key = $Arg.Key; Purpose = $Arg.Purpose; Ok = $false; Lines = @($_.Exception.Message) } }
}
elseif ($Op -eq 'upgrade') {
    $job = $null
    while ($Sync.Jobs.TryDequeue([ref]$job)) {
        if (-not $job -or -not $job.Id) { continue }
        $key = $job.Key
        Write-Log ''
        # Jobs are updates unless they say otherwise (automatic runs and older callers send no Action)
        $action = if ($job.Action) { $job.Action } else { 'update' }
        $verb = @{ update = 'Updating'; install = 'Installing'; uninstall = 'Uninstalling' }[$action]
        Write-Log "==== $verb $($job.Name) ($($job.Id)) ===="
        Send @{ T = 'state'; Key = $key; State = 'running'; Detail = 'Starting' + [char]0x2026 }
        $ctx = @{ Pct = -2; Recent = New-Object Collections.Generic.List[string] }
        switch ($action) {
            'install' {
                $wingetArgs = @('install', '--id', $job.Id, '--exact', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity')
                if ($job.Scope) { $wingetArgs += '--scope', $job.Scope }
                if ($job.Version) { $wingetArgs += '--version', $job.Version }
            }
            'uninstall' {
                $wingetArgs = @('uninstall', '--id', $job.Id, '--exact', '--accept-source-agreements', '--disable-interactivity')
                if ($job.Version) { $wingetArgs += '--version', $job.Version }
            }
            default {
                $wingetArgs = @('upgrade', '--id', $job.Id, '--exact', '--accept-package-agreements', '--accept-source-agreements', '--disable-interactivity', '--include-unknown')
                if ($job.Explicit) { $wingetArgs += '--include-pinned' }
                if ($job.UninstallPrevious) { $wingetArgs += '--uninstall-previous' }
            }
        }
        if ($job.Source) { $wingetArgs += '--source', $job.Source }
        if ($job.Interactive) { $wingetArgs += '--interactive' } elseif ($job.Silent) { $wingetArgs += '--silent' }
        if ($job.Verbose) { $wingetArgs += '--verbose-logs' }
        try {
            $code = Invoke-Winget -ArgumentList $wingetArgs -OnLine {
                param($l)
                if ($l -match '[\u2588\u2592]') {
                    $pct = Get-Percent $l
                    if ($pct -ge 0 -and [int]$pct -ne $ctx.Pct) { $ctx.Pct = [int]$pct; Send @{ T = 'progress'; Key = $key; Value = [double]$pct } }
                    return
                }
                $t = $l.Trim()
                if (-not $t -or $t -match '^[-\\|/]$') { return }
                Write-Log $t
                $ctx.Recent.Add($t); if ($ctx.Recent.Count -gt 6) { $ctx.Recent.RemoveAt(0) }
                # English phase hints; other languages just keep the generic status
                if ($t -match '^Downloading ') {
                    Send @{ T = 'state'; Key = $key; State = 'running'; Detail = 'Downloading' + [char]0x2026 }
                    Send @{ T = 'progress'; Key = $key; Value = 0 }
                }
                elseif ($t -match 'request to run as administrator') { Send @{ T = 'state'; Key = $key; State = 'running'; Detail = 'Waiting for administrator approval' } }
                elseif ($t -match '^Starting package (un)?install') {
                    Send @{ T = 'state'; Key = $key; State = 'running'; Detail = $(if ($Matches[1]) { 'Uninstalling' } else { 'Installing' }) + [char]0x2026 }
                    Send @{ T = 'progress'; Key = $key; Value = -1 }
                }
            }
            Write-Log "Exit code $(Get-Hex $code)"
            $out = Get-Outcome $code $ctx.Recent.ToArray() $action
            Send @{ T = 'state'; Key = $key; State = $out.State; Detail = $out.Detail; SelfUpdating = [bool]$out.SelfUpdating; Id = $job.Id }
            # A chosen version installed with "keep this version": pin it, so updates leave it alone
            if ($job.PinAfter -and $out.State -in 'ok', 'reboot') {
                $pinArgs = @('pin', 'add', '--id', $job.Id, '--exact', '--blocking', '--force', '--accept-source-agreements', '--disable-interactivity')
                if ($job.Source) { $pinArgs += '--source', $job.Source }
                $pc = Invoke-Winget -ArgumentList $pinArgs -OnLine { param($l) if (-not (Test-Noise $l)) { Write-Log $l.Trim() } }
                Send @{ T = 'pinned'; Key = $key; Id = $job.Id; Name = $job.Name; Version = $job.Version; Ok = ($pc -eq 0) }
            }
        }
        catch {
            Write-Log "Error: $($_.Exception.Message)"
            Send @{ T = 'state'; Key = $key; State = 'error'; Detail = $_.Exception.Message }
        }
    }
}
elseif ($Op -eq 'command') {
    # Maintenance (winget source update): the result and winget's last line go back to the Options panel
    $recent = New-Object Collections.Generic.List[string]
    $quiet = $Arg.Name -eq 'version'
    try {
        $code = Invoke-Winget -ArgumentList $Arg.Args -Quiet:$quiet -OnLine { param($l) if (-not (Test-Noise $l)) { if (-not $quiet) { Write-Log $l.Trim() }; $recent.Add($l.Trim()) } }
        if (-not $quiet) { Write-Log "Exit code $(Get-Hex $code)" }
        Send @{ T = 'command'; Name = $Arg.Name; Tag = $Arg.Tag; Ok = ($code -eq 0); Code = (Get-Hex $code); Last = (@($recent) | Select-Object -Last 1) }
    }
    catch { Send @{ T = 'command'; Name = $Arg.Name; Tag = $Arg.Tag; Ok = $false; Code = ''; Last = $_.Exception.Message } }
}
elseif ($Op -eq 'pinmany') {
    # Pins from the Options hidden list, one at a time (winget keeps them in one database)
    foreach ($o in @($Arg.Ops)) {
        $recent = New-Object Collections.Generic.List[string]
        try {
            $code = Invoke-Winget -ArgumentList $o.Args -OnLine { param($l) if (-not (Test-Noise $l)) { Write-Log $l.Trim(); $recent.Add($l.Trim()) } }
            Send @{ T = 'command'; Name = 'pin'; Tag = $o.Tag; Ok = ($code -eq 0); Code = (Get-Hex $code); Last = (@($recent) | Select-Object -Last 1) }
        }
        catch { Send @{ T = 'command'; Name = 'pin'; Tag = $o.Tag; Ok = $false; Code = ''; Last = $_.Exception.Message } }
    }
}
elseif ($Op -eq 'msixsizes') {
    # Store (MSIX) apps: add up each package's install folder. One 'size' event per package, so sizes fill in as
    # they are measured (about 6 seconds for 150 packages).
    $where = @{}
    try { Import-Module Appx -ErrorAction Stop; foreach ($x in @(Get-AppxPackage)) { if ($x.InstallLocation) { $where[$x.PackageFullName] = $x.InstallLocation } } } catch { }
    foreach ($it in @($Arg.Items)) {
        $dir = $where[$it.Full]
        if (-not $dir) { $dir = Join-Path $env:ProgramFiles "WindowsApps\$($it.Full)" }
        $total = [long]0
        if (Test-Path -LiteralPath $dir) {
            $stack = New-Object System.Collections.Generic.Stack[string]
            $stack.Push($dir)
            while ($stack.Count) {
                $d = $stack.Pop()
                try { foreach ($f in [IO.Directory]::GetFiles($d)) { try { $total += (New-Object IO.FileInfo $f).Length } catch { } } } catch { }
                try { foreach ($s in [IO.Directory]::GetDirectories($d)) { if (-not ((New-Object IO.DirectoryInfo $s).Attributes -band [IO.FileAttributes]::ReparsePoint)) { $stack.Push($s) } } } catch { }
            }
        }
        Send @{ T = 'size'; Key = $it.Key; Full = $it.Full; KB = [long]($total / 1KB) }
    }
    Send @{ T = 'sizesdone' }
}
elseif ($Op -eq 'devices') {
    # The PC (maker, model, service tag, BIOS) and every device with its driver. Devices Windows reports a problem
    # for are marked, including ones with no driver at all. Code 45 (not connected right now) is not a problem.
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        $sys = @{ Maker = ([string]$cs.Manufacturer).Trim(); Model = ([string]$cs.Model).Trim(); Family = [string]$cs.SystemFamily; Serial = ([string]$bios.SerialNumber).Trim(); Bios = [string]$bios.SMBIOSBIOSVersion }
        # For picking the right tools: the product name (Lenovo keeps it here), the motherboard (home-built PCs), and the
        # CPU and graphics vendors
        try { $sys.Product = ([string](Get-CimInstance Win32_ComputerSystemProduct).Version).Trim() } catch { $sys.Product = '' }
        try { $bb = Get-CimInstance Win32_BaseBoard; $sys.Board = ([string]$bb.Manufacturer).Trim(); $sys.BoardModel = ([string]$bb.Product).Trim() } catch { $sys.Board = ''; $sys.BoardModel = '' }
        try { $sys.Chips = ((@(Get-CimInstance Win32_Processor | ForEach-Object { "$($_.Manufacturer) $($_.Name)" }) + @(Get-CimInstance Win32_VideoController | ForEach-Object { "$($_.AdapterCompatibility) $($_.Name)" })) -join '; ') } catch { $sys.Chips = '' }
        $problems = @{}
        foreach ($e in @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 45')) { $problems[[string]$e.PNPDeviceID] = $e }
        $list = New-Object Collections.Generic.List[object]
        $seen = @{}
        foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver)) {
            if (-not $d.DeviceName -or -not $d.DeviceID) { continue }
            $id = [string]$d.DeviceID
            $seen[$id] = $true
            $date = ''; try { if ($d.DriverDate) { $date = ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } } catch { }
            $code = if ($problems.ContainsKey($id)) { [int]$problems[$id].ConfigManagerErrorCode } else { 0 }
            $list.Add(@{ Name = [string]$d.DeviceName; Class = [string]$d.DeviceClass; Manufacturer = [string]$d.Manufacturer; Provider = [string]$d.DriverProviderName
                    Version = [string]$d.DriverVersion; Date = $date; Inf = [string]$d.InfName; InstanceId = $id; Code = $code; HardwareId = [string]$d.HardWareID })
        }
        foreach ($id in $problems.Keys) {
            if ($seen.ContainsKey($id)) { continue }
            $e = $problems[$id]
            $list.Add(@{ Name = $(if ($e.Name) { [string]$e.Name } else { $id }); Class = [string]$e.PNPClass; Manufacturer = [string]$e.Manufacturer; Provider = ''
                    Version = ''; Date = ''; Inf = ''; InstanceId = $id; Code = [int]$e.ConfigManagerErrorCode })
        }
        Send @{ T = 'devices'; Sys = $sys; Devices = $list.ToArray(); Error = $null }
    }
    catch { Send @{ T = 'devices'; Sys = $null; Devices = @(); Error = $_.Exception.Message } }
}
elseif ($Op -eq 'wusearch') {
    # Windows Update's driver offers for this PC. Searching needs no administrator rights (installing does).
    try {
        $s = New-Object -ComObject Microsoft.Update.Session
        $s.ClientApplicationID = 'Windows Manager'
        $r = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        $list = New-Object Collections.Generic.List[object]
        foreach ($u in $r.Updates) {
            $date = ''; try { if ($u.DriverVerDate) { $date = ([datetime]$u.DriverVerDate).ToString('yyyy-MM-dd') } } catch { }
            $list.Add(@{ Id = [string]$u.Identity.UpdateID; Title = [string]$u.Title; Maker = [string]$u.DriverManufacturer; Class = [string]$u.DriverClass
                    Model = [string]$u.DriverModel; Date = $date; Size = [long]$u.MaxDownloadSize })
        }
        # Who decides which drivers install: Windows Update for Business driver management (Intune), an update server
        # (WSUS), or a policy that keeps drivers out of Windows Update. Settings only shows what they allow.
        $managed = ''
        try {
            $pm = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -ErrorAction SilentlyContinue
            $gp = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
            $au = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
            if ($pm.ExcludeWUDriversInQualityUpdate -eq 1 -or $gp.ExcludeWUDriversInQualityUpdate -eq 1) { $managed = 'excluded' }
            elseif ($pm.DriverUpdateEnrolled -eq 1) { $managed = 'wufb' }
            elseif ($au.UseWUServer -eq 1 -and $gp.WUServer) { $managed = 'wsus' }
        }
        catch { }
        Send @{ T = 'wusearch'; Updates = $list.ToArray(); Error = $null; Managed = $managed }
    }
    catch { Send @{ T = 'wusearch'; Updates = @(); Error = $_.Exception.Message } }
}
elseif ($Op -eq 'nvlookup') {
    # The newest Game Ready driver for this PC's NVIDIA graphics: the card's product IDs come from NVIDIA's product
    # list, the driver from the lookup service NVIDIA's driver download page uses. Neither is documented by NVIDIA,
    # so any failure just leaves NVIDIA out of the list. The installed version comes from Windows: driver
    # 32.0.15.6094 is NVIDIA's 560.94 (the last five digits).
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $gpu = @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.AdapterCompatibility) $($_.Name)" -match 'NVIDIA' }) | Select-Object -First 1
        $name = if ($Arg.Gpu) { [string]$Arg.Gpu } elseif ($gpu) { [string]$gpu.Name } else { '' }
        if (-not $name) { Send @{ T = 'nvlookup'; None = $true }; return }
        $wv = if ($Arg.DriverVersion) { [string]$Arg.DriverVersion } elseif ($gpu) { [string]$gpu.DriverVersion } else { '' }
        $digits = ($wv -replace '\D', '')
        $installed = if ($digits.Length -ge 5) { $d5 = $digits.Substring($digits.Length - 5); "$([int]$d5.Substring(0, 3)).$($d5.Substring(3))" } else { '' }
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Windows Manager'
        [xml]$px = $wc.DownloadString('https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3')
        $want = ($name -replace '^NVIDIA\s+', '').Trim()
        $all = @($px.LookupValueSearch.LookupValues.LookupValue)
        $prod = @($all | Where-Object { ($_.Name -replace '^NVIDIA\s+', '').Trim() -eq $want }) | Select-Object -First 1
        if (-not $prod) { Send @{ T = 'nvlookup'; Gpu = $name; Installed = $installed; Error = "NVIDIA's product list has no entry for $name" }; return }
        $os = if ([Environment]::OSVersion.Version.Build -ge 22000) { 135 } else { 57 }
        $u = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$($prod.ParentID)&pfid=$($prod.Value)&osID=$os&languageCode=1033&isWHQL=1&dch=1&upCRD=0&sort1=0&numberOfResults=1"
        $j = $wc.DownloadString($u) | ConvertFrom-Json
        $di = @($j.IDS)[0].downloadInfo
        if (-not $di -or -not $di.Version -or -not $di.DownloadURL) { Send @{ T = 'nvlookup'; Gpu = $name; Installed = $installed; Error = 'NVIDIA returned no driver for this card' }; return }
        $date = ''; try { $date = ([datetime]::Parse(($di.ReleaseDateTime -replace '^\w+\s', ''), [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd') } catch { $date = [string]$di.ReleaseDateTime }
        Send @{ T = 'nvlookup'; Gpu = $name; Installed = $installed; Latest = [string]$di.Version; Url = [string]$di.DownloadURL; Size = [string]$di.DownloadURLFileSize
            Date = $date; Title = [Uri]::UnescapeDataString([string]$di.Name); Error = $null }
    }
    catch { Send @{ T = 'nvlookup'; Error = $_.Exception.Message } }
}
elseif ($Op -eq 'elevated') {
    # Follows an elevated script the window has started (Arg.Process): its log files, then its exit code
    $pos = @{}; $rest = @{}
    foreach ($l in @($Arg.Logs)) { $pos[$l] = [long]0; $rest[$l] = '' }
    $follow = {
        foreach ($l in @($Arg.Logs)) {
            if (-not (Test-Path -LiteralPath $l)) { continue }
            try {
                $fs = [IO.File]::Open($l, 'Open', 'Read', 'ReadWrite, Delete')
                try {
                    [void]$fs.Seek($pos[$l], 'Begin')
                    $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8, $true)
                    $text = $rest[$l] + $sr.ReadToEnd()
                    $pos[$l] = $fs.Position
                }
                finally { $fs.Close() }
                $parts = $text -split "`r?`n"
                $rest[$l] = $parts[-1]
                foreach ($line in $parts[0..($parts.Count - 2)]) { if ($line.Trim()) { Write-Log $line.TrimEnd(); Send @{ T = 'elevlog'; Name = $Arg.Name; Text = $line.Trim() } } }
            }
            catch { }
        }
    }
    $p = $Arg.Process
    while (-not $p.HasExited) { Start-Sleep -Milliseconds 700; & $follow }
    $p.WaitForExit()
    & $follow
    foreach ($l in @($Arg.Logs)) { if ($rest[$l].Trim()) { Write-Log $rest[$l].TrimEnd(); Send @{ T = 'elevlog'; Name = $Arg.Name; Text = $rest[$l].Trim() } } }
    Send @{ T = 'elevdone'; Name = $Arg.Name; Tag = $Arg.Tag; Code = [int]$p.ExitCode; Declined = $false }
}
elseif ($Op -eq 'sources') {
    # winget source export prints one JSON object per source (Name, Arg, Type, Identifier, Explicit)
    $list = New-Object Collections.Generic.List[object]
    $err = $null
    try {
        $lines = New-Object Collections.Generic.List[string]
        $code = Invoke-Winget -ArgumentList @('source', 'export', '--disable-interactivity') -Quiet -OnLine { param($l) $lines.Add($l) }
        foreach ($l in $lines) { $s = $l.Trim(); if ($s.StartsWith('{')) { try { $list.Add(($s | ConvertFrom-Json)) } catch { } } }
        if ($code -ne 0 -and -not $list.Count) { $err = "winget exited with $(Get-Hex $code)" }
    }
    catch { $err = $_.Exception.Message }
    Send @{ T = 'sources'; Sources = $list.ToArray(); Error = $err }
}
'@

$Sync = [hashtable]::Synchronized(@{
        Events  = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        Jobs    = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
        LogFile = $LogFile
    })

function Get-ScanArg { return @{ IncludeUnknown = $Settings.IncludeUnknown; Source = $Settings.Source; Verbose = $Settings.VerboseLogs } }

function Start-Background {
    param([string]$Op, $Arg)
    $ps = [powershell]::Create()
    [void]$ps.AddScript($WorkerScript).AddArgument($Sync).AddArgument($Op).AddArgument($WingetPath).AddArgument($Arg)
    return @{ PS = $ps; Handle = $ps.BeginInvoke(); Op = $Op }
}

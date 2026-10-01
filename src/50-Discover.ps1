# Windows Manager - Discover (part of src\; see Windows_Manager.ps1)

$script:StarterVersions = @{}
function Start-StarterVersions {
    if (-not $WingetPath -or $script:StarterVersions.Count) { return }
    $ids = foreach ($s in $StarterApps) { $s.Split('|')[1] }
    $script:Showers.Add((Start-Background 'versions' @{ Ids = @($ids) }))
}
function Complete-Versions($Ev) {
    foreach ($k in @($Ev.Versions.Keys)) { $script:StarterVersions[$k] = [string]$Ev.Versions[$k] }
    foreach ($p in $DiscoverItems) { if (-not $p.Version -and $script:StarterVersions.ContainsKey($p.Id)) { $p.Version = $script:StarterVersions[$p.Id] } }
}

function Show-Starter {
    $script:DiscoverQuery = $null
    $script:DiscoverImport = $null
    $script:DiscoverMode = 'ready'
    $rows = foreach ($s in $StarterApps) {
        $cat, $id, $name = $s.Split('|')
        $p = Get-Row 'discover' @{ Id = $id; Source = 'winget'; Name = $name; Version = [string]$script:StarterVersions[$id] }
        $p.Available = ''
        $p.Category = $cat
        Set-CachedDescription $p
        $p
    }
    Set-SectionRows $DiscoverItems @($rows)
    $DiscoverView.SortDescriptions.Clear()
    $DiscoverView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Category', 'Ascending')))
    $DiscoverView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
    Update-DiscoverInstalled
    Update-SortGlyphs
    Request-Descriptions
}

function Start-Search {
    $q = $UI.Search.Text.Trim()
    if (-not $q) { Show-Starter; Update-View; return }
    if ($script:Searcher -or -not (Test-WingetPresent 'discover')) { return }
    $script:DiscoverQuery = $q
    $script:DiscoverImport = $null
    $script:DiscoverMode = 'loading'
    Add-LogLine ''
    Add-LogLine "---- Searching winget for `"$q`" ----"
    $script:Searcher = Start-Background 'search' @{ Query = $q; Count = 150; Source = $Settings.Source }
    Update-View
}

function Complete-Search($Ev) {
    if ($Ev.Query -ne $script:DiscoverQuery) { return }   # an older search
    if ($Ev.Error) { Set-SectionError 'discover' "Couldn't search winget" $Ev.Error; return }
    $rows = foreach ($r in @($Ev.Rows | Where-Object { $_ -and $_.Id })) {
        $p = Get-Row 'discover' $r
        $p.Available = [string]$r.Match
        $p.Category = ''
        $p.Truncated = [bool]$r.Truncated
        Set-CachedDescription $p
        $p
    }
    Set-SectionRows $DiscoverItems @($rows)
    $DiscoverView.SortDescriptions.Clear()   # winget's own order puts the closest matches first
    Update-SortGlyphs
    $script:DiscoverMode = 'ready'
    Update-DiscoverInstalled
    Request-Descriptions
}

# Descriptions: winget search has none, so each one is fetched (winget show) in the background, then kept in
# descriptions.json so it shows straight away next time.
$DescCachePath = Join-Path $DataDir 'descriptions.json'
$script:DescCache = @{}
try {
    if (Test-Path -LiteralPath $DescCachePath) {
        $saved = Get-Content -LiteralPath $DescCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $saved.PSObject.Properties) { $script:DescCache[$prop.Name] = @{ D = [string]$prop.Value.D; T = [string]$prop.Value.T; N = [string]$prop.Value.N } }
    }
}
catch { }

function Set-CachedDescription($p) {
    $c = $script:DescCache["$($p.Id)|$($p.Source)"]
    # An app list only has IDs: a cached description without the app's name is looked up again for the name
    if (-not $c -or (-not $c.N -and $p.Name -eq $p.Id)) { if ($p.DescState -ne 'loading') { $p.DescState = '' }; return }
    if ($c.N -and $p.Name -eq $p.Id) { $p.Name = $c.N }
    $p.Description = $c.D
    $p.DescState = if ($c.D) { 'ok' } else { 'none' }
}

function Save-DescriptionCache {
    try { $script:DescCache | ConvertTo-Json -Depth 3 -Compress | Set-Content -LiteralPath $DescCachePath -Encoding UTF8 } catch { }
}

# Stores a description (from the background fetch or the Details panel) and shows it on every matching row
function Set-Description([string]$Id, [string]$Source, [string]$Text, [string]$Name) {
    $Text = ($Text -replace '\s+', ' ').Trim()
    if ($Text.Length -gt 600) { $Text = $Text.Substring(0, 597) + $Ellipsis }
    $script:DescCache["$Id|$Source"] = @{ D = $Text; T = (Get-Date).ToString('yyyy-MM-dd'); N = $Name }
    Save-DescriptionCache
    foreach ($d in $DiscoverItems) {
        if ($d.Id -eq $Id -and $d.Source -eq $Source) {
            $d.Description = $Text; $d.DescState = if ($Text) { 'ok' } else { 'none' }
            if ($Name -and $d.Name -eq $d.Id) { $d.Name = $Name }
        }
    }
}

# Every Discover row without a saved description is fetched in the background, a few at a time (8 at once measured
# ~4 s for the 54-app starter list; more barely helps). A new search or the starter list replaces what is still queued.
$DescParallel = 8
$script:DescQueue = New-Object System.Collections.Generic.Queue[object]
function Request-Descriptions {
    # rows dropped from the queue go back to "not fetched" so they are asked for again next time they are shown
    while ($script:DescQueue.Count) { $q = $script:DescQueue.Dequeue(); if ($q.DescState -eq 'loading') { $q.DescState = '' } }
    if (-not $WingetPath -or $script:Section -ne 'discover') { return }
    $busy = @{}
    foreach ($sh in $script:Showers.ToArray()) { if ($sh.DescKey) { $busy[$sh.DescKey] = $true } }
    foreach ($p in $DiscoverItems) {
        if (-not $p.Source -or $p.DescState -eq 'ok' -or $p.DescState -eq 'none') { continue }
        if ($busy.ContainsKey($p.Key)) { $p.DescState = 'loading'; continue }   # already being fetched
        $p.DescState = 'loading'
        $script:DescQueue.Enqueue($p)
    }
    Step-Descriptions
}
# Descriptions first (they are on screen), then release notes for the Updates tab; at most $DescParallel at once
function Step-Descriptions {
    $running = 0
    foreach ($sh in $script:Showers.ToArray()) { if ($sh.DescKey) { $running++ } }
    while (($script:DescQueue.Count -or $script:NotesQueue.Count) -and $running -lt $DescParallel) {
        if ($script:DescQueue.Count) {
            $p = $script:DescQueue.Dequeue()
            if ($p.DescState -ne 'loading') { continue }
            $purpose = 'describe'
        }
        else {
            $p = $script:NotesQueue.Dequeue()
            if (-not $Packages.Contains($p)) { continue }
            $purpose = 'notes'
        }
        $bg = Start-Background 'show' @{ Id = $p.Id; Source = $p.Source; Key = $p.Key; Purpose = $purpose }
        $bg.DescKey = $p.Key
        $script:Showers.Add($bg)
        $running++
    }
}

# Reads winget show's "Key: value" lines; Description, Tags and similar values continue on indented lines
function ConvertFrom-ShowOutput($Lines) {
    $r = @{ Name = $null; Fields = [ordered]@{}; Description = ''; Tags = @() }
    $desc = New-Object System.Collections.Generic.List[string]
    $tags = New-Object System.Collections.Generic.List[string]
    $cur = $null
    foreach ($line in @($Lines)) {
        if ($line -match '^Found (.+) \[(.+)\]\s*$') { $r.Name = $Matches[1]; continue }
        if ($line -match '^(\S[^:]*):\s*(.*)$') {
            $cur = $Matches[1]
            if ($Matches[2]) { $r.Fields[$cur] = $Matches[2] } elseif (-not $r.Fields.Contains($cur)) { $r.Fields[$cur] = '' }
            continue
        }
        if ($cur -and $line -match '^\s+(\S.*)$') {
            $v = $Matches[1]
            if ($cur -eq 'Description') { $desc.Add($v) }
            elseif ($cur -eq 'Tags') { $tags.Add($v) }
            elseif ($cur -eq 'Installer' -and $v -match '^([^:]+):\s*(.*)$') { $r.Fields[$Matches[1]] = $Matches[2] }
            elseif ($r.Fields[$cur]) { $r.Fields[$cur] = "$($r.Fields[$cur])`n$v" }
            else { $r.Fields[$cur] = $v }
        }
    }
    $r.Description = if ($desc.Count) { $desc -join "`n" } elseif ($r.Fields['Description']) { $r.Fields['Description'] } else { '' }
    $r.Tags = $tags.ToArray()
    return $r
}

# App lists: winget's export format (Sources[].Packages[].PackageIdentifier), which winget import also reads, or a
# plain text file with one package ID per line
function Read-AppList([string]$File) {
    $raw = [IO.File]::ReadAllText($File)
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    if ($raw.TrimStart().StartsWith('{')) {
        $doc = $raw | ConvertFrom-Json
        foreach ($s in @($doc.Sources)) {
            $src = if ($s.SourceDetails.Name) { [string]$s.SourceDetails.Name } else { 'winget' }
            foreach ($pk in @($s.Packages)) {
                $id = [string]$pk.PackageIdentifier
                if ($id -and -not $seen.ContainsKey($id)) { $seen[$id] = $true; $list.Add(@{ Id = $id; Source = $src }) }
            }
        }
    }
    else {
        foreach ($line in ($raw -split "`r?`n")) {
            $id = ($line -replace '#.*$', '').Trim()
            if ($id -and $id -notmatch '\s' -and -not $seen.ContainsKey($id)) { $seen[$id] = $true; $list.Add(@{ Id = $id; Source = 'winget' }) }
        }
    }
    return , $list.ToArray()
}

function Import-AppList {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'App lists (*.json;*.txt)|*.json;*.txt|All files (*.*)|*.*'
    if (-not $dlg.ShowDialog($Window)) { return }
    # a setup backup is an app list too, with this app's options in it (see 88-Setup.ps1)
    try { Open-AppListFile $dlg.FileName }
    catch { $script:LastSummary = "Couldn't open that app list: $($_.Exception.Message)"; Update-View }
}

# Shows an app list on Discover: apps not on this PC are selected, so Install selected installs the rest of the list
function Show-ImportedList($Entries, [string]$FileName) {
    $script:DiscoverQuery = $null
    $script:DiscoverImport = $FileName
    $script:DiscoverMode = 'ready'
    $script:SearchTimer.Stop()
    $UI.Search.Text = ''
    $rows = foreach ($e in $Entries) {
        $known = $ByKey["discover|$($e.Id)|$($e.Source)"]
        $inst = @($InstalledItems | Where-Object { $_.Id -eq $e.Id }) | Select-Object -First 1
        $starter = @($StarterApps | Where-Object { $_.Split('|')[1] -eq $e.Id }) | Select-Object -First 1
        $name = if ($known) { $known.Name } elseif ($inst) { $inst.Name } elseif ($starter) { $starter.Split('|')[2] } else { $e.Id }
        $p = Get-Row 'discover' @{ Id = $e.Id; Source = $e.Source; Name = $name; Version = $(if ($known -and $known.Version) { $known.Version } else { [string]$script:StarterVersions[$e.Id] }) }
        $p.Available = ''
        $p.Category = ''
        Set-CachedDescription $p
        $p
    }
    Set-SectionRows $DiscoverItems @($rows)
    $DiscoverView.SortDescriptions.Clear()
    $DiscoverView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
    Update-DiscoverInstalled
    foreach ($p in $DiscoverItems) { $p.Selected = $p.CanUpdate }
    Update-SortGlyphs
    Request-Descriptions
    $ids = @($DiscoverItems | Where-Object { -not $_.Version -and $_.Source -eq 'winget' } | ForEach-Object { $_.Id })
    if ($ids.Count -and $WingetPath) { $script:Showers.Add((Start-Background 'versions' @{ Ids = $ids })) }
    Add-LogLine "Opened the app list $FileName ($($DiscoverItems.Count) apps)."
    Update-View
}

function Update-DiscoverInstalled {
    foreach ($p in $DiscoverItems) {
        $p.IsInstalled = $script:InstalledIds.Contains($p.Id)
        # Installed earlier in this session but gone from the PC now: offer Install again
        if ($p.IsDone -and $p.Action -eq 'install' -and -not $p.IsInstalled) { $p.State = '' }
        if ($p.State -eq '') { $p.Detail = if ($p.Truncated) { 'winget shortened this ID; install it with winget directly' } elseif ($p.IsInstalled) { 'Installed' } else { '' } }
    }
}

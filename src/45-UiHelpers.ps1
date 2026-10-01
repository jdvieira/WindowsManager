# Windows Manager - UiHelpers (part of src\; see Windows_Manager.ps1)

# Log lines are buffered and written to the log box once per timer tick: appending line by line to a large TextBox
# made a winget scan's 150 lines cost the window a noticeable pause
$script:LogBuffer = New-Object System.Text.StringBuilder
function Add-LogLine([string]$Text) { [void]$script:LogBuffer.Append($Text).Append("`r`n") }
function Write-LogBuffer {
    if ($script:LogBuffer.Length -eq 0) { return }
    $box = $UI.LogBox
    if ($box.Text.Length -gt 400000) { $box.Text = $box.Text.Substring($box.Text.Length - 200000) }
    $box.AppendText($script:LogBuffer.ToString())
    [void]$script:LogBuffer.Clear()
    if ($UI.LogPanel.Visibility -eq 'Visible') { $box.ScrollToEnd() }
}

function Get-SectionView([string]$Name = $script:Section) {
    switch ($Name) { 'discover' { return , $DiscoverView } 'installed' { return , $InstalledView } default { return , $View } }
}
function ConvertTo-Visibility([bool]$Show) { if ($Show) { return 'Visible' } else { return 'Collapsed' } }

function Update-View {
    $sec = $script:Section
    $isU = $sec -eq 'updates'; $isD = $sec -eq 'discover'; $isI = $sec -eq 'installed'
    # Panel sections (Drivers, Startup, Windows Update, Health) replace the toolbar and the app list
    $panel = $Panels[$sec]
    $UI.SectionToolbar.Visibility = if ($panel) { 'Collapsed' } else { 'Visible' }
    $UI.MainCard.Visibility = if ($panel) { 'Collapsed' } else { 'Visible' }
    foreach ($k in $Panels.Keys) { $UI[$Panels[$k].Panel].Visibility = ConvertTo-Visibility ($k -eq $sec) }
    if ($panel) { & $panel.Update }
    $busy = [bool]$script:Worker -or $Sync.Jobs.Count -gt 0
    $scanning = [bool]$script:Scanner
    $reading = $scanning -or [bool]$script:Searcher -or [bool]$script:Lister

    # Tabs: pending updates badge, installed count
    $upd = @($Packages)
    $hiddenCount = @($upd | Where-Object { $_.IsConcealed }).Count
    $pendingUpd = @($upd | Where-Object { -not $_.IsDone -and -not $_.IsConcealed }).Count
    $UI.UpdatesBadge.Visibility = ConvertTo-Visibility ($script:Mode -eq 'ready' -and $pendingUpd -gt 0)
    $UI.UpdatesBadgeText.Text = [string]$pendingUpd
    $UI.InstalledCount.Text = if ($script:InstalledKnown) { [string]$InstalledItems.Count } else { '' }

    $view = Get-SectionView
    if (-not [object]::ReferenceEquals($UI.List.ItemsSource, $view)) { $UI.List.ItemsSource = $view }
    $all = @($view.SourceCollection)
    $visible = @($view)
    $mode = switch ($sec) { 'discover' { $script:DiscoverMode } 'installed' { $script:InstalledMode } default { $script:Mode } }
    $ready = $mode -eq 'ready'

    # Toolbar for the current section
    $UI.SearchHint.Text = switch ($sec) { 'discover' { 'Search winget for apps, then press Enter' } 'installed' { 'Filter installed apps' } default { 'Search updates' } }
    $UI.BtnSearchGo.Visibility = ConvertTo-Visibility $isD
    $UI.BtnSearchGo.IsEnabled = -not $script:Searcher -and [bool]$WingetPath
    $UI.ChkWingetOnly.Visibility = ConvertTo-Visibility $isI
    $UI.BtnImportList.Visibility = ConvertTo-Visibility $isD
    $UI.BtnExportList.Visibility = ConvertTo-Visibility $isI
    $UI.BtnExportList.IsEnabled = $script:InstalledMode -eq 'ready'
    $UI.BtnRefresh.Visibility = ConvertTo-Visibility (-not $isD)
    $UI.BtnRefresh.IsEnabled = [bool]$WingetPath -and -not $busy -and $(if ($isI) { -not $script:Lister } else { -not $scanning })
    $UI.BtnRefresh.ToolTip = if ($isI) { 'Read the installed apps again (F5)' } else { 'Check for updates again (F5)' }
    $UI.BtnUpdateSelected.Visibility = ConvertTo-Visibility $isU
    $UI.BtnUpdateAll.Visibility = ConvertTo-Visibility $isU
    $UI.BtnInstallSelected.Visibility = ConvertTo-Visibility $isD

    $updatable = @($upd | Where-Object { $_.CanUpdate -and -not $_.ExplicitTarget })
    $selectedU = @($upd | Where-Object { $_.Selected -and $_.CanUpdate })
    $UI.UpdateAllText.Text = if ($updatable.Count) { "Update all ($($updatable.Count))" } else { 'Update all' }
    $UI.BtnUpdateAll.IsEnabled = $script:Mode -eq 'ready' -and -not $scanning -and $updatable.Count -gt 0
    $UI.BtnUpdateSelected.Content = if ($selectedU.Count) { "Update selected ($($selectedU.Count))" } else { 'Update selected' }
    $UI.BtnUpdateSelected.IsEnabled = $script:Mode -eq 'ready' -and -not $scanning -and $selectedU.Count -gt 0
    $selectedD = @($DiscoverItems | Where-Object { $_.Selected -and $_.CanUpdate })
    $UI.InstallSelectedText.Text = if ($selectedD.Count) { "Install selected ($($selectedD.Count))" } else { 'Install selected' }
    $UI.BtnInstallSelected.IsEnabled = $selectedD.Count -gt 0

    $UI.BtnElevate.IsEnabled = -not $busy -and -not $reading
    $UI.BtnStop.Visibility = ConvertTo-Visibility ($Sync.Jobs.Count -gt 0)
    $UI.BusyBar.Visibility = ConvertTo-Visibility ($busy -or $reading)

    # Updates only: the Show hidden toggle, offered when there is something to show
    $UI.BtnShowHidden.Visibility = ConvertTo-Visibility ($isU -and $script:Mode -eq 'ready' -and ($hiddenCount -or $script:ShowHidden))
    $UI.ShowHiddenText.Text = if ($script:ShowHidden) { "Hide hidden ($hiddenCount)" } else { "Show hidden ($hiddenCount)" }
    $UI.ShowHiddenGlyph.Text = if ($script:ShowHidden) { [string][char]0xED1A } else { [string][char]0xE7B3 }
    $UI.BtnShowHidden.BorderBrush = if ($script:ShowHidden) { $Window.FindResource('Accent') } else { $UI.BtnSchedule.BorderBrush }

    # Column header and the select-all box (all, none or some of the shown actionable rows)
    $UI.HdrVersion.Text = if ($isU) { 'INSTALLED' } else { 'VERSION' }
    $UI.HdrAvailable.Text = if ($isD) { 'DESCRIPTION' } else { 'AVAILABLE' }
    $UI.HdrAvailable.Margin = if ($isD) { '0' } else { '19,0,0,0' }
    # Same widths as the row template's Discover and Installed triggers: Status is only a column on Updates
    $UI.HColVer.Width = if ($isD) { New-Object System.Windows.GridLength 120 } else { New-Object System.Windows.GridLength 150 }
    $UI.HColThird.Width = if ($isD) { New-Object System.Windows.GridLength(1.6, [System.Windows.GridUnitType]::Star) } elseif ($isI) { New-Object System.Windows.GridLength 110 } else { New-Object System.Windows.GridLength 160 }
    $UI.SortSize.Visibility = ConvertTo-Visibility $isI
    $UI.HColSource.Width = if ($isD) { New-Object System.Windows.GridLength 0 } else { New-Object System.Windows.GridLength 84 }
    $UI.HColStatus.Width = if ($isU) { New-Object System.Windows.GridLength 230 } else { New-Object System.Windows.GridLength 0 }
    $UI.HdrAvailable.Visibility = if ($isI) { 'Collapsed' } else { 'Visible' }
    $UI.HdrStatus.Visibility = if ($isU) { 'Visible' } else { 'Collapsed' }
    $UI.SortSource.Visibility = if ($isD) { 'Collapsed' } else { 'Visible' }
    $UI.CheckAll.Visibility = if ($isI) { 'Hidden' } else { 'Visible' }
    $shown = @($visible | Where-Object { $_.CanUpdate })
    $shownSel = @($shown | Where-Object { $_.Selected }).Count
    $UI.CheckAll.IsEnabled = $shown.Count -gt 0
    $UI.CheckAll.IsChecked = if ($shown.Count -eq 0 -or $shownSel -eq 0) { $false } elseif ($shownSel -eq $shown.Count) { $true } else { $null }

    # Which panel fills the card
    $listed = if ($isU) { @($all | Where-Object { $script:ShowHidden -or -not $_.IsConcealed }).Count } elseif ($isI -and $UI.ChkWingetOnly.IsChecked) { @($all | Where-Object { $_.Source }).Count } else { $all.Count }
    $showList = $ready -and $visible.Count -gt 0
    $UI.List.Visibility = if ($showList) { 'Visible' } else { 'Hidden' }
    $UI.ColumnHeader.Visibility = if ($showList) { 'Visible' } else { 'Hidden' }
    $UI.LoadingPanel.Visibility = ConvertTo-Visibility ($mode -eq 'loading')
    switch ($sec) {
        'discover' { $UI.LoadingTitle.Text = "Searching for `"$($script:DiscoverQuery)`""; $UI.LoadingText.Text = 'winget is searching its sources.' }
        'installed' { $UI.LoadingTitle.Text = 'Reading installed apps'; $UI.LoadingText.Text = 'winget is listing everything installed on this PC.' }
        default { $UI.LoadingTitle.Text = 'Checking for updates'; $UI.LoadingText.Text = 'winget is querying its sources. This can take a minute the first time.' }
    }
    $UI.IdlePanel.Visibility = ConvertTo-Visibility ($mode -eq 'idle' -and $isU)
    $err = $script:ErrorInfo[$sec]
    $UI.ErrorPanel.Visibility = ConvertTo-Visibility ($mode -eq 'error')
    if ($mode -eq 'error') {
        $UI.ErrorTitle.Text = $err.Title; $UI.ErrorText.Text = $err.Text
        $UI.BtnGetWinget.Visibility = ConvertTo-Visibility ([bool]$err.GetWinget)
    }
    $UI.EmptyPanel.Visibility = ConvertTo-Visibility ($isU -and $ready -and $listed -eq 0)
    if ($isU -and $ready -and $script:LastChecked) {
        $UI.EmptyText.Text = if ($hiddenCount) { "Nothing else to update. $hiddenCount hidden update$(if ($hiddenCount -ne 1) { 's' }) not shown ({0:t})." -f $script:LastChecked }
        else { 'No updates were found from your winget sources ({0:t}).' -f $script:LastChecked }
    }
    $UI.NoMatchPanel.Visibility = ConvertTo-Visibility ($ready -and $visible.Count -eq 0 -and -not ($isU -and $listed -eq 0))
    $q = $UI.Search.Text.Trim()
    $UI.NoMatchText.Text = if ($isD -and $script:DiscoverQuery -and $all.Count -eq 0) { "winget found nothing for `"$($script:DiscoverQuery)`"" }
    elseif ($isI -and $listed -eq 0) { 'No installed apps to show' } else { "No apps match `"$q`"" }

    if ($UI.OptionsOverlay.Visibility -eq 'Visible') { Update-MaintenanceButtons }
    if ($script:DetailsItem -and $UI.DetailsOverlay.Visibility -eq 'Visible') { Update-DetailsAction }

    # Status line and taskbar progress
    $bar = $Window.TaskbarItemInfo
    if ($busy) {
        $b = $script:Batch
        $n = [Math]::Min($b.Done + 1, $b.Total)
        $UI.StatusText.Text = if ($script:CurrentName) { "$($script:CurrentVerb) $($script:CurrentName)  ($n of $($b.Total))" } else { "Starting$Ellipsis" }
        if ($bar) { $bar.ProgressState = 'Normal'; $bar.ProgressValue = if ($b.Total) { $b.Done / $b.Total } else { 0 } }
        return
    }
    if ($bar) { $bar.ProgressState = if ($reading) { 'Indeterminate' } else { 'None' } }
    $parts = @()
    switch ($sec) {
        'updates' {
            if ($scanning) { $parts += "Checking for updates$Ellipsis" }
            elseif ($script:Mode -eq 'ready') {
                $parts += if ($pendingUpd -eq 1) { '1 update available' } elseif ($pendingUpd) { "$pendingUpd updates available" } else { 'Up to date' }

                if ($hiddenCount) { $parts += "$hiddenCount hidden" }
                if ($script:LastChecked) { $parts += 'checked at {0:t}' -f $script:LastChecked }
            }
        }
        'discover' {
            $inst = @($all | Where-Object { $_.IsInstalled }).Count
            if ($script:Searcher) { $parts += "Searching winget$Ellipsis" }
            elseif ($script:DiscoverQuery -and $ready) { $parts += "$($all.Count) result$(if ($all.Count -ne 1) { 's' }) for `"$($script:DiscoverQuery)`""; if ($inst) { $parts += "$inst installed" } }
            elseif ($script:DiscoverImport -and $ready) {
                $parts += "$($all.Count) app$(if ($all.Count -ne 1) { 's' }) from $($script:DiscoverImport)"
                if ($script:InstalledKnown) { $parts += "$inst already installed" }
                $parts += 'Esc goes back to popular apps'
            }
            elseif ($ready) {
                $parts += 'Popular apps'
                if ($script:InstalledKnown) { $parts += "$inst of $($all.Count) installed" }
                $parts += 'type a name and press Enter to search all of winget'
            }
        }
        'installed' {
            if ($script:Lister) { $parts += "Reading installed apps$Ellipsis" }
            elseif ($ready) {
                $fromWinget = @($all | Where-Object { $_.Source }).Count
                $withUpd = @($all | Where-Object { $_.Available }).Count
                $parts += "$($all.Count) apps installed"; $parts += "$fromWinget from winget"
                $kb = [long]0; foreach ($i in $all) { $kb += $i.SizeKB }
                if ($kb -gt 0) { $parts += "{0:0.0} GB on disk" -f ($kb / 1MB) }
                if ($withUpd) { $parts += "$withUpd with an update" }
                if ($script:InstalledChecked) { $parts += 'read at {0:t}' -f $script:InstalledChecked }
            }
        }
        default {
            # a panel section: an administrator run in progress (from any panel), or the panel's own status
            if ($script:Elev) {
                $parts += "$($script:ElevTitle)$Ellipsis"
                if ($script:ElevStalled) { $parts += "no progress for $([int]((Get-Date) - $script:ElevActivity).TotalMinutes) minutes" } elseif ($script:ElevLast) { $parts += $script:ElevLast }
            }
            elseif ($panel -and $panel.Status) { $parts += @(& $panel.Status | Where-Object { $_ }) }
        }
    }
    if ($script:LastSummary) { $parts += $script:LastSummary }
    $UI.StatusText.Text = $parts -join "  $Dot  "
}

function Set-Section([string]$Name) {
    if ($Name -eq $script:Section) { return }
    $script:SectionSearch[$script:Section] = $UI.Search.Text
    $script:Section = $Name
    $UI.Search.Text = $script:SectionSearch[$Name]
    $script:SearchTimer.Stop()
    (Get-SectionView).Refresh()
    Update-SortGlyphs
    if ($Name -eq 'installed' -and ($script:InstalledMode -eq 'idle' -or $script:InstalledStale) -and -not $script:Worker) { Start-InstalledScan }
    # descriptions are fetched once Discover is opened, so they don't compete with the update check at start-up
    if ($Name -eq 'discover') { Request-Descriptions }
    if ($Panels[$Name] -and $Panels[$Name].Open) { & $Panels[$Name].Open }
    Update-View
}

# Reuses the row already shown for a package (so a running install keeps its status) or makes a new one
function Get-Row([string]$Section, $R) {
    $key = "$Section|$($R.Id)|$($R.Source)"
    if ($Section -eq 'installed') { $key += "|$($R.Version)" }
    $p = $ByKey[$key]
    if (-not $p) {
        $p = New-Object WingetUM.Package
        $p.Section = $Section; $p.Id = $R.Id; $p.Source = [string]$R.Source
    }
    $p.Name = $R.Name; $p.Version = [string]$R.Version
    return $p
}

function Set-SectionRows($Collection, $Rows) {
    foreach ($old in @($Collection)) { if (-not $old.IsBusy) { $ByKey.Remove($old.Key) } }
    $Collection.Clear()
    foreach ($p in $Rows) {
        if ($ByKey.ContainsKey($p.Key) -and -not [object]::ReferenceEquals($ByKey[$p.Key], $p)) { continue }
        if ($Collection.Contains($p)) { continue }
        $ByKey[$p.Key] = $p
        $Collection.Add($p)
    }
}

function Set-SectionError([string]$Section, [string]$Title, [string]$Text, [switch]$GetWinget) {
    $script:ErrorInfo[$Section] = @{ Title = $Title; Text = $Text; GetWinget = [bool]$GetWinget }
    switch ($Section) { 'discover' { $script:DiscoverMode = 'error' } 'installed' { $script:InstalledMode = 'error' } default { $script:Mode = 'error' } }
}

function Test-WingetPresent([string]$Section) {
    if ($WingetPath) { return $true }
    Set-SectionError $Section 'winget is not installed' 'winget comes with App Installer from the Microsoft Store. Install or update App Installer, then try again.' -GetWinget
    Update-View
    return $false
}

function Start-Scan {
    if ($script:Scanner -or $script:Worker -or $script:Maint) { return }
    if (-not (Test-WingetPresent 'updates')) { return }
    $script:Mode = 'loading'
    $script:LastSummary = $null
    Add-LogLine ''
    Add-LogLine "---- Checking for updates ($('{0:G}' -f (Get-Date))) ----"
    $script:Scanner = Start-Background 'scan' (Get-ScanArg)
    Update-View
}

function Complete-Scan($Ev) {
    if ($Ev.Error) { Set-SectionError 'updates' "Couldn't check for updates" $Ev.Error; return }
    foreach ($old in @($Packages)) { $ByKey.Remove($old.Key) }
    $Packages.Clear()
    foreach ($r in @($Ev.Rows | Where-Object { $_ -and $_.Id })) {
        $p = New-Object WingetUM.Package
        $p.Section = 'updates'
        $p.Name = $r.Name; $p.Id = $r.Id; $p.Version = $r.Version; $p.Available = $r.Available; $p.Source = $r.Source
        $p.ExplicitTarget = [bool]$r.Explicit
        $p.Truncated = [bool]$r.Truncated
        $p.Pin = [string]$r.Pin
        $p.Hidden = $Settings.Hidden -contains $p.Id
        $p.SelfUpdating = Test-SelfUpdating $p.Id
        if ($ByKey.ContainsKey($p.Key)) { continue }
        if ($p.Truncated) { $p.Detail = 'winget shortened this ID; update it with winget directly' }
        elseif ($p.ExplicitTarget) { $p.Detail = 'Pinned or needs an explicit upgrade' }
        $ByKey[$p.Key] = $p
        $Packages.Add($p)
    }
    $script:Mode = 'ready'
    $script:LastChecked = Get-Date
    if ($null -ne $Ev.Pins) { $script:Pins = $Ev.Pins; Update-PinRows }
    Request-Notes
}

# Pins apply to every row of a package: its update and its installed copies
function Update-PinRows {
    foreach ($p in @($Packages) + @($InstalledItems)) {
        $p.Pin = [string]$script:Pins[$p.Id]
        if ($p.IsConcealed -and $p.IsUpdates) { $p.Selected = $false }
    }
}

# Hide = keep at this version. The ID goes on the Hidden list (so this app and automatic updates leave it alone and
# Updates stops listing it), and a blocking winget pin stops winget itself from updating it. Unhide undoes both.
function Get-PinArgs([string]$Id, [string]$Source, [bool]$On) {
    if (-not $On) { return , @('pin', 'remove', '--id', $Id, '--exact', '--accept-source-agreements', '--disable-interactivity') }
    $a = @('pin', 'add', '--id', $Id, '--exact', '--blocking', '--force', '--accept-source-agreements', '--disable-interactivity')
    if ($Source) { $a += '--source', $Source }
    return , $a
}

function Set-HiddenId([string]$Id, [bool]$On) {
    $list = @($Settings.Hidden | Where-Object { $_ -and $_ -ne $Id })
    if ($On) { $list += $Id }
    $Settings.Hidden = @($list | Sort-Object -Unique)
    Save-Settings
    foreach ($p in @($Packages) + @($InstalledItems)) { if ($p.Id -eq $Id) { $p.Hidden = $On; if ($On -and $p.IsUpdates) { $p.Selected = $false } } }
}

function Set-Hide($p, [bool]$On) {
    if (-not $p -or -not $p.CanHold) { return }
    Set-HiddenId $p.Id $On
    $pinned = $script:Pins.ContainsKey($p.Id)
    $needPin = $WingetPath -and $(if ($On) { -not $pinned -and $p.Source -and -not $p.Truncated } else { $pinned })
    $tag = @{ Id = $p.Id; Name = $p.Name; Version = $p.Version; On = $On }
    if ($needPin) {
        Add-LogLine ''
        Add-LogLine $(if ($On) { "---- Hiding $($p.Name) (kept at $($p.Version)) ----" } else { "---- Unhiding $($p.Name) ----" })
        $script:Showers.Add((Start-Background 'command' @{ Name = 'pin'; Args = (Get-PinArgs $p.Id $p.Source $On); Tag = $tag }))
    }
    else { Complete-Pin @{ Ok = $true; Tag = $tag; NoPin = $true } }
    $View.Refresh()
    Update-View
}

function Complete-Pin($Ev) {
    $tag = $Ev.Tag
    if ($Ev.Ok) {
        if (-not $Ev.NoPin) { if ($tag.On) { $script:Pins[$tag.Id] = 'Blocking' } else { $script:Pins.Remove($tag.Id) } }
        Update-PinRows
        Add-History $(if ($tag.On) { 'hold' } else { 'release' }) $tag.Name $tag.Id $tag.Version '' 'ok' $(if ($tag.On) { "Hidden, kept at $($tag.Version)" } else { 'Unhidden, updates allowed again' })
        $script:LastSummary = if ($tag.On) { "$($tag.Name) is hidden and kept at $($tag.Version)" } else { "$($tag.Name) is unhidden and can be updated again" }
    }
    elseif ($tag.On) { $script:LastSummary = "$($tag.Name) is hidden, but winget couldn't pin it, so winget itself could still update it: $($Ev.Last)" }
    else { $script:LastSummary = "$($tag.Name) is unhidden, but winget couldn't remove its pin: $($Ev.Last)" }
    $View.Refresh()
    Update-View
}

# Apps Windows updates: after the list changes (learned from a failed update, or set back to winget by the user)
function Update-SelfUpdatingRows {
    foreach ($p in $Packages) { $p.SelfUpdating = Test-SelfUpdating $p.Id; if ($p.IsConcealed) { $p.Selected = $false } }
    $View.Refresh()
}
function Set-WingetUpdates($p) {
    Set-SelfUpdating $p.Id $false
    Update-SelfUpdatingRows
    $script:LastSummary = "winget updates $($p.Name) from now on, like other apps"
    Update-View
}

# A chosen version installed with "keep this version": the worker pinned it
function Complete-Pinned($Ev) {
    if (-not $Ev.Ok) { Add-LogLine "$($Ev.Name) installed, but winget couldn't pin it; right-click it on the Installed tab and choose Hide to try again."; return }
    $script:Pins[$Ev.Id] = 'Blocking'
    Set-HiddenId $Ev.Id $true
    Update-PinRows
    Add-History 'hold' $Ev.Name $Ev.Id $Ev.Version '' 'ok' "Hidden, kept at $($Ev.Version)"
}

# Release notes for the listed updates: winget show of each new version, in the background with the descriptions
$script:NotesQueue = New-Object System.Collections.Generic.Queue[object]
function Request-Notes {
    $script:NotesQueue.Clear()
    if (-not $WingetPath) { return }
    foreach ($p in $Packages) {
        if (-not $p.Source -or $p.Truncated) { continue }
        $c = $script:NotesCache["$($p.Id)|$($p.Available)"]
        if ($c) { $p.Notes = $c.Notes; $p.NotesUrl = $c.Url } else { $script:NotesQueue.Enqueue($p) }
    }
    Step-Descriptions
}

function Show-Notes($p) {
    if (-not $p -or -not $p.HasNotes) { return }
    $script:NotesItem = $p
    $UI.NotesTitle.Text = "What's new in $($p.Name)"
    $UI.NotesSub.Text = "$($p.Id)  $Dot  $($p.Version) $([char]0x2192) $($p.Available)"
    $UI.NotesText.Text = if ($p.Notes) { $p.Notes } else { "winget has no release notes text for this version, but the publisher has a page for them." }
    $UI.NotesOpen.Tag = $p.NotesUrl
    $UI.NotesOpen.Visibility = ConvertTo-Visibility ([bool]$p.NotesUrl)
    $UI.NotesUpdate.Content = $p.ActionText
    $UI.NotesUpdate.IsEnabled = $p.CanUpdate
    $UI.NotesUpdate.Margin = '0'
    $UI.NotesOverlay.Visibility = 'Visible'
}

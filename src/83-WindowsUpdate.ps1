# Windows Manager - WindowsUpdate (part of src\; see Windows_Manager.ps1)

# The Windows Update tab: Windows' own updates (security and cumulative updates, .NET, Defender definitions, other
# Microsoft products when Microsoft Update is on), installed through Windows Update itself in one administrator
# run, and Windows Update's recent history. Drivers stay on the Drivers tab.
$WinUpdates = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.WinUpdate]'
$WinHistory = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.WinUpdate]'
$WinView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($WinUpdates)
$WinHistView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($WinHistory)
foreach ($v in $WinView, $WinHistView) {
    $v.Filter = [Predicate[object]] {
        param($u)
        $q = $UI.WinSearch.Text.Trim()
        return (-not $q) -or ("$($u.Title) $($u.SubText) $($u.Type)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    }
}
$UI.WinList.ItemsSource = $WinView
$UI.WinHistList.ItemsSource = $WinHistView
$script:WinState = 'none'           # none | running | ready | error
$script:WinNote = ''
$script:WinInfo = $null             # the last check's Os, Reboot, Managed
$script:WinChecked = $null
$script:WinSearcher = $null

function Start-WinCheck {
    if ($script:WinSearcher) { return }
    $script:WinState = 'running'
    $script:WinSearcher = Start-Tracked 'wusoftware' @{} {
        $script:WinSearcher = $null
        if ($script:WinState -eq 'running') { $script:WinState = 'error'; $script:WinNote = 'The check stopped unexpectedly.' }
    }
    Update-View
}

# What kind of update it is, from its categories and title
function Get-WinUpdateType($w) {
    $cats = @($w.Categories)
    if ($cats -contains 'Definition Updates' -or $w.Title -match 'Security Intelligence|Defender Antivirus|antimalware') { return 'Definitions' }
    if ($cats -contains 'Upgrades' -or $w.Title -match 'Feature update') { return 'Feature update' }
    if ($w.Title -match 'Cumulative Update') { return $(if ($w.Title -match '\.NET') { '.NET' } else { 'Cumulative' }) }
    if ($w.Title -match '\.NET') { return '.NET' }
    if ($cats -contains 'Security Updates') { return 'Security' }
    if ($cats -contains 'Critical Updates') { return 'Critical' }
    if ($cats -contains 'Update Rollups') { return 'Rollup' }
    if ($cats -contains 'Feature Packs') { return 'Feature pack' }
    return 'Update'
}
function Format-Bytes([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:0.0} GB' -f ($Bytes / 1GB) } elseif ($Bytes -ge 1MB) { return '{0:0} MB' -f ($Bytes / 1MB) } elseif ($Bytes -gt 0) { return '{0:0} KB' -f ($Bytes / 1KB) }
    return ''
}

$EventHandlers.wusoftware = { param($Ev) Complete-WinCheck $Ev; Update-View }
function Complete-WinCheck($Ev) {
    $script:WinInfo = $Ev
    $script:WinChecked = Get-Date
    $WinUpdates.Clear()
    foreach ($w in @($Ev.Updates)) {
        $u = New-Object WingetUM.WinUpdate
        $u.UpdateId = $w.Id; $u.Title = $w.Title; $u.Description = $w.Description; $u.Url = $w.Url
        $u.Type = Get-WinUpdateType $w
        $u.Severity = $w.Severity
        $u.SizeText = Format-Bytes $w.Size
        $u.Released = $w.Date
        $u.Optional = [bool]$w.BrowseOnly
        $sub = @($w.Kb) + @(@($w.Categories) | Where-Object { $_ -notmatch '^(Windows 1\d|Microsoft Defender Antivirus|Windows)$' } | Select-Object -First 1)
        if ($w.Downloaded) { $sub += 'downloaded' }
        if ($u.Optional) { $sub += 'optional' }
        $u.SubText = (@($sub | Where-Object { $_ }) -join "  $Dot  ")
        # optional updates (previews, and ones Windows offers to choose) start unticked
        $u.Included = -not $u.Optional
        $WinUpdates.Add($u)
    }
    $codes = @{ 0 = 'Not started'; 1 = 'In progress'; 2 = 'Installed'; 3 = 'Installed, with errors'; 4 = 'Failed'; 5 = 'Cancelled' }
    $WinHistory.Clear()
    foreach ($h in @($Ev.History)) {
        $r = New-Object WingetUM.WinUpdate
        $r.Title = $h.Title
        $r.SubText = (@(@($h.Categories) | Select-Object -First 2) -join ', ')
        $r.Released = $h.When
        $r.Result = if ($h.Code -in 2, 3) { 'ok' } elseif ($h.Code -in 4, 5) { 'error' } else { 'other' }
        $r.ResultText = "$(if ($codes.ContainsKey([int]$h.Code)) { $codes[[int]$h.Code] } else { "Result $($h.Code)" })$(if ($h.Code -eq 4 -and $h.HResult) { ' ({0})' -f (Get-Hex $h.HResult) })"
        $WinHistory.Add($r)
    }
    if ($Ev.Error) { $script:WinState = 'error'; $script:WinNote = $Ev.Error; Add-LogLine "Windows Update check: $($Ev.Error)" }
    else { $script:WinState = 'ready'; Add-LogLine "Windows Update check: $($WinUpdates.Count) update(s) waiting$(if ($Ev.Reboot) { '; a restart is waiting' })." }
}
function Get-Hex([int]$Code) { '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes($Code), 0) }

function Update-WinView {
    $i = $script:WinInfo
    $busy = [bool]$script:Elev
    $checking = $script:WinState -eq 'running'
    $os = if ($i -and $i.Os) { $i.Os } else { $null }
    $UI.WinTitle.Text = if ($os) { "$($os.Name) $($os.Display)".Trim() } else { 'Windows' }
    $UI.WinVersion.Text = (@($(if ($os -and $os.Build) { "Build $($os.Build)" }), $(if ($script:WinChecked) { 'checked at {0:t}' -f $script:WinChecked }), $env:COMPUTERNAME) | Where-Object { $_ }) -join "  $Dot  "
    $last = @($WinHistory | Where-Object { $_.Result -eq 'ok' }) | Select-Object -First 1
    $UI.WinStatus.Text = if ($i -and $i.Reboot) { 'A restart is waiting to finish installing updates.' }
    elseif ($last) { "Last installed: $($last.Title) ($($last.Released))." }
    elseif ($checking) { "Asking Windows Update$Ellipsis" } else { '' }
    $UI.WinRestart.Visibility = ConvertTo-Visibility ($i -and $i.Reboot)
    $UI.WinNote.Visibility = ConvertTo-Visibility ($i -and $i.Managed -and $UI.WinViewAvail.IsChecked)
    $UI.WinNoteText.Text = switch ($i.Managed) {
        'intune' { "Your organization manages Windows updates on this PC (Windows Update for Business, set through Intune): it decides when updates install, so Settings may hold some back for now. Installing one here installs it straight away." }
        'gpo' { "Group Policy controls Windows updates on this PC: it may delay some, so Settings can show fewer than are listed here. Installing one here installs it straight away." }
        'wsus' { "This PC gets its updates from your organization's update server, which decides what it offers. Installing one here goes through that server." }
        default { '' }
    }
    $showAvail = [bool]$UI.WinViewAvail.IsChecked
    $pending = @($WinUpdates | Where-Object { -not $_.Optional }).Count
    $UI.WinBadge.Visibility = ConvertTo-Visibility ($pending -gt 0)
    $UI.WinBadgeText.Text = [string]$pending
    $UI.WinViewAvailText.Text = if ($WinUpdates.Count) { "Available ($($WinUpdates.Count))" } elseif ($checking) { "Available$Ellipsis" } else { 'Available' }
    $n = @($WinUpdates | Where-Object { $_.Included }).Count
    $UI.WinApply.Visibility = ConvertTo-Visibility ($showAvail -and $WinUpdates.Count -gt 0)
    $UI.WinApplyText.Text = if ($n) { "Install $n update$(if ($n -ne 1) { 's' })" } else { 'Install updates' }
    $UI.WinApply.IsEnabled = $n -gt 0 -and -not $busy -and -not $checking
    $UI.WinRefresh.IsEnabled = -not $checking -and -not $busy
    $UI.WinRefreshText.Text = 'Check again'
    $UI.WinRestore.Visibility = ConvertTo-Visibility $showAvail
    $UI.WinAvailHeader.Visibility = ConvertTo-Visibility ($showAvail -and $WinUpdates.Count)
    $UI.WinHistHeader.Visibility = ConvertTo-Visibility (-not $showAvail -and $WinHistory.Count)
    $msg = $null
    if ($checking -and -not ($showAvail -and $WinUpdates.Count) -and -not (-not $showAvail -and $WinHistory.Count)) {
        $msg = @{ Bar = $true; Title = 'Checking Windows Update'; Text = "Windows Update is looking for updates for this PC. This can take a minute$(if ($busy) { '' })." }
    }
    elseif ($showAvail) {
        if ($script:WinState -eq 'none') { $msg = @{ Title = 'Check Windows Update'; Text = 'Lists the security, cumulative, .NET and Defender updates Windows has for this PC.'; Action = 'Check for updates' } }
        elseif ($script:WinState -eq 'error' -and -not $WinUpdates.Count) { $msg = @{ Title = "Couldn't check Windows Update"; Text = $script:WinNote; Action = 'Try again' } }
        elseif (-not $WinUpdates.Count) { $msg = @{ Title = 'Windows is up to date'; Text = "Windows Update has nothing waiting for this PC$(if ($script:WinChecked) { ' ({0:t})' -f $script:WinChecked }).$(if ($i -and $i.Reboot) { ' A restart is still waiting to finish earlier updates.' })"; Action = 'Check again' } }
        elseif (-not @($WinView).Count) { $msg = @{ Title = 'No updates match'; Text = '' } }
    }
    else {
        if (-not $WinHistory.Count) { $msg = @{ Title = 'No history yet'; Text = $(if ($script:WinState -eq 'none') { 'Check for updates to read Windows Update''s history.' } else { 'Windows Update has no record of installed updates.' }); Action = $(if ($script:WinState -eq 'none') { 'Check for updates' }) } }
        elseif (-not @($WinHistView).Count) { $msg = @{ Title = 'Nothing matches'; Text = '' } }
    }
    $UI.WinList.Visibility = if ($showAvail -and -not $msg) { 'Visible' } else { 'Collapsed' }
    $UI.WinHistList.Visibility = if (-not $showAvail -and -not $msg) { 'Visible' } else { 'Collapsed' }
    $UI.WinMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) {
        $UI.WinMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar)
        $UI.WinMsgTitle.Text = $msg.Title; $UI.WinMsgText.Text = $msg.Text
        $UI.WinMsgAction.Visibility = ConvertTo-Visibility ([bool]$msg.Action -and -not $busy)
        if ($msg.Action) { $UI.WinMsgAction.Content = $msg.Action }
    }
}

function Request-WinApply {
    $chosen = @($WinUpdates | Where-Object { $_.Included })
    if (-not $chosen.Count -or $script:Elev) { return }
    $n = $chosen.Count
    $feature = @($chosen | Where-Object { $_.Type -eq 'Feature update' }).Count
    $text = "$n update$(if ($n -ne 1) { 's' }) download and install through Windows Update, one at a time. Windows asks for administrator approval once. Some need a restart, which is left to you." +
    $(if ($feature) { "`n`nA feature update is a new version of Windows: it takes a long time (often an hour or more) and finishes during a restart." } else { '' }) +
    $(if ($script:WinInfo -and $script:WinInfo.Managed) { "`n`nYour organization manages updates on this PC, and may have meant to hold these back for now." } else { '' }) +
    $(if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." } else { '' })
    Show-Confirm 'winapply' @{ Updates = @($chosen | ForEach-Object { @{ Id = $_.UpdateId; Title = $_.Title } }) } "Install $n Windows update$(if ($n -ne 1) { 's' })?" $text 'Install'
}
$ConfirmHandlers.winapply = { param($Payload) Start-WinApply $Payload.Updates }

# One update at a time, so the log says what is downloading or installing; each update's result is a
# RESULT|win|id|code|title line (Windows Update's result codes: 2 installed, 3 with errors, 4 failed, 5 cancelled)
function Start-WinApply($Updates) {
    $ids = (@($Updates) | ForEach-Object { "'" + ($_.Id -replace "'", "''") + "'" }) -join ', '
    $body = @"
`$fail = 0; `$reboot = `$false
`$ids = @($ids)
`$s = New-Object -ComObject Microsoft.Update.Session
`$s.ClientApplicationID = 'Windows Manager'
Say 'Asking Windows Update for the chosen updates$Ellipsis'
`$found = `$s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software'")
`$todo = @(foreach (`$u in `$found.Updates) { if (`$ids -contains `$u.Identity.UpdateID) { if (-not `$u.EulaAccepted) { `$u.AcceptEula() }; `$u } })
`$total = `$todo.Count
Say "Found `$(`$total) of `$(`$ids.Count)."
`$k = 0
foreach (`$u in `$todo) {
    `$k++
    `$one = New-Object -ComObject Microsoft.Update.UpdateColl; [void]`$one.Add(`$u)
    if (-not `$u.IsDownloaded) {
        Say ("Downloading `$(`$k) of `$(`$total): " + `$u.Title + '$Ellipsis')
        `$dl = `$s.CreateUpdateDownloader(); `$dl.Updates = `$one; `$dr = `$dl.Download()
        if (`$dr.ResultCode -ne 2 -and `$dr.ResultCode -ne 3) { Say ("The download failed (result " + `$dr.ResultCode + ', ' + ('0x{0:X8}' -f `$dr.HResult) + ')'); Say ('RESULT|win|' + `$u.Identity.UpdateID + '|4|' + `$u.Title); `$fail++; continue }
    }
    Say ("Installing `$(`$k) of `$(`$total): " + `$u.Title + '$Ellipsis')
    `$in = `$s.CreateUpdateInstaller(); `$in.Updates = `$one
    `$ir = `$in.Install(); `$r = `$ir.GetUpdateResult(0); `$rc = `$r.ResultCode
    Say ('RESULT|win|' + `$u.Identity.UpdateID + '|' + `$rc + '|' + `$u.Title)
    if (`$rc -ne 2 -and `$rc -ne 3) { `$fail++; Say ("It didn't install (result " + `$rc + ', ' + ('0x{0:X8}' -f `$r.HResult) + ')') }
    if (`$ir.RebootRequired) { `$reboot = `$true }
}
if (`$total -lt `$ids.Count) { `$fail += `$ids.Count - `$total; Say 'Some updates are no longer offered by Windows Update.' }
if (`$reboot) { Say 'Windows says a restart is needed to finish.' }
if (`$fail) { Say "`$(`$fail) update(s) did not install."; exit 1 } elseif (`$reboot) { exit 3010 } else { Say 'All done.'; exit 0 }
"@
    $n = @($Updates).Count
    Start-Elevated 'winupdate' "Installing $n Windows update$(if ($n -ne 1) { 's' })" $body @() @{ Count = $n } -RestorePoint -RestoreText 'Before Windows updates' -StallMinutes 60
}
$ElevHandlers.winupdate = {
    param($Ev, $why, $code, $last, $tag)
    $codes = @{ 2 = 'Installed'; 3 = 'Installed, with errors'; 4 = 'Failed'; 5 = 'Cancelled' }
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8 | Where-Object { $_ -like 'RESULT|win|*' }) } else { @() }
    foreach ($l in $lines) {
        $f = $l.Split('|', 5); $rc = [int]$f[3]
        Add-History 'winupdate' $f[4] 'Windows Update' '' '' $(if ($rc -in 2, 3) { 'ok' } else { 'error' }) $(if ($codes.ContainsKey($rc)) { $codes[$rc] } else { "Result $rc" })
    }
    $text = if ($why) { $why } elseif ($code -eq 0) { 'Installed' } elseif ($code -eq 3010) { 'Installed. Restart to finish' } else { "Some didn't install$(if ($last) { ": $last" })" }
    if (-not $lines.Count -and -not $why) { Add-History 'winupdate' "$($tag.Count) Windows update$(if ($tag.Count -ne 1) { 's' })" 'Windows Update' '' '' $(if ($code -in 0, 3010) { 'ok' } else { 'error' }) $text }
    $script:LastSummary = "Windows updates: $text"
    if (-not $why) { Start-WinCheck }
}

function Request-RestartNow {
    $what = if ($script:Elev) { "`n`n$($script:ElevTitle) is still running as administrator; restarting stops it." } else { '' }
    Show-Confirm 'restartnow' $null 'Restart now?' "Windows restarts in 15 seconds to finish installing updates. Save your work in other apps first.$what" 'Restart'
}
$ConfirmHandlers.restartnow = {
    param($Payload)
    try { Start-Process -FilePath "$env:SystemRoot\System32\shutdown.exe" -ArgumentList '/r /t 15 /c "Restarting to finish installing updates (Windows Manager)"' -WindowStyle Hidden }
    catch { $script:LastSummary = "Couldn't restart: $($_.Exception.Message)"; Update-View }
}

$Panels.windows = @{
    Panel   = 'WinPanel'
    Update  = { Update-WinView }
    Status  = {
        if ($script:WinState -eq 'running') { "Checking Windows Update$Ellipsis" }
        elseif ($script:WinState -eq 'ready') {
            $n = $WinUpdates.Count
            if ($n) { "$n Windows update$(if ($n -ne 1) { 's' }) available" } else { 'Windows is up to date' }
            if ($script:WinInfo.Reboot) { 'restart waiting' }
            if ($script:WinChecked) { 'checked at {0:t}' -f $script:WinChecked }
        }
    }
    Open    = { if ($script:WinState -eq 'none') { Start-WinCheck } }
    Refresh = { if ($UI.WinRefresh.IsEnabled) { Start-WinCheck } }
}

$UI.TabWindows.Add_Checked({ Set-Section 'windows' })
$UI.WinRefresh.Add_Click({ Start-WinCheck })
$UI.WinMsgAction.Add_Click({ Start-WinCheck })
$UI.WinApply.Add_Click({ Request-WinApply })
$UI.WinRestart.Add_Click({ Request-RestartNow })
$UI.WinSettings.Add_Click({ try { Start-Process 'ms-settings:windowsupdate' } catch { } })
$UI.WinViewAvail.Add_Click({ Update-View })
$UI.WinViewHistory.Add_Click({ Update-View })
$UI.WinRestore.IsChecked = $Settings.DriverRestorePoint
$UI.WinRestore.Add_Click({ Set-RestorePointSetting ([bool]$UI.WinRestore.IsChecked) })
$UI.WinList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] { Update-View })
$script:WinSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:WinSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:WinSearchTimer.Add_Tick({ $script:WinSearchTimer.Stop(); $WinView.Refresh(); $WinHistView.Refresh(); Update-View })
$UI.WinSearch.Add_TextChanged({ $script:WinSearchTimer.Stop(); $script:WinSearchTimer.Start() })

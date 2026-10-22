# Windows Manager - Suspects (part of src\; see Windows_Manager.ps1)

# Security > Suspicious changes: the places malware changes to start with Windows or take over the PC (startup keys and
# folders, scheduled tasks, services, sign-in, redirected programs, file-type commands, WMI, browser policies, the hosts
# file, a proxy, Defender's policies and exclusions), and what in them looks suspicious (the suspects op in
# 22-WorkerOps.ps1). These are signs, not verdicts, so nothing starts ticked. Remove saves what it changes first
# (registry values as they were, and each command's undo) in suspects.json, so Restore puts it back; changes outside
# your own account need administrator approval, all of them in one run.
$SusItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.SuspectItem]'
$SusView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($SusItems)
$SusView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortGroup', 'Ascending')))
$SusView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SeverityLevel', 'Descending')))
$SusView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Area', 'Ascending')))
$UI.SusList.ItemsSource = $SusView
$SuspectsPath = Join-Path $DataDir 'suspects.json'
$script:SusState = 'none'          # none | running | ready | error
$script:SusReader = $null
$script:SusFound = @()

function Start-SusRead {
    if ($script:SusReader) { return }
    $script:SusState = 'running'
    $script:SusReader = Start-Tracked 'suspects' @{} {
        $script:SusReader = $null
        if ($script:SusState -eq 'running') { $script:SusState = 'error' }
    }
    Update-View
}

# What was removed, with what puts it back (a list in suspects.json)
function Read-SusStore {
    try { if (Test-Path -LiteralPath $SuspectsPath) { return @([IO.File]::ReadAllText($SuspectsPath) | ConvertFrom-Json) } } catch { Add-LogLine "Suspicious changes: couldn't read ${SuspectsPath}: $($_.Exception.Message)" }
    return @()
}
function Save-SusStore($Entries) {
    try { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null; [IO.File]::WriteAllText($SuspectsPath, (ConvertTo-Json -InputObject @($Entries) -Depth 8), (New-Object Text.UTF8Encoding($false))) }
    catch { Add-LogLine "Suspicious changes: couldn't save ${SuspectsPath}: $($_.Exception.Message)" }
}

function New-SusItem($F, [bool]$Removed) {
    $x = New-Object WingetUM.SuspectItem
    $x.Key = [string]$F.Key; $x.Area = [string]$F.Area; $x.Name = [string]$F.Name; $x.Why = [string]$F.Why; $x.Location = [string]$F.Location
    $x.Target = if ($F.Target -and (Test-Path -LiteralPath ([string]$F.Target) -ErrorAction SilentlyContinue)) { [string]$F.Target } else { '' }; $x.Severity = [string]$F.Severity; $x.SeverityLevel = [int]$F.Level; $x.Fix = $F.Fix; $x.Fixable = $Removed -or [bool]$F.Fix
    $x.Removed = $Removed
    return $x
}
function Update-SusRows {
    $SusItems.Clear()
    foreach ($f in @($script:SusFound)) { $SusItems.Add((New-SusItem $f $false)) }
    foreach ($e in @(Read-SusStore)) { if ($e) { $x = New-SusItem $e $true; $x.Fix = $e; $x.Detail = "Removed $(([datetime]$e.Time).ToString('MMM d'))"; $x.State = ''; $SusItems.Add($x) } }
}
$EventHandlers.suspects = {
    param($Ev)
    $script:SusFound = @($Ev.Items)
    $script:SusState = 'ready'
    Update-SusRows
    Update-View
}

# The backup of a registry change: the value as it is (set and del), or every value in the key (delkey: the keys this
# removes hold values only)
function Get-SusBackupOps($Ops) {
    $undo = @()
    foreach ($o in @($Ops)) {
        if ($o.Do -in 'set', 'del') {
            $v = Get-RegValue ([string]$o.Path) ([string]$o.Name)
            $undo += if ($v.Existed) { @{ Do = 'set'; Path = [string]$o.Path; Name = [string]$o.Name; Kind = [string]$v.Kind; Data = $v.Data } } else { @{ Do = 'del'; Path = [string]$o.Path; Name = [string]$o.Name } }
        }
        elseif ($o.Do -eq 'delkey') {
            $k = Open-RegKey ([string]$o.Path)
            if ($k) { try { foreach ($n in $k.GetValueNames()) { $v = Get-RegValue ([string]$o.Path) $n; if ($v.Existed) { $undo += @{ Do = 'set'; Path = [string]$o.Path; Name = $n; Kind = [string]$v.Kind; Data = $v.Data } } } } finally { $k.Close() } }
        }
    }
    return , $undo
}

# Remove (Mode remove) or put back (Mode restore) the given rows: your own account's changes here and now, the rest in
# one administrator run that reports each one (RESULT|sus|n|ok or error)
function Invoke-SusChange($Items, [string]$Mode) {
    $jobs = @(foreach ($x in @($Items)) {
            if ($Mode -eq 'remove') {
                if (-not $x.CanRemove) { continue }
                $ops = @($x.Fix.Ops)
                $backup = Get-SusBackupOps $ops
                $undo = @($backup) + @($x.Fix.Undo | Where-Object { $_ })
                @{ Item = $x; Ops = $ops; Undo = $undo; Admin = [bool]$x.Fix.Admin -and -not $IsAdmin }
            }
            else {
                if (-not $x.CanRestore) { continue }
                @{ Item = $x; Ops = @($x.Fix.Restore); Admin = [bool]$x.Fix.Admin -and -not $IsAdmin }
            }
        })
    if (-not $jobs.Count) { return }
    $elev = @($jobs | Where-Object { $_.Admin })
    if ($elev.Count -and $script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first."; Update-View; return }
    foreach ($j in @($jobs | Where-Object { -not $_.Admin })) {
        $err = $null
        try { Invoke-RegOps $j.Ops } catch { $err = Get-ExtraError $_ }
        Complete-SusChange $j $Mode $err
    }
    if ($elev.Count) {
        $verb = if ($Mode -eq 'remove') { 'Removing' } else { 'Putting back' }
        $body = "function Invoke-RegOps {`r`n$(${function:Invoke-RegOps})`r`n}`r`n"
        for ($i = 0; $i -lt $elev.Count; $i++) {
            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($elev[$i].Ops) -Depth 6 -Compress)))
            $body += "Say ('$verb ' + '$($elev[$i].Item.Name -replace "'", "''")')`r`ntry { Invoke-RegOps ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) | ConvertFrom-Json); Say 'RESULT|sus|$i|ok' }`r`ncatch { `$e = `$_.Exception; while (`$e.InnerException) { `$e = `$e.InnerException }; Say ('RESULT|sus|$i|error|' + (`$e.Message -replace '[\r\n]+', ' ')) }`r`n"
            $elev[$i].Item.State = 'running'; $elev[$i].Item.Detail = 'Waiting for approval' + $Ellipsis
        }
        $body += 'exit 0'
        Start-Elevated 'suspects' "$verb $($elev.Count) suspicious change$(if ($elev.Count -ne 1) { 's' })" $body @() @{ Jobs = $elev; Mode = $Mode } -RestorePoint -RestoreText 'Before removing suspicious changes'
    }
    if (-not $elev.Count) { Start-SusRead }
    $SusView.Refresh()
    Update-View
}
$ElevHandlers.suspects = {
    param($Ev, $why, $code, $last, $tag)
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8) } else { @() }
    $res = @{}
    foreach ($l in @($lines | Where-Object { $_ -like 'RESULT|sus|*' })) { $p = $l.Split('|', 5); $res[[int]$p[2]] = $(if ($p[3] -eq 'ok') { '' } else { [string]$p[4] }) }
    for ($i = 0; $i -lt @($tag.Jobs).Count; $i++) {
        $err = if ($res.ContainsKey($i)) { $res[$i] } elseif ($why) { $why } else { "Didn't finish$(if ($last) { ": $last" })" }
        Complete-SusChange $tag.Jobs[$i] $tag.Mode $err
    }
    Start-SusRead
    $SusView.Refresh()
}
function Complete-SusChange($Job, [string]$Mode, [string]$Err) {
    $x = $Job.Item
    if ($Err) { $x.State = 'error'; $x.Detail = "Didn't $(if ($Mode -eq 'remove') { 'remove' } else { 'put back' }): $Err"; return }
    $store = @(Read-SusStore | Where-Object { $_ -and $_.Key -ne $x.Key })
    if ($Mode -eq 'remove') {
        $store += [pscustomobject]@{ Key = $x.Key; Area = $x.Area; Name = $x.Name; Why = $x.Why; Location = $x.Location; Target = $x.Target; Severity = $x.Severity; Level = $x.SeverityLevel
            Time = (Get-Date).ToString('o'); Restore = @($Job.Undo); Admin = [bool]$x.Fix.Admin }
        $x.Fix = $store[-1]; $x.Selected = $false; $x.Removed = $true; $x.State = 'ok'
        $x.Detail = if ($Job.Item.Fix.Note) { $Job.Item.Fix.Note } else { 'Removed' }
        Add-History 'suspectremove' $x.Name $x.Location '' '' 'ok' $x.Why
    }
    else {
        $x.Removed = $false; $x.Fixable = $false; $x.State = 'ok'; $x.Detail = 'Put back'
        Add-History 'suspectrestore' $x.Name $x.Location '' '' 'ok' 'Put back as it was'
    }
    Save-SusStore $store
    $script:LastSummary = "$($x.Name): $($x.Detail)"
}

# The location: the program's file in Explorer, the registry key in Registry Editor, or Task Scheduler
function Open-SusLocation($X) {
    try {
        $t = [string]$X.Target
        if ($t -and (Test-Path -LiteralPath $t)) { Start-Process explorer.exe -ArgumentList "/select,`"$t`""; return }
        $loc = [string]$X.Location
        if ($loc -like 'Task Scheduler:*') { Start-Process taskschd.msc; return }
        if ($loc -match '^(HKLM|HKCU)\\') {
            # Registry Editor opens at the key it last showed
            $key = ($loc -replace '^HKLM\\', 'HKEY_LOCAL_MACHINE\' -replace '^HKCU\\', 'HKEY_CURRENT_USER\')
            if (-not (Test-RegKey $loc)) { $key = Split-Path -Parent $key }
            $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Applets\Regedit')
            try { $k.SetValue('LastKey', "Computer\$key") } finally { $k.Close() }
            Start-Process regedit.exe -ArgumentList '-m'
            return
        }
        if ($loc -and (Test-Path -LiteralPath $loc)) { Start-Process explorer.exe -ArgumentList "/select,`"$loc`""; return }
        $script:LastSummary = "Nothing to open for $($X.Name)."; Update-View
    }
    catch { $script:LastSummary = "Couldn't open it: $($_.Exception.Message)"; Update-View }
}

# The Suspicious changes view (the Security header and buttons are shared; Update-SecView calls this)
function Update-SusView {
    $open = @($SusItems | Where-Object { -not $_.Removed })
    $high = @($open | Where-Object { $_.Severity -eq 'High' }).Count
    if (-not ($script:SecScan -and $script:Elev -and $script:ElevName -eq 'secscan')) {
        $UI.SecTitle.Text = if ($script:SusState -eq 'running' -and -not $SusItems.Count) { "Checking for suspicious changes$Ellipsis" }
        elseif ($open.Count) { "$($open.Count) suspicious change$(if ($open.Count -ne 1) { 's' })$(if ($high) { ", $high very likely" })" }
        elseif ($script:SusState -eq 'ready') { 'No suspicious changes found' } else { 'Suspicious changes' }
        $UI.SecText.Text = 'Startup keys and folders, scheduled tasks, services, sign-in, redirected programs, file-type commands, WMI, browser policies, the hosts file, a proxy and Defender''s settings. These are signs, not verdicts: look each one up before removing it. Remove saves what it changes, so Restore puts it back.'
        $UI.SecIcon.Background = if ($high) { '#5A2626' } elseif ($open.Count) { '#4A3A1A' } else { '#17414C' }
    }
    $ticked = @($SusItems | Where-Object { $_.Selected -and $_.CanRemove })
    $UI.SecRemoveText.Text = if ($ticked.Count) { "Remove ticked ($($ticked.Count))" } else { 'Remove ticked' }
    $UI.SecRemove.IsEnabled = $ticked.Count -gt 0
    $UI.SecRefresh.IsEnabled = -not $script:SusReader
    $can = @($SusItems | Where-Object { $_.CanRemove })
    $UI.SusCheckAll.IsEnabled = $can.Count -gt 0
    $sel = @($can | Where-Object { $_.Selected }).Count
    $UI.SusCheckAll.IsChecked = if (-not $can.Count -or -not $sel) { $false } elseif ($sel -eq $can.Count) { $true } else { $null }
    $msg = $null
    if ($script:SusState -eq 'running' -and -not $SusItems.Count) { $msg = @{ Bar = $true; Title = 'Checking for suspicious changes'; Text = 'Looking at startup places, the registry, scheduled tasks, services, WMI, browser policies and network settings. It takes a few seconds.' } }
    elseif ($script:SusState -eq 'error' -and -not $SusItems.Count) { $msg = @{ Title = "Couldn't finish the check"; Text = 'It stopped unexpectedly. Show the log for details.'; Action = 'Try again' } }
    elseif ($script:SusState -eq 'ready' -and -not $SusItems.Count) { $msg = @{ Title = 'No suspicious changes'; Text = "Nothing in the places malware usually changes looks out of place. Signed programs from known publishers aren't listed." } }
    $UI.SusHeader.Visibility = ConvertTo-Visibility (-not $msg)
    $UI.SusList.Visibility = if ($msg) { 'Collapsed' } else { 'Visible' }
    $UI.SecMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) {
        $UI.SecMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar)
        $UI.SecMsgTitle.Text = $msg.Title; $UI.SecMsgText.Text = $msg.Text
        $UI.SecMsgAction.Visibility = ConvertTo-Visibility ([bool]$msg.Action)
        if ($msg.Action) { $UI.SecMsgAction.Content = $msg.Action }
    }
}

function Request-SusChange($Items, [string]$Mode) {
    $items = @($Items | Where-Object { if ($Mode -eq 'remove') { $_.CanRemove } else { $_.CanRestore } })
    if (-not $items.Count) { return }
    $names = @($items | Select-Object -First 8 | ForEach-Object { "  $($_.Name)" })
    if ($items.Count -gt 8) { $names += "  and $($items.Count - 8) more" }
    $admin = @($items | Where-Object { $_.Fix.Admin }).Count -and -not $IsAdmin
    if ($Mode -eq 'remove') {
        Show-Confirm 'susremove' @{ Items = $items } "Remove $($items.Count) suspicious change$(if ($items.Count -ne 1) { 's' })?" "What each one changed is saved first, so Restore puts it back. Tasks are turned off and services stop starting by themselves rather than being deleted.$(if ($admin) { " Changes outside your account need one administrator approval$(if ($Settings.DriverRestorePoint) { ', after a restore point' })." })`n`n$($names -join "`n")" 'Remove' -Danger
    }
    else { Invoke-SusChange $items 'restore' }
}
$ConfirmHandlers.susremove = { param($Payload) Invoke-SusChange $Payload.Items 'remove' }

$UI.SecViewDefender.Add_Checked({ Update-View })
$UI.SecViewSuspects.Add_Checked({ if ($script:SusState -eq 'none') { Start-SusRead }; Update-View })
$UI.SusCheckAll.Add_Click({
        $on = $UI.SusCheckAll.IsChecked -eq $true
        foreach ($s in $SusItems) { if ($s.CanRemove) { $s.Selected = $on } }
        Update-View
    })
$UI.SusList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        $it = $src.DataContext
        if ($src -is [System.Windows.Controls.Button] -and $it -is [WingetUM.SuspectItem]) {
            if ($src.Tag -eq 'susscan') { Start-DefenderScan 'custom' @($it.Target) }
            elseif ($src.Tag -eq 'susact') { Request-SusChange @($it) $(if ($it.Removed) { 'restore' } else { 'remove' }) }
        }
        else { Update-View }
    })
[System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.MenuItem], [System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $it = $s.DataContext
        if ($it -isnot [WingetUM.SuspectItem]) { return }
        switch ($s.Tag) {
            'susopen' { Open-SusLocation $it }
            'susscan' { Start-DefenderScan 'custom' @($it.Target) }
            'suscopy' { [System.Windows.Clipboard]::SetText("$($it.Name)`r`n$($it.Why)`r`n$($it.Location)") }
        }
    })
# More scans: a menu under the button
$SecMoreMenu = New-Object System.Windows.Controls.ContextMenu
foreach ($m in @(@(('Scan a folder or drive' + $Ellipsis), { Select-ScanFolder }), @(('Offline scan (restarts the PC)' + $Ellipsis), { Start-OfflineScan }))) {
    $mi = New-Object System.Windows.Controls.MenuItem
    $mi.Header = $m[0]; $mi.Add_Click($m[1])
    [void]$SecMoreMenu.Items.Add($mi)
}
$UI.SecMore.ContextMenu = $SecMoreMenu
$UI.SecMore.Add_Click({ $SecMoreMenu.PlacementTarget = $UI.SecMore; $SecMoreMenu.Placement = 'Bottom'; $SecMoreMenu.IsOpen = $true })

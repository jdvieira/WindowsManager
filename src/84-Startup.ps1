# Windows Manager - Startup (part of src\; see Windows_Manager.ps1)

# The Startup tab: apps that start when you sign in, turned on or off the way Task Manager does it (its
# StartupApproved values, or a Store app's startup task state), so Task Manager and Settings > Apps > Startup agree.
# Nothing is deleted. Apps that start for every user need administrator approval to change.
$StartupItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.StartupItem]'
$StartupView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($StartupItems)
$StartupView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Enabled', 'Descending')))
$StartupView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
$StartupView.Filter = [Predicate[object]] {
    param($s)
    if ($UI.StOffOnly.IsChecked -and $s.Enabled) { return $false }
    $q = $UI.StSearch.Text.Trim()
    return (-not $q) -or ("$($s.Name) $($s.Command) $($s.Publisher) $($s.LocationText)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$UI.StList.ItemsSource = $StartupView
$script:StartupState = 'none'      # none | running | ready | error
$script:StartupError = ''
$script:StartupReader = $null
$StartupApprovedKey = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'

function Start-StartupScan {
    if ($script:StartupReader) { return }
    $script:StartupState = 'running'
    $script:StartupReader = Start-Tracked 'startup' @{} {
        $script:StartupReader = $null
        if ($script:StartupState -eq 'running') { $script:StartupState = 'error'; $script:StartupError = 'Reading the startup apps stopped unexpectedly.' }
    }
    Update-View
}

$EventHandlers.startup = {
    param($Ev)
    $StartupItems.Clear()
    foreach ($i in @($Ev.Items)) {
        $s = New-Object WingetUM.StartupItem
        $s.Name = $i.Name; $s.Command = $i.Command; $s.Publisher = $i.Publisher; $s.Location = $i.Location; $s.LocationText = $i.LocationText
        $s.Entry = $i.Entry; $s.FilePath = $(if ($i.File) { $i.File } else { $i.Target }); $s.NeedsAdmin = [bool]$i.NeedsAdmin; $s.Enabled = [bool]$i.Enabled
        if ($i.Policy) { $s.State = 'policy'; $s.Detail = "Set by your organization ($(if ($s.Enabled) { 'on' } else { 'off' }))" }
        $StartupItems.Add($s)
    }
    if ($Ev.Error) { $script:StartupState = 'error'; $script:StartupError = $Ev.Error } else { $script:StartupState = 'ready' }
    Update-View
}

# StartupApproved data: 02 then zeros = allowed; 03 then the time it was turned off (a FILETIME) = turned off
function Get-ApprovedBytes([bool]$On) {
    if ($On) { return , [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) }
    # byte[] + byte[] makes an object[] in PowerShell, which the registry won't take as binary
    return , [byte[]](@(3, 0, 0, 0) + @([BitConverter]::GetBytes([DateTime]::UtcNow.ToFileTimeUtc())))
}
function Get-ApprovedSub([string]$Location) {
    switch ($Location) { 'hklm32' { 'Run32' } { $_ -in 'userfolder', 'commonfolder' } { 'StartupFolder' } default { 'Run' } }
}

function Set-StartupItem($s, [bool]$On) {
    if (-not $s -or -not $s.CanToggle) { return }
    if ($s.State -eq 'policy') { $script:LastSummary = "Your organization sets whether $($s.Name) starts with Windows."; Update-View; return }
    $verb = if ($On) { 'on' } else { 'off' }
    if (-not $s.NeedsAdmin -or $IsAdmin) {
        try {
            if ($s.Location -eq 'appx') {
                $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($s.Entry, $true)
                if (-not $k) { throw "the app's startup task is gone" }
                try { $k.SetValue('State', $(if ($On) { 2 } else { 1 }), 'DWord') } finally { $k.Close() }
            }
            else {
                $base = if ($s.NeedsAdmin) { [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64') } else { [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64') }
                $k = $base.CreateSubKey("$StartupApprovedKey\$(Get-ApprovedSub $s.Location)")
                try { $k.SetValue($s.Entry, (Get-ApprovedBytes $On), 'Binary') } finally { $k.Close(); $base.Close() }
            }
            $s.Enabled = $On; $s.State = 'ok'; $s.Detail = if ($On) { 'Turned on' } else { 'Turned off' }
            Add-History "startup$verb" $s.Name $s.LocationText '' '' 'ok' $(if ($On) { 'Starts with Windows again' } else { "Won't start with Windows" })
            $script:LastSummary = "$($s.Name) $(if ($On) { 'starts with Windows again' } else { "won't start with Windows any more" })"
        }
        catch { $s.State = 'error'; $s.Detail = "Couldn't change it: $($_.Exception.Message)" }
        $StartupView.Refresh()
        Update-View
        return
    }
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first."; Update-View; return }
    $bytes = (Get-ApprovedBytes $On) -join ','
    $sub = "$StartupApprovedKey\$(Get-ApprovedSub $s.Location)" -replace "'", "''"
    $body = @"
`$k = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64').CreateSubKey('$sub')
`$k.SetValue('$($s.Entry -replace "'", "''")', [byte[]]@($bytes), 'Binary'); `$k.Close()
Say 'Turned $verb.'
exit 0
"@
    $s.State = 'running'; $s.Detail = 'Waiting for approval' + $Ellipsis
    Start-Elevated 'startup' "Turning $verb $($s.Name) at startup" $body @() @{ Item = $s; On = $On }
}
$ElevHandlers.startup = {
    param($Ev, $why, $code, $last, $tag)
    $s = $tag.Item
    if ($why) { $s.State = 'error'; $s.Detail = $why }
    elseif ($code -eq 0) {
        $s.Enabled = $tag.On; $s.State = 'ok'; $s.Detail = if ($tag.On) { 'Turned on' } else { 'Turned off' }
        Add-History "startup$(if ($tag.On) { 'on' } else { 'off' })" $s.Name $s.LocationText '' '' 'ok' $(if ($tag.On) { 'Starts with Windows again' } else { "Won't start with Windows" })
    }
    else { $s.State = 'error'; $s.Detail = "Couldn't change it$(if ($last) { ": $last" })" }
    $script:LastSummary = "$($s.Name): $($s.Detail)"
    $StartupView.Refresh()
}

function Open-StartupLocation($s) {
    $p = [Environment]::ExpandEnvironmentVariables([string]$s.FilePath)
    try {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { Start-Process explorer.exe -ArgumentList "/select,`"$p`"" }
        elseif ($p -and (Test-Path -LiteralPath $p)) { Start-Process explorer.exe -ArgumentList "`"$p`"" }
        else { $script:LastSummary = "The file it starts wasn't found ($(if ($p) { $p } else { 'no path' }))."; Update-View }
    }
    catch { }
}

function Update-StartupView {
    $on = @($StartupItems | Where-Object { $_.Enabled }).Count
    $off = $StartupItems.Count - $on
    $UI.StText.Text = if ($script:StartupState -eq 'ready') { "$on app$(if ($on -ne 1) { 's' }) start when you sign in$(if ($off) { "; $off $(if ($off -ne 1) { 'are' } else { 'is' }) turned off" }). Turning one off only stops it starting by itself: it still works when you open it. Apps marked with a shield start for every user, so changing them asks for administrator approval." }
    elseif ($script:StartupState -eq 'running') { "Reading the apps that start with Windows$Ellipsis" } else { '' }
    $UI.StRefresh.IsEnabled = -not $script:StartupReader
    $msg = $null
    if ($script:StartupState -eq 'running' -and -not $StartupItems.Count) { $msg = @{ Bar = $true; Title = 'Reading startup apps'; Text = 'Looking in the registry, the Startup folders and Store apps.' } }
    elseif ($script:StartupState -eq 'error' -and -not $StartupItems.Count) { $msg = @{ Title = "Couldn't read the startup apps"; Text = $script:StartupError; Action = 'Try again' } }
    elseif ($script:StartupState -eq 'ready' -and -not $StartupItems.Count) { $msg = @{ Title = 'Nothing starts with Windows'; Text = 'No apps are set to start when you sign in.' } }
    elseif ($StartupItems.Count -and -not @($StartupView).Count) { $msg = @{ Title = $(if ($UI.StOffOnly.IsChecked -and -not $UI.StSearch.Text) { 'Nothing is turned off' } else { 'No apps match' }); Text = '' } }
    $UI.StHeader.Visibility = ConvertTo-Visibility (-not $msg)
    $UI.StList.Visibility = if ($msg) { 'Collapsed' } else { 'Visible' }
    $UI.StMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) {
        $UI.StMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar)
        $UI.StMsgTitle.Text = $msg.Title; $UI.StMsgText.Text = $msg.Text
        $UI.StMsgAction.Visibility = ConvertTo-Visibility ([bool]$msg.Action)
        if ($msg.Action) { $UI.StMsgAction.Content = $msg.Action }
    }
}

$Panels.startup = @{
    Panel   = 'StartupPanel'
    Update  = { Update-StartupView }
    Status  = {
        if ($script:StartupReader) { "Reading startup apps$Ellipsis" }
        elseif ($script:StartupState -eq 'ready') {
            $on = @($StartupItems | Where-Object { $_.Enabled }).Count
            "$on app$(if ($on -ne 1) { 's' }) start with Windows"
            $off = $StartupItems.Count - $on
            if ($off) { "$off turned off" }
        }
    }
    Open    = { if ($script:StartupState -eq 'none') { Start-StartupScan } }
    Refresh = { Start-StartupScan }
}

$UI.TabStartup.Add_Checked({ Set-Section 'startup' })
$UI.StRefresh.Add_Click({ Start-StartupScan })
$UI.StMsgAction.Add_Click({ Start-StartupScan })
$UI.StOffOnly.Add_Click({ $StartupView.Refresh(); Update-View })
$UI.StOpenTaskMgr.Add_Click({ try { Start-Process taskmgr.exe -ArgumentList '/7 /startup' } catch { try { Start-Process taskmgr.exe } catch { } } })
$script:StSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:StSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:StSearchTimer.Add_Tick({ $script:StSearchTimer.Stop(); $StartupView.Refresh(); Update-View })
$UI.StSearch.Add_TextChanged({ $script:StSearchTimer.Stop(); $script:StSearchTimer.Start() })
$UI.StList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'sttoggle') { Set-StartupItem $src.DataContext (-not $src.DataContext.Enabled) }
    })
# The row's right-click menu (menu items are handled at class level, like the app list's)
[System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.MenuItem], [System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $it = $s.DataContext
        if ($it -isnot [WingetUM.StartupItem]) { return }
        switch ($s.Tag) {
            'sttoggle' { Set-StartupItem $it (-not $it.Enabled) }
            'stopen' { Open-StartupLocation $it }
            'stcopy' { [System.Windows.Clipboard]::SetText([string]$it.Command) }
        }
    })

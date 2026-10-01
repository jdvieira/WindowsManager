# Windows Manager - Options (part of src\; see Windows_Manager.ps1)

$WingetLogDir = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe\LocalState\DiagOutputDir'
$script:OptHidden = New-Object 'System.Collections.Generic.List[string]'
$script:ImportedSchedule = $null
$script:Maint = $null
$script:MaintNext = $null
$script:WingetVersion = $null

function Show-OptionsPage([string]$Name) {
    foreach ($p in 'PageUpdates', 'PageSources', 'PageAuto', 'PageLogs', 'PageApp', 'PageMaint') { $UI[$p].Visibility = if ($p -eq $Name) { 'Visible' } else { 'Collapsed' } }
}

function Set-OptionMessage([string]$Text, [switch]$IsError) {
    $UI.OptMessage.Text = $Text
    $UI.OptMessage.Foreground = $Window.FindResource($(if ($IsError) { 'Bad' } else { 'Muted' }))
}

# The Hidden list on the Packages page
function Update-IdList([string]$Kind) {
    $list = $script:OptHidden
    $panel = $UI.OptHiddenList
    $empty = $UI.OptHiddenEmpty
    $panel.Children.Clear()
    foreach ($id in @($list | Sort-Object)) {
        $row = New-Object System.Windows.Controls.DockPanel
        $row.Margin = '0,0,0,6'
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = 'Remove'; $btn.Tag = "$Kind|$id"; $btn.Style = $Window.FindResource('Ghost'); $btn.Margin = '8,0,0,0'
        $btn.Add_Click({
                param($s, $e)
                $kind, $id = ([string]$s.Tag).Split('|', 2)
                $l = $script:OptHidden
                [void]$l.Remove($id)
                Update-IdList $kind
            })
        [System.Windows.Controls.DockPanel]::SetDock($btn, 'Right')
        $label = New-Object System.Windows.Controls.TextBlock
        $label.Text = $id; $label.FontFamily = 'Consolas'; $label.VerticalAlignment = 'Center'; $label.Foreground = $Window.FindResource('Highlight')
        [void]$row.Children.Add($btn); [void]$row.Children.Add($label)
        [void]$panel.Children.Add($row)
    }
    $empty.Visibility = if ($list.Count) { 'Collapsed' } else { 'Visible' }
}


function Add-OptionId([string]$Kind, $Box) {
    $id = $Box.Text.Trim()
    $list = $script:OptHidden
    if ($id -and $id -notmatch '\s' -and -not $list.Contains($id)) { $list.Add($id); Update-IdList $Kind }
    $Box.Text = ''
}

# Fills every control from a settings table (the saved settings, the defaults, or an import)
function Set-OptionControls($S) {
    $UI.OptSrcAll.IsChecked = -not $S.Source
    $UI.OptSrcWinget.IsChecked = $S.Source -eq 'winget'
    $UI.OptSrcStore.IsChecked = $S.Source -eq 'msstore'
    $UI.OptScopeDefault.IsChecked = -not $S.InstallScope
    $UI.OptScopeUser.IsChecked = $S.InstallScope -eq 'user'
    $UI.OptScopeMachine.IsChecked = $S.InstallScope -eq 'machine'
    $UI.OptSilent.IsChecked = $S.Silent
    $UI.OptUnknown.IsChecked = $S.IncludeUnknown
    $UI.OptUninstallPrev.IsChecked = $S.UninstallPrevious
    $UI.OptScanOnOpen.IsChecked = $S.ScanOnOpen

    $script:OptHidden.Clear()
    foreach ($id in @($S.Hidden)) { if ($id -and -not $script:OptHidden.Contains($id)) { $script:OptHidden.Add($id) } }
    Update-IdList 'Hidden'
    $UI.OptRetry.IsChecked = $S.AutoRetry
    $UI.OptRestorePoint.IsChecked = $S.RestorePoint
    $UI.OptNetwork.IsChecked = $S.RequireNetwork
    $UI.OptAC.IsChecked = $S.RequireAC
    $UI.OptDelay.Text = [string]$S.RandomDelayMin
    $UI.OptMaxHours.Text = [string]$S.MaxRunHours
    $UI.OptDismiss.Text = [string]$S.AutoDismissMin
    $UI.OptRetention.Text = [string]$S.LogRetentionDays
    $UI.OptLogDir.Text = $S.LogDir
    $UI.OptVerbose.IsChecked = $S.VerboseLogs
    $UI.OptNotifyToast.IsChecked = $S.NotifyStyle -ne 'window'
    $UI.OptAppCheck.IsChecked = $S.AppUpdateCheck
    $UI.OptAppAuto.IsChecked = $S.AppUpdateAuto
    $UI.OptNotifyWindow.IsChecked = $S.NotifyStyle -eq 'window'
    $script:OptLearned = @($S.WindowsUpdated)
    $script:OptToWinget = @($S.WingetUpdates)
    Update-WinUpdatedText
}

# The Packages page's "Updated by Windows" list: the built-in apps, the learned ones, and those set back to winget
function Update-WinUpdatedText {
    $left = @($SelfUpdatingIds | Where-Object { $script:OptToWinget -notcontains $_ }) + @($script:OptLearned)
    $t = "Left to Windows: $(if ($left.Count) { ($left | Sort-Object -Unique) -join ', ' } else { 'none' })."
    if (@($script:OptLearned).Count) { $t += "`nLearned from failed updates: $(@($script:OptLearned) -join ', ')." }
    if (@($script:OptToWinget).Count) { $t += "`nSet back to winget: $(@($script:OptToWinget) -join ', ')." }
    $UI.OptWinUpdated.Text = $t
    $UI.OptWinUpdReset.IsEnabled = (@($script:OptLearned).Count + @($script:OptToWinget).Count) -gt 0
}

function Read-OptionInt($Box, [int]$Min, [int]$Max, [string]$Label) {
    $v = 0
    if (-not [int]::TryParse($Box.Text.Trim(), [ref]$v) -or $v -lt $Min -or $v -gt $Max) { throw "$Label must be a whole number from $Min to $Max." }
    return $v
}

# Validates the controls and returns the new settings (throws a readable message on bad input)
function Read-OptionControls {
    $n = @{}
    foreach ($k in $Settings.Keys) { $n[$k] = $Settings[$k] }
    $n.Source = if ($UI.OptSrcWinget.IsChecked) { 'winget' } elseif ($UI.OptSrcStore.IsChecked) { 'msstore' } else { '' }
    $n.InstallScope = if ($UI.OptScopeUser.IsChecked) { 'user' } elseif ($UI.OptScopeMachine.IsChecked) { 'machine' } else { '' }
    $n.Silent = [bool]$UI.OptSilent.IsChecked
    $n.IncludeUnknown = [bool]$UI.OptUnknown.IsChecked
    $n.UninstallPrevious = [bool]$UI.OptUninstallPrev.IsChecked
    $n.ScanOnOpen = [bool]$UI.OptScanOnOpen.IsChecked
    $n.Excluded = @()
    $n.Hidden = @($script:OptHidden | Sort-Object -Unique)
    $n.AutoRetry = [bool]$UI.OptRetry.IsChecked
    $n.RestorePoint = [bool]$UI.OptRestorePoint.IsChecked
    $n.RequireNetwork = [bool]$UI.OptNetwork.IsChecked
    $n.RequireAC = [bool]$UI.OptAC.IsChecked
    $n.RandomDelayMin = Read-OptionInt $UI.OptDelay 0 60 'Random start delay'
    $n.MaxRunHours = Read-OptionInt $UI.OptMaxHours 1 24 'Stop a run after'
    $n.AutoDismissMin = Read-OptionInt $UI.OptDismiss 0 240 'Close success notifications after'
    $n.LogRetentionDays = Read-OptionInt $UI.OptRetention 1 365 'Keep logs for'
    $n.VerboseLogs = [bool]$UI.OptVerbose.IsChecked
    $n.NotifyStyle = if ($UI.OptNotifyWindow.IsChecked) { 'window' } else { 'toast' }
    $n.AppUpdateCheck = [bool]$UI.OptAppCheck.IsChecked
    $n.AppUpdateAuto = [bool]$UI.OptAppAuto.IsChecked
    $n.WindowsUpdated = @($script:OptLearned | Where-Object { $_ })
    $n.WingetUpdates = @($script:OptToWinget | Where-Object { $_ })
    $dir = $UI.OptLogDir.Text.Trim()
    if ($dir -and [Environment]::ExpandEnvironmentVariables($dir) -ne $DefaultLogDir) {
        $full = [Environment]::ExpandEnvironmentVariables($dir)
        try {
            New-Item -ItemType Directory -Path $full -Force -ErrorAction Stop | Out-Null
            $probe = Join-Path $full ('.write_test_{0}' -f [guid]::NewGuid().ToString('N'))
            [IO.File]::WriteAllText($probe, ''); Remove-Item -LiteralPath $probe -Force
        }
        catch { throw "The log folder can't be used: $($_.Exception.Message)" }
        $n.LogDir = $dir
    }
    else { $n.LogDir = '' }
    return $n
}

# Starts "winget --version" in the background; Complete-Maintenance stores the answer and refreshes the Options page
function Start-WingetVersion {
    if (-not $WingetPath -or $script:VersionPending) { return }
    $script:VersionPending = $true
    $script:Showers.Add((Start-Background 'command' @{ Name = 'version'; Args = @('--version') }))
}

function Get-WingetVersion {
    if (-not $WingetPath) { return $null }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $WingetPath; $psi.Arguments = '--version'
        $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.RedirectStandardOutput = $true
        $p = [Diagnostics.Process]::Start($psi)
        $out = $p.StandardOutput.ReadToEnd().Trim()
        [void]$p.WaitForExit(10000)
        return $out
    }
    catch { return $null }
}

function Update-OptionInfo {
    $UI.OptVersion.Text = "Windows Manager v$AppVersion`nSettings: $SettingsPath"
    $UI.OptLogHint.Text = "Leave empty for the default ($DefaultLogDir). Logs are being written to $LogDir."
    $s = Get-AutoSchedule
    $UI.OptTaskNote.Text = if ($s -and $s.Elevated -and -not $IsAdmin) { "These settings apply to the scheduled task ($(Format-Schedule $s)). Because the task runs elevated, changing any of them asks for administrator approval when you click Save. Other options save without a prompt." }
    elseif ($s) { "These settings apply to the scheduled task ($(Format-Schedule $s)). Saving updates the task." }
    else { 'There is no scheduled task yet. These settings apply once you turn on Automatic updates.' }
    if (-not $script:WingetVersion) { Start-WingetVersion }
    Update-WingetInfo
    Update-MaintenanceButtons
}

function Update-WingetInfo {
    $UI.OptWingetInfo.Text = if ($WingetPath) { "winget $(if ($script:WingetVersion) { $script:WingetVersion } else { "(reading version$Ellipsis)" })`n$WingetPath" }
    else { 'winget was not found. Install or update App Installer from the Microsoft Store.' }
}

function Open-Options {
    Set-OptionControls $Settings
    $script:ImportedSchedule = $null
    Set-OptionMessage ''
    $UI.OptMaintStatus.Visibility = 'Collapsed'
    if ($UI.OptNav.SelectedIndex -lt 0) { $UI.OptNav.SelectedIndex = 0 }
    Update-OptionInfo
    Update-AppUpdateStatus
    Update-SourceList
    Start-SourceList
    $UI.OptionsOverlay.Visibility = 'Visible'
}

function Save-Options {
    try { $n = Read-OptionControls }
    catch { Set-OptionMessage $_.Exception.Message -IsError; return }
    $rescan = $n.IncludeUnknown -ne $Settings.IncludeUnknown -or $n.Source -ne $Settings.Source
    # Compared with the task itself, so a task that predates an option (or was edited in Task Scheduler) is brought in line
    $current = Get-AutoSchedule
    $taskChanged = $current -and @('RequireNetwork', 'RequireAC', 'RandomDelayMin', 'MaxRunHours' | Where-Object { $n[$_] -ne $current[$_] }).Count -gt 0
    $logChanged = $n.LogDir -ne $Settings.LogDir -or $n.LogRetentionDays -ne $Settings.LogRetentionDays
    $wasHidden = @($Settings.Hidden)
    foreach ($k in @($n.Keys)) { $Settings[$k] = $n[$k] }
    Save-Settings
    if ($logChanged) { Set-LogLocation; Remove-OldLogs }
    foreach ($p in @($Packages) + @($InstalledItems)) { $p.Hidden = $Settings.Hidden -contains $p.Id; if ($p.Hidden -and $p.IsUpdates) { $p.Selected = $false } }
    Update-SelfUpdatingRows
    Sync-HiddenPins $wasHidden @($Settings.Hidden)

    # The task carries the run conditions, so an existing task (or an imported schedule) is registered again
    $schedule = if ($script:ImportedSchedule) { $script:ImportedSchedule } elseif ($taskChanged) { $current } else { $null }
    if ($schedule) {
        $Window.Cursor = [System.Windows.Input.Cursors]::Wait
        $why = if ($script:ImportedSchedule) { 'the imported schedule' } else { (@('RequireNetwork', 'RequireAC', 'RandomDelayMin', 'MaxRunHours' | Where-Object { $n[$_] -ne $current[$_] }) -join ', ') }
        Add-LogLine "Updating the scheduled task ($why)$(if ($schedule.Elevated -and -not $IsAdmin) { '; this needs administrator approval because the task runs elevated' })."
        try { Invoke-TaskAction (New-RegisterSpec $schedule); $script:ImportedSchedule = $null }
        catch { Set-OptionMessage "Options were saved, but the scheduled task wasn't updated: $($_.Exception.Message)" -IsError; return }
        finally { $Window.Cursor = $null }
        Update-ScheduleSummary
    }
    Add-LogLine 'Options saved.'
    $UI.OptionsOverlay.Visibility = 'Collapsed'
    if ($rescan -and $script:Mode -ne 'idle') { Start-Scan }
    Update-View
}

# Apps added to the hidden list in Options get their pin, removed ones lose it (one background run, in order)
function Sync-HiddenPins($Before, $After) {
    if (-not $WingetPath) { return }
    $ops = @()
    foreach ($id in @($After | Where-Object { $Before -notcontains $_ -and -not $script:Pins.ContainsKey($_) })) {
        $row = @(@($Packages) + @($InstalledItems) | Where-Object { $_.Id -eq $id -and $_.Source }) | Select-Object -First 1
        $ops += @{ Args = (Get-PinArgs $id $(if ($row) { $row.Source } else { '' }) $true); Tag = @{ Id = $id; Name = $(if ($row) { $row.Name } else { $id }); Version = $(if ($row) { $row.Version } else { '' }); On = $true } }
    }
    foreach ($id in @($Before | Where-Object { $After -notcontains $_ -and $script:Pins.ContainsKey($_) })) {
        $row = @(@($Packages) + @($InstalledItems) | Where-Object { $_.Id -eq $id }) | Select-Object -First 1
        $ops += @{ Args = (Get-PinArgs $id '' $false); Tag = @{ Id = $id; Name = $(if ($row) { $row.Name } else { $id }); Version = $(if ($row) { $row.Version } else { '' }); On = $false } }
    }
    if ($ops.Count) { Add-LogLine ''; Add-LogLine "---- Updating winget pins for the hidden list ($($ops.Count)) ----"; $script:Showers.Add((Start-Background 'pinmany' @{ Ops = $ops })) }
}

function Update-MaintenanceButtons {
    $free = [bool]$WingetPath -and -not $script:Maint -and -not $script:Scanner -and -not $script:Worker -and $Sync.Jobs.Count -eq 0
    $UI.OptSrcUpdate.IsEnabled = $free
    $UI.OptSrcReset.IsEnabled = $free
    $UI.OptSrcAdd.IsEnabled = $free
    foreach ($b in $script:SourceButtons) { $b.IsEnabled = $free }
}

# Sources (winget source export), read in the background whenever the Options panel opens or a source changes
$script:SourceButtons = New-Object System.Collections.Generic.List[object]
function Start-SourceList {
    if (-not $WingetPath -or $script:SourceReading) { return }
    $script:SourceReading = $true
    $script:Showers.Add((Start-Background 'sources' @{}))
}

function Complete-Sources($Ev) {
    $script:SourceReading = $false
    $script:SourceError = $Ev.Error
    if (-not $Ev.Error) { $script:Sources = @($Ev.Sources) }
    if ($UI.OptionsOverlay.Visibility -eq 'Visible') { Update-SourceList }
}

function Update-SourceList {
    $UI.OptSourceList.Children.Clear()
    $script:SourceButtons.Clear()
    $muted = $Window.FindResource('Muted')
    $conv = New-Object System.Windows.Media.BrushConverter
    foreach ($s in @($script:Sources)) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = $conv.ConvertFrom('#1C1C1C'); $card.CornerRadius = 8; $card.Padding = '14,11'; $card.Margin = '0,0,0,8'
        $dock = New-Object System.Windows.Controls.DockPanel
        $right = New-Object System.Windows.Controls.StackPanel
        $right.Orientation = 'Horizontal'; $right.VerticalAlignment = 'Center'
        [System.Windows.Controls.DockPanel]::SetDock($right, 'Right')
        $use = New-Object System.Windows.Controls.CheckBox
        $use.Content = 'In searches'; $use.IsChecked = -not [bool]$s.Explicit; $use.Tag = [string]$s.Name; $use.Margin = '12,0,14,0'; $use.VerticalAlignment = 'Center'
        $use.ToolTip = 'On: winget searches and checks this source for updates. Off (explicit): only when a package asks for it by name.'
        $use.Add_Click({ param($s, $e) Invoke-SourceChange @('source', 'edit', '--name', [string]$s.Tag, '--explicit', $(if ($s.IsChecked) { 'false' } else { 'true' }), '--disable-interactivity') "Changing the source $($s.Tag)" })
        $rm = New-Object System.Windows.Controls.Button
        $rm.Content = 'Remove'; $rm.Style = $Window.FindResource('Ghost'); $rm.Margin = '0'; $rm.Tag = [string]$s.Name
        $rm.Add_Click({ param($s, $e)
                $n = [string]$s.Tag
                Show-Confirm 'srcremove' @{ Name = $n } "Remove the source $n?" "winget stops finding and updating apps from $n. Apps already installed from it stay installed. Reset sources brings back winget's default sources." 'Remove' -Danger })
        [void]$right.Children.Add($use); [void]$right.Children.Add($rm)
        $script:SourceButtons.Add($use); $script:SourceButtons.Add($rm)
        $left = New-Object System.Windows.Controls.StackPanel
        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = [string]$s.Name; $head.FontWeight = 'SemiBold'; $head.Foreground = [System.Windows.Media.Brushes]::White
        $kind = New-Object System.Windows.Controls.TextBlock
        $kind.Text = $(if ($s.Type -eq 'Microsoft.Rest') { 'REST source' } else { 'Pre-indexed source' }) + $(if ($s.Explicit) { "  $Dot  only when named" } else { '' })
        $kind.Foreground = $muted; $kind.FontSize = 12; $kind.Margin = '0,2,0,0'
        $arg = New-Object System.Windows.Controls.TextBlock
        $arg.Text = [string]$s.Arg; $arg.FontFamily = 'Consolas'; $arg.FontSize = 12; $arg.Foreground = $muted; $arg.TextWrapping = 'Wrap'; $arg.Margin = '0,2,0,0'
        [void]$left.Children.Add($head); [void]$left.Children.Add($kind); [void]$left.Children.Add($arg)
        [void]$dock.Children.Add($right); [void]$dock.Children.Add($left)
        $card.Child = $dock
        [void]$UI.OptSourceList.Children.Add($card)
    }
    $n = @($script:Sources).Count
    $UI.OptSourceEmpty.Text = if ($script:SourceError) { "Couldn't read winget's sources: $($script:SourceError)" } elseif ($n) { '' } elseif ($script:SourceReading) { "Reading sources$Ellipsis" } else { "winget has no sources. Reset sources to bring back the defaults." }
    $UI.OptSourceEmpty.Visibility = ConvertTo-Visibility ([bool]$UI.OptSourceEmpty.Text)
    Update-MaintenanceButtons
}

# Adding, removing and switching a source needs administrator rights: directly when elevated, otherwise through an
# elevated winget (one UAC prompt). The list is read again afterwards either way.
function Invoke-SourceChange([string[]]$WingetArgs, [string]$Message) {
    if (-not $WingetPath) { return }
    if ($IsAdmin) { Start-Maintenance 'source' $WingetArgs $Message; return }
    Show-MaintStatus "$Message`: waiting for administrator approval$Ellipsis"
    Add-LogLine ''
    Add-LogLine "---- $Message (elevated) ----"
    Add-LogLine "> winget $($WingetArgs -join ' ')"
    $argText = ($WingetArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ } }) -join ' '
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $p = Start-Process -FilePath $WingetPath -ArgumentList $argText -Verb RunAs -WindowStyle Hidden -PassThru -Wait
        $hex = '0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$p.ExitCode), 0)
        Add-LogLine "Exit code $hex"
        if ($p.ExitCode -ne 0) { Show-MaintStatus "$Message failed (winget exit code $hex). See the log." -IsError }
        else { Show-MaintStatus "$Message`: done." }
    }
    catch { Show-MaintStatus 'Administrator approval was declined, so the sources were not changed.' -IsError }
    finally { $Window.Cursor = $null }
    Start-SourceList
}

function Add-WingetSource {
    $name = $UI.OptSrcName.Text.Trim()
    $url = $UI.OptSrcUrl.Text.Trim()
    if ($name -notmatch '^[A-Za-z0-9._-]+$') { Show-MaintStatus 'Give the source a short name (letters, numbers, dots, dashes).' -IsError; return }
    if ($url -notmatch '^https?://\S+$') { Show-MaintStatus 'Enter the source URL, starting with https://.' -IsError; return }
    if (@($script:Sources | Where-Object { $_.Name -eq $name }).Count) { Show-MaintStatus "There is already a source named $name." -IsError; return }
    $wargs = @('source', 'add', '--name', $name, '--arg', $url, '--type', $(if ($UI.OptSrcTypeRest.IsChecked) { 'Microsoft.Rest' } else { 'Microsoft.PreIndexed.Package' }))
    if ($UI.OptSrcExplicit.IsChecked) { $wargs += '--explicit' }
    $wargs += '--accept-source-agreements', '--disable-interactivity'
    Invoke-SourceChange $wargs "Adding the source $name"
    $UI.OptSrcName.Text = ''; $UI.OptSrcUrl.Text = ''
}

function Show-MaintStatus([string]$Text, [switch]$IsError) {
    $UI.OptMaintStatus.Text = $Text
    $UI.OptMaintStatus.Foreground = $Window.FindResource($(if ($IsError) { 'Bad' } else { 'Muted' }))
    $UI.OptMaintStatus.Visibility = 'Visible'
}

function Start-Maintenance([string]$Name, [string[]]$WingetArgs, [string]$Message) {
    Add-LogLine ''
    Add-LogLine "---- $Message ----"
    Show-MaintStatus "$Message$Ellipsis"
    $script:Maint = Start-Background 'command' @{ Name = $Name; Args = $WingetArgs; Tag = $Message }
    Update-MaintenanceButtons
    Update-View
}

function Complete-Maintenance($Ev) {
    if ($Ev.Name -eq 'version') {
        $script:VersionPending = $false
        if ($Ev.Ok -and $Ev.Last) { $script:WingetVersion = $Ev.Last }
        if ($UI.OptionsOverlay.Visibility -eq 'Visible') { Update-WingetInfo }
        return
    }
    if ($Ev.Name -eq 'pin') { Complete-Pin $Ev; return }
    if ($Ev.Name -eq 'source') {
        if ($Ev.Ok) { Show-MaintStatus "$($Ev.Tag): done." } else { Show-MaintStatus "$($Ev.Tag) failed ($($Ev.Code)): $($Ev.Last)" -IsError }
        Start-SourceList
        return
    }
    if ($Ev.Name -eq 'update') { Start-SourceList }
    if ($Ev.Ok) {
        if ($Ev.Name -eq 'reset') { $script:MaintNext = 'update'; Show-MaintStatus "Sources reset. Updating them$Ellipsis" }
        else { Show-MaintStatus "Sources updated ($('{0:t}' -f (Get-Date))). Refresh to check for updates with them." }
    }
    else { Show-MaintStatus "winget failed ($($Ev.Code)): $($Ev.Last)" -IsError }
}

# Reset needs administrator rights: an elevated winget does the reset, then the sources are updated as usual
function Reset-WingetSources {
    if ($IsAdmin) { Start-Maintenance 'reset' @('source', 'reset', '--force', '--disable-interactivity') 'Resetting winget sources'; return }
    Show-MaintStatus "Waiting for administrator approval$Ellipsis"
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $p = Start-Process -FilePath $WingetPath -ArgumentList 'source', 'reset', '--force', '--disable-interactivity' -Verb RunAs -WindowStyle Hidden -PassThru -Wait
        Add-LogLine "Source reset (elevated) exit code $('0x{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$p.ExitCode), 0))"
        if ($p.ExitCode -ne 0) { Show-MaintStatus "The source reset failed (exit code $($p.ExitCode)). See the log." -IsError; return }
        Start-Maintenance 'update' @('source', 'update', '--disable-interactivity') 'Updating winget sources'
    }
    catch { Show-MaintStatus 'Administrator approval was declined, so the sources were not reset.' -IsError }
    finally { $Window.Cursor = $null }
}

function Export-Options {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Windows Manager settings (*.json)|*.json'
    $dlg.FileName = "WindowsManager-$env:COMPUTERNAME.json"
    if (-not $dlg.ShowDialog($Window)) { return }
    $s = Get-AutoSchedule
    $export = [ordered]@{
        App = $AppName; Version = $AppVersion; Exported = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME
        Settings = Get-SettingsCopy
        Schedule = $(if ($s) { [ordered]@{ Enabled = $s.Enabled; Frequency = $s.Frequency; Days = @($s.Days); Time = $s.Time; Elevated = $s.Elevated; CatchUp = $s.CatchUp } } else { $null })
    }
    try {
        $export | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dlg.FileName -Encoding UTF8
        Set-OptionMessage "Exported the saved options$(if ($s) { ' and schedule' }) to $([IO.Path]::GetFileName($dlg.FileName))."
    }
    catch { Set-OptionMessage "Export failed: $($_.Exception.Message)" -IsError }
}

function Import-Options {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Windows Manager settings (*.json)|*.json|All files (*.*)|*.*'
    if (-not $dlg.ShowDialog($Window)) { return }
    try {
        $data = Get-Content -LiteralPath $dlg.FileName -Raw | ConvertFrom-Json
        if (-not $data.Settings) { throw 'This file has no Windows Manager settings in it.' }
        $imported = New-DefaultSettings
        Merge-Settings $imported $data.Settings
        Set-OptionControls $imported
        $script:ImportedSchedule = if ($data.Schedule -and $data.Schedule.Enabled -and $data.Schedule.Time) { $data.Schedule } else { $null }
        $what = if ($script:ImportedSchedule) { "options and schedule ($(Format-Schedule $script:ImportedSchedule))" } else { 'options' }
        Set-OptionMessage "Imported $what from $([IO.Path]::GetFileName($dlg.FileName)). Review them, then click Save to apply."
    }
    catch { Set-OptionMessage "Import failed: $($_.Exception.Message)" -IsError }
}

function Select-LogFolder {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Choose the folder for Windows Manager logs'
    $dlg.SelectedPath = $LogDir
    if ($dlg.ShowDialog() -eq 'OK') { $UI.OptLogDir.Text = $dlg.SelectedPath }
}

# Windows Manager - Wiring (part of src\; see Windows_Manager.ps1)

$UI.SubTitle.Text = "Software, drivers and health on $env:COMPUTERNAME"
$UI.HeaderVersion.Text = "v$AppVersion"
if ($IsAdmin) {
    $UI.AdminText.Text = 'Administrator'
    $UI.AdminGlyph.Foreground = $Window.FindResource('Good')
    $UI.BtnElevate.Visibility = 'Collapsed'
}
else {
    $UI.AdminText.Text = 'Standard user'
    $UI.AdminGlyph.Foreground = $Window.FindResource('Muted')
    $UI.AdminBadge.ToolTip = 'Installers that need administrator rights will ask for approval (UAC) one by one.'
}

$UI.BtnRefresh.Add_Click({ if ($script:Section -eq 'installed') { Start-InstalledScan } else { Start-Scan } })
$UI.BtnRetry.Add_Click({
        $script:WingetPath = Find-Winget
        switch ($script:Section) { 'discover' { Start-Search } 'installed' { Start-InstalledScan } default { Start-Scan } }
    })
$UI.TabUpdates.Add_Checked({ Set-Section 'updates' })
$UI.TabDiscover.Add_Checked({ Set-Section 'discover' })
$UI.TabInstalled.Add_Checked({ Set-Section 'installed' })
$UI.TabDrivers.Add_Checked({ Set-Section 'drivers' })
$UI.DrvRestore.IsChecked = $Settings.DriverRestorePoint
$UI.DrvRestore.Add_Click({ Set-RestorePointSetting ([bool]$UI.DrvRestore.IsChecked) })

# Drivers tab
$UI.DrvToolAction.Add_Click({ $tool = Get-VendorTool; if ($tool -and -not $tool.Installed) { Invoke-ToolButton $tool } else { Start-DriverCheck } })
$UI.DrvOpenTool.Add_Click({ Open-VendorTool })
$UI.DrvSupport.Add_Click({ if ($UI.DrvSupport.Tag -match '^https?://') { try { Start-Process ([string]$UI.DrvSupport.Tag) } catch { } } })
$UI.DrvUpdates.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'drvaction') { Invoke-DriverAction $src.DataContext }
        Update-View
    })
$UI.DrvReinstallAll.Add_Click({ Request-DellDriverInstall })
$UI.DrvMsgAction.Add_Click({ if ([string]$UI.DrvMsgAction.Content -eq 'Stop waiting') { Stop-ElevatedWait } else { Start-DriverCheck } })
$UI.DrvNoteAction.Add_Click({ Stop-ElevatedWait })
$UI.DrvRefresh.Add_Click({ if ($UI.DrvViewUpdates.IsChecked) { Start-DriverCheck } else { Start-DeviceScan } })
$UI.DrvApply.Add_Click({ Request-DellApply })
$UI.DrvViewDevices.Add_Click({ Update-View })
$UI.DrvViewUpdates.Add_Click({ Update-View })
$UI.DrvProblemsOnly.Add_Click({ $DrvDevicesView.Refresh(); Update-View })
foreach ($chip in 'DrvTypeDriver', 'DrvTypeFirmware', 'DrvTypeBios', 'DrvTypeApp') { $UI[$chip].Add_Click({ Update-DrvIncluded; Update-View }) }
$script:DrvSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:DrvSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:DrvSearchTimer.Add_Tick({ $script:DrvSearchTimer.Stop(); $DrvDevicesView.Refresh(); $DrvUpdatesView.Refresh(); Update-View })
$UI.DrvSearch.Add_TextChanged({ $script:DrvSearchTimer.Stop(); $script:DrvSearchTimer.Start() })
$UI.DrvDevices.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -in 'reinstall', 'remove') { Request-DeviceAction $src.DataContext ([string]$src.Tag) }
        elseif ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'rollback') { Request-DeviceRollback $src.DataContext }
    })
$UI.BtnSearchGo.Add_Click({ Start-Search })
$UI.Search.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return' -and $script:Section -eq 'discover') { Start-Search; $e.Handled = $true } })
$UI.ChkWingetOnly.Add_Click({ $InstalledView.Refresh(); Update-View })
$UI.BtnInstallSelected.Add_Click({ Add-Job @($DiscoverItems | Where-Object { $_.Selected -and $_.CanUpdate }) })
$UI.BtnGetWinget.Add_Click({ try { Start-Process 'ms-windows-store://pdp/?productid=9NBLGGH4NNS1' } catch { Start-Process 'https://aka.ms/getwinget' } })
$UI.BtnUpdateAll.Add_Click({ Add-UpdateJob @($Packages | Where-Object { $_.CanUpdate -and -not $_.ExplicitTarget -and -not $_.Hidden }) })
$UI.BtnUpdateSelected.Add_Click({ Add-UpdateJob @($View | Where-Object { $_.Selected -and $_.CanUpdate }) })
$UI.BtnStop.Add_Click({ Stop-Queue })
$UI.BtnShowHidden.Add_Click({ $script:ShowHidden = -not $script:ShowHidden; $View.Refresh(); Update-View })
$UI.BtnElevate.Add_Click({ Restart-Elevated })
# Filtering waits for a short pause in typing, so each keystroke does not re-filter a long list
$script:SearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:SearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:SearchTimer.Add_Tick({ $script:SearchTimer.Stop(); (Get-SectionView).Refresh(); Update-View })
$UI.Search.Add_TextChanged({ $script:SearchTimer.Stop(); $script:SearchTimer.Start() })
$UI.SortName.Add_Click({ Set-Sort 'Name' })
$UI.SortSource.Add_Click({ Set-Sort 'Source' })
$UI.SortSize.Add_Click({ Set-Sort 'SizeKB' })
$UI.CheckAll.Add_Click({
        $on = $UI.CheckAll.IsChecked -eq $true
        foreach ($p in @(Get-SectionView)) { if ($p.CanUpdate) { $p.Selected = $on } }
        Update-View
    })
$UI.BtnLog.Add_Click({
        if ($UI.LogPanel.Visibility -eq 'Visible') { $UI.LogPanel.Visibility = 'Collapsed'; $UI.BtnLog.Content = 'Show log' }
        else {
            Write-LogBuffer; $UI.LogPanel.Visibility = 'Visible'; $UI.BtnLog.Content = 'Hide log'
            # a panel that was collapsed has no layout yet, so scroll once it has been measured and drawn
            $UI.LogPanel.UpdateLayout()
            $UI.LogBox.CaretIndex = $UI.LogBox.Text.Length
            $UI.LogBox.ScrollToEnd()
            [void]$Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Loaded, [action] { $UI.LogBox.ScrollToEnd() })
        }
    })
$UI.BtnLogFolder.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })

# Row buttons and check boxes: one handler on the list for every row
$UI.List.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'update') { Invoke-RowAction $src.DataContext }
        elseif ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'notes') { Show-Notes $src.DataContext }
        else { Update-View }
    })

# Double-click a row for its details
$UI.List.Add_MouseDoubleClick({
        param($s, $e)
        $el = $e.OriginalSource
        while ($el -and $el -isnot [System.Windows.Controls.ListBoxItem]) { $el = [System.Windows.Media.VisualTreeHelper]::GetParent($el) }
        if ($el -and $el.DataContext -is [WingetUM.Package] -and $e.OriginalSource -isnot [System.Windows.Controls.Primitives.ButtonBase]) { Show-Details $el.DataContext }
    })

# About
$UI.AboutVersion.Text = "Version $AppVersion"
$UI.BtnAbout.Add_Click({ $UI.AboutOverlay.Visibility = 'Visible' })
$UI.AboutClose.Add_Click({ $UI.AboutOverlay.Visibility = 'Collapsed' })
$UI.AboutCopy.Add_Click({ [System.Windows.Clipboard]::SetText('jdvieira@icloud.com'); $UI.AboutCopy.Content = 'Copied' })
$UI.AboutMail.Add_RequestNavigate({ param($s, $e) try { Start-Process $e.Uri.AbsoluteUri } catch { }; $e.Handled = $true })
$UI.AboutOverlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $UI.AboutOverlay) { $UI.AboutOverlay.Visibility = 'Collapsed' } })

# Details and confirmation overlays
$UI.DetClose.Add_Click({ $UI.DetailsOverlay.Visibility = 'Collapsed' })
$UI.DetAction.Add_Click({ $p = $script:DetailsItem; $UI.DetailsOverlay.Visibility = 'Collapsed'; Invoke-RowAction $p })
$UI.DetHomepage.Add_Click({ if ($UI.DetHomepage.Tag -match '^https?://') { try { Start-Process ([string]$UI.DetHomepage.Tag) } catch { } } })
$UI.DetailsOverlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $UI.DetailsOverlay) { $UI.DetailsOverlay.Visibility = 'Collapsed' } })
$UI.ConfirmYes.Add_Click({ Complete-Confirm $true })
$UI.ConfirmNo.Add_Click({ Complete-Confirm $false })

# Keep the column header aligned with the rows whether or not the list shows its scroll bar
$UI.List.AddHandler([System.Windows.Controls.ScrollViewer]::ScrollChangedEvent, [System.Windows.Controls.ScrollChangedEventHandler] {
        param($s, $e)
        $sv = $e.OriginalSource
        if ($sv -is [System.Windows.Controls.ScrollViewer]) {
            $UI.ColumnHeader.Padding = if ($sv.ComputedVerticalScrollBarVisibility -eq 'Visible') { '0,0,10,0' } else { '0' }
        }
    })

# Context menu items live in their own popup tree, so they are handled at class level
$script:MenuHandler = [System.Windows.RoutedEventHandler] {
    param($s, $e)
    $p = $s.DataContext
    if ($p -isnot [WingetUM.Package]) { return }
    switch ($s.Tag) {
        'update' { Invoke-RowAction $p }
        'interactive' { Invoke-RowAction $p -Interactive }
        'machine' { Invoke-RowAction $p -Scope 'machine' }
        'details' { Show-Details $p }
        'copyid' { [System.Windows.Clipboard]::SetText($p.Id) }
        'copycmd' { [System.Windows.Clipboard]::SetText((Get-WingetCommand $p)) }
        'hide' { if ($p.IsWindowsUpdated) { Set-WingetUpdates $p } else { Set-Hide $p (-not $p.IsConcealed) } }
        'notes' { Show-Notes $p }
        'version' { Open-VersionPicker $p }

    }
}
[System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.MenuItem], [System.Windows.Controls.MenuItem]::ClickEvent, $script:MenuHandler)

$Window.Add_KeyDown({
        param($s, $e)
        $ctrl = [System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control
        if ($e.Key -eq 'F5' -and $Panels[$script:Section]) { if ($Panels[$script:Section].Refresh) { & $Panels[$script:Section].Refresh }; $e.Handled = $true }
        elseif ($e.Key -eq 'F5' -and $UI.BtnRefresh.IsEnabled -and $UI.BtnRefresh.Visibility -eq 'Visible') { if ($script:Section -eq 'installed') { Start-InstalledScan } else { Start-Scan }; $e.Handled = $true }
        elseif ($ctrl -and $e.Key -eq 'F') { [void]$UI.Search.Focus(); $UI.Search.SelectAll(); $e.Handled = $true }
        elseif ($ctrl -and "$($e.Key)" -match '^(D|NumPad)([1-9])$') {
            # Ctrl+1 to Ctrl+9: the tabs, left to right
            $tabs = 'TabHealth', 'TabUpdates', 'TabDiscover', 'TabInstalled', 'TabStartup', 'TabDrivers', 'TabWindows', 'TabFeatures', 'TabCleanup'
            $UI[$tabs[[int]$Matches[2] - 1]].IsChecked = $true; $e.Handled = $true
        }
        elseif ($e.Key -eq 'Escape' -and $UI.ConfirmOverlay.Visibility -eq 'Visible') { Complete-Confirm $false; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.PickOverlay.Visibility -eq 'Visible') { $UI.PickOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.VersionOverlay.Visibility -eq 'Visible') { $UI.VersionOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.NotesOverlay.Visibility -eq 'Visible') { $UI.NotesOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.HistoryOverlay.Visibility -eq 'Visible') { $UI.HistoryOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.AboutOverlay.Visibility -eq 'Visible') { $UI.AboutOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.DetailsOverlay.Visibility -eq 'Visible') { $UI.DetailsOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.OptionsOverlay.Visibility -eq 'Visible') { $UI.OptionsOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and $UI.ScheduleOverlay.Visibility -eq 'Visible') { $UI.ScheduleOverlay.Visibility = 'Collapsed'; $e.Handled = $true }
        elseif ($e.Key -eq 'Escape' -and ($UI.Search.Text -or ($script:Section -eq 'discover' -and ($script:DiscoverQuery -or $script:DiscoverImport)))) {
            $UI.Search.Text = ''
            if ($script:Section -eq 'discover' -and ($script:DiscoverQuery -or $script:DiscoverImport) -and -not $script:Searcher) { Show-Starter; Update-View }
            $e.Handled = $true
        }
    })

# Drains worker events and collects finished runspaces
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(120)
$Timer.Add_Tick({
        try {
            Receive-WorkerEvents
            Write-LogBuffer
            if ($script:Scanner -and $script:Scanner.Handle.IsCompleted) {
                Complete-Background $script:Scanner
                $script:Scanner = $null
                if ($script:Mode -eq 'loading') { Set-SectionError 'updates' "Couldn't check for updates" 'The update check stopped unexpectedly. Show the log for details.' }
                Start-QueuedWork
                Update-View
            }
            if ($script:Searcher -and $script:Searcher.Handle.IsCompleted) {
                Complete-Background $script:Searcher
                $script:Searcher = $null
                if ($script:DiscoverMode -eq 'loading') { Set-SectionError 'discover' "Couldn't search winget" 'The search stopped unexpectedly. Show the log for details.' }
                Update-View
            }
            if ($script:Lister -and $script:Lister.Handle.IsCompleted) {
                Complete-Background $script:Lister
                $script:Lister = $null
                if ($script:InstalledMode -eq 'loading') { Set-SectionError 'installed' "Couldn't read the installed apps" 'Reading the list stopped unexpectedly. Show the log for details.' }
                Update-View
            }
            # ToArray, not @(): Windows PowerShell 5.1 throws "Argument types do not match" for @() over this list
            foreach ($sh in $script:Showers.ToArray()) { if ($sh.Handle.IsCompleted) { Complete-Background $sh; [void]$script:Showers.Remove($sh) } }
            if ($script:DescQueue.Count -or $script:NotesQueue.Count) { Step-Descriptions }
            if ($script:Sizer -and $script:Sizer.Handle.IsCompleted) { Complete-Background $script:Sizer; $script:Sizer = $null }
            if ($script:DeviceScanner -and $script:DeviceScanner.Handle.IsCompleted) { Complete-Background $script:DeviceScanner; $script:DeviceScanner = $null; Update-View }
            if ($script:NvSearcher -and $script:NvSearcher.Handle.IsCompleted) {
                Complete-Background $script:NvSearcher; $script:NvSearcher = $null
                if ($script:NvState -eq 'running') { $script:NvState = 'error'; $script:NvNote = 'The lookup stopped unexpectedly.' }
                Update-View
            }
            if ($script:WuSearcher -and $script:WuSearcher.Handle.IsCompleted) {
                Complete-Background $script:WuSearcher; $script:WuSearcher = $null
                if ($script:WuState -eq 'running') { $script:WuState = 'error'; $script:WuNote = 'The search stopped unexpectedly.' }
                Update-View
            }
            if ($script:Elev -and -not $script:ElevStalled -and $script:ElevActivity -and ((Get-Date) - $script:ElevActivity).TotalMinutes -ge $script:ElevStallLimit) { $script:ElevStalled = $true; Update-View }
            elseif ($script:ElevStalled -and $Panels[$script:Section] -and (Get-Date).Second -eq 0 -and (Get-Date).Millisecond -lt 130) { Update-View }
            if ($script:Elev -and $script:Elev.Handle.IsCompleted) {
                # normally the worker's elevdone event has already cleared this; a runspace that died still ends the run
                $bg = $script:Elev; Complete-Background $bg
                if ($script:Elev) { $script:Elev.PS.Dispose(); $script:Elev = $null; $script:DrvScan = if ($script:DrvScan -eq 'running') { 'error' } else { $script:DrvScan }; Update-View }
            }
            if ($script:DeviceRefreshAt -and (Get-Date) -ge $script:DeviceRefreshAt) { $script:DeviceRefreshAt = $null; Start-DeviceScan }
            foreach ($t in $script:Tracked.ToArray()) {
                if (-not $t.Bg.Handle.IsCompleted) { continue }
                [void]$script:Tracked.Remove($t)
                Complete-Background $t.Bg
                try { & $t.Done $t.Bg } catch { Add-LogLine "UI error: $($_.Exception.Message)" }
                Update-View
            }
            if ($script:Maint -and $script:Maint.Handle.IsCompleted) {
                Complete-Background $script:Maint
                $script:Maint = $null
                if ($script:MaintNext -eq 'update') { $script:MaintNext = $null; Start-Maintenance 'update' @('source', 'update', '--disable-interactivity') 'Updating winget sources' }
                Update-MaintenanceButtons
                Update-View
            }
            if ($script:Worker -and $script:Worker.Handle.IsCompleted) {
                Complete-Background $script:Worker
                $script:Worker = $null
                if ($Sync.Jobs.Count -gt 0) { Start-QueuedWork } else { Complete-Batch }
                if ($script:InstalledRefresh -and -not $script:Worker) { $script:InstalledRefresh = $false; Start-InstalledScan -Quiet }
                Complete-VendorInstall
                if ($script:Section -eq 'drivers') { Update-View }
                Update-View
            }
        }
        catch { Add-LogLine "UI error: $($_.Exception.Message)" }
    })

$Window.Add_Closing({
        param($s, $e)
        if ($script:Elev) {
            $answer = [System.Windows.MessageBox]::Show("$($script:ElevTitle) is still running as administrator.`n`nIt carries on after this window closes, but you won't see how it ends. Close anyway?", $AppName, 'YesNo', 'Warning')
            if ($answer -ne 'Yes') { $e.Cancel = $true; return }
        }
        if ($script:Worker) {
            $answer = [System.Windows.MessageBox]::Show("winget is working on an app.`n`nClosing cancels the queued work. The app being installed, updated or uninstalled now carries on in the background.`n`nClose anyway?", $AppName, 'YesNo', 'Warning')
            if ($answer -ne 'Yes') { $e.Cancel = $true; return }
            $job = $null
            while ($Sync.Jobs.TryDequeue([ref]$job)) { }
        }
        $Timer.Stop()
    })
$Window.Add_Activated({ if (-not $script:Worker -and $Window.TaskbarItemInfo) { $Window.TaskbarItemInfo.ProgressState = 'None' } })
$Window.Add_ContentRendered({
        if ($SelfTest) { return }
        try { Update-ScheduleSummary } catch { }
        Show-Starter
        if ($Settings.ScanOnOpen) { Start-Scan } else { $script:Mode = 'idle'; Update-View }
        # The installed list also tells Discover what is already on this PC
        Start-InstalledScan
        Start-WingetVersion
        Start-StarterVersions
        Start-SourceList       # for Export list (each source's details) and the Options panel
        Limit-History
        # the tab the app opens on (Device Health) reads its details now
        if ($Panels[$script:Section] -and $Panels[$script:Section].Open) { & $Panels[$script:Section].Open }
        Update-View
        try { if (Test-LegacyTask) { Request-TaskMove } else { Request-TaskCopy } } catch { }
    })

# Automatic updates panel
$UI.BtnSchedule.Add_Click({ if (Test-LegacyTask) { Request-TaskMove } else { Open-SchedulePanel } })
$UI.SchEnabled.Add_Click({ Update-SchedulePanelState })
$UI.SchDaily.Add_Click({ Update-SchedulePanelState })
$UI.SchWeekly.Add_Click({ Update-SchedulePanelState })
$UI.SchModeInstall.Add_Click({ Update-SchedulePanelState })
$UI.SchModeNotify.Add_Click({ Update-SchedulePanelState })
$UI.SchCancel.Add_Click({ $UI.ScheduleOverlay.Visibility = 'Collapsed' })
$UI.SchSave.Add_Click({ Save-SchedulePanel })
$UI.SchRunNow.Add_Click({
        $UI.SchError.Visibility = 'Collapsed'
        try {
            Invoke-TaskAction @{ Op = 'start' }
            $UI.SchStatus.Text = "Started. It runs in the background; you'll only see a notification if something needs attention. Refresh afterwards to see the new versions."
        }
        catch { Show-ScheduleError $_.Exception.Message }
    })
$UI.SchDryRun.Add_Click({
        try { Start-AutoProcess @('-DryRun'); $UI.SchStatus.Text = "Checking for updates in the background. The notification appears in the corner of the screen in a moment$Ellipsis" }
        catch { Show-ScheduleError $_.Exception.Message }
    })
# Options panel
$UI.BtnOptions.Add_Click({ Open-Options })
$UI.OptNav.Add_SelectionChanged({ if ($UI.OptNav.SelectedItem) { Show-OptionsPage ([string]$UI.OptNav.SelectedItem.Tag) } })
$UI.OptCancel.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed' })
$UI.OptSave.Add_Click({ Save-Options })

$UI.OptHideAddBtn.Add_Click({ Add-OptionId 'Hidden' $UI.OptHideAdd })
$UI.OptHideAdd.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { Add-OptionId 'Hidden' $UI.OptHideAdd; $e.Handled = $true } })
$UI.OptLogBrowse.Add_Click({ Select-LogFolder })
$UI.OptLogDefault.Add_Click({ $UI.OptLogDir.Text = '' })
$UI.OptOpenLogs.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$LogDir`"" })
$UI.OptOpenWingetLogs.Add_Click({
        if (Test-Path -LiteralPath $WingetLogDir) { Start-Process explorer.exe -ArgumentList "`"$WingetLogDir`"" }
        else { Set-OptionMessage "winget hasn't written any diagnostic logs yet ($WingetLogDir)." }
    })
$UI.OptOpenData.Add_Click({ Start-Process explorer.exe -ArgumentList "`"$DataDir`"" })
$UI.OptSrcUpdate.Add_Click({ Start-Maintenance 'update' @('source', 'update', '--disable-interactivity') 'Updating winget sources' })
$UI.OptSrcReset.Add_Click({ Reset-WingetSources })
$UI.OptExport.Add_Click({ Export-Options })
$UI.OptImport.Add_Click({ Import-Options })
$UI.OptWinUpdReset.Add_Click({ $script:OptLearned = @(); $script:OptToWinget = @(); Update-WinUpdatedText; Set-OptionMessage 'Cleared. Click Save to apply.' })
$UI.OptResetAll.Add_Click({
        Set-OptionControls (New-DefaultSettings)
        $script:ImportedSchedule = $null
        Set-OptionMessage 'Defaults filled in, including empty hidden and skip lists. Click Save to apply them; the schedule is not changed.'
    })

$UI.ScheduleOverlay.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $UI.ScheduleOverlay) { $UI.ScheduleOverlay.Visibility = 'Collapsed' } })
$UI.OptSrcAdd.Add_Click({ Add-WingetSource })

# App lists: import on Discover, export on Installed
$UI.BtnImportList.Add_Click({ Import-AppList })
$UI.BtnExportList.Add_Click({ Open-ExportList })
$UI.PickAll.Add_Click({ foreach ($c in $UI.PickList.Children) { $c.IsChecked = $true }; Update-PickCount })
$UI.PickNone.Add_Click({ foreach ($c in $UI.PickList.Children) { $c.IsChecked = $false }; Update-PickCount })
$UI.PickCancel.Add_Click({ $UI.PickOverlay.Visibility = 'Collapsed' })
$UI.PickOk.Add_Click({ Complete-Pick })

# Release notes and chosen versions
$UI.NotesClose.Add_Click({ $UI.NotesOverlay.Visibility = 'Collapsed' })
$UI.NotesOpen.Add_Click({ if ($UI.NotesOpen.Tag -match '^https?://') { try { Start-Process ([string]$UI.NotesOpen.Tag) } catch { } } })
$UI.NotesUpdate.Add_Click({ $p = $script:NotesItem; $UI.NotesOverlay.Visibility = 'Collapsed'; Invoke-RowAction $p })
$UI.VerCancel.Add_Click({ $UI.VersionOverlay.Visibility = 'Collapsed' })
$UI.VerInstall.Add_Click({ Install-ChosenVersion })
$UI.VerList.Add_MouseDoubleClick({ if ($UI.VerList.SelectedItem) { Install-ChosenVersion } })

# History
$UI.BtnHistory.Add_Click({ Open-History })
$UI.HistClose.Add_Click({ $UI.HistoryOverlay.Visibility = 'Collapsed' })
$UI.HistDone.Add_Click({ $UI.HistoryOverlay.Visibility = 'Collapsed' })
$UI.HistSearch.Add_TextChanged({ Update-HistoryView })
foreach ($chip in 'HistAll', 'HistAutoOnly', 'HistFailed') { $UI[$chip].Add_Click({ Update-HistoryView }) }
$UI.HistClear.Add_Click({ Show-Confirm 'clearhistory' $null 'Clear the history?' 'This deletes the record of past installs, updates, uninstalls and holds. Apps and logs are not affected.' 'Clear history' -Danger })

foreach ($ov in 'HistoryOverlay', 'NotesOverlay', 'VersionOverlay', 'PickOverlay') {
    $UI[$ov].Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $s) { $s.Visibility = 'Collapsed' } })
}

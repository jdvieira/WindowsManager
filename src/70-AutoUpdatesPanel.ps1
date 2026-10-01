# Windows Manager - AutoUpdatesPanel (part of src\; see Windows_Manager.ps1)

function ConvertTo-TaskTime([string]$Text) {
    $dt = [datetime]::MinValue
    $formats = [string[]]@('H:mm', 'HH:mm', 'h:mm tt', 'h:mmtt', 'h tt', 'htt', '%H', 'HHmm')
    if ([datetime]::TryParseExact($Text.Trim(), $formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$dt)) { return $dt.ToString('HH:mm') }
    if ([datetime]::TryParse($Text.Trim(), [ref]$dt)) { return $dt.ToString('HH:mm') }
    return $null
}

function Update-ScheduleSummary {
    $script:Schedule = Get-AutoSchedule
    $s = $script:Schedule
    $label = if ($Settings.AutoMode -eq 'notify') { 'Update check' } else { 'Automatic' }
    $UI.ScheduleText.Text = if (-not $s -and (Get-LegacyTaskName)) { 'Automatic updates: move needed' } elseif (-not $s) { 'Automatic updates: off' } elseif (-not $s.Enabled) { 'Automatic updates: disabled' } else { "$label`: $(Format-Schedule $s)" }
}

function Update-SchedulePanelState {
    $on = [bool]$UI.SchEnabled.IsChecked
    $UI.SchOptions.IsEnabled = $on
    $UI.SchOptions.Opacity = if ($on) { 1 } else { 0.45 }
    $UI.SchDays.Visibility = if ($UI.SchWeekly.IsChecked) { 'Visible' } else { 'Collapsed' }
    $notify = [bool]$UI.SchModeNotify.IsChecked
    $UI.SchModeHint.Text = if ($notify) { 'Nothing is installed. When updates are waiting, a notification lists them, with a button to open this app.' }
    else { 'Updates install silently. You only hear about failures, and about restarts or a summary if you turn those on below.' }
    $UI.SchNotifyReboot.IsEnabled = -not $notify
    $UI.SchNotifyAlways.IsEnabled = -not $notify
    $UI.SchRunNow.IsEnabled = [bool]$script:Schedule
    $UI.SchSave.Content = if ($on -or $script:Schedule) { 'Save' } else { 'Close' }
}

function Update-ScheduleStatus {
    $s = $script:Schedule
    $lines = @()
    if ($s) {
        $state = if ($s.Enabled) { 'Scheduled' } else { 'Disabled in Task Scheduler' }
        $lines += "$state`: $(Format-Schedule $s)$(if ($s.Elevated) { ', elevated' })."
        if ($s.Enabled -and $s.NextRun) { $lines += 'Next run: {0:dddd M/d, h:mm tt}.' -f $s.NextRun }
        $cmd = Get-AutoCommand
        if ($s.Execute -and $s.Execute -ne $cmd.Execute) { $lines += "The task runs another copy ($($s.Execute)). Save to point it at this one." }
    }
    else { $lines += "No scheduled task yet. Saving creates `"$TaskName`" in Task Scheduler. It runs while you are signed in." }
    $last = Format-LastRun (Get-LastRun)
    if ($last) { $lines += $last }
    $UI.SchStatus.Text = $lines -join "`n"
}

function Open-SchedulePanel {
    $UI.SchError.Visibility = 'Collapsed'
    $script:Schedule = Get-AutoSchedule
    $s = $script:Schedule
    $UI.SchEnabled.IsChecked = [bool]($s -and $s.Enabled)
    $weekly = $s -and $s.Frequency -eq 'Weekly'
    $UI.SchWeekly.IsChecked = $weekly
    $UI.SchDaily.IsChecked = -not $weekly
    $days = if ($s -and $s.Days) { $s.Days } else { @('Monday') }
    foreach ($b in $UI.SchDays.Children) { $b.IsChecked = $days -contains [string]$b.Tag }
    $time = if ($s) { $s.Time } else { '03:00' }
    $UI.SchTime.Text = [datetime]::Today.Add([TimeSpan]::Parse($time)).ToString('t')
    $UI.SchElevated.IsChecked = if ($s) { $s.Elevated } else { $true }
    $UI.SchCatchUp.IsChecked = if ($s) { $s.CatchUp } else { $true }
    $UI.SchNotifyReboot.IsChecked = $Settings.NotifyReboot
    $UI.SchNotifyAlways.IsChecked = $Settings.NotifyAlways
    $UI.SchModeNotify.IsChecked = $Settings.AutoMode -eq 'notify'
    $UI.SchModeInstall.IsChecked = $Settings.AutoMode -ne 'notify'
    Update-ScheduleStatus
    Update-SchedulePanelState
    $UI.ScheduleOverlay.Visibility = 'Visible'
}

function Show-ScheduleError([string]$Text) {
    $UI.SchError.Text = $Text
    $UI.SchError.Visibility = 'Visible'
}

function Save-SchedulePanel {
    $UI.SchError.Visibility = 'Collapsed'
    $Settings.NotifyReboot = [bool]$UI.SchNotifyReboot.IsChecked
    $Settings.NotifyAlways = [bool]$UI.SchNotifyAlways.IsChecked
    $Settings.AutoMode = if ($UI.SchModeNotify.IsChecked) { 'notify' } else { 'install' }
    Save-Settings
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        if ($UI.SchEnabled.IsChecked) {
            $time = ConvertTo-TaskTime $UI.SchTime.Text
            if (-not $time) { throw 'Enter a time such as 3:00 AM or 15:30.' }
            $weekly = [bool]$UI.SchWeekly.IsChecked
            $days = @($UI.SchDays.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
            if ($weekly -and -not $days) { throw 'Pick at least one day for the weekly schedule.' }
            Invoke-TaskAction (New-RegisterSpec @{
                    Frequency = $(if ($weekly) { 'Weekly' } else { 'Daily' }); Days = $days; Time = $time
                    Elevated = [bool]$UI.SchElevated.IsChecked; CatchUp = [bool]$UI.SchCatchUp.IsChecked
                })
            Add-LogLine "Automatic $(if ($Settings.AutoMode -eq 'notify') { 'update check (notify only)' } else { 'updates' }) scheduled: $(Format-Schedule @{ Frequency = $(if ($weekly) { 'Weekly' } else { 'Daily' }); Days = $days; Time = $time })."
        }
        elseif (Get-AutoTask) {
            Invoke-TaskAction @{ Op = 'unregister' }
            Add-LogLine 'Automatic updates turned off (scheduled task removed).'
        }
        Update-ScheduleSummary
        $UI.ScheduleOverlay.Visibility = 'Collapsed'
    }
    catch { Show-ScheduleError $_.Exception.Message }
    finally { $Window.Cursor = $null }
}

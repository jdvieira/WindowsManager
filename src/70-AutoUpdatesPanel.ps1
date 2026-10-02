# Windows Manager - AutoUpdatesPanel (part of src\; see Windows_Manager.ps1)

# The Automatic maintenance panel: the scheduled task (when, elevated, catch-up), then one card per job (what each
# job does is in 29-AutoJobs.ps1) with Off / Tell me / Do it, how often, and the job's own settings, then the
# notifications. The cards are built once, from $AutoJobCards.

function ConvertTo-TaskTime([string]$Text) {
    $dt = [datetime]::MinValue
    $formats = [string[]]@('H:mm', 'HH:mm', 'h:mm tt', 'h:mmtt', 'h tt', 'htt', '%H', 'HHmm')
    if ([datetime]::TryParseExact($Text.Trim(), $formats, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AllowWhiteSpaces, [ref]$dt)) { return $dt.ToString('HH:mm') }
    if ([datetime]::TryParse($Text.Trim(), [ref]$dt)) { return $dt.ToString('HH:mm') }
    return $null
}

$AutoJobCards = @(
    @{ Key = 'apps'; Name = 'App updates'; Modes = @('off', 'notify', 'install')
        About = 'Apps winget can update. Hidden apps, and apps Windows updates itself, are left alone.'
    }
    @{ Key = 'win'; Name = 'Windows updates'; Modes = @('off', 'notify', 'install')
        About = "Security, cumulative, .NET and Defender updates, through Windows Update. Nothing restarts by itself: you're told when a restart is needed."
    }
    @{ Key = 'clean'; Name = 'Cleanup'; Modes = @('off', 'notify', 'install')
        About = "Leftovers from the Cleanup tab. Tell me lets you know once 1 GB or more can be freed."
    }
    @{ Key = 'health'; Name = 'Health check'; Modes = @('off', 'notify')
        About = "Antivirus, firewall, drives, battery and blue screens. Each new problem is mentioned once, and again after a week if it's still there. Each check also saves a reading for Device Health's trends."
    }
)
$JobModeText = @{ off = 'Off'; notify = 'Tell me'; install = 'Do it' }
$JobEveryText = @{ run = 'Every run'; week = 'Weekly'; month = 'Monthly' }
$JobUI = @{}

function New-SchTextBlock([string]$Text, [string]$Style) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Text; $t.TextWrapping = 'Wrap'
    if ($Style) { $t.Style = $Window.FindResource($Style) }
    return $t
}

function New-JobCards {
    $conv = New-Object System.Windows.Media.BrushConverter
    foreach ($j in $AutoJobCards) {
        $jc = @{ Modes = @{}; Every = @{}; Items = @{} }
        $card = New-Object System.Windows.Controls.Border
        $card.Background = $conv.ConvertFrom('#1C1C1C'); $card.CornerRadius = 8; $card.Padding = '16,14,12,8'; $card.Margin = '0,0,0,10'
        $stack = New-Object System.Windows.Controls.StackPanel
        # name and what it does, with Off / Tell me / Do it on the right
        $top = New-Object System.Windows.Controls.DockPanel
        $modes = New-Object System.Windows.Controls.StackPanel
        $modes.Orientation = 'Horizontal'; $modes.VerticalAlignment = 'Top'
        [System.Windows.Controls.DockPanel]::SetDock($modes, 'Right')
        foreach ($m in $j.Modes) {
            $rb = New-Object System.Windows.Controls.RadioButton
            $rb.Content = $JobModeText[$m]; $rb.GroupName = "JobMode-$($j.Key)"; $rb.Style = $Window.FindResource('Chip'); $rb.Tag = $m
            $rb.Add_Click({ Update-SchedulePanelState })
            [void]$modes.Children.Add($rb)
            $jc.Modes[$m] = $rb
        }
        [void]$top.Children.Add($modes)
        $head = New-Object System.Windows.Controls.StackPanel
        $head.Margin = '0,0,14,8'
        $name = New-SchTextBlock $j.Name
        $name.FontSize = 14.5; $name.FontWeight = 'SemiBold'; $name.Foreground = [System.Windows.Media.Brushes]::White
        [void]$head.Children.Add($name)
        $about = New-SchTextBlock $j.About 'Hint'
        $about.Margin = '0,3,0,0'
        [void]$head.Children.Add($about)
        [void]$top.Children.Add($head)
        [void]$stack.Children.Add($top)
        # how often, then the job's own settings; dimmed while the job is off
        $opts = New-Object System.Windows.Controls.StackPanel
        $opts.Margin = '0,6,0,0'
        $every = New-Object System.Windows.Controls.StackPanel
        $every.Orientation = 'Horizontal'
        $lbl = New-SchTextBlock 'How often'
        $lbl.Foreground = $conv.ConvertFrom('#BDBDBD'); $lbl.Width = 92; $lbl.VerticalAlignment = 'Center'; $lbl.Margin = '0,0,0,8'
        [void]$every.Children.Add($lbl)
        foreach ($e in 'run', 'week', 'month') {
            $rb = New-Object System.Windows.Controls.RadioButton
            $rb.Content = $JobEveryText[$e]; $rb.GroupName = "JobEvery-$($j.Key)"; $rb.Style = $Window.FindResource('Chip'); $rb.Tag = $e
            [void]$every.Children.Add($rb)
            $jc.Every[$e] = $rb
        }
        [void]$opts.Children.Add($every)
        switch ($j.Key) {
            'apps' {
                $jc.Retry = New-Object System.Windows.Controls.CheckBox
                $jc.Retry.Content = 'Try failed updates again once, 30 seconds later'; $jc.Retry.Margin = '0,4,0,10'
                $jc.Retry.ToolTip = 'Helps when an app was open or a download dropped.'
                [void]$opts.Children.Add($jc.Retry)
            }
            'win' {
                $jc.Optional = New-Object System.Windows.Controls.CheckBox
                $jc.Optional.Content = 'Include optional updates'; $jc.Optional.Margin = '0,4,0,10'
                $jc.Optional.ToolTip = "Previews and updates Windows lets you choose; the Windows Update tab lists them either way."
                $jc.Feature = New-Object System.Windows.Controls.CheckBox
                $jc.Feature.Content = 'Include feature updates (a new version of Windows)'; $jc.Feature.Margin = '0,0,0,10'
                $jc.Feature.ToolTip = 'A feature update can take an hour or more and finishes during a restart.'
                [void]$opts.Children.Add($jc.Optional); [void]$opts.Children.Add($jc.Feature)
            }
            'clean' {
                $wrap = New-Object System.Windows.Controls.WrapPanel
                $wrap.Margin = '-8,0,0,6'
                foreach ($c in Get-CleanCatalog) {
                    $cb = New-Object System.Windows.Controls.CheckBox
                    $cb.Style = $Window.FindResource('CheckItem'); $cb.Width = 270; $cb.Tag = $c.Key; $cb.ToolTip = $c.About
                    $content = New-Object System.Windows.Controls.StackPanel
                    $content.Orientation = 'Horizontal'
                    [void]$content.Children.Add((New-SchTextBlock $c.Name))
                    if ($c.Admin) {
                        $shield = New-SchTextBlock ([string][char]0xE83D)
                        $shield.FontFamily = 'Segoe MDL2 Assets'; $shield.FontSize = 12; $shield.Margin = '8,1,0,0'; $shield.Foreground = $conv.ConvertFrom('#9A9A9A'); $shield.VerticalAlignment = 'Center'
                        $shield.ToolTip = 'Needs Run elevated'
                        [void]$content.Children.Add($shield)
                    }
                    $cb.Content = $content
                    $cb.Add_Click({ Update-SchedulePanelState })
                    [void]$wrap.Children.Add($cb)
                    $jc.Items[$c.Key] = $cb
                }
                [void]$opts.Children.Add($wrap)
            }
        }
        # what Do it can't do without Run elevated
        $jc.Warn = New-SchTextBlock '' 'Hint'
        $jc.Warn.Foreground = $Window.FindResource('Warn'); $jc.Warn.Margin = '0,0,0,8'; $jc.Warn.Visibility = 'Collapsed'
        [void]$opts.Children.Add($jc.Warn)
        [void]$stack.Children.Add($opts)
        $card.Child = $stack
        [void]$UI.SchJobs.Children.Add($card)
        $jc.Opts = $opts
        $JobUI[$j.Key] = $jc
    }
}

function Get-JobMode([string]$Key) { foreach ($m in $JobUI[$Key].Modes.Keys) { if ($JobUI[$Key].Modes[$m].IsChecked) { return $m } }; return 'off' }
function Get-JobEvery([string]$Key) { foreach ($e in $JobUI[$Key].Every.Keys) { if ($JobUI[$Key].Every[$e].IsChecked) { return $e } }; return 'run' }

function Update-ScheduleSummary {
    $script:Schedule = Get-AutoSchedule
    $s = $script:Schedule
    $UI.ScheduleText.Text = if (-not $s -and (Get-LegacyTaskName)) { 'Automatic maintenance: move needed' } elseif (-not $s) { 'Automatic maintenance: off' } elseif (-not $s.Enabled) { 'Automatic maintenance: disabled' } else { "Automatic: $(Format-Schedule $s)" }
}

function Update-SchedulePanelState {
    $on = [bool]$UI.SchEnabled.IsChecked
    $UI.SchOptions.IsEnabled = $on
    $UI.SchOptions.Opacity = if ($on) { 1 } else { 0.45 }
    $UI.SchDays.Visibility = if ($UI.SchWeekly.IsChecked) { 'Visible' } else { 'Collapsed' }
    $elevated = [bool]$UI.SchElevated.IsChecked
    foreach ($k in $JobUI.Keys) {
        $jc = $JobUI[$k]
        $mode = Get-JobMode $k
        $jc.Opts.IsEnabled = $mode -ne 'off'
        $jc.Opts.Opacity = if ($mode -ne 'off') { 1 } else { 0.45 }
        $warn = ''
        if ($k -eq 'win' -and $mode -eq 'install' -and -not $elevated) { $warn = 'Installing Windows updates needs Run elevated (above). Without it, they are only listed.' }
        if ($k -eq 'clean' -and $mode -ne 'off' -and -not $elevated) {
            $admin = @(Get-CleanCatalog | Where-Object { $_.Admin -and $jc.Items[$_.Key].IsChecked }).Count
            if ($admin) { $warn = "Items with a shield need Run elevated (above). Without it, $(if ($admin -eq 1) { "that one is" } else { "those $admin are" }) left out." }
        }
        $jc.Warn.Text = $warn
        $jc.Warn.Visibility = if ($warn -and $mode -ne 'off') { 'Visible' } else { 'Collapsed' }
    }
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
        $need = Get-TaskCopyNeed $s
        $cmd = Get-AutoCommand $s.Elevated
        if ($need -eq 'protect') { $lines += "It runs $AppName as administrator from a folder other programs can change ($($s.Execute)). Save to have it run a protected copy in $TaskCopyDir instead." }
        elseif ($need -eq 'update') { $lines += $(if ($v = Get-TaskCopyVersion) { "It runs a protected copy of version $v in $TaskCopyDir. Save to update it to $AppVersion." } else { "Its protected copy in $TaskCopyDir is missing, so automatic runs fail. Save to copy $AppVersion there." }) }
        elseif ($s.Execute -and $s.Execute -ne $cmd.Execute) { $lines += "The task runs another copy ($($s.Execute)). Save to point it at this one." }
        elseif ($s.Elevated) { $lines += "It runs a protected copy of $AppName in $TaskCopyDir, which only administrators can change." }
        # when each job last ran (jobs that don't run every time wait for their turn)
        $times = Read-AutoJobTimes
        $last = @(foreach ($j in Get-AutoJobs) { if ($j.Mode -ne 'off' -and $j.Every -ne 'run' -and $times.ContainsKey($j.Key)) { "$($j.Name) last ran {0:ddd M/d}" -f $times[$j.Key] } })
        if ($last.Count) { $lines += "$($last -join '; ')." }
    }
    else { $lines += "No scheduled task yet. Saving creates `"$TaskName`" in Task Scheduler. It runs while you are signed in." }
    $lastRun = Format-LastRun (Get-LastRun)
    if ($lastRun) { $lines += $lastRun }
    $UI.SchStatus.Text = $lines -join "`n"
}

function Open-SchedulePanel {
    if (-not $JobUI.Count) { New-JobCards }
    $UI.SchError.Visibility = 'Collapsed'
    $UI.SchCard.MaxHeight = [Math]::Max(400, $Window.ActualHeight - 60)
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
    foreach ($j in Get-AutoJobs) {
        $jc = $JobUI[$j.Key]
        foreach ($m in $jc.Modes.Keys) { $jc.Modes[$m].IsChecked = $m -eq $j.Mode }
        foreach ($e in $jc.Every.Keys) { $jc.Every[$e].IsChecked = $e -eq $j.Every }
    }
    $JobUI.apps.Retry.IsChecked = $Settings.AutoRetry
    $JobUI.win.Optional.IsChecked = $Settings.AutoWinOptional
    $JobUI.win.Feature.IsChecked = $Settings.AutoWinFeature
    $chosen = @(Get-AutoCleanItems | ForEach-Object { $_.Key })
    foreach ($k in $JobUI.clean.Items.Keys) { $JobUI.clean.Items[$k].IsChecked = $chosen -contains $k }
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
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $on = [bool]$UI.SchEnabled.IsChecked
        $cleanKeys = @($JobUI.clean.Items.Keys | Where-Object { $JobUI.clean.Items[$_].IsChecked } | Sort-Object)
        if ($on) {
            if (-not @($JobUI.Keys | Where-Object { (Get-JobMode $_) -ne 'off' }).Count) { throw 'Turn on at least one job, or switch automatic maintenance off.' }
            if ((Get-JobMode 'clean') -ne 'off' -and -not $cleanKeys.Count) { throw 'Pick at least one thing for Cleanup to clean up, or turn Cleanup off.' }
        }
        $Settings.NotifyReboot = [bool]$UI.SchNotifyReboot.IsChecked
        $Settings.NotifyAlways = [bool]$UI.SchNotifyAlways.IsChecked
        $Settings.AutoMode = Get-JobMode 'apps'; $Settings.AutoAppsEvery = Get-JobEvery 'apps'
        $Settings.AutoWin = Get-JobMode 'win'; $Settings.AutoWinEvery = Get-JobEvery 'win'
        $Settings.AutoClean = Get-JobMode 'clean'; $Settings.AutoCleanEvery = Get-JobEvery 'clean'
        $Settings.HealthAlerts = (Get-JobMode 'health') -ne 'off'; $Settings.AutoHealthEvery = Get-JobEvery 'health'
        $Settings.AutoRetry = [bool]$JobUI.apps.Retry.IsChecked
        $Settings.AutoWinOptional = [bool]$JobUI.win.Optional.IsChecked
        $Settings.AutoWinFeature = [bool]$JobUI.win.Feature.IsChecked
        if ($cleanKeys.Count) { $Settings.AutoCleanItems = $cleanKeys }
        Save-Settings
        if ($on) {
            $time = ConvertTo-TaskTime $UI.SchTime.Text
            if (-not $time) { throw 'Enter a time such as 3:00 AM or 15:30.' }
            $weekly = [bool]$UI.SchWeekly.IsChecked
            $days = @($UI.SchDays.Children | Where-Object { $_.IsChecked } | ForEach-Object { [string]$_.Tag })
            if ($weekly -and -not $days) { throw 'Pick at least one day for the weekly schedule.' }
            Invoke-TaskAction (New-RegisterSpec @{
                    Frequency = $(if ($weekly) { 'Weekly' } else { 'Daily' }); Days = $days; Time = $time
                    Elevated = [bool]$UI.SchElevated.IsChecked; CatchUp = [bool]$UI.SchCatchUp.IsChecked
                })
            $what = @(Get-AutoJobs | Where-Object { $_.Mode -ne 'off' } | ForEach-Object { "$($_.Name.ToLower()) ($(if ($_.Mode -eq 'notify') { 'tell me' } else { 'do it' }), $($AutoEveryText[[string]$_.Every]))" }) -join ', '
            Add-LogLine "Automatic maintenance scheduled: $(Format-Schedule @{ Frequency = $(if ($weekly) { 'Weekly' } else { 'Daily' }); Days = $days; Time = $time }): $what."
        }
        elseif (Get-AutoTask) {
            Invoke-TaskAction @{ Op = 'unregister'; Copy = (Test-Path -LiteralPath $TaskCopyDir) }
            Add-LogLine 'Automatic maintenance turned off (scheduled task removed).'
        }
        Update-ScheduleSummary
        $UI.ScheduleOverlay.Visibility = 'Collapsed'
    }
    catch { Show-ScheduleError $_.Exception.Message }
    finally { $Window.Cursor = $null }
}

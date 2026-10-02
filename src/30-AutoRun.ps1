# Windows Manager - AutoRun (part of src\; see Windows_Manager.ps1)

# The notification borrows the main window's styles (its Window.Resources block) so both look the same.
$NotifyXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Manager" Width="460" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" Topmost="True" ResizeMode="NoResize" WindowStartupLocation="Manual" Left="-10000" Top="-10000"
        FontFamily="Segoe UI" FontSize="13.5" Foreground="#F2F2F2" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  __RESOURCES__
  <Border x:Name="Card" Margin="18" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
    <Border.Effect><DropShadowEffect BlurRadius="26" ShadowDepth="3" Opacity="0.55"/></Border.Effect>
    <Grid Margin="20,18,14,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <DockPanel>
        <Button x:Name="BtnClose" DockPanel.Dock="Right" Style="{StaticResource Ghost}" Padding="9,5" Margin="0" VerticalAlignment="Top" ToolTip="Dismiss">
          <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11"/>
        </Button>
        <Border x:Name="GlyphBg" Width="36" Height="36" CornerRadius="18" Margin="0,0,13,0" VerticalAlignment="Top">
          <TextBlock x:Name="Glyph" FontFamily="Segoe MDL2 Assets" FontSize="15" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel VerticalAlignment="Center">
          <TextBlock x:Name="Head" FontSize="15.5" FontWeight="SemiBold" Foreground="White" TextWrapping="Wrap"/>
          <TextBlock x:Name="Sub" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,2,0,0" TextWrapping="Wrap"/>
        </StackPanel>
      </DockPanel>
      <ScrollViewer Grid.Row="1" MaxHeight="280" VerticalScrollBarVisibility="Auto" Margin="49,14,6,0">
        <StackPanel x:Name="Items"/>
      </ScrollViewer>
      <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,6,0">
        <Button x:Name="BtnViewLog" Content="View log" Style="{StaticResource Ghost}"/>
        <Button x:Name="BtnOpenApp" Content="Open Windows Manager" Style="{StaticResource Primary}" Margin="0"/>
      </StackPanel>
    </Grid>
  </Border>
</Window>
'@

function Write-RunLog([string]$Text) {
    try { [IO.File]::AppendAllText($LogFile, ('{0:HH:mm:ss}  {1}{2}' -f (Get-Date), $Text, "`r`n")) } catch { }
}

# Runs one worker operation to completion on this thread and returns its non-log events
function Invoke-WorkerNow([string]$Op, $Arg) {
    $ps = [powershell]::Create()
    try {
        [void]$ps.AddScript($WorkerScript).AddArgument($Sync).AddArgument($Op).AddArgument($WingetPath).AddArgument($Arg)
        [void]$ps.Invoke()
        foreach ($e in $ps.Streams.Error) { Write-RunLog "Worker error: $($e.Exception.Message)" }
    }
    finally { $ps.Dispose() }
    $events = New-Object Collections.Generic.List[object]
    $ev = $null
    while ($Sync.Events.TryDequeue([ref]$ev)) { if ($ev.T -ne 'log') { $events.Add($ev) } }
    return , $events.ToArray()
}

# The run as a whole: its title, one line about what the jobs did, a hint, and how serious it is
function Get-RunSummary($Run) {
    $jobs = @($Run.Jobs)
    $problems = @($jobs | Where-Object { $_.Error -or $_.Failed })
    $reboot = [bool](@($jobs | Where-Object { $_.Reboot }).Count)
    $waiting = @($jobs | Where-Object { $_.Key -ne 'health' -and (Test-AutoJobWaiting $_) })
    $lines = @($jobs | Where-Object { $_.Key -ne 'health' -or $_.Available -or $_.Error } | ForEach-Object { "$($_.Name): $(Format-AutoJobSummary $_ $Run.DryRun)" })
    $s = @{ Line = ($lines -join '. ') + $(if ($lines.Count) { '.' } else { '' }); Kind = 'ok' }
    if ($Run.DryRun) { $s.Title = 'Test run: what automatic maintenance would do'; $s.Hint = 'Nothing was changed. This is how automatic maintenance will notify you.'; $s.Kind = 'info' }
    elseif ($problems.Count) {
        $s.Title = if ($problems.Count -eq 1) { "$($problems[0].Name) didn't all go to plan" } else { "Automatic maintenance hit $($problems.Count) problems" }
        $failed = @($problems | ForEach-Object { @($_.Items | Where-Object { $_.State -eq 'error' } | ForEach-Object { $_.Name }) })
        $s.Hint = if ($failed.Count) { "Not done: $((@($failed) | Select-Object -First 3) -join ', ')$(if ($failed.Count -gt 3) { " and $($failed.Count - 3) more" }). Open the app to retry." } else { 'Open the app, or View log, for details.' }
        $s.Kind = 'error'
    }
    elseif ($reboot) { $s.Title = 'Restart to finish updating'; $s.Hint = "Some updates finish when Windows restarts. Nothing restarts by itself: restart when it suits you."; $s.Kind = 'warn' }
    elseif ($waiting.Count) {
        $s.Title = if ($waiting.Count -eq 1) { "$($waiting[0].Name): $(Format-AutoJobSummary $waiting[0] $false)" } else { "$($waiting.Count) things are waiting for you" }
        $s.Hint = 'Nothing was changed. Open the app to choose what to do.'; $s.Kind = 'info'
    }
    else { $s.Title = 'Automatic maintenance finished'; $s.Hint = 'Everything went to plan.' }
    $notes = @($jobs | Where-Object { $_.Note } | ForEach-Object { $_.Note })
    if ($notes.Count) { $s.Hint = "$($s.Hint) $($notes -join ' ')" }
    return $s
}

# The run's result as a Windows notification (the default) or, when those are off or the pop-up is chosen, as this
# app's own pop-up with each job and what it did
function Show-RunNotification($Run) {
    $sum = Get-RunSummary $Run
    if ($Settings.NotifyStyle -eq 'toast' -and -not $Screenshot) {
        if (Show-Toast $sum.Title $sum.Line $sum.Hint -Important:($sum.Kind -eq 'error')) { return }
    }
    $resources = [regex]::Match($Xaml, '(?s)<Window\.Resources>.*?</Window\.Resources>').Value
    $win = [System.Windows.Markup.XamlReader]::Parse($NotifyXaml.Replace('__RESOURCES__', $resources))
    $icon = Get-AppIcon
    if ($icon) { $win.Icon = $icon }
    $f = @{}
    foreach ($n in 'Head', 'Sub', 'Glyph', 'GlyphBg', 'Items', 'BtnClose', 'BtnViewLog', 'BtnOpenApp') { $f[$n] = $win.FindName($n) }
    $kind = $sum.Kind
    $f.Head.Text = $sum.Title
    $f.Sub.Text = $sum.Hint
    $colors = @{ error = '#FF7B6B'; warn = '#F6B115'; ok = '#5BC27A'; info = '#4FD8E0' }
    $bgs = @{ error = '#3A2220'; warn = '#3A3120'; ok = '#1F3326'; info = '#17414C' }
    $glyphs = @{ error = [string][char]0xE783; warn = [string][char]0xE777; ok = [string][char]0xE73E; info = [string][char]0xE946 }
    $conv = New-Object System.Windows.Media.BrushConverter
    $f.Glyph.Text = $glyphs[$kind]; $f.Glyph.Foreground = $conv.ConvertFrom($colors[$kind]); $f.GlyphBg.Background = $conv.ConvertFrom($bgs[$kind])

    # Each job with what it did, then its items: failures first, then restarts, then the rest
    $stateColor = @{ error = '#FF7B6B'; reboot = '#F6B115'; warn = '#F6B115'; ok = '#5BC27A'; skipped = '#9A9A9A'; cancelled = '#9A9A9A'; pending = '#4FD8E0' }
    $order = @{ error = 0; reboot = 1; warn = 1; ok = 2 }
    $shown = 0
    foreach ($job in @($Run.Jobs)) {
        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = "$($job.Name.ToUpper()): $(Format-AutoJobSummary $job $Run.DryRun)"
        $head.Foreground = $conv.ConvertFrom('#9A9A9A'); $head.FontSize = 11.5; $head.FontWeight = 'SemiBold'; $head.TextWrapping = 'Wrap'
        $head.Margin = $(if ($shown) { '0,8,0,8' } else { '0,0,0,8' })
        [void]$f.Items.Children.Add($head)
        $shown++
        $list = @($job.Items | Sort-Object { if ($order.ContainsKey("$($_.State)")) { $order["$($_.State)"] } else { 3 } }, Name)
        foreach ($item in @($list | Select-Object -First 8)) {
            $row = New-Object System.Windows.Controls.StackPanel
            $row.Margin = '0,0,0,9'
            $name = New-Object System.Windows.Controls.TextBlock
            $name.Text = $item.Name; $name.FontWeight = 'SemiBold'; $name.TextTrimming = 'CharacterEllipsis'
            [void]$row.Children.Add($name)
            if ($item.Detail) {
                $detail = New-Object System.Windows.Controls.TextBlock
                $detail.Text = $item.Detail; $detail.FontSize = 12.5; $detail.TextWrapping = 'Wrap'
                $c = $stateColor["$($item.State)"]; if (-not $c) { $c = '#BDBDBD' }
                $detail.Foreground = $conv.ConvertFrom($c)
                [void]$row.Children.Add($detail)
            }
            [void]$f.Items.Children.Add($row)
        }
        if ($list.Count -gt 8) {
            $more = New-Object System.Windows.Controls.TextBlock
            $more.Text = "and $($list.Count - 8) more (see the log)"; $more.Foreground = $conv.ConvertFrom('#9A9A9A'); $more.FontSize = 12.5; $more.Margin = '0,0,0,9'
            [void]$f.Items.Children.Add($more)
        }
    }
    if (-not $shown) { $f.Items.Parent.Visibility = 'Collapsed' }

    $f.BtnClose.Add_Click({ $win.Close() })
    if ($kind -in 'ok', 'warn' -and $Settings.AutoDismissMin -gt 0) {
        $script:DismissTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:DismissTimer.Interval = [TimeSpan]::FromMinutes($Settings.AutoDismissMin)
        $script:DismissTimer.Add_Tick({ $script:DismissTimer.Stop(); $win.Close() })
        $script:DismissTimer.Start()
    }
    $f.BtnViewLog.Add_Click({ try { Start-Process notepad.exe -ArgumentList "`"$LogFile`"" } catch { } })
    $f.BtnOpenApp.Add_Click({
            try {
                if ($IsCompiled) { Start-Process -FilePath $ExePath }
                else { Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$AppScript`"") }
            }
            catch { }
            $win.Close()
        })
    # Bottom-right corner of the work area, like a Windows notification
    $win.Add_ContentRendered({
            $area = [System.Windows.SystemParameters]::WorkArea
            $win.Left = $area.Right - $win.ActualWidth
            $win.Top = $area.Bottom - $win.ActualHeight
            if ($Screenshot) {
                $win.Dispatcher.Invoke([action] {}, 'ApplicationIdle')
                $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$win.ActualWidth, [int]$win.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
                $bmp.Render($win)
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
                $fs = [IO.File]::Create($Screenshot); $enc.Save($fs); $fs.Close()
                $win.Close()
            }
        })
    [void]$win.ShowDialog()
}

# An automatic run (what the scheduled task starts with -Auto): each job that is on and due (29-AutoJobs.ps1), then
# one notification for the run, when there's something to say. A test run (-DryRun) does every job that is on,
# whether due or not, and changes nothing.
function Invoke-AutoRun {
    $run = [ordered]@{ Time = (Get-Date).ToString('o'); DryRun = [bool]$DryRun; Jobs = @(); Error = $null
        # totals, as runs before 2.5 kept them
        Mode = $Settings.AutoMode; Available = 0; Updated = 0; Reboot = 0; Failed = 0; Skipped = 0; Items = @()
    }
    Write-RunLog ''
    Write-RunLog "==== Automatic maintenance$(if ($DryRun) { ' (test run: nothing is changed)' }) ===="
    $times = Read-AutoJobTimes
    $script:RunRestorePoint = $false
    foreach ($job in Get-AutoJobs) {
        if ($job.Mode -eq 'off') { continue }
        if (-not $DryRun -and -not (Test-AutoJobDue $job $times)) {
            Write-RunLog "$($job.Name): not due yet (it runs $($AutoEveryText[[string]$job.Every]); last ran $($times[$job.Key].ToString('g')))."
            continue
        }
        Write-RunLog "---- $($job.Name) ($(if ($job.Mode -eq 'notify') { 'tell me' } else { 'do it' })) ----"
        $r = New-AutoJobResult $job
        try {
            switch ($job.Key) {
                'apps' { Invoke-AutoApps $r }
                'win' { Invoke-AutoWindows $r }
                'clean' { Invoke-AutoClean $r }
                'health' { Invoke-AutoHealth $r }
            }
        }
        catch { $r.Error = $_.Exception.Message }
        if (-not $DryRun -and -not $r.Error) { Save-AutoJobTime $job.Key }
        Write-RunLog "$($job.Name): $(Format-AutoJobSummary $r $DryRun)"
        $run.Jobs += [pscustomobject]$r
    }
    foreach ($j in $run.Jobs) { $run.Updated += $j.Updated; $run.Reboot += $j.Reboot; $run.Failed += $j.Failed; $run.Skipped += $j.Skipped }
    $apps = @($run.Jobs | Where-Object { $_.Key -eq 'apps' }) | Select-Object -First 1
    if ($apps) { $run.Available = $apps.Available; $run.Items = $apps.Items; $run.Error = $apps.Error }
    if (-not $run.Jobs.Count) { Write-RunLog 'Nothing to do: every job is off or not due yet.' }
    Write-RunLog ("Automatic maintenance finished: {0} done, {1} need a restart, {2} failed" -f $run.Updated, $run.Reboot, $run.Failed)
    try { [IO.File]::WriteAllText($LastRunPath, ([pscustomobject]$run | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false))) } catch { }

    $jobs = @($run.Jobs | Where-Object { $_.Key -ne 'health' })   # health problems get their own notification
    $problem = [bool](@($jobs | Where-Object { $_.Error -or $_.Failed }).Count)
    $waiting = [bool](@($jobs | Where-Object { Test-AutoJobWaiting $_ }).Count)
    $changed = [bool](@($jobs | Where-Object { -not $_.Listed -and ($_.Updated -or $_.Reboot) }).Count)
    $notify = $DryRun -or $problem -or $waiting -or ($Settings.NotifyReboot -and $run.Reboot) -or ($Settings.NotifyAlways -and $changed)
    if ($notify -and $run.Jobs.Count) { Show-RunNotification ([pscustomobject]$run) }
    return [int]$problem
}

if ($Auto) { exit (Invoke-AutoRun) }

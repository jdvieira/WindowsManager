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

# The run's result as a Windows notification (the default) or, when those are off or the pop-up is chosen, as this
# app's own pop-up with every app's result
function Show-RunNotification($Run) {
    if ($Settings.NotifyStyle -eq 'toast' -and -not $Screenshot) {
        $failed = @($Run.Items | Where-Object { $_.State -eq 'error' })
        $reboot = @($Run.Items | Where-Object { $_.State -eq 'reboot' })
        $done = [int]$Run.Updated + [int]$Run.Reboot
        $n = @($Run.Items).Count
        $names = { param($list) $s = @($list | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ', '; if (@($list).Count -gt 3) { $s += " and $(@($list).Count - 3) more" }; $s }
        $t = if ($Run.Error) { @("Automatic updates couldn't check for updates", $Run.Error, '') }
        elseif ($Run.DryRun) { @($(if ($n) { "Test run: $n app$(if ($n -ne 1) { 's' }) would be $(if ($Run.Mode -eq 'notify') { 'listed' } else { 'updated' })" } else { 'Test run: everything is up to date' }), 'Nothing was installed. This is how automatic updates will notify you.', (& $names $Run.Items)) }
        elseif ($Run.Mode -eq 'notify') { @("$n update$(if ($n -ne 1) { 's are' } else { ' is' }) available", (& $names $Run.Items), 'Nothing was installed. Open the app to choose what to update.') }
        elseif ($failed.Count) { @("$($failed.Count) automatic update$(if ($failed.Count -ne 1) { 's' }) failed", (& $names $failed), $(if ($done) { "$done other app$(if ($done -ne 1) { 's' }) updated." } else { 'Open the app to retry them.' })) }
        elseif ($reboot.Count) { @('Restart to finish updating', "$done app$(if ($done -ne 1) { 's' }) updated; some need a restart.", (& $names $reboot)) }
        else { @("$done app$(if ($done -ne 1) { 's' }) updated", (& $names $Run.Items), 'Automatic updates finished without problems.') }
        if (Show-Toast $t[0] $t[1] $t[2] -Important:([bool]($Run.Error -or $failed.Count))) { return }
    }
    $resources = [regex]::Match($Xaml, '(?s)<Window\.Resources>.*?</Window\.Resources>').Value
    $win = [System.Windows.Markup.XamlReader]::Parse($NotifyXaml.Replace('__RESOURCES__', $resources))
    $icon = Get-AppIcon
    if ($icon) { $win.Icon = $icon }
    $f = @{}
    foreach ($n in 'Head', 'Sub', 'Glyph', 'GlyphBg', 'Items', 'BtnClose', 'BtnViewLog', 'BtnOpenApp') { $f[$n] = $win.FindName($n) }

    $failed = @($Run.Items | Where-Object { $_.State -eq 'error' })
    $reboot = @($Run.Items | Where-Object { $_.State -eq 'reboot' })
    $done = [int]$Run.Updated + [int]$Run.Reboot
    if ($Run.Error) {
        $f.Head.Text = "Automatic updates couldn't check for updates"; $f.Sub.Text = $Run.Error; $kind = 'error'
    }
    elseif ($Run.DryRun) {
        $n = @($Run.Items).Count
        $f.Head.Text = if ($n) { "Test run: $n app$(if ($n -ne 1) { 's' }) would be $(if ($Run.Mode -eq 'notify') { 'listed' } else { 'updated' })" } else { 'Test run: everything is up to date' }
        $f.Sub.Text = 'Nothing was installed. This is how automatic updates will notify you.'; $kind = 'info'
    }
    elseif ($Run.Mode -eq 'notify') {
        $n = @($Run.Items).Count
        $f.Head.Text = "$n update$(if ($n -ne 1) { 's are' } else { ' is' }) available"
        $f.Sub.Text = 'Nothing was installed. Open the app to choose what to update.'; $kind = 'info'
    }
    elseif ($failed.Count) {
        $f.Head.Text = "$($failed.Count) automatic update$(if ($failed.Count -ne 1) { 's' }) failed"
        $f.Sub.Text = if ($done) { "$done other app$(if ($done -ne 1) { 's' }) updated." } else { 'Open the app to retry, or update interactively to see the installer.' }
        $kind = 'error'
    }
    elseif ($reboot.Count) {
        $f.Head.Text = 'Restart to finish updating'; $f.Sub.Text = "$done app$(if ($done -ne 1) { 's' }) updated; some need a restart."; $kind = 'warn'
    }
    else { $f.Head.Text = "$done app$(if ($done -ne 1) { 's' }) updated"; $f.Sub.Text = 'Automatic updates finished without problems.'; $kind = 'ok' }

    $colors = @{ error = '#FF7B6B'; warn = '#F6B115'; ok = '#5BC27A'; info = '#4FD8E0' }
    $bgs = @{ error = '#3A2220'; warn = '#3A3120'; ok = '#1F3326'; info = '#17414C' }
    $glyphs = @{ error = [string][char]0xE783; warn = [string][char]0xE777; ok = [string][char]0xE73E; info = [string][char]0xE946 }
    $conv = New-Object System.Windows.Media.BrushConverter
    $f.Glyph.Text = $glyphs[$kind]; $f.Glyph.Foreground = $conv.ConvertFrom($colors[$kind]); $f.GlyphBg.Background = $conv.ConvertFrom($bgs[$kind])

    # Failures first, then restarts, then the rest; each app with its result
    $stateColor = @{ error = '#FF7B6B'; reboot = '#F6B115'; ok = '#5BC27A'; skipped = '#9A9A9A'; cancelled = '#9A9A9A'; pending = '#4FD8E0' }
    $order = @{ error = 0; reboot = 1; ok = 2 }
    foreach ($item in @($Run.Items | Sort-Object { if ($order.ContainsKey("$($_.State)")) { $order["$($_.State)"] } else { 3 } }, Name)) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Margin = '0,0,0,9'
        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $item.Name; $name.FontWeight = 'SemiBold'; $name.TextTrimming = 'CharacterEllipsis'
        $detail = New-Object System.Windows.Controls.TextBlock
        $detail.Text = $item.Detail; $detail.FontSize = 12.5; $detail.TextWrapping = 'Wrap'
        $c = $stateColor["$($item.State)"]; if (-not $c) { $c = '#BDBDBD' }
        $detail.Foreground = $conv.ConvertFrom($c)
        [void]$row.Children.Add($name); [void]$row.Children.Add($detail)
        [void]$f.Items.Children.Add($row)
    }
    if (-not @($Run.Items).Count) { $f.Items.Parent.Visibility = 'Collapsed' }

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

# One pass over the given rows; results land in $Items (keyed Id|Source)
function Invoke-AutoPass($Rows, $Items) {
    foreach ($r in $Rows) { $Sync.Jobs.Enqueue(@{ Key = "$($r.Id)|$($r.Source)"; Id = $r.Id; Name = $r.Name; Source = $r.Source; Explicit = $false; Interactive = $false; Silent = $true; UninstallPrevious = $Settings.UninstallPrevious; Verbose = $Settings.VerboseLogs }) }
    foreach ($ev in (Invoke-WorkerNow 'upgrade' $null)) {
        if ($ev.T -eq 'state' -and $ev.SelfUpdating) { Set-SelfUpdating $ev.Id $true; Write-RunLog "$($ev.Id) is updated by Windows or by itself; automatic updates leave it alone from now on." }
        if ($ev.T -eq 'state' -and $ev.State -in $TerminalStates -and $Items.Contains($ev.Key)) {
            $Items[$ev.Key].State = $ev.State
            $Items[$ev.Key].Detail = if ($ev.State -in 'ok', 'reboot') { "$($ev.Detail): $($Items[$ev.Key].From) to $($Items[$ev.Key].To)" } else { $ev.Detail }
        }
    }
}

# Restore point before installing. Needs administrator rights (an elevated task) and System Protection on the system
# drive; Windows also creates at most one every 24 hours. A missing restore point never stops the updates.
function New-RunRestorePoint {
    if (-not $IsAdmin) { Write-RunLog 'Restore point skipped: turn on "Run elevated" for the scheduled task to create one.'; return }
    try {
        $warn = $null
        Checkpoint-Computer -Description 'Before Windows Manager automatic updates' -RestorePointType APPLICATION_INSTALL -WarningAction SilentlyContinue -WarningVariable warn
        if ($warn) { Write-RunLog "Restore point not created: $($warn -join ' ')" } else { Write-RunLog 'Restore point created.' }
    }
    catch { Write-RunLog "Restore point not created: $($_.Exception.Message)" }
}

# Unattended update of everything winget offers, except hidden (or pinned), explicit and shortened-ID apps
function Invoke-AutoRun {
    $notifyOnly = $Settings.AutoMode -eq 'notify'
    $run = [ordered]@{ Time = (Get-Date).ToString('o'); DryRun = [bool]$DryRun; Mode = $(if ($notifyOnly) { 'notify' } else { 'install' }); Available = 0
        Updated = 0; Reboot = 0; Failed = 0; Skipped = 0; Error = $null; Items = @()
    }
    Write-RunLog ''
    Write-RunLog "==== Automatic $(if ($notifyOnly) { 'update check (notify only)' } else { 'update run' })$(if ($DryRun) { ' (dry run)' }) ===="
    if (-not $WingetPath) { $run.Error = 'winget is not installed.' }
    else {
        $scan = @(Invoke-WorkerNow 'scan' (Get-ScanArg)) | Where-Object { $_.T -eq 'scan' } | Select-Object -Last 1
        if (-not $scan) { $run.Error = 'The update check stopped unexpectedly.' }
        elseif ($scan.Error) { $run.Error = ($scan.Error -split "`n")[0] }
        else {
            # An empty list can arrive as $null, and $null | Where-Object would pass one empty row through
            $rows = @($scan.Rows | Where-Object { $_ -and $_.Id })
            $todo = @($rows | Where-Object { -not $_.Explicit -and -not $_.Truncated -and -not $_.Pin -and $Settings.Hidden -notcontains $_.Id -and -not (Test-SelfUpdating $_.Id) })
            $left = $rows.Count - $todo.Count
            if ($left) { Write-RunLog "Skipping $left app(s) that are hidden (kept at their version), updated by Windows, or need an explicit upgrade." }
            $items = [ordered]@{}
            foreach ($r in $todo) { $items["$($r.Id)|$($r.Source)"] = [ordered]@{ Name = $r.Name; Id = $r.Id; From = $r.Version; To = $r.Available; State = 'pending'; Detail = "$($r.Version) to $($r.Available)" } }
            if ($DryRun) { foreach ($i in $items.Values) { $i.Detail = "Would $(if ($notifyOnly) { 'list' } else { 'update' }) $($i.From) to $($i.To)" } }
            elseif ($notifyOnly) {
                $run.Available = $todo.Count
                Write-RunLog "$($todo.Count) update(s) available; notify-only mode installs nothing."
            }
            elseif ($todo.Count) {
                if ($Settings.RestorePoint) { New-RunRestorePoint }
                $byKey = @{}
                foreach ($r in $todo) { $byKey["$($r.Id)|$($r.Source)"] = $r }
                Invoke-AutoPass $todo $items
                # One more try for failures that may be temporary (app in use, download hiccup); policy and approval failures are final
                $retry = @($items.Keys | Where-Object { $items[$_].State -in 'error', 'pending' -and $items[$_].Detail -notmatch 'policy|declined|shortened' } | ForEach-Object { $byKey[$_] })
                if ($Settings.AutoRetry -and $retry.Count) {
                    Write-RunLog "Retrying $($retry.Count) failed update(s) in 30 seconds."
                    Start-Sleep -Seconds 30
                    Invoke-AutoPass $retry $items
                    foreach ($r in $retry) { $i = $items["$($r.Id)|$($r.Source)"]; if ($i.State -in 'ok', 'reboot') { $i.Detail += ' (second try)' } }
                }
                foreach ($i in $items.Values) {
                    switch ($i.State) { 'ok' { $run.Updated++ } 'reboot' { $run.Reboot++ } 'error' { $run.Failed++ } 'pending' { $i.State = 'error'; $i.Detail = 'Did not finish; see the log'; $run.Failed++ } default { $run.Skipped++ } }
                    Add-History 'update' $i.Name $i.Id $i.From $i.To $i.State $i.Detail 'auto'
                }
            }
            $run.Items = @($items.Values | ForEach-Object { [pscustomobject]$_ })
        }
    }
    Write-RunLog ("Automatic run finished: {0} updated, {1} need a restart, {2} failed, {3} skipped{4}" -f $run.Updated, $run.Reboot, $run.Failed, $run.Skipped, $(if ($run.Error) { "; error: $($run.Error)" }))
    try { [pscustomobject]$run | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $LastRunPath -Encoding UTF8 } catch { }

    $notify = $DryRun -or $run.Error -or $run.Failed -or ($notifyOnly -and $run.Available) -or ($Settings.NotifyReboot -and $run.Reboot) -or ($Settings.NotifyAlways -and ($run.Updated + $run.Reboot))
    if ($notify) { Show-RunNotification ([pscustomobject]$run) }
    # then the PC's health: a reading for Device Health's trends, and a notification about any new problem
    if ($Settings.HealthAlerts -and -not $DryRun) {
        try {
            $hev = @(Invoke-WorkerNow 'health' @{}) | Where-Object { $_.T -eq 'health' } | Select-Object -Last 1
            if ($hev) { Add-HealthSnapshot $hev; Invoke-HealthAlerts $hev }
        }
        catch { Write-RunLog "Health check failed: $($_.Exception.Message)" }
    }
    return [int]([bool]($run.Error -or $run.Failed))
}

$TerminalStates = 'ok', 'reboot', 'skipped', 'error', 'cancelled'
if ($Auto) { exit (Invoke-AutoRun) }

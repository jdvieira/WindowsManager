# Windows Manager - Main (part of src\; see Windows_Manager.ps1)

if ($SelfTest) {
    # Validation only: a real update check, installed list and details lookup through the same worker and event
    # handlers the window uses, then a summary of what each section holds
    function Invoke-SelfTestOp([string]$Op, $Arg) {
        $bg = Start-Background $Op $Arg
        [void]$bg.Handle.AsyncWaitHandle.WaitOne([TimeSpan]::FromMinutes(5))
        Complete-Background $bg
    }
    Invoke-SelfTestOp 'scan' (Get-ScanArg)
    Invoke-SelfTestOp 'list' @{}
    Show-Starter
    Update-View
    "winget:     $WingetPath"
    "Updates:    mode=$($script:Mode) apps=$($Packages.Count)"
    if ($script:Mode -eq 'error') { "  error:    $($script:ErrorInfo.updates.Text)" }
    $Packages | Select-Object Name, Id, Version, Available, Source, ExplicitTarget, Truncated | Format-Table -AutoSize | Out-String -Width 250
    "Installed:  mode=$($script:InstalledMode) apps=$($InstalledItems.Count) from winget=$(@($InstalledItems | Where-Object { $_.Source }).Count) with update=$(@($InstalledItems | Where-Object { $_.Available }).Count)"
    "Discover:   starter=$($DiscoverItems.Count) installed=$(@($DiscoverItems | Where-Object { $_.IsInstalled }).Count)"
    "Status:     $($UI.StatusText.Text)"
    if ($Screenshot) {
        function Save-Snap([string]$Suffix) {
            $Window.Dispatcher.Invoke([action] {}, 'ApplicationIdle')
            $root = $Window.Content
            $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap([int]$root.ActualWidth, [int]$root.ActualHeight, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
            $bmp.Render($root)
            $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
            $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bmp))
            $file = if ($Suffix) { [IO.Path]::ChangeExtension($Screenshot, ".$Suffix.png") } else { $Screenshot }
            $fs = [IO.File]::Create($file); $enc.Save($fs); $fs.Close()
        }
        # Preview every row state on the real update list
        $states = @(@('running', ('Downloading' + $Ellipsis), 42), @('queued', 'Queued', -1), @('ok', 'Updated', -1), @('error', 'Installer failed with exit code: 1603', -1), @('reboot', 'Updated, restart required', -1))
        $sorted = @($View)
        for ($k = 0; $k -lt [Math]::Min($states.Count, $sorted.Count); $k++) { $sorted[$k].State = $states[$k][0]; $sorted[$k].Detail = $states[$k][1]; $sorted[$k].Progress = $states[$k][2] }
        if ($sorted.Count -gt 5) { $sorted[5].Selected = $true }
        $Window.Add_ContentRendered({
                $UI.TabUpdates.IsChecked = $true
                Save-Snap ''
                # Discover (starter list with an install running), Installed, and the details panel
                $UI.TabDiscover.IsChecked = $true
                $d = @($DiscoverView | Where-Object { -not $_.IsInstalled }) | Select-Object -First 2
                if ($d.Count -ge 2) { $d[0].State = 'running'; $d[0].Detail = 'Installing' + $Ellipsis; $d[0].Progress = -1; $d[1].Selected = $true }
                Update-View
                Save-Snap 'discover'
                $UI.TabInstalled.IsChecked = $true
                Save-Snap 'installed'
                $pick = @($InstalledView | Where-Object { $_.Source -eq 'winget' }) | Select-Object -First 1
                if ($pick) {
                    Show-Details $pick
                    $sh = $script:Showers[$script:Showers.Count - 1]
                    [void]$sh.Handle.AsyncWaitHandle.WaitOne([TimeSpan]::FromMinutes(2))
                    Complete-Background $sh; [void]$script:Showers.Remove($sh)
                    Save-Snap 'details'
                    $UI.DetailsOverlay.Visibility = 'Collapsed'
                    Invoke-RowAction $pick
                    Save-Snap 'confirm'
                    Complete-Confirm $false
                }
                $UI.TabUpdates.IsChecked = $true
                Open-SchedulePanel
                Save-Snap 'schedule'
                $UI.ScheduleOverlay.Visibility = 'Collapsed'
                Open-Options
                for ($pg = 0; $pg -lt 5; $pg++) { $UI.OptNav.SelectedIndex = $pg; Save-Snap "options$pg" }
                $Window.Close()
            })
        Update-View
        $Window.ShowInTaskbar = $false
        [void]$Window.ShowDialog()
        "Screenshot: $Screenshot"
    }
    exit 0
}

$Timer.Start()
[void]$Window.ShowDialog()
exit 0

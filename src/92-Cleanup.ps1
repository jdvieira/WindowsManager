# Windows Manager - Cleanup (part of src\; see Windows_Manager.ps1)

# The Cleanup tab: the system drive's space, the leftover files Clean up deletes (measured and cleaned by
# 86-Health.ps1), the largest files in your folders, and the apps that take the most space.
$BigFiles = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.BigFile]'
$UI.ClBigList.ItemsSource = $BigFiles
$script:BigReader = $null
$script:BigRead = $false
$BigMinBytes = 100MB
$script:AppsKey = ''

function Get-BigFolders {
    return @((Get-DownloadsFolder), [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('MyVideos'),
        [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyMusic')) | Where-Object { $_ } | Select-Object -Unique
}
function Start-BigFiles {
    if ($script:BigReader) { return }
    $script:BigReader = Start-Tracked 'bigfiles' @{ Folders = @(Get-BigFolders); MinBytes = $BigMinBytes; Top = 25 } { $script:BigReader = $null; $script:BigRead = $true }
    Update-View
}
$EventHandlers.bigfiles = {
    param($Ev)
    $BigFiles.Clear()
    foreach ($f in @($Ev.Files)) {
        $b = New-Object WingetUM.BigFile
        $b.Name = $f.Name; $b.Folder = $f.Folder; $b.Path = $f.Path; $b.Bytes = $f.Bytes; $b.Modified = $f.Modified
        $BigFiles.Add($b)
    }
    $script:BigRead = $true
    Update-View
}

function Request-BigDelete($b) {
    if (-not $b -or -not $b.CanDelete) { return }
    Show-Confirm 'bigdel' @{ File = $b } "Move $($b.Name) to the Recycle Bin?" "$($b.Path)`n`n$($b.SizeText), last changed $($b.Modified). It stays in the Recycle Bin until you empty it, so you can still get it back." 'Move to Recycle Bin' -Danger
}
$ConfirmHandlers.bigdel = {
    param($Payload)
    $b = $Payload.File
    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($b.Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        $b.State = 'ok'; $b.Detail = 'Moved to the Recycle Bin'
        Add-History 'cleanup' $b.Name $b.Path '' '' 'ok' "Moved to the Recycle Bin ($($b.SizeText))"
        $script:LastSummary = "$($b.Name) is in the Recycle Bin"
        $r = @($CleanItems | Where-Object { $_.Key -eq 'recycle' }) | Select-Object -First 1
        if ($r -and $r.Bytes -ge 0) { $r.Bytes += $b.Bytes }
    }
    catch { $b.State = 'error'; $b.Detail = "Couldn't move it: $($_.Exception.Message)" }
    Update-View
}

# The biggest apps, from the Installed Software list (sizes as each app reports them)
function Update-CleanupApps {
    $key = "$($script:InstalledChecked)|$($InstalledItems.Count)"
    if ($key -eq $script:AppsKey) { return }
    $script:AppsKey = $key
    $UI.ClAppList.ItemsSource = @($InstalledItems | Where-Object { $_.SizeKB -gt 0 } | Sort-Object SizeKB -Descending | Select-Object -First 8)
}

function Update-CleanupView {
    $h = $script:HealthInfo
    $sys = if ($h) { @($h.Volumes | Where-Object { $_.Letter -eq $env:SystemDrive }) | Select-Object -First 1 } else { $null }
    if ($sys -and $sys.Size) {
        $used = 100.0 * ($sys.Size - $sys.Free) / $sys.Size
        $UI.ClDriveBar.Value = $used
        $UI.ClDriveBar.Foreground = if ($used -ge 90) { $Window.FindResource('Bad') } elseif ($used -ge 80) { $Window.FindResource('Warn') } else { $Window.FindResource('BarGradient') }
        $UI.ClDriveText.Text = "$($sys.Letter) $(Format-Size $sys.Free) free of $(Format-Size $sys.Size)"
    }
    else { $UI.ClDriveText.Text = "Reading the drives$Ellipsis" }
    $all = [long]0; foreach ($i in $CleanItems) { if ($i.Bytes -gt 0) { $all += $i.Bytes } }
    $UI.ClTitle.Text = if ($all -gt 0) { "Free up space: about $(Format-Size $all) of leftover files" } else { 'Free up space' }
    Update-CleanView
    # large files
    $names = 'Downloads, Desktop, Documents, Videos, Pictures and Music'
    $bigTotal = [long]0; foreach ($b in $BigFiles) { if ($b.State -ne 'ok') { $bigTotal += $b.Bytes } }
    $UI.ClBigInfo.Text = if ($script:BigReader) { "Looking through $names for files over $(Format-Size $BigMinBytes)$Ellipsis" }
    elseif ($BigFiles.Count) { "The $($BigFiles.Count) largest files over $(Format-Size $BigMinBytes) in $names ($(Format-Size $bigTotal) in all). Delete moves a file to the Recycle Bin; files kept only in OneDrive are left out." }
    elseif ($script:BigRead) { "No files over $(Format-Size $BigMinBytes) in $names." } else { '' }
    $UI.ClBigList.Visibility = ConvertTo-Visibility ($BigFiles.Count -gt 0)
    $UI.ClBigScan.IsEnabled = -not $script:BigReader
    # biggest apps
    Update-CleanupApps
    $UI.ClAppsInfo.Text = if (-not $script:InstalledKnown) { "Reading installed software$Ellipsis" } else { 'The apps taking the most space, as each app reports its size. Uninstall asks first.' }
    $UI.ClRefresh.IsEnabled = -not $script:CleanReader -and -not $script:Cleaner -and -not $script:BigReader
}

$Panels.cleanup = @{
    Panel   = 'CleanupPanel'
    Update  = { Update-CleanupView }
    Status  = {
        if ($script:Cleaner) { "Cleaning up$Ellipsis" }
        elseif ($script:CleanReader -or $script:BigReader) { "Measuring$Ellipsis" }
        else { $all = [long]0; foreach ($i in $CleanItems) { if ($i.Bytes -gt 0) { $all += $i.Bytes } }; if ($all -gt 0) { "About $(Format-Size $all) of leftover files" } }
    }
    Open    = {
        if (-not $script:CleanMeasured -and -not $script:CleanReader) { Start-CleanScan }
        if (-not $script:HealthInfo -and -not $script:HealthReader) { Start-HealthScan }
        if (-not $script:BigRead) { Start-BigFiles }
        if (-not $script:InstalledKnown -and -not $script:Lister) { Start-InstalledScan }
    }
    Refresh = { if ($UI.ClRefresh.IsEnabled) { Start-CleanScan; Start-HealthScan; Start-BigFiles } }
}

$UI.TabCleanup.Add_Checked({ Set-Section 'cleanup' })
$UI.ClRefresh.Add_Click({ Start-CleanScan; Start-HealthScan; Start-BigFiles })
$UI.ClBigScan.Add_Click({ Start-BigFiles })
$UI.ClAllApps.Add_Click({
        $UI.TabInstalled.IsChecked = $true
        $v = $InstalledView
        if (-not ($v.SortDescriptions.Count -and $v.SortDescriptions[0].PropertyName -eq 'SizeKB' -and $v.SortDescriptions[0].Direction -eq 'Descending')) { Set-Sort 'SizeKB' }
        Update-View
    })
$UI.ClBigList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -isnot [System.Windows.Controls.Button]) { return }
        $b = $src.DataContext
        if ($src.Tag -eq 'bigshow' -and $b) { try { Start-Process explorer.exe -ArgumentList "/select,`"$($b.Path)`"" } catch { } }
        elseif ($src.Tag -eq 'bigdel') { Request-BigDelete $b }
    })
$UI.ClAppList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'appuninstall') { Invoke-RowAction $src.DataContext }
    })

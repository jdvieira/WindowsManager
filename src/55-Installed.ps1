# Windows Manager - Installed (part of src\; see Windows_Manager.ps1)

# -Quiet (after installs and uninstalls) keeps the current list on screen while it is read again
function Start-InstalledScan([switch]$Quiet) {
    if ($script:Lister) { return }
    if (-not (Test-WingetPresent 'installed')) { return }
    if (-not $Quiet -or $script:InstalledMode -ne 'ready') { $script:InstalledMode = 'loading' }
    Add-LogLine ''
    Add-LogLine "---- Reading installed apps ($('{0:G}' -f (Get-Date))) ----"
    $script:Lister = Start-Background 'list' @{}
    Update-View
}

# Store (MSIX) app sizes: remembered in sizes.json by package full name, measured in the background when new
$SizeCachePath = Join-Path $DataDir 'sizes.json'
$script:SizeCache = @{}
try {
    if (Test-Path -LiteralPath $SizeCachePath) {
        $saved = Get-Content -LiteralPath $SizeCachePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($prop in $saved.PSObject.Properties) { $script:SizeCache[$prop.Name] = [long]$prop.Value }
    }
}
catch { }
$script:Sizer = $null
function Start-MsixSizes {
    $todo = @()
    foreach ($p in $InstalledItems) {
        if ($p.Id -notlike 'MSIX\*' -or $p.Truncated -or $p.SizeKB -gt 0) { continue }
        $full = $p.Id.Substring(5)
        if ($script:SizeCache.ContainsKey($full)) { $p.SizeKB = $script:SizeCache[$full] }
        else { $todo += @{ Key = $p.Key; Full = $full } }
    }
    if ($todo.Count -and -not $script:Sizer) { $script:Sizer = Start-Background 'msixsizes' @{ Items = $todo } }
}
function Complete-Size($Ev) {
    if ($Ev.KB -gt 0) { $script:SizeCache[$Ev.Full] = [long]$Ev.KB }
    $p = $ByKey[$Ev.Key]
    if ($p -and $Ev.KB -gt 0) { $p.SizeKB = $Ev.KB }
}
function Save-SizeCache {
    # only packages still installed are kept
    $keep = [ordered]@{}
    foreach ($p in $InstalledItems) { if ($p.Id -like 'MSIX\*') { $full = $p.Id.Substring(5); if ($script:SizeCache.ContainsKey($full)) { $keep[$full] = $script:SizeCache[$full] } } }
    try { [pscustomobject]$keep | ConvertTo-Json -Compress | Set-Content -LiteralPath $SizeCachePath -Encoding UTF8 } catch { }
}

function Complete-List($Ev) {
    if ($Ev.Error) { Set-SectionError 'installed' "Couldn't read the installed apps" $Ev.Error; return }
    $good = @($Ev.Rows | Where-Object { $_ -and $_.Id })
    $rows = foreach ($r in $good) {
        $p = Get-Row 'installed' $r
        $p.Available = [string]$r.Available
        $p.SizeKB = [long]$r.SizeKB
        $p.Hidden = $Settings.Hidden -contains $p.Id
        $p.Truncated = [bool]$r.Truncated
        if ($p.State -eq '') { $p.Detail = if ($p.Truncated) { 'winget shortened this ID; uninstall it from Settings > Apps' } else { '' } }
        $p
    }
    Set-SectionRows $InstalledItems @($rows)
    Start-MsixSizes
    if ($null -ne $Ev.Pins) { $script:Pins = $Ev.Pins }
    Update-PinRows
    $script:InstalledIds.Clear()
    foreach ($r in $good) { [void]$script:InstalledIds.Add($r.Id) }
    $script:InstalledKnown = $true
    $script:InstalledStale = $false
    $script:InstalledMode = 'ready'
    $script:InstalledChecked = Get-Date
    Update-DiscoverInstalled
    $script:VendorCache = $null
    if ($script:Section -eq 'drivers' -and $script:DrvDevicesRead) { Request-VendorInstall }
}

# Export list: pick the apps, then save them in winget's export format, grouped by source
function Open-ExportList {
    $seen = @{}
    $apps = @($InstalledItems | Where-Object { $_.Source -and -not $_.Truncated } | Sort-Object Name, Id | Where-Object {
            if ($seen.ContainsKey($_.Id)) { $false } else { $seen[$_.Id] = $true; $true } })
    if (-not $apps.Count) { $script:LastSummary = 'No apps from a winget source to export yet.'; Update-View; return }
    Show-Pick 'export' 'Export your app list' "Choose the apps to save. On another PC, or after a reset, open the file with Import list on the Discover tab to install them. winget import reads it too." "Save list$Ellipsis" $apps
}

function Show-Pick([string]$Kind, [string]$Title, [string]$Text, [string]$OkText, $Items) {
    $script:Pick = $Kind
    $UI.PickTitle.Text = $Title
    $UI.PickText.Text = $Text
    $UI.PickOk.Content = $OkText
    $UI.PickList.Children.Clear()
    $muted = $Window.FindResource('Muted')
    foreach ($p in $Items) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Style = $Window.FindResource('CheckItem')
        $cb.IsChecked = $true
        $cb.Tag = $p
        $stack = New-Object System.Windows.Controls.StackPanel
        $n = New-Object System.Windows.Controls.TextBlock
        $n.Text = $p.Name; $n.TextTrimming = 'CharacterEllipsis'
        $s = New-Object System.Windows.Controls.TextBlock
        $s.Text = "$($p.Id)  $Dot  $($p.Source)"; $s.FontFamily = 'Consolas'; $s.FontSize = 12; $s.Foreground = $muted; $s.Margin = '0,2,0,0'
        [void]$stack.Children.Add($n); [void]$stack.Children.Add($s)
        $cb.Content = $stack
        $cb.Add_Click({ Update-PickCount })
        [void]$UI.PickList.Children.Add($cb)
    }
    Update-PickCount
    $UI.PickOverlay.Visibility = 'Visible'
}

function Update-PickCount {
    $n = @($UI.PickList.Children | Where-Object { $_.IsChecked }).Count
    $UI.PickCount.Text = "$n of $($UI.PickList.Children.Count) selected"
    $UI.PickOk.IsEnabled = $n -gt 0
}

function Complete-Pick {
    $chosen = @($UI.PickList.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if ($script:Pick -eq 'export') { Save-AppList $chosen }
    elseif ($script:Pick -eq 'setup') { Save-SetupFile $chosen }
    elseif ($script:Pick -eq 'leftovers') { Remove-Leftovers $chosen }
}

# A source's details as winget export writes them (from winget source export, or the defaults)
function Get-SourceDetails([string]$Name) {
    $s = @($script:Sources | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if ($s) { return [ordered]@{ Argument = [string]$s.Arg; Identifier = [string]$s.Identifier; Name = [string]$s.Name; Type = [string]$s.Type } }
    if ($Name -eq 'msstore') { return [ordered]@{ Argument = 'https://storeedgefd.dsx.mp.microsoft.com/v9.0'; Identifier = 'StoreEdgeFD'; Name = 'msstore'; Type = 'Microsoft.Rest' } }
    return [ordered]@{ Argument = 'https://cdn.winget.microsoft.com/cache'; Identifier = 'Microsoft.Winget.Source_8wekyb3d8bbwe'; Name = $Name; Type = 'Microsoft.PreIndexed.Package' }
}

function Write-AppList($Apps, [string]$File) {
    $sources = @(foreach ($g in @($Apps | Group-Object Source)) {
            [ordered]@{ Packages = @($g.Group | ForEach-Object { [ordered]@{ PackageIdentifier = $_.Id } }); SourceDetails = (Get-SourceDetails $g.Name) }
        })
    $doc = [ordered]@{ '$schema' = 'https://aka.ms/winget-packages.schema.2.0.json'; CreationDate = (Get-Date).ToString('o'); Sources = $sources; WinGetVersion = ([string]$script:WingetVersion).TrimStart('v') }
    [IO.File]::WriteAllText($File, ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

function Save-AppList($Apps) {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'App list (*.json)|*.json'
    $dlg.FileName = "Apps-$env:COMPUTERNAME.json"
    if (-not $dlg.ShowDialog($Window)) { return }
    try {
        Write-AppList $Apps $dlg.FileName
        $UI.PickOverlay.Visibility = 'Collapsed'
        Add-LogLine "Saved $(@($Apps).Count) apps to $($dlg.FileName)."
        $script:LastSummary = "Saved $(@($Apps).Count) apps to $([IO.Path]::GetFileName($dlg.FileName))"
        Update-View
    }
    catch { $UI.PickCount.Text = "Couldn't save the list: $($_.Exception.Message)" }
}

# Install a specific version: winget show --versions fills the list; the chosen one installs, optionally held there
function Open-VersionPicker($p) {
    if (-not $p -or -not $p.CanUpdate -or -not $p.Source -or -not $WingetPath) { return }
    $script:VersionItem = $p
    $UI.VerSub.Text = "$($p.Name)  $Dot  $($p.Id)"
    $UI.VerList.Items.Clear()
    $UI.VerLoading.Visibility = 'Visible'
    $UI.VerError.Visibility = 'Collapsed'
    $UI.VerInstall.IsEnabled = $false
    $UI.VerHold.IsChecked = $true
    $UI.VersionOverlay.Visibility = 'Visible'
    $script:Showers.Add((Start-Background 'show' @{ Id = $p.Id; Source = $p.Source; Key = $p.Key; Purpose = 'versions'; Versions = $true }))
}

function Complete-VersionList($Ev) {
    $p = $script:VersionItem
    if (-not $p -or $Ev.Key -ne $p.Key -or $UI.VersionOverlay.Visibility -ne 'Visible') { return }
    $UI.VerLoading.Visibility = 'Collapsed'
    $versions = New-Object System.Collections.Generic.List[string]
    $table = $false
    foreach ($l in @($Ev.Lines)) {
        if ($table) { if ($l.Trim()) { $versions.Add($l.Trim()) } }
        elseif ($l.Trim() -match '^-{4,}$') { $table = $true }
    }
    if (-not $Ev.Ok -or -not $versions.Count) {
        $UI.VerError.Text = "winget didn't list any versions for this app. $(@($Ev.Lines) | Select-Object -Last 1)"
        $UI.VerError.Visibility = 'Visible'
        return
    }
    foreach ($v in $versions) { [void]$UI.VerList.Items.Add($v) }
    $UI.VerList.SelectedIndex = 0
    $UI.VerInstall.IsEnabled = $true
}

function Install-ChosenVersion {
    $p = $script:VersionItem
    $v = [string]$UI.VerList.SelectedItem
    if (-not $p -or -not $v) { return }
    $UI.VersionOverlay.Visibility = 'Collapsed'
    $p.Version = $v
    Add-Job @($p) -Version $v -PinAfter:([bool]$UI.VerHold.IsChecked)
}

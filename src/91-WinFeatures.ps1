# Windows Manager - WinFeatures (part of src\; see Windows_Manager.ps1)

# The Windows Features tab. Built-in apps: the Store apps that came with Windows and can be removed for you; removed
# ones stay listed (removed-apps.json) with Reinstall, which registers them again from their files or, when those are
# gone, opens their Microsoft Store page. Optional features: Windows' optional features, turned on or off with
# administrator approval (Enable/Disable-WindowsOptionalFeature); some need a restart.
$FeatureItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.FeatureItem]'
$FeatureView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($FeatureItems)
$FeatureView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
$FeatureView.Filter = [Predicate[object]] {
    param($f)
    if ($f.Kind -ne $(if ($UI.FtViewFeatures.IsChecked) { 'feature' } else { 'app' })) { return $false }
    if ($UI.FtOnOnly.IsChecked -and -not $f.On) { return $false }
    $q = $UI.FtSearch.Text.Trim()
    return (-not $q) -or ("$($f.Name) $($f.SubText) $($f.Publisher) $($f.Description)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$UI.FtList.ItemsSource = $FeatureView
$RemovedAppsPath = Join-Path $DataDir 'removed-apps.json'
$FeatureDescPath = Join-Path $DataDir 'feature-descriptions.json'
$script:FeatDescReader = $null
$script:AppxState = 'none'; $script:AppxError = ''; $script:AppxReader = $null
$script:FeatState = 'none'; $script:FeatError = ''; $script:FeatReader = $null

function Read-RemovedApps {
    try { if (Test-Path -LiteralPath $RemovedAppsPath) { return , @(Get-Content -LiteralPath $RemovedAppsPath -Raw | ConvertFrom-Json) } } catch { }
    return , @()
}
function Save-RemovedApps($List) { try { ConvertTo-Json -InputObject @($List) -Depth 3 | Set-Content -LiteralPath $RemovedAppsPath -Encoding UTF8 } catch { } }

# A description worth showing: not empty, and not just the name again (".NET Framework 4.8 Advanced Services" under
# that name, or "SupportAssist" under "Dell SupportAssist for PCs")
function Get-UsefulDescription([string]$Name, [string]$Text) {
    if (-not $Text) { return '' }
    $n = $Name.ToLowerInvariant() -replace '[^a-z0-9]', ''
    $d = $Text.ToLowerInvariant() -replace '[^a-z0-9]', ''
    if (-not $d -or $d -eq $n -or (($n.Contains($d) -or $d.Contains($n)) -and $d.Length -lt $n.Length + 15)) { return '' }
    return $Text
}

# An optional feature's description: Windows' own text (16-FeatureText.ps1), or one read from Windows earlier
# (feature-descriptions.json; '' where Windows has none)
$script:FeatureDescCache = $null
function Read-FeatureDescCache {
    if ($null -ne $script:FeatureDescCache) { return }
    $script:FeatureDescCache = @{}
    try { if (Test-Path -LiteralPath $FeatureDescPath) { foreach ($p in (Get-Content -LiteralPath $FeatureDescPath -Raw | ConvertFrom-Json).PSObject.Properties) { $script:FeatureDescCache[$p.Name] = [string]$p.Value } } } catch { }
}
function Get-FeatureDescription([string]$Name) {
    if ($FeatureText.ContainsKey($Name)) { return $FeatureText[$Name] }
    Read-FeatureDescCache
    return [string]$script:FeatureDescCache[$Name]
}

function Start-FeatureScan {
    if (-not $script:AppxReader) { $script:AppxState = 'running'; $script:AppxReader = Start-Tracked 'appxlist' @{} { $script:AppxReader = $null; if ($script:AppxState -eq 'running') { $script:AppxState = 'error' } } }
    if (-not $script:FeatReader) { $script:FeatState = 'running'; $script:FeatReader = Start-Tracked 'features' @{} { $script:FeatReader = $null; if ($script:FeatState -eq 'running') { $script:FeatState = 'error' } } }
    Update-View
}

$EventHandlers.appxlist = {
    param($Ev)
    foreach ($f in @($FeatureItems | Where-Object { $_.Kind -eq 'app' })) { [void]$FeatureItems.Remove($f) }
    $have = @{}
    foreach ($a in @($Ev.Items)) {
        $f = New-Object WingetUM.FeatureItem
        $f.Kind = 'app'; $f.Name = $a.Name; $f.SubText = $a.Package; $f.Publisher = $a.Publisher; $f.Description = Get-UsefulDescription $a.Name $a.Description; $f.Key = $a.Full; $f.Family = $a.Family; $f.Location = $a.Location; $f.On = $true
        $FeatureItems.Add($f); $have[$a.Family] = $true
    }
    # removed earlier, and still gone: offered back
    $removed = @(Read-RemovedApps | Where-Object { $_.Family -and -not $have.ContainsKey([string]$_.Family) })
    foreach ($r in $removed) {
        $f = New-Object WingetUM.FeatureItem
        $f.Kind = 'app'; $f.Name = [string]$r.Name; $f.SubText = [string]$r.Package; $f.Publisher = [string]$r.Publisher; $f.Description = Get-UsefulDescription ([string]$r.Name) ([string]$r.Description); $f.Key = [string]$r.Full; $f.Family = [string]$r.Family; $f.Location = [string]$r.Location; $f.On = $false
        $FeatureItems.Add($f)
    }
    Save-RemovedApps $removed
    if ($Ev.Error) { $script:AppxState = 'error'; $script:AppxError = $Ev.Error } else { $script:AppxState = 'ready' }
    Update-View
}
$EventHandlers.features = {
    param($Ev)
    foreach ($f in @($FeatureItems | Where-Object { $_.Kind -eq 'feature' })) { [void]$FeatureItems.Remove($f) }
    foreach ($o in @($Ev.Items)) {
        $f = New-Object WingetUM.FeatureItem
        $f.Kind = 'feature'; $f.Name = $(if ($o.Caption) { $o.Caption } else { $o.Name }); $f.SubText = $o.Name; $f.Key = $o.Name; $f.Publisher = ''
        $f.Description = Get-UsefulDescription $f.Name (Get-FeatureDescription $o.Name)
        $f.Available = $o.State -ne 3; $f.On = $o.State -eq 1
        $FeatureItems.Add($f)
    }
    if ($Ev.Error) { $script:FeatState = 'error'; $script:FeatError = $Ev.Error } else { $script:FeatState = 'ready' }
    # features this app has no words for (newer Windows builds): Windows can say, but only to an administrator
    Read-FeatureDescCache
    $missing = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and -not $FeatureText.ContainsKey($_.Key) -and -not $script:FeatureDescCache.ContainsKey($_.Key) } | ForEach-Object { $_.Key })
    if ($missing.Count -and $IsAdmin -and -not $script:FeatDescReader) { $script:FeatDescReader = Start-Tracked 'featuredesc' @{ Names = $missing } { $script:FeatDescReader = $null } }
    Update-View
}
$EventHandlers.featuredesc = {
    param($Ev)
    $found = $Ev.Items
    if (-not $found -or -not $found.Count) { return }
    foreach ($f in @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $found.ContainsKey($_.Key) })) { $f.Description = Get-UsefulDescription $f.Name $found[$f.Key] }
    Read-FeatureDescCache
    foreach ($k in $found.Keys) { $script:FeatureDescCache[$k] = $found[$k] }
    try { [pscustomobject]$script:FeatureDescCache | ConvertTo-Json | Set-Content -LiteralPath $FeatureDescPath -Encoding UTF8 } catch { }
}

function Request-FeatureChange($f) {
    if (-not $f -or -not $f.CanChange) { return }
    if ($f.Kind -eq 'app') {
        if ($f.On) { Show-Confirm 'ftapp' @{ Item = $f } "Remove $($f.Name)?" "$($f.Name) is removed for you ($($f.SubText)). It stays on this list, so Reinstall can bring it back; if Windows has cleared its files by then, Reinstall opens its Microsoft Store page instead." 'Remove' -Danger }
        else { Start-FeatureChange $f }
        return
    }
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first"; Update-View; return }
    $verb = if ($f.On) { 'Turn off' } else { 'Turn on' }
    Show-Confirm 'ftfeature' @{ Item = $f } "$verb $($f.Name)?" "Windows $(if ($f.On) { 'removes' } else { 'adds' }) the optional feature $($f.SubText). It can take a few minutes, Windows asks for administrator approval, and some features need a restart to finish.$(if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." })" $verb
}
$ConfirmHandlers.ftapp = { param($Payload) Start-FeatureChange $Payload.Item }
$ConfirmHandlers.ftfeature = { param($Payload) Start-FeatureChange $Payload.Item }

function Start-FeatureChange($f) {
    if ($f.Kind -eq 'app') {
        $f.State = 'running'; $f.Detail = $(if ($f.On) { 'Removing' } else { 'Reinstalling' }) + $Ellipsis
        if ($f.On) {
            # remember it first, so it can be offered back
            $list = @(Read-RemovedApps | Where-Object { $_.Family -ne $f.Family }) + @([pscustomobject]@{ Name = $f.Name; Package = $f.SubText; Full = $f.Key; Family = $f.Family; Location = $f.Location; Publisher = $f.Publisher; Description = $f.Description; Removed = (Get-Date).ToString('o') })
            Save-RemovedApps $list
        }
        $script:Showers.Add((Start-Background 'appxchange' @{ Key = $f.Key; Full = $f.Key; Location = $f.Location; Remove = [bool]$f.On }))
        return
    }
    $name = $f.Key -replace "'", "''"
    $body = if ($f.On) {
        "Say 'Turning off $name$Ellipsis'`r`n`$r = Disable-WindowsOptionalFeature -Online -FeatureName '$name' -NoRestart -ErrorAction Stop`r`nif (`$r.RestartNeeded) { Say 'Restart to finish.'; exit 3010 }`r`nSay 'Done.'`r`nexit 0"
    }
    else {
        "Say 'Turning on $name$Ellipsis'`r`n`$r = Enable-WindowsOptionalFeature -Online -FeatureName '$name' -All -NoRestart -ErrorAction Stop`r`nif (`$r.RestartNeeded) { Say 'Restart to finish.'; exit 3010 }`r`nSay 'Done.'`r`nexit 0"
    }
    $f.State = 'running'; $f.Detail = if ($IsAdmin) { 'Working' + $Ellipsis } else { 'Waiting for approval' + $Ellipsis }
    Start-Elevated 'feature' "$(if ($f.On) { 'Turning off' } else { 'Turning on' }) $($f.Name)" $body @() @{ Item = $f; On = -not $f.On } -RestorePoint -RestoreText 'Before changing Windows features' -StallMinutes 30
}
$ElevHandlers.feature = {
    param($Ev, $why, $code, $last, $tag)
    $f = $tag.Item
    if ($why) { $f.State = 'error'; $f.Detail = $why }
    elseif ($code -in 0, 3010) { $f.On = $tag.On; $f.State = $(if ($code -eq 3010) { 'reboot' } else { 'ok' }); $f.Detail = "$(if ($tag.On) { 'Turned on' } else { 'Turned off' })$(if ($code -eq 3010) { '. Restart to finish' })" }
    else { $f.State = 'error'; $f.Detail = "Didn't change$(if ($last) { ": $last" })" }
    Add-History $(if ($tag.On) { 'install' } else { 'uninstall' }) "Windows feature: $($f.Name)" $f.Key '' '' $f.State $f.Detail
    $script:LastSummary = "$($f.Name): $($f.Detail)"
    $FeatureView.Refresh()
}
$EventHandlers.appxchanged = {
    param($Ev)
    $f = @($FeatureItems | Where-Object { $_.Kind -eq 'app' -and $_.Key -eq $Ev.Key }) | Select-Object -First 1
    if (-not $f) { return }
    if ($Ev.Error) {
        if (-not $Ev.Remove -and $f.Family) {
            # its files are gone: the Store can install it again
            $f.State = ''; $f.Detail = ''
            try { Start-Process "ms-windows-store://pdp/?PFN=$($f.Family)" } catch { }
            $script:LastSummary = "$($f.Name) can't be registered again from this PC ($($Ev.Error)), so its Microsoft Store page is open"
        }
        else { $f.State = 'error'; $f.Detail = "Couldn't remove it: $($Ev.Error)" }
    }
    else {
        $f.On = -not $Ev.Remove; $f.State = 'ok'; $f.Detail = if ($Ev.Remove) { 'Removed' } else { 'Reinstalled' }
        if (-not $Ev.Remove) { Save-RemovedApps @(Read-RemovedApps | Where-Object { $_.Family -ne $f.Family }) }
        Add-History $(if ($Ev.Remove) { 'uninstall' } else { 'install' }) $f.Name $f.SubText '' '' 'ok' "Built-in app $(if ($Ev.Remove) { 'removed' } else { 'reinstalled' })"
        $script:LastSummary = "$($f.Name): $($f.Detail)"
    }
    $FeatureView.Refresh()
    Update-View
}

function Update-FeaturesView {
    $apps = $UI.FtViewApps.IsChecked
    $state = if ($apps) { $script:AppxState } else { $script:FeatState }
    $err = if ($apps) { $script:AppxError } else { $script:FeatError }
    $n = @($FeatureItems | Where-Object { $_.Kind -eq 'app' }).Count
    $removed = @($FeatureItems | Where-Object { $_.Kind -eq 'app' -and -not $_.On }).Count
    $fOn = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.On }).Count
    $fAll = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.Available }).Count
    $UI.FtViewAppsText.Text = if ($n) { "Built-in apps ($n)" } else { 'Built-in apps' }
    $UI.FtViewFeaturesText.Text = if ($fAll) { "Optional features ($fOn of $fAll on)" } else { 'Optional features' }
    $UI.FtText.Text = if ($apps) { "Store apps that came with Windows (or that you added) and that Windows lets you remove for your account$(if ($removed) { "; $removed removed, which Reinstall brings back" }). Parts of Windows itself aren't listed." }
    else { "Windows' optional features. Turning one on or off asks for administrator approval and can take a few minutes; some need a restart to finish." }
    $UI.FtHeadName.Text = if ($apps) { 'APP' } else { 'FEATURE' }
    $UI.FtHeadPub.Text = if ($apps) { 'PUBLISHER' } else { '' }
    $UI.FtRefresh.IsEnabled = -not $script:AppxReader -and -not $script:FeatReader
    $msg = $null
    if ($state -eq 'running') { $msg = @{ Bar = $true; Title = $(if ($apps) { 'Reading built-in apps' } else { 'Reading optional features' }); Text = '' } }
    elseif ($state -eq 'error' -and -not @($FeatureView).Count) { $msg = @{ Title = "Couldn't read them"; Text = $err } }
    elseif (-not @($FeatureView).Count) { $msg = @{ Title = 'Nothing matches'; Text = '' } }
    $UI.FtHeader.Visibility = ConvertTo-Visibility (-not $msg)
    $UI.FtList.Visibility = if ($msg) { 'Collapsed' } else { 'Visible' }
    $UI.FtMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) { $UI.FtMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar); $UI.FtMsgTitle.Text = $msg.Title; $UI.FtMsgText.Text = $msg.Text }
}

$Panels.features = @{
    Panel   = 'FeaturesPanel'
    Update  = { Update-FeaturesView }
    Status  = {
        if ($script:AppxReader -or $script:FeatReader) { "Reading$Ellipsis" }
        else {
            $n = @($FeatureItems | Where-Object { $_.Kind -eq 'app' -and $_.On }).Count; if ($n) { "$n built-in apps" }
            $fOn = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.On }).Count; if ($fOn) { "$fOn optional features on" }
        }
    }
    Open    = { if ($script:AppxState -eq 'none' -or $script:FeatState -eq 'none') { Start-FeatureScan } }
    Refresh = { if ($UI.FtRefresh.IsEnabled) { Start-FeatureScan } }
}

$UI.TabFeatures.Add_Checked({ Set-Section 'features' })
$UI.FtRefresh.Add_Click({ Start-FeatureScan })
foreach ($c in 'FtViewApps', 'FtViewFeatures', 'FtOnOnly') { $UI[$c].Add_Click({ $FeatureView.Refresh(); Update-View }) }
$script:FtSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FtSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:FtSearchTimer.Add_Tick({ $script:FtSearchTimer.Stop(); $FeatureView.Refresh(); Update-View })
$UI.FtSearch.Add_TextChanged({ $script:FtSearchTimer.Stop(); $script:FtSearchTimer.Start() })
$UI.FtList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'ftaction') { Request-FeatureChange $src.DataContext }
    })

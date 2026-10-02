# Windows Manager - WinFeatures (part of src\; see Windows_Manager.ps1)

# The Windows Features tab: Windows' optional features, turned on or off with administrator approval
# (Enable/Disable-WindowsOptionalFeature), and shown as Windows' own tree; some need a restart. (Built-in Store apps
# were listed here too in earlier versions; Installed Software lists and uninstalls them.)
$FeatureItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.FeatureItem]'
$FeatureView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($FeatureItems)
# in tree order
$FeatureView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortKey', 'Ascending')))
function Test-FeatureMatch($f) {
    if ($UI.FtOnOnly.IsChecked -and -not $f.On) { return $false }
    $q = $UI.FtSearch.Text.Trim()
    return (-not $q) -or ("$($f.Name) $($f.SubText) $($f.Publisher) $($f.Description)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$FeatureView.Filter = [Predicate[object]] {
    param($f)
    return $f.Kind -eq 'feature' -and $script:FtShown.Contains($f.Key)
}
$UI.FtList.ItemsSource = $FeatureView

# ---- Optional features as a tree, like Windows' "Turn Windows features on or off": collapsed to start with; a
# chevron shows what's under a feature. Filtering (or On only) shows each match with the features it sits under.
$script:FtByKey = @{}        # feature name -> its row
$script:FtChildren = @{}     # feature name -> the rows directly under it
$script:FtExpanded = @{}     # feature name -> open (kept across refreshes)
$script:FtShown = New-Object 'System.Collections.Generic.HashSet[string]'
function Get-FeatureAncestors($f) {
    $list = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $p = $f.ParentKey
    while ($p -and $script:FtByKey.ContainsKey($p) -and -not $seen.ContainsKey($p)) { $seen[$p] = $true; $a = $script:FtByKey[$p]; $list.Add($a); $p = $a.ParentKey }
    return $list.ToArray()
}
function Get-FeatureDescendants($f) {
    $list = New-Object System.Collections.Generic.List[object]
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push($f)
    while ($stack.Count) {
        $kids = $script:FtChildren[$stack.Pop().Key]
        if (-not $kids) { continue }
        foreach ($c in $kids) { if ($list.Count -lt 1000) { $list.Add($c); $stack.Push($c) } }
    }
    return $list.ToArray()
}
# Which features show: with no filter, those whose parents are all open; with one, the matches and what they sit under
function Update-FeatureList {
    $script:FtShown.Clear()
    $filtering = $UI.FtOnOnly.IsChecked -or $UI.FtSearch.Text.Trim()
    foreach ($f in $script:FtByKey.Values) {
        if ($filtering) {
            if (-not (Test-FeatureMatch $f)) { continue }
            [void]$script:FtShown.Add($f.Key)
            foreach ($a in Get-FeatureAncestors $f) { [void]$script:FtShown.Add($a.Key) }
        }
        elseif (-not @(Get-FeatureAncestors $f | Where-Object { -not $_.IsExpanded }).Count) { [void]$script:FtShown.Add($f.Key) }
    }
    # while filtering, a parent that's showing for a match is shown open
    if ($filtering) { foreach ($f in $script:FtByKey.Values) { if ($f.HasChildren) { $f.IsExpanded = @($script:FtChildren[$f.Key] | Where-Object { $_ -and $script:FtShown.Contains($_.Key) }).Count -gt 0 } } }
    else { foreach ($f in $script:FtByKey.Values) { if ($f.HasChildren) { $f.IsExpanded = [bool]$script:FtExpanded[$f.Key] } } }
    $FeatureView.Refresh()
}
function Set-FeatureExpanded([string]$Key, [bool]$Open) {
    if (-not $script:FtByKey.ContainsKey($Key)) { return }
    $script:FtExpanded[$Key] = $Open
    Update-FeatureList
}
# "2 of 5 under it on", like the half-filled box Windows shows for a feature with some of its parts on
function Update-FeatureTreeNotes {
    foreach ($f in $script:FtByKey.Values) {
        if (-not $f.HasChildren) { $f.TreeNote = ''; continue }
        $d = @(Get-FeatureDescendants $f | Where-Object { $_.Available })
        $on = @($d | Where-Object { $_.On }).Count
        $f.TreeNote = if ($d.Count) { "$on of $($d.Count) under it on" } else { '' }
    }
}
$FeatureDescPath = Join-Path $DataDir 'feature-descriptions.json'
$script:FeatDescReader = $null
$script:FeatState = 'none'; $script:FeatError = ''; $script:FeatReader = $null

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

    if (-not $script:FeatReader) { $script:FeatState = 'running'; $script:FeatReader = Start-Tracked 'features' @{} { $script:FeatReader = $null; if ($script:FeatState -eq 'running') { $script:FeatState = 'error' } } }
    Update-View
}

$EventHandlers.features = {
    param($Ev)
    foreach ($f in @($FeatureItems | Where-Object { $_.Kind -eq 'feature' })) { [void]$FeatureItems.Remove($f) }
    $script:FtByKey = @{}; $script:FtChildren = @{}
    # Windows' dialog leaves out the features with no name to show (parts of another feature); so does this list
    foreach ($o in @($Ev.Items | Where-Object { $_.Caption })) {
        $f = New-Object WingetUM.FeatureItem
        $f.Kind = 'feature'; $f.Name = $o.Caption; $f.SubText = $o.Name; $f.Key = $o.Name; $f.Publisher = ''; $f.ParentKey = [string]$o.Parent
        $f.Description = Get-UsefulDescription $f.Name (Get-FeatureDescription $o.Name)
        $f.Available = $o.State -ne 3; $f.On = $o.State -eq 1
        $script:FtByKey[$f.Key] = $f
    }
    foreach ($f in $script:FtByKey.Values) {
        if ($f.ParentKey -and -not $script:FtByKey.ContainsKey($f.ParentKey)) { $f.ParentKey = '' }
        if ($f.ParentKey) { if ($script:FtChildren.ContainsKey($f.ParentKey)) { $script:FtChildren[$f.ParentKey] += $f } else { $script:FtChildren[$f.ParentKey] = [object[]]@($f) } }
    }
    # tree order: each feature, then what's under it, siblings by name (a loop in the links is cut at the top)
    $walk = {
        param($f, [int]$Depth)
        $script:FtOrderSeen[$f.Key] = $true
        $f.Depth = $Depth; $f.SortKey = '{0:D5}' -f (++$script:FtOrder)
        $kids = @($script:FtChildren[$f.Key] | Where-Object { $_ -and -not $script:FtOrderSeen.ContainsKey($_.Key) } | Sort-Object Name)
        $f.HasChildren = $kids.Count -gt 0
        $f.IsExpanded = [bool]$script:FtExpanded[$f.Key]
        foreach ($c in $kids) { & $walk $c ($Depth + 1) }
    }
    $script:FtOrder = 0; $script:FtOrderSeen = @{}
    foreach ($f in @($script:FtByKey.Values | Where-Object { -not $_.ParentKey } | Sort-Object Name)) { & $walk $f 0 }
    foreach ($f in @($script:FtByKey.Values | Where-Object { -not $script:FtOrderSeen.ContainsKey($_.Key) } | Sort-Object Name)) { $f.ParentKey = ''; & $walk $f 0 }
    foreach ($f in $script:FtByKey.Values) { $FeatureItems.Add($f) }
    if ($script:FtKeep -and $script:FtByKey.ContainsKey($script:FtKeep.Key)) { $k = $script:FtByKey[$script:FtKeep.Key]; $k.State = $script:FtKeep.State; $k.Detail = $script:FtKeep.Detail }
    $script:FtKeep = $null
    Update-FeatureTreeNotes
    Update-FeatureList
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
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first"; Update-View; return }
    $verb = if ($f.On) { 'Turn off' } else { 'Turn on' }
    # what changes with it: the features it sits under turn on too; the ones under it that are on turn off too
    if ($f.On) { $also = @(Get-FeatureDescendants $f | Where-Object { $_.On } | ForEach-Object { $_.Name }) }
    else { $also = @(Get-FeatureAncestors $f | Where-Object { -not $_.On } | ForEach-Object { $_.Name }); [array]::Reverse($also) }
    $alsoText = if (-not $also.Count) { '' } elseif ($f.On) { "`n`nThese features under it turn off too:`n$(($also | Select-Object -First 12 | ForEach-Object { "  $([char]0x2022) $_" }) -join "`n")$(if ($also.Count -gt 12) { "`n  and $($also.Count - 12) more" })" } else { "`n`nIt sits under $($also -join ' > '), which turn$(if ($also.Count -eq 1) { 's' }) on too." }
    Show-Confirm 'ftfeature' @{ Item = $f } "$verb $($f.Name)?" "Windows $(if ($f.On) { 'removes' } else { 'adds' }) the optional feature $($f.SubText). It can take a few minutes, Windows asks for administrator approval, and some features need a restart to finish.$alsoText$(if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." })" $verb
}

$ConfirmHandlers.ftfeature = { param($Payload) Start-FeatureChange $Payload.Item }

function Start-FeatureChange($f) {
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
    # the features above or under it may have changed too: read them all again, keeping this one's result showing
    if ($f.State -in 'ok', 'reboot' -and -not $script:FeatReader) {
        $script:FtKeep = @{ Key = $f.Key; State = $f.State; Detail = $f.Detail }
        $script:FeatState = 'running'; $script:FeatReader = Start-Tracked 'features' @{} { $script:FeatReader = $null; if ($script:FeatState -eq 'running') { $script:FeatState = 'error' } }
    }
    Update-FeatureTreeNotes
    Update-FeatureList
}
function Update-FeaturesView {
    $state = $script:FeatState
    $err = $script:FeatError
    $fOn = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.On }).Count
    $fAll = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.Available }).Count
    $UI.FtViewFeaturesText.Text = if ($fAll) { "$fOn of $fAll on" } else { 'Optional features' }
    $UI.FtText.Text = "Windows' optional features, grouped as Windows shows them: the arrow shows what's under one. Turning one on or off asks for administrator approval and can take a few minutes; some need a restart to finish."
    $UI.FtRefresh.IsEnabled = -not $script:FeatReader
    $msg = $null
    if ($state -eq 'running' -and -not @($FeatureView).Count) { $msg = @{ Bar = $true; Title = 'Reading optional features'; Text = '' } }
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
        if ($script:FeatReader) { "Reading$Ellipsis" }
        else {
            $fOn = @($FeatureItems | Where-Object { $_.Kind -eq 'feature' -and $_.On }).Count; if ($fOn) { "$fOn optional features on" }
        }
    }
    Open    = { if ($script:FeatState -eq 'none') { Start-FeatureScan } }
    Refresh = { if ($UI.FtRefresh.IsEnabled) { Start-FeatureScan } }
}

$UI.TabFeatures.Add_Checked({ Set-Section 'features' })
$UI.FtRefresh.Add_Click({ Start-FeatureScan })
$UI.FtOnOnly.Add_Click({ Update-FeatureList; Update-View })
$script:FtSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FtSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:FtSearchTimer.Add_Tick({ $script:FtSearchTimer.Stop(); Update-FeatureList; Update-View })
$UI.FtSearch.Add_TextChanged({ $script:FtSearchTimer.Stop(); $script:FtSearchTimer.Start() })
$UI.FtList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'ftaction') { Request-FeatureChange $src.DataContext }
        # the chevron: show or hide what's under it (while filtering, every match already shows with its parents)
        elseif ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'fttoggle' -and $src.DataContext.HasChildren) {
            if ($UI.FtOnOnly.IsChecked -or $UI.FtSearch.Text.Trim()) { return }
            Set-FeatureExpanded $src.DataContext.Key (-not $src.DataContext.IsExpanded)
            Update-View
        }
    })

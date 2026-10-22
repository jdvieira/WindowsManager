# Windows Manager - Security (part of src\; see Windows_Manager.ps1)

# The Security tab: Microsoft Defender's quick and full scans, what it found (active threats to remove, and what it
# already quarantined or removed, as history), its blocking of potentially unwanted apps, and installed apps on a list
# of known unwanted ones (browser hijackers, adware, fake optimizers and driver updaters). Finding threats is
# Defender's job: this tab reads what it found and asks it to act. Removing one threat rescans the file it was found
# in, so Defender quarantines or removes it; removing all of them is Defender's own Remove-MpThreat. Unwanted apps are
# uninstalled through the queue. When another antivirus is in charge, Defender stands by and can't scan or remove, so
# that is left to the other antivirus.
$SecItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.ThreatItem]'
$SecView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($SecItems)
$SecView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortGroup', 'Ascending')))
$SecView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Time', 'Descending')))
$SecView.Filter = [Predicate[object]] { param($s) $UI.SecHistory.IsChecked -or $s.IsActive -or $s.State }
$UI.SecList.ItemsSource = $SecView
$script:SecState = 'none'          # none | running | ready | error
$script:SecInfo = $null
$script:SecReader = $null
$script:SecScan = $null            # while a scan runs: Kind (quick | full) and Started
$script:SecAppsRead = $null        # the installed list the unwanted apps were matched against

# Installed apps that are unwanted: a regex against the app's name or ID, junk (ticked) or keep (unticked: some
# people choose them), and what it is
$UnwantedApps = @(
    @{ Match = '^Wave ?Browser'; Kind = 'junk'; Note = 'Browser hijacker: changes your search and shows ads' }
    @{ Match = '^OneLaunch|^OneStart'; Kind = 'junk'; Note = 'Browser hijacker: changes your search and shows ads' }
    @{ Match = '^Segurazo|^SAntivirus'; Kind = 'junk'; Note = 'Fake antivirus that is hard to remove' }
    @{ Match = '^Web ?Companion|Lavasoft'; Kind = 'junk'; Note = 'Browser add-on that changes your search and home page' }
    @{ Match = '^ByteFence'; Kind = 'junk'; Note = 'Bundled scanner that changes your browser settings' }
    @{ Match = '^Search Protect|^Conduit|^Ask Toolbar|^Babylon|^MyWay|Mindspark|^Yahoo (Toolbar|Powered)'; Kind = 'junk'; Note = 'Toolbar or search hijacker bundled with free downloads' }
    @{ Match = '^McAfee WebAdvisor'; Kind = 'junk'; Note = 'Browser add-on bundled with other downloads' }
    @{ Match = '^Reimage|^Restoro|^Fortect'; Kind = 'junk'; Note = 'PC repair app that reports problems to sell a license' }
    @{ Match = '^PC Accelerate|^PC Optimizer Pro|^Advanced PC Cleaner|^Smart PC Fixer|^Speedy PC|^PC Cleaner Pro|^Advanced System Repair|^PC Speed Maximizer'; Kind = 'junk'; Note = 'Fake optimizer that reports problems to sell a license' }
    @{ Match = '^Driver ?Support|^PC HelpSoft|^Outbyte|^DriverUpdate|^Slimware|^SlimCleaner|^Advanced Driver Updater|^Smart Driver Manager|^Driver Whiz|^WinZip Driver Updater'; Kind = 'junk'; Note = 'Driver updater that sells a license; the Drivers tab does this for free' }
    @{ Match = '^WinZip System Utilities|^WinZip Registry Optimizer|^Systweak|^Advanced System Optimizer|^RegCure|^Registry Reviver|^Registry Mechanic'; Kind = 'junk'; Note = 'Registry cleaner that reports problems to sell a license' }
    @{ Match = '^Hola (VPN|Better Internet)'; Kind = 'junk'; Note = 'Free VPN that lets other people use your connection' }
    @{ Match = '^Coupon Printer|^SaveSense|^Shopping Helper'; Kind = 'junk'; Note = 'Shopping add-on that shows ads' }
    @{ Match = '^Advanced SystemCare|^IObit|^Driver Booster'; Kind = 'keep'; Note = 'Optimizer suite that bundles other apps; keep it if you chose it' }
    @{ Match = '^Driver Easy'; Kind = 'keep'; Note = 'Driver updater that sells a license; keep it if you chose it' }
    @{ Match = '^CCleaner'; Kind = 'keep'; Note = 'Cleaner known for bundling other apps; keep it if you chose it' }
    @{ Match = '^(Avast|AVG) Secure Browser|^CCleaner Browser'; Kind = 'keep'; Note = 'Browser often installed along with other software; keep it if you use it' }
)

$SecCategories = @{ 1 = 'Adware'; 2 = 'Spyware'; 3 = 'Password stealer'; 4 = 'Trojan downloader'; 5 = 'Worm'; 6 = 'Backdoor'; 7 = 'Remote access trojan'
    8 = 'Trojan'; 10 = 'Keylogger'; 12 = 'Monitoring software'; 13 = 'Browser modifier'; 18 = 'Security disabler'; 21 = 'Software bundler'
    23 = 'Settings modifier'; 24 = 'Toolbar'; 25 = 'Remote control software'; 27 = 'Potentially unwanted app'; 30 = 'Exploit'; 32 = 'Hacking tool'
    34 = 'Tool'; 37 = 'Trojan dropper'; 42 = 'Virus'; 46 = 'Suspicious behavior'; 49 = 'Unwanted software'; 50 = 'Ransomware' }
$SecSeverities = @{ 1 = 'Low'; 2 = 'Moderate'; 4 = 'High'; 5 = 'Severe' }
# Defender's ThreatStatusID; the ones that leave the threat in place count as active
$SecStatuses = @{ 0 = 'Found'; 1 = 'Active'; 2 = 'Cleaned'; 3 = 'Quarantined'; 4 = 'Removed'; 5 = 'Allowed'; 6 = 'Blocked'
    102 = 'Quarantine failed'; 103 = 'Removal failed'; 104 = 'Allowing failed'; 105 = 'Abandoned'; 107 = 'Blocking failed' }

function Test-DefenderInCharge {
    $st = if ($script:SecInfo) { $script:SecInfo.Status } else { $null }
    return [bool]($st -and $st.On -and $st.Mode -eq 'Normal')
}
function Get-OtherAntivirus {
    if (-not $script:SecInfo) { return '' }
    return (@($script:SecInfo.Av | Where-Object { $_.On -and $_.Name -notmatch 'Defender' } | ForEach-Object { $_.Name }) | Select-Object -First 1)
}

function Start-SecRead {
    if ($script:SecReader) { return }
    $script:SecState = 'running'
    $script:SecReader = Start-Tracked 'security' @{} {
        $script:SecReader = $null
        if ($script:SecState -eq 'running') { $script:SecState = 'error'; $script:SecError = "Reading Microsoft Defender's findings stopped unexpectedly." }
    }
    if (-not $script:InstalledKnown -and -not $script:Lister) { Start-InstalledScan -Quiet }
    Update-View
}

# A detection's place: a file (file:_ and containerfile:_), a registry key, a process or a download
function Format-SecResource([string]$R) {
    if ($R -match '^(file|containerfile):_(.+)$') { return ($Matches[2] -replace '->.*$', '') }
    if ($R -match '^regkey(value)?:_(.+)$') { return "Registry: $($Matches[2])" }
    if ($R -match '^process:_(.+)$') { return "Process: $($Matches[1])" }
    if ($R -match '^webfile:_(.+)$') { return "Download: $(($Matches[1] -split '\|')[0])" }
    return $R
}

$EventHandlers.security = {
    param($Ev)
    $script:SecInfo = $Ev
    $script:SecError = $Ev.Error
    $script:SecState = if ($Ev.Error -and -not $Ev.Status) { 'error' } else { 'ready' }
    foreach ($s in @($SecItems | Where-Object { -not $_.IsApp })) { [void]$SecItems.Remove($s) }
    foreach ($t in @($Ev.Threats)) {
        $x = New-Object WingetUM.ThreatItem
        $x.Kind = 'threat'; $x.Name = $t.Name; $x.ThreatId = [long]$t.Id
        $x.Category = if ($SecCategories.ContainsKey([int]$t.Category)) { $SecCategories[[int]$t.Category] } elseif ($t.Name -match '^PUA') { 'Potentially unwanted app' } elseif ($t.Name -match '^([A-Za-z]+):') { $Matches[1] } else { 'Threat' }
        $x.Severity = if ($SecSeverities.ContainsKey([int]$t.Severity)) { $SecSeverities[[int]$t.Severity] } else { 'Unknown' }
        $x.SeverityLevel = [int]$t.Severity
        $places = @(@($t.Resources) | ForEach-Object { Format-SecResource $_ })
        $x.Location = if (-not $places.Count) { 'No location recorded' } elseif ($places.Count -eq 1) { $places[0] } else { "$($places[0]) and $($places.Count - 1) more" }
        $x.LocationTip = $places -join "`n"
        $x.Files = [string[]]@(@($t.Resources) | Where-Object { $_ -match '^(file|containerfile):_' } | ForEach-Object { Format-SecResource $_ })
        if ($t.Time) { $x.Time = [datetime]$t.Time; $x.Found = $x.Time.ToString('MMM d, yyyy') } else { $x.Time = [datetime]::MinValue; $x.Found = '' }
        $x.IsActive = [bool]$t.Active -or [int]$t.Status -in 1, 102, 103, 105, 107
        $x.Status = if ($x.IsActive -and [int]$t.Status -in 0, 1) { 'Active' } elseif ($SecStatuses.ContainsKey([int]$t.Status)) { $SecStatuses[[int]$t.Status] } else { 'Found' }
        $x.Selected = $x.IsActive
        $SecItems.Add($x)
    }
    Update-SecApps -Force
    Update-View
}

# The unwanted apps among the installed ones, again whenever the installed list has been read again
function Update-SecApps([switch]$Force) {
    if (-not $script:InstalledKnown) { return }
    if (-not $Force -and $script:SecAppsRead -eq $script:InstalledChecked) { return }
    $script:SecAppsRead = $script:InstalledChecked
    $old = @{}; foreach ($s in @($SecItems | Where-Object { $_.IsApp })) { $old[$s.Package.Key] = $s; [void]$SecItems.Remove($s) }
    foreach ($p in @($InstalledItems)) {
        if (-not $p.CanUpdate -or $p.Name -match 'Microsoft') { continue }
        $hit = @($UnwantedApps | Where-Object { $p.Name -match $_.Match -or $p.Id -match $_.Match }) | Select-Object -First 1
        if (-not $hit) { continue }
        $x = New-Object WingetUM.ThreatItem
        $x.Kind = 'app'; $x.Name = $p.Name; $x.Package = $p; $x.Category = $hit.Note; $x.Location = $p.Id; $x.LocationTip = $p.Id
        $x.Severity = 'Unwanted'; $x.Found = 'Installed'; $x.Time = [datetime]::MinValue; $x.Files = [string[]]@()
        $x.IsActive = $true; $x.Status = 'Installed'
        $prev = $old[$p.Key]
        $x.Selected = if ($prev) { $prev.Selected } else { $hit.Kind -eq 'junk' }
        # an uninstall on its way keeps showing; once the list is read again with the app still there, it didn't work
        if ($prev -and $prev.State -eq 'running') {
            if ([object]::ReferenceEquals($prev.Package, $p)) { $x.State = $prev.State; $x.Detail = $prev.Detail }
            else { $x.State = 'error'; $x.Detail = "Still installed (Uninstall Software has why)" }
        }
        $SecItems.Add($x)
    }
}

# ---- Scans (as administrator: Defender's scans need it), with the definitions updated first
function Start-DefenderScan([string]$Kind) {
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first."; Update-View; return }
    if (-not (Test-DefenderInCharge)) { return }
    $type = if ($Kind -eq 'full') { 'FullScan' } else { 'QuickScan' }
    $body = @"
Say 'Updating virus definitions first$Ellipsis'
try { Update-MpSignature -ErrorAction Stop; Say 'Definitions updated.' } catch { Say ('Definitions not updated: ' + `$_.Exception.Message) }
`$t0 = Get-Date
Say 'Scanning$Ellipsis'
Start-MpScan -ScanType $type -ErrorAction Stop
`$found = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { `$_.InitialDetectionTime -ge `$t0 }).Count
Say ('RESULT|secscan|' + `$found)
exit 0
"@
    $script:SecScan = @{ Kind = $Kind; Started = Get-Date }
    Start-Elevated 'secscan' "Running a $Kind virus scan" $body @() @{ Kind = $Kind } -StallMinutes $(if ($Kind -eq 'full') { 600 } else { 90 })
    Update-View
}
$ElevHandlers.secscan = {
    param($Ev, $why, $code, $last, $tag)
    $script:SecScan = $null
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8) } else { @() }
    $res = @($lines | Where-Object { $_ -like 'RESULT|secscan|*' }) | Select-Object -Last 1
    $what = "$((Get-Culture).TextInfo.ToTitleCase($tag.Kind)) scan"
    if ($res) {
        $found = [int]($res.Split('|')[2])
        $text = if ($found) { "Found $found threat$(if ($found -ne 1) { 's' })" } else { 'Nothing found' }
        Add-History 'secscan' $what '' '' '' $(if ($found) { 'error' } else { 'ok' }) $text
        $script:LastSummary = "$what`: $text"
    }
    else {
        $text = if ($why) { $why } else { "Didn't finish$(if ($last) { ": $last" })" }
        Add-History 'secscan' $what '' '' '' 'error' $text
        $script:LastSummary = "$what`: $text"
    }
    Start-SecRead
    if ($script:HealthInfo) { Start-HealthScan }
}

# ---- Removing: threats by Defender (as administrator, after a restore point with Restore point first on), then
# unwanted apps through the uninstall queue
function Remove-SecItems($Items) {
    $threats = @($Items | Where-Object { -not $_.IsApp -and $_.CanRemove })
    $apps = @($Items | Where-Object { $_.IsApp -and $_.CanRemove })
    if (-not ($threats.Count + $apps.Count)) { return }
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first."; Update-View; return }
    if ($threats.Count -and -not (Test-DefenderInCharge)) {
        foreach ($t in $threats) { $t.State = 'error'; $t.Detail = "Microsoft Defender isn't in charge; remove it in $(if (Get-OtherAntivirus) { Get-OtherAntivirus } else { 'your antivirus' })" }
        $threats = @()
    }
    foreach ($a in $apps) { $a.State = 'running'; $a.Detail = 'Waiting to uninstall' + $Ellipsis }
    if (-not $threats.Count -and -not $Settings.DriverRestorePoint) { Complete-SecApps $apps; return }
    $body = ''
    if ($threats.Count) {
        $allActive = @($SecItems | Where-Object { -not $_.IsApp -and $_.IsActive })
        if ($threats.Count -ge $allActive.Count) {
            # every active threat: Defender's own removal
            $body += "Say 'Removing every active threat$Ellipsis'`r`nRemove-MpThreat -ErrorAction Stop`r`nStart-Sleep -Seconds 3`r`n"
        }
        else {
            # some of them: a scan of the files each was found in, so Defender acts on just those
            foreach ($t in $threats) {
                foreach ($f in @($t.Files)) {
                    $q = "'" + ($f -replace "'", "''") + "'"
                    $body += "if (Test-Path -LiteralPath $q) { Say ('Scanning ' + $q); Start-MpScan -ScanType CustomScan -ScanPath $q -ErrorAction SilentlyContinue }`r`n"
                }
            }
            $body += "Start-Sleep -Seconds 3`r`n"
        }
        $ids = (@($threats | ForEach-Object { [string]$_.ThreatId }) | Select-Object -Unique) -join ','
        $body += "`$left = @(Get-MpThreat -ErrorAction SilentlyContinue | Where-Object { `$_.IsActive } | ForEach-Object { [string]`$_.ThreatID })`r`n"
        $body += "foreach (`$id in '$ids'.Split(',')) { if (`$left -contains `$id) { Say ('RESULT|secrm|' + `$id + '|error') } else { Say ('RESULT|secrm|' + `$id + '|ok') } }`r`n"
        foreach ($t in $threats) { $t.State = 'running'; $t.Detail = 'Removing' + $Ellipsis }
    }
    else { $body = "Say 'Restore point step finished.'`r`n" }
    $body += 'exit 0'
    $title = if ($threats.Count) { "Removing $($threats.Count) threat$(if ($threats.Count -ne 1) { 's' })" } else { 'Creating a restore point' }
    Start-Elevated 'secremove' $title $body @() @{ Threats = $threats; Apps = $apps } -RestorePoint -RestoreText 'Before removing threats and unwanted apps'
    Update-View
}
$ElevHandlers.secremove = {
    param($Ev, $why, $code, $last, $tag)
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8) } else { @() }
    $results = @{}
    foreach ($l in @($lines | Where-Object { $_ -like 'RESULT|secrm|*' })) { $p = $l.Split('|'); $results[$p[2]] = $p[3] }
    $ok = 0
    foreach ($t in @($tag.Threats)) {
        $r = $results[[string]$t.ThreatId]
        if ($r -eq 'ok') { $t.State = 'ok'; $t.Detail = 'Removed'; $t.Selected = $false; $ok++ }
        else { $t.State = 'error'; $t.Detail = if ($why) { $why } elseif ($r) { "Still active: Windows Security can remove it, or a restart may finish it" } else { "Didn't finish$(if ($last) { ": $last" })" } }
    }
    if (@($tag.Threats).Count) {
        $n = @($tag.Threats).Count
        Add-History 'secremove' (@($tag.Threats | ForEach-Object { $_.Name }) -join ', ') '' '' '' $(if ($ok -eq $n) { 'ok' } else { 'error' }) "$ok of $n removed"
        $script:LastSummary = "Removed $ok of $n threat$(if ($n -ne 1) { 's' })"
    }
    # approval declined: nothing else happens; otherwise the apps go on to the queue
    if ($Ev.Declined) { foreach ($a in @($tag.Apps)) { $a.State = ''; $a.Detail = '' } }
    else { Complete-SecApps @($tag.Apps) }
    Start-SecRead
}
function Complete-SecApps($Apps) {
    $pk = @($Apps | ForEach-Object { $_.Package } | Where-Object { $_ -and $_.CanUpdate })
    if (-not $pk.Count) { return }
    foreach ($a in $Apps) { $a.State = 'running'; $a.Detail = 'Uninstalling (see Uninstall Software)' }
    Add-LogLine "Removing unwanted apps: $(($pk | ForEach-Object { $_.Name }) -join ', ')"
    Add-Job $pk
}

# ---- Blocking potentially unwanted apps (Defender's PUAProtection: 0 off, 1 on, 2 audit only)
function Set-PuaBlocking([bool]$On) {
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first."; Update-View; return }
    $body = @"
Set-MpPreference -PUAProtection $(if ($On) { 'Enabled' } else { 'Disabled' }) -ErrorAction Stop
Say ('RESULT|pua|' + [int](Get-MpPreference).PUAProtection)
exit 0
"@
    Start-Elevated 'secpua' "$(if ($On) { 'Turning on' } else { 'Turning off' }) blocking of unwanted apps" $body @() @{ On = $On }
    Update-View
}
$ElevHandlers.secpua = {
    param($Ev, $why, $code, $last, $tag)
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8) } else { @() }
    $res = @($lines | Where-Object { $_ -like 'RESULT|pua|*' }) | Select-Object -Last 1
    if ($res -and (([int]$res.Split('|')[2] -eq 1) -eq $tag.On)) {
        Add-History $(if ($tag.On) { 'puaon' } else { 'puaoff' }) 'Microsoft Defender' '' '' '' 'ok' $(if ($tag.On) { 'Unwanted apps are blocked as they download or install' } else { 'Unwanted apps are no longer blocked' })
        $script:LastSummary = if ($tag.On) { 'Unwanted apps are blocked now' } else { 'Unwanted apps are no longer blocked' }
    }
    else { $script:LastSummary = "Blocking of unwanted apps didn't change: $(if ($why) { $why } elseif ($last) { $last } else { 'your organization may set it' })" }
    Start-SecRead
}

function Update-SecView {
    Update-SecApps
    $st = if ($script:SecInfo) { $script:SecInfo.Status } else { $null }
    $inCharge = Test-DefenderInCharge
    $other = Get-OtherAntivirus
    $threats = @($SecItems | Where-Object { -not $_.IsApp -and $_.IsActive -and $_.State -ne 'ok' })
    $apps = @($SecItems | Where-Object { $_.IsApp -and $_.State -ne 'ok' })
    $scanning = $script:SecScan -and $script:Elev -and $script:ElevName -eq 'secscan'
    $UI.SecTitle.Text = if ($scanning) { "Running a $($script:SecScan.Kind) scan$Ellipsis" }
    elseif (-not $script:SecInfo) { if ($script:SecState -eq 'error') { "Couldn't read Microsoft Defender" } else { "Reading Microsoft Defender$Ellipsis" } }
    elseif ($threats.Count) { "$($threats.Count) active threat$(if ($threats.Count -ne 1) { 's' }) found" }
    elseif (-not $inCharge) { if ($other) { "$other is protecting this PC" } else { "Microsoft Defender isn't protecting this PC" } }
    elseif ($apps.Count) { "No threats; $($apps.Count) unwanted app$(if ($apps.Count -ne 1) { 's' }) installed" }
    else { 'No threats found' }
    $days = { param($d) if ($d -gt 30000) { 'never' } elseif ($d -le 0) { 'today' } elseif ($d -eq 1) { 'yesterday' } else { "$d days ago" } }
    $UI.SecText.Text = if ($scanning) { "Started at {0:t}. You can keep using the app; the list updates when it's done.$(if ($script:ElevLast) { " $($script:ElevLast)" })" -f $script:SecScan.Started }
    elseif ($st -and $inCharge) { "Real-time protection is $(if ($st.Realtime) { 'on' } else { 'OFF' }). Last quick scan $(& $days $st.QuickAge), last full scan $(& $days $st.FullAge); virus definitions updated $(& $days $st.SigAge). Scanning and removing ask for administrator approval." }
    elseif ($script:SecInfo -and $other) { "Microsoft Defender stands by while $other is in charge, so scans and removing threats happen in $other. Unwanted apps below can still be uninstalled here." }
    elseif ($script:SecInfo) { 'Windows Security can turn Microsoft Defender back on. Unwanted apps below can still be uninstalled here.' }
    elseif ($script:SecState -eq 'error') { $script:SecError } else { '' }
    $UI.SecScanBar.Visibility = ConvertTo-Visibility $scanning
    $UI.SecIcon.Background = if ($threats.Count -or ($script:SecInfo -and -not $inCharge -and -not $other)) { '#5A2626' } elseif ($apps.Count) { '#4A3A1A' } else { '#17414C' }
    $free = -not $script:Elev
    $UI.SecQuick.IsEnabled = $inCharge -and $free
    $UI.SecFull.IsEnabled = $inCharge -and $free
    $UI.SecRefresh.IsEnabled = -not $script:SecReader
    $pua = if ($script:SecInfo) { $script:SecInfo.Pua } else { $null }
    $UI.SecPua.IsChecked = $pua -eq 1
    $UI.SecPua.IsEnabled = $inCharge -and $free -and $null -ne $pua
    $UI.SecPua.Content = if ($pua -eq 2) { 'Block unwanted apps (audit only)' } else { 'Block unwanted apps' }
    $ticked = @($SecItems | Where-Object { $_.Selected -and $_.CanRemove })
    $UI.SecRemoveText.Text = if ($ticked.Count) { "Remove ticked ($($ticked.Count))" } else { 'Remove ticked' }
    $UI.SecRemove.IsEnabled = $ticked.Count -gt 0 -and $free
    $can = @($SecItems | Where-Object { $_.CanRemove })
    $UI.SecCheckAll.IsEnabled = $can.Count -gt 0
    $sel = @($can | Where-Object { $_.Selected }).Count
    $UI.SecCheckAll.IsChecked = if (-not $can.Count -or -not $sel) { $false } elseif ($sel -eq $can.Count) { $true } else { $null }
    $UI.SecBadge.Visibility = ConvertTo-Visibility ($threats.Count -gt 0)
    $UI.SecBadgeText.Text = [string]$threats.Count
    $msg = $null
    if ($script:SecState -eq 'running' -and -not $SecItems.Count) { $msg = @{ Bar = $true; Title = "Reading Microsoft Defender's findings"; Text = '' } }
    elseif ($script:SecState -eq 'error' -and -not $SecItems.Count) { $msg = @{ Title = "Couldn't read what Microsoft Defender found"; Text = $script:SecError; Action = 'Try again' } }
    elseif (-not @($SecView).Count) { $msg = @{ Title = 'Nothing to remove'; Text = "No active threats, and none of the installed apps are on the list of unwanted ones (browser hijackers, adware, fake optimizers and driver updaters).$(if (-not $UI.SecHistory.IsChecked -and $SecItems.Count) { ' Show history lists what Defender already dealt with.' })" } }
    $UI.SecHeader.Visibility = ConvertTo-Visibility (-not $msg)
    $UI.SecList.Visibility = if ($msg) { 'Collapsed' } else { 'Visible' }
    $UI.SecMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) {
        $UI.SecMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar)
        $UI.SecMsgTitle.Text = $msg.Title; $UI.SecMsgText.Text = $msg.Text
        $UI.SecMsgAction.Visibility = ConvertTo-Visibility ([bool]$msg.Action)
        if ($msg.Action) { $UI.SecMsgAction.Content = $msg.Action }
    }
}

$Panels.security = @{
    Panel   = 'SecurityPanel'
    Update  = { Update-SecView }
    Status  = {
        if ($script:SecScan) { "$((Get-Culture).TextInfo.ToTitleCase($script:SecScan.Kind)) scan running" }
        elseif ($script:SecReader) { "Reading Microsoft Defender$Ellipsis" }
        elseif ($script:SecState -eq 'ready') {
            $t = @($SecItems | Where-Object { -not $_.IsApp -and $_.IsActive -and $_.State -ne 'ok' }).Count
            $a = @($SecItems | Where-Object { $_.IsApp -and $_.State -ne 'ok' }).Count
            if ($t) { "$t active threat$(if ($t -ne 1) { 's' })" } else { 'no active threats' }
            if ($a) { "$a unwanted app$(if ($a -ne 1) { 's' })" }
        }
    }
    Open    = { if ($script:SecState -eq 'none') { Start-SecRead } }
    Refresh = { Start-SecRead }
}

$UI.TabSecurity.Add_Checked({ Set-Section 'security' })
$UI.SecRefresh.Add_Click({ Start-SecRead })
$UI.SecMsgAction.Add_Click({ Start-SecRead })
$UI.SecQuick.Add_Click({ Start-DefenderScan 'quick' })
$UI.SecFull.Add_Click({ Start-DefenderScan 'full' })
$UI.SecWinSec.Add_Click({ try { Start-Process 'windowsdefender://threat' } catch { try { Start-Process 'windowsdefender:' } catch { } } })
$UI.SecHistory.Add_Click({ $SecView.Refresh(); Update-View })
$UI.SecPua.Add_Click({ $want = $UI.SecPua.IsChecked -eq $true; $UI.SecPua.IsChecked = -not $want; Set-PuaBlocking $want })
$UI.SecCheckAll.Add_Click({
        $on = $UI.SecCheckAll.IsChecked -eq $true
        foreach ($s in $SecView) { if ($s.CanRemove) { $s.Selected = $on } }
        Update-View
    })
$UI.SecRemove.Add_Click({
        $items = @($SecItems | Where-Object { $_.Selected -and $_.CanRemove })
        if (-not $items.Count) { return }
        $names = @($items | Select-Object -First 8 | ForEach-Object { "  $($_.Name)" })
        if ($items.Count -gt 8) { $names += "  and $($items.Count - 8) more" }
        $t = @($items | Where-Object { -not $_.IsApp }).Count; $a = $items.Count - $t
        $how = @()
        if ($t) { $how += "Microsoft Defender removes the threat$(if ($t -ne 1) { 's' }) (one administrator approval$(if ($Settings.DriverRestorePoint) { ', after a restore point' }))." }
        if ($a) { $how += "The app$(if ($a -ne 1) { 's are' } else { ' is' }) uninstalled one at a time, like on Uninstall Software." }
        Show-Confirm 'secremove' @{ Items = $items } "Remove $($items.Count) item$(if ($items.Count -ne 1) { 's' })?" "$($how -join ' ')`n`n$($names -join "`n")" 'Remove' -Danger
    })
$ConfirmHandlers.secremove = { param($Payload) Remove-SecItems $Payload.Items }
$UI.SecList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'secremove') {
            $it = $src.DataContext
            Show-Confirm 'secremove' @{ Items = @($it) } "Remove $($it.Name)?" $(if ($it.IsApp) { "It's uninstalled like on Uninstall Software. $($it.Category)." } else { "Microsoft Defender removes it (one administrator approval$(if ($Settings.DriverRestorePoint) { ', after a restore point' })).`n`n$($it.LocationTip)" }) 'Remove' -Danger
        }
        else { Update-View }
    })
[System.Windows.EventManager]::RegisterClassHandler([System.Windows.Controls.MenuItem], [System.Windows.Controls.MenuItem]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $it = $s.DataContext
        if ($it -isnot [WingetUM.ThreatItem]) { return }
        switch ($s.Tag) {
            'secopen' {
                $f = @($it.Files) | Select-Object -First 1
                if ($f -and (Test-Path -LiteralPath $f)) { Start-Process explorer.exe -ArgumentList "/select,`"$f`"" }
                elseif ($f -and (Test-Path -LiteralPath (Split-Path -Parent $f))) { Start-Process explorer.exe -ArgumentList "`"$(Split-Path -Parent $f)`"" }
                else { $script:LastSummary = 'The file is gone (quarantined or removed).'; Update-View }
            }
            'seccopy' { [System.Windows.Clipboard]::SetText([string]$it.Name) }
            'secweb' { Start-Process "https://www.microsoft.com/en-us/wdsi/threats/threat-search?query=$([uri]::EscapeDataString($it.Name))" }
        }
    })

# Windows Manager - Health (part of src\; see Windows_Manager.ps1)

# The Health tab: this PC and Windows (and a restart that is waiting), its BIOS and whether the last driver check
# found a newer one, the battery's wear, each drive's space and health, and Clean up, which measures and deletes
# what apps, installers and Windows leave behind.
$script:HealthState = 'none'      # none | running | ready | error
$script:HealthInfo = $null
$script:HealthReader = $null
$script:HealthRead = $null

function Start-HealthScan {
    if ($script:HealthReader) { return }
    $script:HealthState = 'running'
    $script:HealthReader = Start-Tracked 'health' @{} {
        $script:HealthReader = $null
        if ($script:HealthState -eq 'running') { $script:HealthState = 'error' }
    }
    Update-View
}
$EventHandlers.health = {
    param($Ev)
    $script:HealthInfo = $Ev
    $script:HealthRead = Get-Date
    $script:HealthState = if ($Ev.Error -and -not $Ev.Sys) { 'error' } else { 'ready' }
    if (-not $SelfTest -or $env:WSM_T2) { try { Add-HealthSnapshot $Ev } catch { } }
    Update-HealthTrends
    Update-View
}

# Format-Size is in 29-AutoJobs.ps1 (automatic runs use it too)
function Format-Span([TimeSpan]$T) {
    if ($T.TotalDays -ge 2) { return "$([int][Math]::Floor($T.TotalDays)) days" }
    if ($T.TotalHours -ge 2) { return "$([int][Math]::Floor($T.TotalHours)) hours" }
    return "$([int][Math]::Max(1, $T.TotalMinutes)) minutes"
}

# A BIOS or firmware update the last driver check found, if any
function Get-BiosUpdate {
    return @($DrvUpdates | Where-Object { $_.Kind -eq 'bios' -or $_.Type -eq 'BIOS' -or ($_.IsWu -and $_.Type -eq 'Firmware' -and $_.Name -match 'BIOS|System Firmware|UEFI') }) | Select-Object -First 1
}

function Update-HealthView {
    $h = $script:HealthInfo
    $UI.HlBusy.Visibility = ConvertTo-Visibility ([bool]$script:HealthReader -or [bool]$script:CleanReader -or [bool]$script:Cleaner)
    $UI.HlRefresh.IsEnabled = -not $script:HealthReader -and -not $script:CleanReader -and -not $script:Cleaner
    if (-not $h -or -not $h.Sys) {
        $UI.HlSummary.Text = if ($script:HealthState -eq 'error') { "Couldn't read this PC's details$(if ($h.Error) { ": $($h.Error)" })." } else { "Reading this PC's health$Ellipsis" }
        foreach ($t in 'HlSysTitle', 'HlBiosTitle', 'HlBatTitle') { $UI[$t].Text = $Ellipsis }
        foreach ($t in 'HlSysText', 'HlBiosText', 'HlBatText') { $UI[$t].Text = '' }
        $UI.HlSysNote.Visibility = 'Collapsed'; $UI.HlBatBar.Visibility = 'Collapsed'; $UI.HlBatReport.Visibility = 'Collapsed'
        Update-CleanView
        return
    }
    $s = $h.Sys
    $notes = @("Read at {0:t}" -f $script:HealthRead)
    # This PC
    $maker = ($s.Maker -replace '(?i),?\s+(inc\.?|corporation|corp\.?|co\.,? ltd\.?|ltd\.?|gmbh)$', '').Trim()
    $UI.HlSysTitle.Text = if (-not $maker -or $s.Model -like "$maker*") { $s.Model } else { "$maker $($s.Model)".Trim() }
    $up = (Get-Date) - $s.Boot
    $UI.HlSysText.Text = @("$($s.Os) $($s.Display) (build $($s.Build))", $s.Cpu, "$($s.MemoryGB) GB memory", ("Running for {0}, since {1:MMM d, h:mm tt}" -f (Format-Span $up), $s.Boot), ("Windows installed {0:MMM d, yyyy}" -f $s.Installed)) -join "`n"
    $sysNote = if ($h.Reboot) { 'A restart is waiting to finish installing updates.' } elseif ($up.TotalDays -ge 14) { "It hasn't restarted for $(Format-Span $up). Restarting now and then finishes updates and keeps Windows quick." } else { '' }
    $UI.HlSysNote.Text = $sysNote; $UI.HlSysNote.Visibility = ConvertTo-Visibility ([bool]$sysNote)
    # BIOS
    $UI.HlBiosTitle.Text = "BIOS $($s.Bios)"
    $age = ''
    try { if ($s.BiosDate) { $months = [int](((Get-Date) - [datetime]$s.BiosDate).TotalDays / 30.4); $age = if ($months -ge 24) { " ($([int]($months / 12)) years ago)" } elseif ($months -ge 2) { " ($months months ago)" } else { '' } } } catch { }
    $bu = Get-BiosUpdate
    $checked = $script:WuState -eq 'ready' -or $script:DrvScan -in 'ready', 'uptodate'
    $UI.HlBiosText.Text = "From $($s.BiosMaker)$(if ($s.BiosDate) { ", released $($s.BiosDate)$age" }).`n" +
    $(if ($bu) { "An update is waiting on the Drivers tab: $($bu.Name) $($bu.Version)." } elseif ($checked) { 'The last driver check found no newer BIOS or firmware.' } else { 'Check for updates looks for a newer BIOS and firmware through Windows Update and the vendor''s tool.' })
    $UI.HlBiosCheck.Content = if ($bu) { 'Open Driver Updates' } else { 'Check for updates' }
    # Battery: a PC without one (a desktop) has no Battery card, and This PC and BIOS share the top row
    $b = $h.Battery
    $UI.HlBatCard.Visibility = ConvertTo-Visibility ([bool]$b)
    $span = if ($b) { 2 } else { 3 }
    [System.Windows.Controls.Grid]::SetColumnSpan($UI.HlSysCard, $span)
    [System.Windows.Controls.Grid]::SetColumn($UI.HlBiosCard, $span)
    [System.Windows.Controls.Grid]::SetColumnSpan($UI.HlBiosCard, $span)
    if (-not $b) {
        $UI.HlBatTitle.Text = 'No battery'; $UI.HlBatText.Text = 'This PC runs on mains power.'
        $UI.HlBatBar.Visibility = 'Collapsed'; $UI.HlBatReport.Visibility = 'Collapsed'
    }
    else {
        $status = @{ 1 = 'on battery'; 2 = 'plugged in'; 3 = 'fully charged'; 4 = 'low'; 5 = 'critically low'; 6 = 'charging'; 7 = 'charging'; 8 = 'charging'; 9 = 'charging'; 11 = 'partly charged' }[[int]$b.Status]
        $charge = "Charged to $($b.Charge)%$(if ($status) { ", $status" })."
        if ($b.Design -gt 0 -and $b.Full -gt 0) {
            $pct = [Math]::Min(100, [Math]::Round(100.0 * $b.Full / $b.Design))
            $UI.HlBatTitle.Text = "Health $pct%"
            $UI.HlBatBar.Value = $pct; $UI.HlBatBar.Visibility = 'Visible'
            $UI.HlBatBar.Foreground = if ($pct -lt 60) { $Window.FindResource('Bad') } elseif ($pct -lt 80) { $Window.FindResource('Warn') } else { $Window.FindResource('BarGradient') }
            $UI.HlBatText.Text = ("Holds {0:N0} mWh of the {1:N0} mWh it held new{2}.`n{3}" -f $b.Full, $b.Design, $(if ($b.Cycles) { ", after $($b.Cycles) charge cycles" } else { '' }), $charge) +
            $(if ($pct -lt 60) { "`nIt has worn a lot: a new battery would last much longer." } elseif ($pct -lt 80) { "`nIt has worn noticeably, which is normal after a few years." } else { '' })
        }
        else { $UI.HlBatTitle.Text = "Charged to $($b.Charge)%"; $UI.HlBatBar.Visibility = 'Collapsed'; $UI.HlBatText.Text = "Windows doesn't report this battery's capacity.`n$charge" }
        $UI.HlBatReport.Visibility = 'Visible'
    }
    # Drives
    $vols = foreach ($v in @($h.Volumes)) {
        $x = New-Object WingetUM.HealthVolume
        $x.Name = "$($v.Letter)  $($v.Label)".Trim()
        $x.UsedPct = if ($v.Size) { 100.0 * ($v.Size - $v.Free) / $v.Size } else { 0 }
        $freePct = 100 - $x.UsedPct
        $x.Detail = "$(Format-Size $v.Free) free of $(Format-Size $v.Size)"
        $x.Level = if ($freePct -lt 10) { 'bad' } elseif ($freePct -lt 20) { 'warn' } else { 'ok' }
        $x
    }
    $UI.HlVolumes.ItemsSource = @($vols)
    $anyRel = $false
    $disks = foreach ($d in @($h.Disks)) {
        $x = New-Object WingetUM.HealthDisk
        $x.Name = $d.Name
        $extra = @()
        if ($null -ne $d.Wear) { $anyRel = $true; $extra += "$($d.Wear)% worn" }
        if ($d.Temp) { $anyRel = $true; $extra += "$($d.Temp) $([char]0x00B0)C" }
        if ($d.Hours) { $extra += "$([int]$d.Hours) hours of use" }
        $x.Detail = (@($d.Media, $d.Bus, $(Format-Size $d.Size)) + $extra | Where-Object { $_ -and $_ -ne 'Unspecified' }) -join "  $Dot  "
        $x.Health = switch ($d.Health) { 'Healthy' { 'Healthy' } 'Warning' { "Warning: $($d.Status). Back up your files." } 'Unhealthy' { "Failing: $($d.Status). Back up your files now." } default { "Health unknown ($($d.Health))" } }
        $x.Level = switch ($d.Health) { 'Healthy' { 'ok' } 'Warning' { 'warn' } 'Unhealthy' { 'bad' } default { 'info' } }
        $x
    }
    $UI.HlDisks.ItemsSource = @($disks)
    $issues = Update-HealthCards $h
    $notes = @($(if ($issues) { "$issues thing$(if ($issues -ne 1) { 's' }) to look at (amber or red)" } else { 'Everything looks good' })) + $notes
    if (@($h.Disks).Count -and -not $anyRel -and -not $IsAdmin) { $notes += 'Drive wear and temperature show when the app runs as administrator' }
    $UI.HlSummary.Text = $notes -join "  $Dot  "
    Update-CleanView
}

# ---- Clean up ----------------------------------------------------------------------------------------------------
$CleanItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.CleanupItem]'
$UI.HlCleanList.ItemsSource = $CleanItems
$script:CleanReader = $null
$script:Cleaner = $null
$script:CleanMeasured = $null

# What Clean up offers (Get-CleanCatalog) and Get-DownloadsFolder are in 29-AutoJobs.ps1: automatic runs clean up too
$CleanCatalog = @{}

function Start-CleanScan {
    if ($script:CleanReader -or $script:Cleaner) { return }
    $keep = @{}; foreach ($c in $CleanItems) { $keep[$c.Key] = $c.Included }
    $CleanItems.Clear(); $CleanCatalog.Clear()
    foreach ($c in Get-CleanCatalog) {
        # a folder under one you can't read counts as there (Test-Path throws for it)
        if (-not $c.Always -and -not @($c.Paths | Where-Object { try { Test-Path -LiteralPath $_ } catch { $true } }).Count) { continue }
        $CleanCatalog[$c.Key] = $c
        $i = New-Object WingetUM.CleanupItem
        $i.Key = $c.Key; $i.Name = $c.Name; $i.About = $c.About; $i.NeedsAdmin = [bool]$c.Admin
        $i.Included = if ($keep.ContainsKey($c.Key)) { $keep[$c.Key] } else { [bool]$c.On }
        $CleanItems.Add($i)
    }
    $items = @($CleanCatalog.Values | Where-Object { -not $_.Special } | ForEach-Object { @{ Key = $_.Key; Paths = @($_.Paths); OlderDays = [int]$_.OlderDays; Skip = @($_.Skip); Recycle = [bool]$_.Recycle } })
    $script:CleanReader = Start-Tracked 'cleanscan' @{ Items = $items } { $script:CleanReader = $null; $script:CleanMeasured = Get-Date }
    Update-View
}
$EventHandlers.cleansize = {
    param($Ev)
    $i = @($CleanItems | Where-Object { $_.Key -eq $Ev.Key }) | Select-Object -First 1
    if ($i) { $i.Bytes = [long]$Ev.Bytes }
}
$EventHandlers.cleanscandone = { param($Ev) Update-View }

function Update-CleanView {
    $sel = @($CleanItems | Where-Object { $_.Included })
    $known = [long]0; foreach ($i in $sel) { if ($i.Bytes -gt 0) { $known += $i.Bytes } }
    $all = [long]0; foreach ($i in $CleanItems) { if ($i.Bytes -gt 0) { $all += $i.Bytes } }
    $unknown = @($CleanItems | Where-Object { $_.Bytes -lt 0 -and $_.NeedsAdmin }).Count
    $UI.HlCleanInfo.Text = if ($script:Cleaner) { "Cleaning up$Ellipsis" } elseif ($script:CleanReader) { "Measuring$Ellipsis" } elseif ($CleanItems.Count) { "About $(Format-Size $all) can be freed$(if ($unknown) { "; sizes marked ? need administrator rights to measure" }). Files in use are left alone." } else { '' }
    $UI.HlCleanText.Text = if ($sel.Count -and $known -gt 0) { "Clean up $(Format-Size $known)" } else { 'Clean up' }
    $UI.HlClean.IsEnabled = $sel.Count -gt 0 -and -not $script:Cleaner -and -not $script:CleanReader -and -not ($script:Elev -and @($sel | Where-Object { $_.NeedsAdmin }).Count)
}

function Request-Clean {
    $sel = @($CleanItems | Where-Object { $_.Included })
    if (-not $sel.Count) { return }
    $admin = @($sel | Where-Object { $_.NeedsAdmin })
    $known = [long]0; foreach ($i in $sel) { if ($i.Bytes -gt 0) { $known += $i.Bytes } }
    $list = ($sel | ForEach-Object { "  $([char]0x2022) $($_.Name)$(if ($_.Bytes -gt 0) { " ($(Format-Size $_.Bytes))" })" }) -join "`n"
    $text = "These are deleted:`n$list`n`nFiles that are in use are left alone.$(if ($admin.Count) { ' Windows asks for administrator approval once for the ones marked with a shield.' })$(if (@($sel | Where-Object { $_.Key -eq 'recycle' }).Count) { "`n`nEmptying the Recycle Bin can't be undone." })"
    Show-Confirm 'clean' $null "Clean up$(if ($known -gt 0) { " $(Format-Size $known)" })?" $text 'Clean up' -Danger
}
$ConfirmHandlers.clean = { param($Payload) Start-Clean }

function Start-Clean {
    $sel = @($CleanItems | Where-Object { $_.Included })
    $script:CleanFreed = [long]0; $script:CleanFailed = 0; $script:CleanDone = @()
    $mine = @($sel | Where-Object { -not $_.NeedsAdmin })
    $admin = @($sel | Where-Object { $_.NeedsAdmin })
    foreach ($i in $sel) { $i.State = 'running'; $i.Detail = if ($i.NeedsAdmin -and -not $IsAdmin) { 'Waiting for approval' + $Ellipsis } else { 'Cleaning' + $Ellipsis } }
    Add-LogLine ''
    Add-LogLine "---- Cleaning up ($($sel.Count) items) ----"
    if ($mine.Count) {
        $items = @($mine | ForEach-Object { $c = $CleanCatalog[$_.Key]; @{ Key = $c.Key; Paths = @($c.Paths); OlderDays = [int]$c.OlderDays; Skip = @($c.Skip); Recycle = [bool]$c.Recycle } })
        $script:Cleaner = Start-Tracked 'clean' @{ Items = $items } { $script:Cleaner = $null; Complete-CleanPart }
    }
    if ($admin.Count) {
        $q = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
        $body = $CleanFunctions + "`r`n"
        foreach ($i in $admin) {
            $c = $CleanCatalog[$i.Key]
            $paths = (@($c.Paths) | ForEach-Object { & $q $_ }) -join ', '
            $body += "Say 'Cleaning up: $($c.Name -replace "'", "''")$Ellipsis'`r`n`$freed = [long]0; `$failed = 0`r`n"
            switch ($c.Special) {
                'wu' { $body += "Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue`r`nforeach (`$p in @($paths)) { `$r = Remove-CleanPath `$p 0 @(); `$freed += `$r.Freed; `$failed += `$r.Failed }`r`nStart-Service -Name bits, wuauserv -ErrorAction SilentlyContinue`r`n" }
                'do' { $body += "try { `$before = [long](Get-DeliveryOptimizationStatus -ErrorAction SilentlyContinue | Measure-Object -Property FileSizeInCache -Sum).Sum; Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; `$freed = `$before } catch { `$failed++; Say ('Delivery Optimization: ' + `$_.Exception.Message) }`r`n" }
                default { $body += "foreach (`$p in @($paths)) { `$r = Remove-CleanPath `$p $([int]$c.OlderDays) @($((@($c.Skip) | ForEach-Object { & $q $_ }) -join ', ')); `$freed += `$r.Freed; `$failed += `$r.Failed }`r`n" }
            }
            $body += "Say ('RESULT|clean|$($c.Key)|' + `$freed + '|' + `$failed + '|$($c.Name -replace "'", "''")')`r`n"
        }
        $body += "exit 0"
        if ($script:Elev) { foreach ($i in $admin) { $i.State = 'error'; $i.Detail = "Wait for $($script:ElevTitle) to finish, then clean up again" } }
        else { Start-Elevated 'clean' "Cleaning up $($admin.Count) Windows item$(if ($admin.Count -ne 1) { 's' })" $body @() @{ Count = $admin.Count } }
    }
    Update-View
}

# One item's result, from the worker or the administrator run
function Set-CleanResult([string]$Key, [long]$Freed, [int]$Failed) {
    $i = @($CleanItems | Where-Object { $_.Key -eq $Key }) | Select-Object -First 1
    if (-not $i) { return }
    if ($Freed -gt 0) { $script:CleanFreed += $Freed }
    $script:CleanFailed += $Failed
    $script:CleanDone += $i.Name
    $i.State = 'ok'
    $i.Detail = "$(if ($Freed -gt 0) { "Freed $(Format-Size $Freed)" } elseif ($Freed -lt 0) { 'Cleaned' } else { 'Nothing to free' })$(if ($Failed) { "; $Failed in use or protected, left alone" })"
    $i.Bytes = if ($Freed -ge 0) { [Math]::Max([long]0, $i.Bytes - $Freed) } else { [long]-1 }
}
$EventHandlers.cleaned = { param($Ev) Set-CleanResult $Ev.Key ([long]$Ev.Freed) ([int]$Ev.Failed) }
$EventHandlers.cleandone = { param($Ev) Update-View }
$ElevHandlers.clean = {
    param($Ev, $why, $code, $last, $tag)
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8 | Where-Object { $_ -like 'RESULT|clean|*' }) } else { @() }
    foreach ($l in $lines) { $f = $l.Split('|', 6); Set-CleanResult $f[2] ([long]$f[3]) ([int]$f[4]) }
    foreach ($i in @($CleanItems | Where-Object { $_.NeedsAdmin -and $_.State -eq 'running' })) { $i.State = 'error'; $i.Detail = if ($why) { $why } else { "Didn't finish$(if ($last) { ": $last" })" } }
    Complete-CleanPart
}
# History and the status line once nothing is cleaning any more
function Complete-CleanPart {
    if ($script:Cleaner -or ($script:Elev -and $script:ElevName -eq 'clean')) { return }
    if (-not @($script:CleanDone).Count) { Update-View; return }
    $text = "Freed $(Format-Size $script:CleanFreed)$(if ($script:CleanFailed) { "; $($script:CleanFailed) file(s) in use were left alone" })"
    $what = (@($script:CleanDone) | Select-Object -First 4) -join ', '
    if (@($script:CleanDone).Count -gt 4) { $what += ", and $(@($script:CleanDone).Count - 4) more" }
    Add-History 'cleanup' $what '' '' '' 'ok' $text
    Add-LogLine "Clean up finished: $text."
    $script:LastSummary = "Clean up: $text"
    $script:CleanDone = @()
    Start-HealthScan
    Update-View
}

$Panels.health = @{
    Panel   = 'HealthPanel'
    Update  = { Update-HealthView }
    Status  = {
        if ($script:HealthReader) { "Reading this PC's health$Ellipsis" }
        elseif ($script:HealthInfo -and $script:HealthInfo.Sys) {
            $low = @($script:HealthInfo.Volumes | Where-Object { $_.Size -and $_.Free / $_.Size -lt 0.1 }).Count
            if ($low) { "$low drive$(if ($low -ne 1) { 's are' } else { ' is' }) nearly full" }
            $bad = @($script:HealthInfo.Disks | Where-Object { $_.Health -ne 'Healthy' }).Count
            if ($bad) { "$bad disk$(if ($bad -ne 1) { 's' }) not healthy" }
            if ($script:HealthInfo.Reboot) { 'restart waiting' }
            'read at {0:t}' -f $script:HealthRead
        }
    }
    # the landing page also starts the checks its cards show: Windows Update, startup apps, Cleanup's sizes
    Open    = {
        if ($script:HealthState -eq 'none') { Start-HealthScan }
        if (-not $script:CleanMeasured -and -not $script:CleanReader) { Start-CleanScan }
        if ($script:WinState -eq 'none') { Start-WinCheck }
        if ($script:StartupState -eq 'none') { Start-StartupScan }
    }
    Refresh = { if ($UI.HlRefresh.IsEnabled) { Start-HealthScan; Start-CleanScan } }
}

$UI.TabHealth.Add_Checked({ Set-Section 'health' })
$UI.HlRefresh.Add_Click({ Start-HealthScan; Start-CleanScan })
$UI.HlClean.Add_Click({ Request-Clean })
$UI.HlCleanList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] { Update-View })
$UI.HlDiskCleanup.Add_Click({ try { Start-Process cleanmgr.exe } catch { } })
$UI.HlStorage.Add_Click({ try { Start-Process 'ms-settings:storagesense' } catch { } })
$UI.HlBiosCheck.Add_Click({
        $UI.TabDrivers.IsChecked = $true
        $UI.DrvViewUpdates.IsChecked = $true
        if ($script:DrvDevicesRead -and -not (Get-BiosUpdate)) { Start-DriverCheck }
        Update-View
    })
$UI.HlBatReport.Add_Click({
        $f = Join-Path ([IO.Path]::GetTempPath()) 'battery-report.html'
        try {
            $null = & "$env:SystemRoot\System32\powercfg.exe" /batteryreport /output $f 2>&1
            if (Test-Path -LiteralPath $f) { Start-Process $f } else { $script:LastSummary = "Windows didn't write the battery report."; Update-View }
        }
        catch { $script:LastSummary = "Couldn't make the battery report: $($_.Exception.Message)"; Update-View }
    })

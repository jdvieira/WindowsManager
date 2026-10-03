# Windows Manager - FixMyPC (part of src\; see Windows_Manager.ps1)

# Fix my PC (Device Health's button): reads what the other tabs read (app and Windows updates, leftover files, Device
# Health's security and reliability, startup apps), suggests what would make the PC run better (ticked where it's safe,
# the rest left to the person, and what it can't do itself with a button to where it can be done), then does the
# ticked ones: everything that needs administrator rights in one approved run (a restore point first, with Restore
# point first on), then app updates, the rest of the cleanup and startup apps, the way their own tabs do them.
# Nothing here restarts the PC, turns off services or changes settings for speed.
$FixItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.FixItem]'
$FixView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($FixItems)
$FixView.GroupDescriptions.Add((New-Object System.Windows.Data.PropertyGroupDescription('Section')))
$FixView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortKey', 'Ascending')))
$UI.FixList.ItemsSource = $FixView

$script:FixPhase = 'none'          # none | checking | ready | running | done
$script:FixRefs = @{}              # key -> what the suggestion acts on (updates, cleanup items, a startup app, an action)
$script:FixQueue = New-Object System.Collections.Generic.Queue[string]
$script:FixStep = $null
$script:FixStarted = $null
$script:FixTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:FixTimer.Interval = [TimeSpan]::FromSeconds(1)

function Add-FixItem([string]$Key, [string]$Section, [string]$Name, [string]$Detail, [bool]$Ticked, [switch]$Admin, [string]$Action, $Ref) {
    $order = @{ 'Recommended' = 1; 'Optional' = 2; 'Worth a look' = 3 }
    $f = New-Object WingetUM.FixItem
    $f.Key = $Key; $f.Section = $Section; $f.Name = $Name; $f.Detail = $Detail
    $f.SortKey = '{0}-{1:D3}' -f $order[$Section], $FixItems.Count
    $f.CanChoose = $Section -ne 'Worth a look'; $f.Included = $Ticked -and $f.CanChoose; $f.NeedsAdmin = [bool]$Admin; $f.ActionText = $Action
    if ($null -ne $Ref) { $script:FixRefs[$Key] = $Ref }
    $FixItems.Add($f)
}
function Get-FixItem([string]$Key) { return @($FixItems | Where-Object { $_.Key -eq $Key }) | Select-Object -First 1 }
function Format-FixNames($Names, [int]$Max = 4) {
    $n = @($Names)
    $text = ($n | Select-Object -First $Max) -join ', '
    if ($n.Count -gt $Max) { $text += " and $($n.Count - $Max) more" }
    return $text
}

# ---- Checking: start whatever hasn't been read yet (or is old), and wait for it, at most four minutes
function Open-FixMyPC {
    $UI.FixOverlay.Visibility = 'Visible'
    if ($script:FixPhase -in 'checking', 'running') { Update-FixView; return }
    $FixItems.Clear(); $script:FixRefs = @{}
    $script:FixPhase = 'checking'
    $script:FixStarted = Get-Date
    if ($WingetPath -and $script:Mode -eq 'idle' -and -not $script:Scanner) { Start-Scan }
    if ($script:WinState -in 'none', 'error') { Start-WinCheck }
    if (-not $script:CleanReader -and -not $script:Cleaner) { Start-CleanScan }
    if (-not $script:HealthReader) { Start-HealthScan }
    if ($script:StartupState -in 'none', 'error') { Start-StartupScan }
    $script:FixTimer.Start()
    Update-FixView
}
function Test-FixChecked {
    if (((Get-Date) - $script:FixStarted).TotalMinutes -ge 4) { return $true }
    if ($script:Scanner -or $script:Mode -eq 'loading') { return $false }
    if ($script:WinState -eq 'running') { return $false }
    if ($script:CleanReader -or -not $script:CleanMeasured) { return $false }
    if ($script:HealthReader -or -not $script:HealthInfo) { return $false }
    if ($script:StartupState -eq 'running') { return $false }
    return $true
}

# ---- The suggestions
function Build-FixList {
    $FixItems.Clear(); $script:FixRefs = @{}
    $hi = $script:HealthInfo
    $sec = if ($hi) { $hi.Security } else { $null }
    $rel = if ($hi) { $hi.Reliability } else { $null }
    $otherAv = @($sec.Av | Where-Object { $_.On -and $_.Name -notmatch 'Defender' }).Count -gt 0
    $def = $sec.Defender

    # Recommended: what Windows itself would do, and safe
    $apps = @($Packages | Where-Object { $_.CanUpdate -and -not $_.ExplicitTarget -and -not $_.Hidden })
    if ($script:Mode -eq 'ready' -and $apps.Count) {
        Add-FixItem 'apps' 'Recommended' "Update $($apps.Count) app$(if ($apps.Count -ne 1) { 's' })" "Through winget: $(Format-FixNames @($apps | ForEach-Object { $_.Name })). Hidden and pinned apps are left alone; some installers may ask for approval themselves." $true -Ref $apps
    }
    $wins = @($WinUpdates | Where-Object { -not $_.Optional -and $_.Type -ne 'Feature update' })
    if ($script:WinState -eq 'ready' -and $wins.Count) {
        Add-FixItem 'win' 'Recommended' "Install $($wins.Count) Windows update$(if ($wins.Count -ne 1) { 's' })" "$(Format-FixNames @($wins | ForEach-Object { $_.Title }) 3). Nothing restarts by itself; if one needs a restart, you're told." $true -Admin -Ref $wins
    }
    if ($def -and $def.On -and -not $otherAv) {
        if ($def.SigAge -ge 1) { Add-FixItem 'defsig' 'Recommended' "Update Defender's virus definitions" "They're $($def.SigAge) day$(if ($def.SigAge -ne 1) { 's' }) old; Defender needs current ones to recognize new threats." $true -Admin }
        if ($def.ScanAge -ge 7) { Add-FixItem 'defscan' 'Recommended' 'Run a quick virus scan' "The last quick scan was $(if ($def.ScanAge -gt 3650) { 'never run' } else { "$($def.ScanAge) days ago" }). It takes a few minutes; Windows Security has the details if it finds anything." $true -Admin }
        if (-not $def.Realtime) { Add-FixItem 'realtime' 'Recommended' "Turn Defender's real-time protection back on" "It's off, so files aren't checked as they're opened or downloaded." $true -Admin }
    }
    $fwOff = @($sec.Firewall | Where-Object { -not $_.On } | ForEach-Object { $_.Name })
    if ($fwOff.Count) { Add-FixItem 'firewall' 'Recommended' 'Turn the firewall back on' "Windows Firewall is off for the $($fwOff -join ', ') network profile$(if ($fwOff.Count -ne 1) { 's' }).$(if ($otherAv) { ' If another security app has its own firewall, it may have turned this off on purpose: untick it then.' })" (-not $otherAv) -Admin }
    # the leftover files the Cleanup tab ticks by default (never the Recycle Bin, old downloads or saved drivers)
    $clean = @($CleanItems | Where-Object { $c = $CleanCatalog[$_.Key]; $c -and $c.On -and $_.Bytes -ne 0 })
    if ($clean.Count) {
        $known = [long]0; foreach ($c in $clean) { if ($c.Bytes -gt 0) { $known += $c.Bytes } }
        $size = if ($known -gt 0) { "About $(Format-Size $known)" } else { 'Space' }
        Add-FixItem 'clean' 'Recommended' "Clean up leftover files" "$size in $(Format-FixNames @($clean | ForEach-Object { $_.Name }) 5). Files in use are left alone; the Recycle Bin and your downloads aren't touched." $true -Admin:([bool]@($clean | Where-Object { $_.NeedsAdmin }).Count) -Ref $clean
    }

    # Optional: up to the person
    $crashy = $rel -and (([int]$rel.BlueScreens) -gt 0 -or ($null -ne $rel.Index -and [double]$rel.Index -lt 5))
    Add-FixItem 'repair' 'Optional' 'Repair Windows files' "Checks Windows' own files and repairs damaged ones (DISM, then SFC). Takes 10 to 20 minutes.$(if ($crashy) { " Worth it here: $(if ([int]$rel.BlueScreens) { "$($rel.BlueScreens) blue screen$(if ([int]$rel.BlueScreens -ne 1) { 's' }) in 30 days" } else { "stability is $([Math]::Round([double]$rel.Index, 1)) of 10" })." })" $false -Admin
    Add-FixItem 'optimize' 'Optional' 'Optimize drives' 'Trims SSDs and defragments hard drives. Windows usually does this every week by itself.' $false -Admin
    foreach ($s in @($StartupItems | Where-Object { $_.Enabled -and -not $_.NeedsAdmin -and $_.State -ne 'policy' -and $_.Location -ne 'task' } | Sort-Object Name)) {
        Add-FixItem "startup|$($s.Name)|$($s.Entry)" 'Optional' "Don't start $($s.Name) when you sign in" "Starting fewer apps makes signing in faster. It still works when you open it; turn it back on from the Startup tab." $false -Ref $s
    }

    # Worth a look: what it can't do itself
    $restart = $hi -and $hi.Reboot
    if ($restart) { Add-FixItem 'look-restart' 'Worth a look' 'A restart is waiting' 'Windows needs a restart to finish installing updates.' $false -Action 'Restart now' -Ref { Request-RestartNow } }
    $feature = @($WinUpdates | Where-Object { $_.Type -eq 'Feature update' })
    if ($feature.Count) { Add-FixItem 'look-feature' 'Worth a look' 'A new version of Windows is available' "$($feature[0].Title). It takes an hour or more and finishes during a restart, so it's left to you." $false -Action 'Windows Update' -Ref { $UI.FixOverlay.Visibility = 'Collapsed'; $UI.TabWindows.IsChecked = $true } }
    Add-FixItem 'look-drivers' 'Worth a look' 'Driver updates' "Drivers from Windows Update, the PC's vendor, NVIDIA and AMD are on the Drivers tab, with a saved copy to roll back to." $false -Action 'Drivers' -Ref { $UI.FixOverlay.Visibility = 'Collapsed'; $UI.TabDrivers.IsChecked = $true; $UI.DrvViewUpdates.IsChecked = $true; Update-View }
    if ($rel -and [int]$rel.Devices -gt 0) { Add-FixItem 'look-devices' 'Worth a look' "$($rel.Devices) device$(if ([int]$rel.Devices -ne 1) { 's have' } else { ' has' }) a problem" 'Windows reports a problem with their driver or the device itself.' $false -Action 'Drivers' -Ref { $UI.FixOverlay.Visibility = 'Collapsed'; $UI.TabDrivers.IsChecked = $true; $UI.DrvViewDevices.IsChecked = $true; $UI.DrvProblemsOnly.IsChecked = $true; Update-View } }
    $low = @($hi.Volumes | Where-Object { $_.Size -and $_.Free / $_.Size -lt 0.1 } | ForEach-Object { $_.Letter })
    if ($low.Count) { Add-FixItem 'look-space' 'Worth a look' "$($low -join ', ') $(if ($low.Count -ne 1) { 'are' } else { 'is' }) nearly full" 'Cleanup lists your largest files and the apps that take the most space.' $false -Action 'Cleanup' -Ref { $UI.FixOverlay.Visibility = 'Collapsed'; $UI.TabCleanup.IsChecked = $true } }
    $badDisk = @($hi.Disks | Where-Object { $_.Health -and $_.Health -ne 'Healthy' } | ForEach-Object { $_.Name })
    if ($badDisk.Count) { Add-FixItem 'look-disk' 'Worth a look' 'A drive reports a problem' "$($badDisk -join ', '). Back up what's on it." $false }
    if ($sec -and $sec.SecureBoot -eq 0) { Add-FixItem 'look-secureboot' 'Worth a look' 'Secure Boot is off' "It's turned on in the PC's firmware (BIOS or UEFI) setup, which this app can't change." $false }
    if ($sec -and $null -ne $sec.License -and [int]$sec.License -ne 1) { Add-FixItem 'look-activation' 'Worth a look' "Windows isn't activated" 'Settings > System > Activation says why and how to fix it.' $false -Action 'Activation' -Ref { Start-Process 'ms-settings:activation' } }
}

# ---- The administrator run: each part says RESULT|fix|key|state|text (cleanup: RESULT|clean, Windows updates: RESULT|win)
function Get-FixPart([string]$Key, [string]$Title, [string]$Code) {
    $t = $Title -replace "'", "''"
    return "Say ''`r`nSay '---- $t'`r`ntry {`r`n& {`r`n$Code`r`n}`r`n}`r`ncatch { Say ('RESULT|fix|$Key|error|' + (`$_.Exception.Message -replace '[\r\n]+', ' ')) }`r`n"
}
function Get-FixAdminBody($Keys, $Wins, $CleanAdmin) {
    $body = ''
    if ('defsig' -in $Keys) { $body += Get-FixPart 'defsig' "Updating Defender's virus definitions" @'
Update-MpSignature -ErrorAction Stop
Say 'RESULT|fix|defsig|ok|Updated'
'@ }
    if ('realtime' -in $Keys) { $body += Get-FixPart 'realtime' 'Turning on real-time protection' @'
Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
Start-Sleep -Seconds 2
if ((Get-MpComputerStatus).RealTimeProtectionEnabled) { Say 'RESULT|fix|realtime|ok|Turned on' }
else { Say 'RESULT|fix|realtime|error|Still off: Tamper Protection or your organization may keep it off. Windows Security can turn it on' }
'@ }
    if ('firewall' -in $Keys) { $body += Get-FixPart 'firewall' 'Turning on the firewall' @'
Set-NetFirewallProfile -Profile Domain, Private, Public -Enabled True -ErrorAction Stop
Say 'RESULT|fix|firewall|ok|Turned on'
'@ }
    if ('win' -in $Keys) {
        $code = (Get-WinApplyBody @($Wins | ForEach-Object { @{ Id = $_.UpdateId; Title = $_.Title } })) + "`r`n" + @'
if ($fail) { Say ('RESULT|fix|win|error|' + $fail + ' update(s) did not install') }
elseif ($reboot) { Say 'RESULT|fix|win|reboot|Installed. Restart to finish' }
else { Say 'RESULT|fix|win|ok|Installed' }
'@
        $body += Get-FixPart 'win' 'Installing Windows updates' $code
    }
    if (@($CleanAdmin).Count) { $body += Get-FixPart 'cleanadmin' "Cleaning up Windows' leftover files" (Get-CleanAdminBody $CleanAdmin) }
    if ('defscan' -in $Keys) { $body += Get-FixPart 'defscan' 'Running a quick virus scan' @'
$t0 = Get-Date
Start-MpScan -ScanType QuickScan -ErrorAction Stop
$found = @(Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $t0 }).Count
if ($found) { Say ('RESULT|fix|defscan|reboot|Found ' + $found + ' threat(s): Windows Security has the details') } else { Say 'RESULT|fix|defscan|ok|Nothing found' }
'@ }
    if ('optimize' -in $Keys) { $body += Get-FixPart 'optimize' 'Optimizing drives' @'
$done = @()
foreach ($v in @(Get-Volume | Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter -and $_.FileSystem -eq 'NTFS' })) {
    Say ('Optimizing ' + $v.DriveLetter + ':')
    Optimize-Volume -DriveLetter $v.DriveLetter -ErrorAction Stop
    $done += [string]$v.DriveLetter + ':'
}
Say ('RESULT|fix|optimize|ok|Optimized ' + ($done -join ', '))
'@ }
    if ('repair' -in $Keys) { $body += Get-FixPart 'repair' 'Repairing Windows files' @'
Say 'Checking the Windows image (DISM); this can take a while...'
& "$env:SystemRoot\System32\Dism.exe" /Online /Cleanup-Image /RestoreHealth /NoRestart | Out-Null
$d = $LASTEXITCODE
Say ('DISM finished with code ' + $d)
Say 'Checking Windows files (SFC)...'
& "$env:SystemRoot\System32\sfc.exe" /scannow | Out-Null
Say ('SFC finished with code ' + $LASTEXITCODE)
if ($d -ne 0) { Say ('RESULT|fix|repair|error|DISM stopped with code ' + $d + '; the details are in C:\Windows\Logs\DISM\dism.log') }
else { Say 'RESULT|fix|repair|ok|Done. What SFC found is in C:\Windows\Logs\CBS\CBS.log; a restart finishes any repairs' }
'@ }
    return $body + "`r`nexit 0"
}

# ---- The run, one step at a time: admin (the administrator run), apps, clean (your own leftover files), startup
function Start-FixRun {
    $chosen = @($FixItems | Where-Object { $_.CanChoose -and $_.Included })
    if (-not $chosen.Count) { return }
    if ($script:Elev) { $UI.FixNote.Text = "Wait for $($script:ElevTitle) to finish first."; return }
    if ($script:Worker -or $Sync.Jobs.Count) { $UI.FixNote.Text = 'Wait for the app updates and installs that are running to finish first.'; return }
    foreach ($f in $FixItems) { $f.Locked = $true; if ($f.CanChoose -and -not $f.Included) { $f.State = 'skipped'; $f.Result = 'Not chosen' } }
    foreach ($f in $chosen) { $f.State = 'running'; $f.Result = '' }
    $script:FixPhase = 'running'
    $script:FixRun = @{ Keys = @($chosen | ForEach-Object { $_.Key }); Started = Get-Date }
    $script:FixQueue.Clear()
    $keys = $script:FixRun.Keys
    if (@($chosen | Where-Object { $_.NeedsAdmin }).Count) { $script:FixQueue.Enqueue('admin') }
    if ('apps' -in $keys) { $script:FixQueue.Enqueue('apps') }
    if ('clean' -in $keys) { $script:FixQueue.Enqueue('clean') }
    if (@($keys | Where-Object { $_ -like 'startup|*' }).Count) { $script:FixQueue.Enqueue('startup') }
    if ('clean' -in $keys) { $script:CleanFreed = [long]0; $script:CleanFailed = 0; $script:CleanDone = @(); foreach ($i in $script:FixRefs['clean']) { $i.State = 'running'; $i.Detail = 'Cleaning' + $Ellipsis } }
    $script:FixStep = $null
    $script:FixTimer.Start()
    Step-FixRun
}
function Start-FixStep([string]$Step) {
    $keys = $script:FixRun.Keys
    switch ($Step) {
        'admin' {
            $wins = if ('win' -in $keys) { $script:FixRefs['win'] } else { @() }
            $cleanAdmin = if ('clean' -in $keys) { @($script:FixRefs['clean'] | Where-Object { $_.NeedsAdmin }) } else { @() }
            $body = Get-FixAdminBody $keys $wins $cleanAdmin
            Start-Elevated 'fixpc' 'Fix my PC' $body @() @{ Keys = $keys } -RestorePoint -RestoreText 'Before Fix my PC' -StallMinutes 90
        }
        'apps' { Add-UpdateJob @($script:FixRefs['apps'] | Where-Object { $_.CanUpdate }) }
        'clean' {
            $mine = @($script:FixRefs['clean'] | Where-Object { -not $_.NeedsAdmin })
            if ($mine.Count) { Start-CleanMine $mine }
        }
        'startup' {
            foreach ($k in @($keys | Where-Object { $_ -like 'startup|*' })) {
                $s = $script:FixRefs[$k]; $f = Get-FixItem $k
                Set-StartupItem $s $false
                if ($s.Enabled) { $f.State = 'error'; $f.Result = "Didn't change$(if ($s.Detail) { ": $($s.Detail)" })" } else { $f.State = 'ok'; $f.Result = "Won't start when you sign in" }
            }
        }
    }
}
# Is the step that's running finished? Then record how it went
function Test-FixStepDone([string]$Step) {
    switch ($Step) {
        'admin' { return -not $script:Elev }
        'apps' {
            if ($script:Worker -or $Sync.Jobs.Count) { return $false }
            $apps = @($script:FixRefs['apps']); $f = Get-FixItem 'apps'
            $ok = @($apps | Where-Object { $_.State -in 'ok', 'reboot' }).Count
            $bad = @($apps | Where-Object { $_.State -eq 'error' }).Count
            $f.State = if ($bad) { 'error' } elseif (@($apps | Where-Object { $_.State -eq 'reboot' }).Count) { 'reboot' } else { 'ok' }
            $f.Result = "$ok of $($apps.Count) updated$(if ($bad) { "; $bad didn't update (Software Updates has why)" })$(if ($f.State -eq 'reboot') { '. Restart to finish' })"
            return $true
        }
        'clean' {
            if ($script:Cleaner -or ($script:Elev -and $script:ElevName -eq 'clean')) { return $false }
            $f = Get-FixItem 'clean'
            $failedItems = @($script:FixRefs['clean'] | Where-Object { $_.State -eq 'error' })
            $f.State = if ($failedItems.Count) { 'error' } else { 'ok' }
            $f.Result = "Freed $(Format-Size $script:CleanFreed)$(if ($failedItems.Count) { "; $(Format-FixNames @($failedItems | ForEach-Object { $_.Name })) didn't clean" })"
            Complete-CleanPart
            return $true
        }
        default { return $true }
    }
}
function Step-FixRun {
    if ($script:FixPhase -eq 'checking') {
        if (Test-FixChecked) { $script:FixTimer.Stop(); Build-FixList; $script:FixPhase = 'ready'; Update-FixView }
        return
    }
    if ($script:FixPhase -ne 'running') { $script:FixTimer.Stop(); return }
    while ($true) {
        if ($script:FixStep) {
            if (-not (Test-FixStepDone $script:FixStep)) { Update-FixView; return }
            $script:FixStep = $null
        }
        if (-not $script:FixQueue.Count) { Complete-FixRun; return }
        $script:FixStep = $script:FixQueue.Dequeue()
        Start-FixStep $script:FixStep
    }
}
$script:FixTimer.Add_Tick({ try { Step-FixRun } catch { Add-LogLine "Fix my PC: $($_.Exception.Message)" } })

$ElevHandlers.fixpc = {
    param($Ev, $why, $code, $last, $tag)
    $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8) } else { @() }
    foreach ($l in @($lines | Where-Object { $_ -like 'RESULT|fix|*' })) {
        $p = $l.Split('|', 5); $f = Get-FixItem $p[2]
        if ($f) { $f.State = $(if ($p[3] -in 'ok', 'reboot', 'error') { $p[3] } else { 'ok' }); $f.Result = $p[4] }
        if ($p[2] -eq 'cleanadmin' -and $p[3] -eq 'error') { foreach ($i in @($script:FixRefs['clean'] | Where-Object { $_.NeedsAdmin -and $_.State -eq 'running' })) { $i.State = 'error'; $i.Detail = $p[4] } }
    }
    foreach ($l in @($lines | Where-Object { $_ -like 'RESULT|clean|*' })) { $p = $l.Split('|', 6); Set-CleanResult $p[2] ([long]$p[3]) ([int]$p[4]) }
    [void](Add-WinResultHistory $tag.Log)
    # what the run didn't get to (declined, stopped): marked, and the steps after it still run
    $stop = if ($why) { $why } else { "Didn't finish$(if ($last) { ": $last" })" }
    foreach ($f in @($FixItems | Where-Object { $_.NeedsAdmin -and $_.State -eq 'running' -and $_.Key -ne 'clean' })) { $f.State = 'error'; $f.Result = $stop }
    foreach ($i in @($script:FixRefs['clean'] | Where-Object { $_.NeedsAdmin -and $_.State -eq 'running' })) { $i.State = 'error'; $i.Detail = $stop }
    if ('win' -in $tag.Keys -and -not $why) { Start-WinCheck }
    Update-FixView
}

function Complete-FixRun {
    $script:FixTimer.Stop()
    $script:FixPhase = 'done'
    $done = @($FixItems | Where-Object { $_.CanChoose -and $_.Included })
    $ok = @($done | Where-Object { $_.State -in 'ok', 'reboot' }).Count
    $bad = @($done | Where-Object { $_.State -eq 'error' }).Count
    $restart = @($done | Where-Object { $_.State -eq 'reboot' -and $_.Result -match 'Restart' }).Count
    $text = "$ok of $($done.Count) done$(if ($bad) { ", $bad didn't work" })$(if ($restart) { '; restart to finish' })"
    Add-History 'fixpc' (Format-FixNames @($done | ForEach-Object { $_.Name }) 3) '' '' '' $(if ($bad) { 'error' } else { 'ok' }) $text
    $script:FixSummary = $text
    $script:LastSummary = "Fix my PC: $text"
    Start-HealthScan
    Update-FixView
    Update-View
}

function Update-FixView {
    $phase = $script:FixPhase
    $chosen = @($FixItems | Where-Object { $_.CanChoose -and $_.Included }).Count
    $UI.FixBar.Visibility = ConvertTo-Visibility ($phase -in 'checking', 'running')
    $UI.FixText.Text = switch ($phase) {
        'checking' { "Checking this PC: app and Windows updates, leftover files, security, reliability and startup apps$Ellipsis This takes a minute or two." }
        'ready' {
            if (-not @($FixItems | Where-Object { $_.Section -eq 'Recommended' }).Count) { "Nothing needs fixing: apps and Windows are up to date, protection is on and there's little to clean up. The optional items below are there if you want them." }
            else { "This is what can make this PC run better. The ticked items are safe to do now; the optional ones are up to you. Everything marked with a shield happens in one administrator approval$(if ($Settings.DriverRestorePoint) { ', after a restore point' })." }
        }
        'running' { "Working through them$Ellipsis Each item shows how it went. You can close this and keep using the app; it carries on." }
        'done' { "Done: $($script:FixSummary). History has each change." }
        default { '' }
    }
    $UI.FixGo.Visibility = ConvertTo-Visibility ($phase -eq 'ready')
    $UI.FixGo.IsEnabled = $chosen -gt 0
    $UI.FixGoText.Text = "Fix $chosen item$(if ($chosen -ne 1) { 's' })"
    $UI.FixClose.Content = if ($phase -eq 'ready') { 'Cancel' } else { 'Close' }
    $UI.FixNote.Text = if ($phase -eq 'running' -and $script:Elev -and $script:ElevName -eq 'fixpc') { "Administrator step: $(if ($script:ElevLast) { $script:ElevLast } else { 'running' })" } else { '' }
}

$UI.HlFix.Add_Click({ Open-FixMyPC })
$UI.FixClose.Add_Click({
        $UI.FixOverlay.Visibility = 'Collapsed'
        if ($script:FixPhase -in 'ready', 'done') { $script:FixPhase = 'none' }
    })
$UI.FixGo.Add_Click({ Start-FixRun; Update-FixView })
$UI.FixList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -is [System.Windows.Controls.Button] -and $src.Tag -eq 'fixopen') {
            $act = $script:FixRefs[$src.DataContext.Key]
            if ($act -is [scriptblock]) { & $act }
        }
        # a tick box: the button counts what is ticked
        else { Update-FixView }
    })

# Windows Manager - AppUpdate (part of src\; see Windows_Manager.ps1)

# Windows Manager's own updates. On start (Options > App updates > Check for a new version), the latest release on
# GitHub is read in the background (pre-releases too, with Get beta versions); when its tag (v<version>) is newer
# than this app, the user is offered the update, or it installs straight away with Update without asking.
# Installing downloads the release's exe and checks it against GitHub's SHA-256 and its own file version. Then the
# exes switch places: a running exe can be renamed, so this one becomes "<name>.exe.old", the new one takes its name
# (so the scheduled task and shortcuts still point at it), and the new version starts. This copy stays, out of sight, until
# the new one has opened its window; if it closes or doesn't open, everything is put back and this copy carries on.
# The new version keeps the old exe in Previous\ (one version), so Options > App updates can go back to it.
$AppRepo = 'jdvieira/WindowsManager'
$AppUpdateDir = Join-Path $DataDir 'Update'
$AppPreviousDir = Join-Path $DataDir 'Previous'
$AppUpdateMarker = Join-Path $DataDir 'updated.json'
$AppStartedFlag = Join-Path $DataDir 'update-started.json'
$script:AppLatest = $null          # the latest release as the last check found it
$script:AppUpdateError = ''
$script:AppChecking = $null
$script:AppChecked = $null
$script:AppDownload = $null
$script:AppProgress = -1
$script:AppSwitch = $null          # a switch to another version, while waiting for it to open

# The update's progress goes to the log panel and the daily log file
function Write-UpdateLog([string]$Text) { Add-LogLine $Text; Write-RunLog $Text }

# After a switch: the old exe moves to Previous\ (replacing what was there), and the switch is recorded. The old
# version is still running for a few seconds (it waits for this one to open), so moving it is retried every 2 seconds
# for two minutes.
$OldExe = "$ExePath.old"
function Save-OldExe {
    if (-not (Test-Path -LiteralPath $OldExe)) { return $true }
    try {
        $v = [string](Get-Item -LiteralPath $OldExe).VersionInfo.FileVersion
        if ($v -eq $AppVersion) { Remove-Item -LiteralPath $OldExe -Force -ErrorAction Stop; return $true }
        New-Item -ItemType Directory -Path $AppPreviousDir -Force | Out-Null
        $dest = Join-Path $AppPreviousDir "Windows Manager $v.exe"
        Move-Item -LiteralPath $OldExe -Destination $dest -Force -ErrorAction Stop
        foreach ($f in @(Get-ChildItem -LiteralPath $AppPreviousDir -Filter '*.exe' | Where-Object { $_.FullName -ne $dest })) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        return $true
    }
    catch { return $false }
}
if ($IsCompiled -and -not $SelfTest -and -not (Save-OldExe)) {
    $script:OldExeTries = 0
    $script:OldExeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:OldExeTimer.Interval = [TimeSpan]::FromSeconds(2)
    $script:OldExeTimer.Add_Tick({
            $script:OldExeTries++
            if ((Save-OldExe) -or $script:OldExeTries -ge 60) { $script:OldExeTimer.Stop(); Update-AppUpdateStatus }
        })
    $script:OldExeTimer.Start()
}
if (-not $SelfTest -and -not $Auto -and (Test-Path -LiteralPath $AppUpdateMarker)) {
    try {
        $m = Get-Content -LiteralPath $AppUpdateMarker -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $AppUpdateMarker -Force
        if ([string]$m.To -eq $AppVersion) {
            if ($m.Kind -eq 'rollback') {
                Add-History 'appupdate' $AppName '' ([string]$m.From) $AppVersion 'ok' 'Went back to the previous version'
                $script:LastSummary = "Back on Windows Manager $AppVersion"
            }
            else {
                Add-History 'appupdate' $AppName '' ([string]$m.From) $AppVersion 'ok' 'Updated from GitHub'
                $script:LastSummary = "Updated to Windows Manager $AppVersion"
            }
        }
    }
    catch { }
    try { Remove-Item -LiteralPath $AppUpdateDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

# v2.3.0.0, or v2.4.0.0-beta.1 for a pre-release (the part after the dash is ignored)
function Get-ReleaseVersion([string]$Tag) {
    $v = $null
    if ([version]::TryParse((($Tag -replace '^[vV]', '') -replace '-.*$', '').Trim(), [ref]$v)) { return $v }
    return $null
}

function Start-AppUpdateCheck([switch]$Manual) {
    if ($script:AppChecking) { return }
    $script:AppChecking = Start-Tracked 'appupdate' @{ Repo = $AppRepo; Manual = [bool]$Manual; Beta = [bool]$Settings.AppUpdateBeta } { $script:AppChecking = $null; Update-AppUpdateStatus }
    Update-AppUpdateStatus
}

$EventHandlers.appupdate = {
    param($Ev)
    $script:AppChecked = Get-Date
    # tests only: pretend the latest release is another version
    if ($env:WM_UPDATE_TEST) { try { $o = $env:WM_UPDATE_TEST | ConvertFrom-Json; $Ev.Tag = [string]$o.Tag; $Ev.Expect = [string]$o.Expect; $Ev.Auto = [bool]$o.Auto } catch { } }
    if ($Ev.Error) {
        $script:AppUpdateError = $Ev.Error
        Write-UpdateLog "Checking GitHub for a new version: $($Ev.Error)"
        if ($Ev.Manual) { $script:LastSummary = "Couldn't check GitHub for a new version: $($Ev.Error)" }
        Update-AppUpdateStatus; Update-View
        return
    }
    $script:AppUpdateError = ''
    $Ev.Version = Get-ReleaseVersion $Ev.Tag
    $script:AppLatest = $Ev
    $newer = $Ev.Version -and $Ev.Version -gt [version]$AppVersion
    Write-UpdateLog "GitHub's latest $(if ($Ev.Prerelease) { 'pre-release' } else { 'release' }) is $($Ev.Tag); this is $AppVersion$(if ($newer) { ': an update is available' })."
    Update-AppUpdateStatus
    if (-not $newer) {
        if ($Ev.Manual) { $script:LastSummary = "Windows Manager $AppVersion is the latest version" }
        Update-View
        return
    }
    if ($Ev.Manual) { Request-AppUpdate; return }
    if ($Settings.AppUpdateSkip -eq [string]$Ev.Version) { Write-UpdateLog "Version $($Ev.Version) was skipped (Not now); Options > App updates can still install it."; return }
    if (($Settings.AppUpdateAuto -or $Ev.Auto) -and $IsCompiled) { Start-AppUpdate; return }
    Request-AppUpdate
}

function Request-AppUpdate {
    $r = $script:AppLatest
    if (-not $r) { return }
    $when = ''; try { $when = ', released {0:MMM d}' -f [datetime]$r.Published } catch { }
    $kind = if ($r.Prerelease) { ' (a pre-release, for testing)' } else { '' }
    # release notes are Markdown with wrapped lines: plain text, one paragraph or bullet per line
    $notes = (([string]$r.Notes) -replace "`r", '' -replace '\*\*|`', '' -replace '(?m)^#+\s*', '' -replace '\n(?![ \t]*(- |\n|$))[ \t]*', ' ').Trim()
    if ($notes.Length -gt 900) { $notes = $notes.Substring(0, 900).TrimEnd() + $Ellipsis }
    if (-not $IsCompiled) {
        Show-Confirm 'appupdatesrc' $null "Windows Manager $($r.Version) is available" "Version $($r.Version)$kind is on GitHub$when (this is $AppVersion). This copy runs from its source files, so it can't replace itself: pull the new version with git, or download the exe from the release page.$(if ($notes) { "`n`nWhat's new:`n$notes" })" 'Open the release page'
        return
    }
    Show-Confirm 'appupdate' $null "Update to Windows Manager $($r.Version)?" "Version $($r.Version)$kind is on GitHub$when (you have $AppVersion).$(if ($notes) { "`n`nWhat's new:`n$notes" })`n`nThe app downloads it, checks it, restarts on the new version and keeps your settings, history and schedule. If the new version doesn't open, this one comes back by itself, and Options > App updates can go back to $AppVersion later. Not now skips this version." 'Update now'
    $UI.ConfirmNo.Content = 'Not now'
}
$ConfirmHandlers.appupdate = { param($Payload) Start-AppUpdate }
$ConfirmDeclined.appupdate = { param($Payload) if ($script:AppLatest) { $Settings.AppUpdateSkip = [string]$script:AppLatest.Version; Save-Settings } }
$ConfirmHandlers.appupdatesrc = { param($Payload) if ($script:AppLatest.Page -match '^https://github\.com/') { try { Start-Process $script:AppLatest.Page } catch { } } }

# Nothing may be installing or running as administrator while the app swaps itself
function Test-AppBusy { return [bool]($script:Worker -or $Sync.Jobs.Count -or $script:Elev -or $script:Cleaner -or $script:AppSwitch) }

function Start-AppUpdate {
    $r = $script:AppLatest
    if (-not $r -or $script:AppDownload) { return }
    if (-not $IsCompiled) { Request-AppUpdate; return }
    if (Test-AppBusy) {
        $script:LastSummary = "Windows Manager $($r.Version) will be offered again next time: something is still working right now"
        Update-View
        return
    }
    if ($r.Url -notmatch '^https://github\.com/') { $script:LastSummary = "The $($r.Tag) release on GitHub has no exe to download"; Update-View; return }
    New-Item -ItemType Directory -Path $AppUpdateDir -Force | Out-Null
    $file = Join-Path $AppUpdateDir "Windows Manager $($r.Version).exe"
    $sha = if ($r.Digest -match '^sha256:([0-9a-fA-F]{64})$') { $Matches[1].ToUpperInvariant() } else { '' }
    Write-UpdateLog ''
    Write-UpdateLog "---- Updating Windows Manager to $($r.Version) ----"
    Write-UpdateLog $r.Url
    $script:AppProgress = 0
    $script:LastSummary = "Downloading Windows Manager $($r.Version)$Ellipsis"
    $script:AppDownload = Start-Tracked 'download' @{ Key = 'app'; Url = $r.Url; File = $file; Sha256 = $sha; Total = $r.Size } { $script:AppDownload = $null; Update-AppUpdateStatus }
    Update-AppUpdateStatus
    Update-View
}

# Download events are shared with AMD's installer: this app's own are Key 'app'
$EventHandlers.dlprogress = {
    param($Ev)
    if ($Ev.Key -ne 'app') { & $AmdProgressHandler $Ev; return }
    $script:AppProgress = $Ev.Value
    $script:LastSummary = "Downloading Windows Manager $($script:AppLatest.Version): $($Ev.Value)%"
    if ($Ev.Value % 10 -eq 0) { Update-View }
}
$EventHandlers.download = {
    param($Ev)
    if ($Ev.Key -ne 'app') { & $AmdDownloadHandler $Ev; return }
    $script:AppProgress = -1
    if ($Ev.Error) {
        Write-UpdateLog "The update didn't download: $($Ev.Error)"
        $script:LastSummary = "Windows Manager's update didn't download: $($Ev.Error)"
        Update-AppUpdateStatus; Update-View
        return
    }
    Install-AppUpdate $Ev.File
}

function Install-AppUpdate([string]$File) {
    $r = $script:AppLatest
    $expect = if ($r.Expect) { [version]$r.Expect } else { $r.Version }
    $got = $null
    try { $got = [version](Get-Item -LiteralPath $File).VersionInfo.FileVersion } catch { }
    if (-not $got -or $got -ne $expect) {
        Remove-Item -LiteralPath $File -Force -ErrorAction SilentlyContinue
        $script:LastSummary = "The downloaded update says it is version $got, not $expect, so it wasn't installed"
        Write-UpdateLog $script:LastSummary
        Update-View
        return
    }
    Write-UpdateLog "Downloaded and checked ($(if ($r.Digest) { "SHA-256 matches GitHub's, " })version $got)."
    Switch-AppVersion $File ([string]$got) 'update'
}

# Puts $File in this exe's place and starts it, then waits (out of sight) for it to open its window. If it closes, or
# hasn't opened after 90 seconds, the switch is undone and this copy comes back. Versions from 2.3 on say so through
# $AppStartedFlag; older ones (going back to one) count as open once their window has been up for a few seconds.
function Switch-AppVersion([string]$File, [string]$To, [string]$Kind, [switch]$Copy) {
    $exe = $ExePath
    $old = "$exe.old"
    try {
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction Stop }
        Rename-Item -LiteralPath $exe -NewName ([IO.Path]::GetFileName($old)) -ErrorAction Stop
        try { if ($Copy) { Copy-Item -LiteralPath $File -Destination $exe -ErrorAction Stop } else { Move-Item -LiteralPath $File -Destination $exe -ErrorAction Stop } }
        catch { Rename-Item -LiteralPath $old -NewName ([IO.Path]::GetFileName($exe)) -ErrorAction SilentlyContinue; throw }
    }
    catch {
        $script:LastSummary = "Couldn't replace $([IO.Path]::GetFileName($exe)) (it may be in a folder that needs administrator rights): $($_.Exception.Message)"
        Write-UpdateLog $script:LastSummary
        Update-View
        return
    }
    [ordered]@{ From = $AppVersion; To = $To; Kind = $Kind; At = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $AppUpdateMarker -Encoding UTF8
    Remove-Item -LiteralPath $AppStartedFlag -Force -ErrorAction SilentlyContinue
    Write-UpdateLog "$(if ($Kind -eq 'rollback') { 'Going back to' } else { 'Installed' }) Windows Manager $To; starting it."
    Exit-AppMutex
    $proc = $null
    $env:WM_AFTER_UPDATE = '1'
    try { $proc = Start-Process -FilePath $exe -PassThru } catch { }
    $env:WM_AFTER_UPDATE = $null
    $script:AppSwitch = @{ Proc = $proc; Start = Get-Date; To = $To; Kind = $Kind; Exe = $exe; Old = $old; SeenWindow = $null; Place = @($Window.Left, $Window.Top, $Window.WindowState) }
    # out of sight while waiting: Hide() would end ShowDialog and with it this copy
    $Window.ShowInTaskbar = $false; $Window.WindowState = 'Normal'; $Window.Left = -32000; $Window.Top = -32000
    $script:AppSwitchTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:AppSwitchTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:AppSwitchTimer.Add_Tick({ Watch-AppSwitch })
    $script:AppSwitchTimer.Start()
}

function Watch-AppSwitch {
    $w = $script:AppSwitch
    if (-not $w) { $script:AppSwitchTimer.Stop(); return }
    $age = ((Get-Date) - $w.Start).TotalSeconds
    $p = $w.Proc
    if (Test-Path -LiteralPath $AppStartedFlag) { $script:AppSwitchTimer.Stop(); Write-UpdateLog "Windows Manager $($w.To) is open."; $Window.Close(); return }
    if (-not $p) { Undo-AppSwitch "it couldn't be started"; return }
    if ($p.HasExited) { Undo-AppSwitch "it closed straight away (exit code $($p.ExitCode))"; return }
    $p.Refresh()
    if ($p.MainWindowHandle -ne [IntPtr]::Zero -and $p.MainWindowTitle -eq 'Windows Manager') {
        if (-not $w.SeenWindow) { $w.SeenWindow = Get-Date }
        elseif (((Get-Date) - $w.SeenWindow).TotalSeconds -ge 8) { $script:AppSwitchTimer.Stop(); Write-UpdateLog "Windows Manager $($w.To) is open."; $Window.Close(); return }
    }
    if ($age -ge 90) { Undo-AppSwitch "it didn't open within 90 seconds" }
}

function Undo-AppSwitch([string]$Why) {
    $script:AppSwitchTimer.Stop()
    $w = $script:AppSwitch
    $script:AppSwitch = $null
    try { if ($w.Proc -and -not $w.Proc.HasExited) { $w.Proc.Kill(); [void]$w.Proc.WaitForExit(5000) } } catch { }
    $back = $false
    try {
        Remove-Item -LiteralPath $w.Exe -Force -ErrorAction Stop
        Rename-Item -LiteralPath $w.Old -NewName ([IO.Path]::GetFileName($w.Exe)) -ErrorAction Stop
        $back = $true
    }
    catch { }
    Remove-Item -LiteralPath $AppUpdateMarker -Force -ErrorAction SilentlyContinue
    if ($w.Kind -ne 'rollback') { $Settings.AppUpdateSkip = $w.To; Save-Settings }
    $script:AppMutex = Get-AppMutex 5
    $text = "Windows Manager $($w.To) didn't start: $Why. $(if ($back) { "This version ($AppVersion) is back in its place" } else { "Put $([IO.Path]::GetFileName($w.Old)) back as $([IO.Path]::GetFileName($w.Exe)) by hand" })$(if ($w.Kind -ne 'rollback') { ', and that version won''t be offered again on start' })."
    Write-UpdateLog $text
    Add-History 'appupdate' $AppName '' $AppVersion $w.To 'error' "Didn't start: $Why; $(if ($back) { 'kept' } else { 'restore' }) $AppVersion"
    $script:LastSummary = $text
    $Window.WindowState = 'Normal'; $Window.Left = $w.Place[0]; $Window.Top = $w.Place[1]; $Window.WindowState = $w.Place[2]; $Window.ShowInTaskbar = $true
    $Window.Activate() | Out-Null
    [void][System.Windows.MessageBox]::Show($Window, $text, $AppName, 'OK', 'Warning')
    Update-AppUpdateStatus
    Update-View
}

# The version kept from before the last switch, if any
function Get-PreviousExe {
    $f = @(Get-ChildItem -LiteralPath $AppPreviousDir -Filter '*.exe' -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $f) { return $null }
    $v = $null; try { $v = [version]$f.VersionInfo.FileVersion } catch { }
    if (-not $v -or $v -eq [version]$AppVersion) { return $null }
    return @{ File = $f.FullName; Version = $v }
}
function Request-AppRollback {
    $p = Get-PreviousExe
    if (-not $p -or -not $IsCompiled) { return }
    if (Test-AppBusy) { $script:LastSummary = 'Wait for the current work to finish first'; Update-View; return }
    Show-Confirm 'approllback' @{ Prev = $p } "Go back to Windows Manager $($p.Version)?" "Version $($p.Version) replaces this one ($AppVersion), and the app restarts on it. Your settings, history and schedule stay as they are, and $AppVersion is kept, so you can come back to it.$(if ($p.Version -lt [version]'2.3.0.0') { " Versions before 2.3 can't come back to a newer one by themselves: to return, update from GitHub or download $AppVersion again." })`n`nThe app won't offer $AppVersion again when it opens; Check now still finds it." 'Go back'
}
$ConfirmHandlers.approllback = {
    param($Payload)
    $Settings.AppUpdateSkip = $AppVersion; Save-Settings
    Switch-AppVersion $Payload.Prev.File ([string]$Payload.Prev.Version) 'rollback' -Copy
}

function Update-AppUpdateStatus {
    $r = $script:AppLatest
    $newer = $r -and $r.Version -and $r.Version -gt [version]$AppVersion
    $UI.OptAppStatus.Text = "Windows Manager $AppVersion$(if (-not $IsCompiled) { ' (running from its source files)' })`n" + $(
        if ($script:AppDownload) { "Downloading $($r.Version)$(if ($script:AppProgress -ge 0) { ": $($script:AppProgress)%" })$Ellipsis" }
        elseif ($script:AppChecking) { "Checking GitHub$Ellipsis" }
        elseif ($script:AppUpdateError) { "Couldn't check GitHub: $($script:AppUpdateError)" }
        elseif ($newer) { "Version $($r.Version) is available$(if ($r.Prerelease) { ' (pre-release)' })$(try { ' (released {0:MMM d})' -f [datetime]$r.Published } catch { '' })." }
        elseif ($r) { "This is the latest version (checked {0:t})." -f $script:AppChecked }
        else { 'Not checked yet.' })
    $UI.OptAppInstall.Visibility = ConvertTo-Visibility ($newer -and -not $script:AppDownload)
    if ($newer) { $UI.OptAppInstall.Content = if ($IsCompiled) { "Update to $($r.Version)" } else { 'Get it on GitHub' } }
    $UI.OptAppCheckNow.IsEnabled = -not $script:AppChecking -and -not $script:AppDownload
    $prev = if ($IsCompiled) { Get-PreviousExe } else { $null }
    $UI.OptAppBack.Visibility = ConvertTo-Visibility ([bool]$prev)
    if ($prev) { $UI.OptAppBack.Content = "Go back to $($prev.Version)" }
}

$UI.OptAppCheckNow.Add_Click({ Start-AppUpdateCheck -Manual })
$UI.OptAppInstall.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed'; if ($IsCompiled) { Start-AppUpdate } else { Request-AppUpdate } })
$UI.OptAppBack.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed'; Request-AppRollback })
$UI.OptAppReleases.Add_Click({ try { Start-Process "https://github.com/$AppRepo/releases" } catch { } })
$Window.Add_ContentRendered({
        if ($SelfTest) { return }
        # started by a version switch: tell the old copy this one is open
        if ($env:WM_AFTER_UPDATE) {
            try { @{ Version = $AppVersion; Pid = $PID } | ConvertTo-Json | Set-Content -LiteralPath $AppStartedFlag -Encoding UTF8 } catch { }
            [Environment]::SetEnvironmentVariable('WM_AFTER_UPDATE', $null, 'Process')
        }
        elseif (Test-Path -LiteralPath $AppStartedFlag) { Remove-Item -LiteralPath $AppStartedFlag -Force -ErrorAction SilentlyContinue }
        if ($Settings.AppUpdateCheck) { Start-AppUpdateCheck } else { Write-UpdateLog 'Checking GitHub for a new version is turned off (Options > App updates).' }
    })

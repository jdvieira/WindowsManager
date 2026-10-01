# Windows Manager - AppUpdate (part of src\; see Windows_Manager.ps1)

# Windows Manager's own updates. On start (Options > App updates > Check for a new version), the latest release on
# GitHub is read in the background; when its tag (v<version>) is newer than this app, the user is offered the update,
# or it installs straight away with Update without asking. Installing downloads the release's exe, checks it against
# GitHub's SHA-256 and its own file version, then swaps it in: a running exe can be renamed, so this one becomes
# "<name>.exe.old", the new one takes its name (so the scheduled task and shortcuts still point at it), and the new
# version starts. It deletes the .old file and records the update when it opens.
$AppRepo = 'jdvieira/WindowsManager'
$AppUpdateDir = Join-Path $DataDir 'Update'
$AppUpdateMarker = Join-Path $DataDir 'updated.json'
$script:AppLatest = $null          # the latest release as the last check found it
$script:AppUpdateError = ''
$script:AppChecking = $null
$script:AppChecked = $null
$script:AppDownload = $null
$script:AppProgress = -1

# After an update: the old exe goes, and the update is recorded. The old version may still be closing when this one
# starts (its file is then in use), so deleting it is tried again every 2 seconds for a minute.
$OldExe = "$ExePath.old"
function Remove-OldExe {
    if (-not (Test-Path -LiteralPath $OldExe)) { return $true }
    try { Remove-Item -LiteralPath $OldExe -Force -ErrorAction Stop; return $true } catch { return $false }
}
if ($IsCompiled -and -not (Remove-OldExe)) {
    $script:OldExeTries = 0
    $script:OldExeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:OldExeTimer.Interval = [TimeSpan]::FromSeconds(2)
    $script:OldExeTimer.Add_Tick({
            $script:OldExeTries++
            if ((Remove-OldExe) -or $script:OldExeTries -ge 30) { $script:OldExeTimer.Stop() }
        })
    $script:OldExeTimer.Start()
}
if (-not $SelfTest -and -not $Auto -and (Test-Path -LiteralPath $AppUpdateMarker)) {
    try {
        $m = Get-Content -LiteralPath $AppUpdateMarker -Raw | ConvertFrom-Json
        Remove-Item -LiteralPath $AppUpdateMarker -Force
        if ([string]$m.To -eq $AppVersion) {
            Add-History 'appupdate' $AppName '' ([string]$m.From) $AppVersion 'ok' 'Updated from GitHub'
            $script:LastSummary = "Updated to Windows Manager $AppVersion"
        }
    }
    catch { }
    try { Remove-Item -LiteralPath $AppUpdateDir -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

# The update's progress goes to the log panel and the daily log file
function Write-UpdateLog([string]$Text) { Add-LogLine $Text; Write-RunLog $Text }

function Get-ReleaseVersion([string]$Tag) {
    $v = $null
    if ([version]::TryParse(($Tag -replace '^[vV]', '').Trim(), [ref]$v)) { return $v }
    return $null
}

function Start-AppUpdateCheck([switch]$Manual) {
    if ($script:AppChecking) { return }
    $script:AppChecking = Start-Tracked 'appupdate' @{ Repo = $AppRepo; Manual = [bool]$Manual } { $script:AppChecking = $null; Update-AppUpdateStatus }
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
    Write-UpdateLog "GitHub's latest release is $($Ev.Tag); this is $AppVersion$(if ($newer) { ': an update is available' })."
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
    # release notes are Markdown with wrapped lines: plain text, one paragraph or bullet per line
    $notes = (([string]$r.Notes) -replace "`r", '' -replace '\*\*|`', '' -replace '(?m)^#+\s*', '' -replace '\n(?![ \t]*(- |\n|$))[ \t]*', ' ').Trim()
    if ($notes.Length -gt 900) { $notes = $notes.Substring(0, 900).TrimEnd() + $Ellipsis }
    if (-not $IsCompiled) {
        Show-Confirm 'appupdatesrc' $null "Windows Manager $($r.Version) is available" "Version $($r.Version) is on GitHub$when (this is $AppVersion). This copy runs from its source files, so it can't replace itself: pull the new version with git, or download the exe from the release page.$(if ($notes) { "`n`nWhat's new:`n$notes" })" 'Open the release page'
        return
    }
    Show-Confirm 'appupdate' $null "Update to Windows Manager $($r.Version)?" "Version $($r.Version) is on GitHub$when (you have $AppVersion).$(if ($notes) { "`n`nWhat's new:`n$notes" })`n`nThe app downloads it, checks it, restarts on the new version and keeps your settings, history and schedule. Not now skips this version; Options > App updates can install it later." 'Update now'
    $UI.ConfirmNo.Content = 'Not now'
}
$ConfirmHandlers.appupdate = { param($Payload) Start-AppUpdate }
$ConfirmDeclined.appupdate = { param($Payload) if ($script:AppLatest) { $Settings.AppUpdateSkip = [string]$script:AppLatest.Version; Save-Settings } }
$ConfirmHandlers.appupdatesrc = { param($Payload) if ($script:AppLatest.Page -match '^https://github\.com/') { try { Start-Process $script:AppLatest.Page } catch { } } }

function Start-AppUpdate {
    $r = $script:AppLatest
    if (-not $r -or $script:AppDownload) { return }
    if (-not $IsCompiled) { Request-AppUpdate; return }
    if ($script:Worker -or $Sync.Jobs.Count -or $script:Elev -or $script:Cleaner) {
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
    $exe = $ExePath
    $old = "$exe.old"
    try {
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force -ErrorAction Stop }
        Rename-Item -LiteralPath $exe -NewName ([IO.Path]::GetFileName($old)) -ErrorAction Stop
        try { Move-Item -LiteralPath $File -Destination $exe -ErrorAction Stop }
        catch { Rename-Item -LiteralPath $old -NewName ([IO.Path]::GetFileName($exe)) -ErrorAction SilentlyContinue; throw }
    }
    catch {
        $script:LastSummary = "Couldn't replace $([IO.Path]::GetFileName($exe)) (it may be in a folder that needs administrator rights): $($_.Exception.Message)"
        Write-UpdateLog $script:LastSummary
        Update-View
        return
    }
    [ordered]@{ From = $AppVersion; To = [string]$got; At = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $AppUpdateMarker -Encoding UTF8
    Write-UpdateLog "Installed Windows Manager $got; restarting."
    try { Start-Process -FilePath $exe } catch { }
    $Window.Close()
}

function Update-AppUpdateStatus {
    $r = $script:AppLatest
    $newer = $r -and $r.Version -and $r.Version -gt [version]$AppVersion
    $UI.OptAppStatus.Text = "Windows Manager $AppVersion$(if (-not $IsCompiled) { ' (running from its source files)' })`n" + $(
        if ($script:AppDownload) { "Downloading $($r.Version)$(if ($script:AppProgress -ge 0) { ": $($script:AppProgress)%" })$Ellipsis" }
        elseif ($script:AppChecking) { "Checking GitHub$Ellipsis" }
        elseif ($script:AppUpdateError) { "Couldn't check GitHub: $($script:AppUpdateError)" }
        elseif ($newer) { "Version $($r.Version) is available$(try { ' (released {0:MMM d})' -f [datetime]$r.Published } catch { '' })." }
        elseif ($r) { "This is the latest version (checked {0:t})." -f $script:AppChecked }
        else { 'Not checked yet.' })
    $UI.OptAppInstall.Visibility = ConvertTo-Visibility ($newer -and -not $script:AppDownload)
    if ($newer) { $UI.OptAppInstall.Content = if ($IsCompiled) { "Update to $($r.Version)" } else { 'Get it on GitHub' } }
    $UI.OptAppCheckNow.IsEnabled = -not $script:AppChecking -and -not $script:AppDownload
}

$UI.OptAppCheckNow.Add_Click({ Start-AppUpdateCheck -Manual })
$UI.OptAppInstall.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed'; if ($IsCompiled) { Start-AppUpdate } else { Request-AppUpdate } })
$UI.OptAppReleases.Add_Click({ try { Start-Process "https://github.com/$AppRepo/releases" } catch { } })
$Window.Add_ContentRendered({
        if ($SelfTest) { return }
        if ($Settings.AppUpdateCheck) { Start-AppUpdateCheck } else { Write-UpdateLog 'Checking GitHub for a new version is turned off (Options > App updates).' }
    })

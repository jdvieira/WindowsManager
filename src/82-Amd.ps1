# Windows Manager - Amd (part of src\; see Windows_Manager.ps1)

# AMD Radeon graphics: AMD has no lookup service like NVIDIA's, so the newest recommended driver is read from AMD's
# driver page (the version in its auto-detect installer's file name). AMD doesn't document a silent switch for that
# installer, so it isn't part of the install run: its row has its own button, which downloads it (from AMD, with AMD's
# page as the referrer, which AMD's server requires), checks AMD's signature, and opens it. The installer then finds
# the right driver for this PC and installs it in its own window.
$script:AmdState = 'none'            # none | running | ready | error | nogpu
$script:AmdNote = ''
$script:AmdSearcher = $null
$script:AmdDownload = $null
$script:AmdTest = $null              # tests only: Gpu and Installed to look up instead of this PC's
$AmdPage = 'https://www.amd.com/en/support/download/drivers.html'

function Start-AmdLookup {
    if ($script:AmdSearcher) { return }
    $chips = if ($script:DrvSys) { [string]$script:DrvSys.Chips } else { '' }
    if (-not $script:AmdTest -and $chips -notmatch 'Radeon|FirePro') { $script:AmdState = 'nogpu'; return }
    $script:AmdState = 'running'
    $script:AmdSearcher = Start-Tracked 'amdlookup' $(if ($script:AmdTest) { $script:AmdTest } else { @{} }) {
        $script:AmdSearcher = $null
        if ($script:AmdState -eq 'running') { $script:AmdState = 'error'; $script:AmdNote = 'the lookup stopped unexpectedly' }
    }
    Update-View
}

$EventHandlers.amdlookup = { param($Ev) Complete-AmdLookup $Ev; Update-View }
function Complete-AmdLookup($Ev) {
    foreach ($u in @($DrvUpdates | Where-Object { $_.Source -eq 'AMD' })) { [void]$DrvUpdates.Remove($u) }
    if ($Ev.None) { $script:AmdState = 'nogpu'; return }
    if ($Ev.Error) { $script:AmdState = 'error'; $script:AmdNote = $Ev.Error; Add-LogLine "AMD driver lookup: $($Ev.Error)"; return }
    $script:AmdState = 'ready'
    $known = [bool]$Ev.Installed
    $newer = $true
    if ($known) { try { $newer = [version]$Ev.Latest -gt [version]$Ev.Installed } catch { $newer = $Ev.Latest -ne $Ev.Installed } }
    Add-LogLine "AMD driver lookup: $($Ev.Gpu) has AMD Software $(if ($known) { $Ev.Installed } else { '(version unknown)' }); AMD's newest recommended is $($Ev.Latest) ($($Ev.Date))."
    $script:AmdNote = if ($newer) { '' } else { "AMD's newest recommended driver, Adrenalin $($Ev.Latest), is installed for the $($Ev.Gpu)." }
    if (-not $newer) { return }
    $u = New-Object WingetUM.DriverUpdate
    $u.Source = 'AMD'; $u.Kind = 'amd'; $u.Url = $Ev.Url; $u.UpdateId = $Ev.Latest
    $u.Name = "AMD Software: Adrenalin Edition $($Ev.Latest)"
    $u.Version = $Ev.Latest
    $u.Type = 'Display'
    $u.Category = "$($Ev.Gpu)  $Dot  $(if ($known) { "installed $($Ev.Installed)" } else { "installed version unknown" })"
    $u.Severity = 'Recommended'
    $u.SizeText = ''
    $u.Released = $Ev.Date
    $u.Included = $true
    $u.ActionText = 'Get installer'
    $u.ActionTip = "Downloads AMD's installer, checks that AMD signed it, and opens it. It finds the right driver for this PC and installs it in its own window (Windows asks for approval)."
    # after NVIDIA's row, before the rest
    $at = @($DrvUpdates | Where-Object { $_.Source -eq 'NVIDIA' }).Count
    $DrvUpdates.Insert($at, $u)
}

# A Driver Updates row's own button (AMD's installer)
function Invoke-DriverAction($u) {
    if (-not $u -or $u.Kind -ne 'amd' -or $script:AmdDownload) { return }
    $file = Join-Path $DrvWorkDir "amd-software-$($u.Version -replace '[^\d.]', '')-setup.exe"
    if ((Test-Path -LiteralPath $file) -and (Get-AuthenticodeSignature -LiteralPath $file).Status -eq 'Valid') { Open-AmdInstaller $u $file; return }
    $u.ActionText = 'Downloading' + $Ellipsis
    Add-LogLine ''
    Add-LogLine "---- Downloading AMD's installer for Adrenalin $($u.Version) ----"
    Add-LogLine $u.Url
    $script:AmdDownload = Start-Tracked 'download' @{ Key = 'amd'; Url = $u.Url; Referer = $AmdPage; File = $file; Signer = 'Advanced Micro Devices'; SignerName = 'AMD' } {
        $script:AmdDownload = $null
        $row = @($DrvUpdates | Where-Object { $_.Kind -eq 'amd' }) | Select-Object -First 1
        if ($row -and $row.ActionText -like 'Downloading*') { $row.ActionText = 'Get installer' }
    }
    Update-View
}
$EventHandlers.dlprogress = {
    param($Ev)
    if ($Ev.Key -ne 'amd') { return }
    $row = @($DrvUpdates | Where-Object { $_.Kind -eq 'amd' }) | Select-Object -First 1
    if ($row) { $row.ActionText = "Downloading $($Ev.Value)%" }
}
$EventHandlers.download = {
    param($Ev)
    if ($Ev.Key -ne 'amd') { return }
    $row = @($DrvUpdates | Where-Object { $_.Kind -eq 'amd' }) | Select-Object -First 1
    if ($Ev.Error) {
        if ($row) { $row.ActionText = 'Get installer' }
        Add-LogLine "AMD's installer didn't download: $($Ev.Error)"
        $script:LastSummary = "AMD's installer didn't download: $($Ev.Error)"
        Update-View
        return
    }
    Add-LogLine "Downloaded and checked (signed by $($Ev.Signer)): $($Ev.File)"
    if ($row) { Open-AmdInstaller $row $Ev.File }
}
function Open-AmdInstaller($u, [string]$File) {
    try {
        Start-Process -FilePath $File
        $u.ActionText = 'Open again'
        $script:LastSummary = "AMD's installer is open: follow it to install the driver, then click Check again"
        Add-History 'drvupdate' "AMD Software: Adrenalin Edition $($u.Version)" 'AMD' '' $u.Version 'ok' "AMD's installer opened; it installs in its own window"
    }
    catch {
        $u.ActionText = 'Open again'
        $script:LastSummary = "AMD's installer didn't open: $($_.Exception.Message)"
    }
    Update-View
}

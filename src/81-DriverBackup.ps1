# Windows Manager - DriverBackup (part of src\; see Windows_Manager.ps1)

# Before this app removes, reinstalls or replaces a third-party driver (oem*.inf), the administrator run saves the
# driver package with pnputil /export-driver into DriverBackups\<time> <device>\, with a manifest.json saying which
# device and version it is. Roll back forces a saved driver back onto its device (UpdateDriverForPlugAndPlayDevices
# with INSTALLFLAG_FORCE, which installs it even though Windows ranks the newer one higher). The newest two saved
# drivers per device are kept.
$DriverBackupDir = Join-Path $DataDir 'DriverBackups'
$DriverBackupKeep = 2

# Script text for administrator runs: Save-DeviceDriver (Say and the backup folder come from the run)
$BackupFunctionText = @'
function Save-DeviceDriver([string]$Inf, [string]$Name, [string]$InstanceId, [string]$HardwareId, [string]$Version, [string]$Date, [string]$Provider) {
    if ($Inf -notmatch '^oem\d+\.inf$') { return }
    $safe = ($Name -replace '[\\/:*?"<>|]', '_').Trim()
    if ($safe.Length -gt 60) { $safe = $safe.Substring(0, 60).Trim() }
    $dir = Join-Path __BACKUPDIR__ ((Get-Date -Format 'yyyyMMdd-HHmmss') + ' ' + $safe)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $o = & pnputil.exe /export-driver $Inf $dir 2>&1; $c = $LASTEXITCODE
    if ($c -ne 0) { Say ("Couldn't save the current driver ($Inf): " + ((@($o) | Select-Object -Last 1) -join ' ')); Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue; return }
    [ordered]@{ Device = $Name; InstanceId = $InstanceId; HardwareId = $HardwareId; Inf = $Inf; Version = $Version; Date = $Date; Provider = $Provider; Saved = (Get-Date).ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dir 'manifest.json') -Encoding UTF8
    Say "Saved the current driver $Version ($Inf) first, so it can be rolled back to."
    # keep the newest few per device
    $mine = @(Get-ChildItem -LiteralPath __BACKUPDIR__ -Directory -ErrorAction SilentlyContinue | Where-Object {
            $m = Join-Path $_.FullName 'manifest.json'
            (Test-Path -LiteralPath $m) -and ((Get-Content -LiteralPath $m -Raw | ConvertFrom-Json).InstanceId -eq $InstanceId) } | Sort-Object Name -Descending)
    foreach ($old in @($mine | Select-Object -Skip __KEEP__)) { Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}
# Every device with a third-party driver whose hardware IDs include $HardwareId (what a Windows Update driver targets)
function Save-DriversFor([string]$HardwareId) {
    if (-not $HardwareId) { return }
    if (-not $script:PnpEntities) { $script:PnpEntities = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.HardwareID }); $script:PnpDrivers = @{}; foreach ($d in @(Get-CimInstance Win32_PnPSignedDriver)) { if ($d.DeviceID) { $script:PnpDrivers[[string]$d.DeviceID] = $d } } }
    foreach ($e in $script:PnpEntities) {
        if (@($e.HardwareID) -notcontains $HardwareId) { continue }
        $d = $script:PnpDrivers[[string]$e.PNPDeviceID]
        if (-not $d -or [string]$d.InfName -notmatch '^oem') { continue }
        $date = ''; try { $date = ([datetime]$d.DriverDate).ToString('yyyy-MM-dd') } catch { }
        Save-DeviceDriver ([string]$d.InfName) ([string]$d.DeviceName) ([string]$d.DeviceID) ([string]$d.HardWareID) ([string]$d.DriverVersion) $date ([string]$d.DriverProviderName)
    }
}
'@
function Get-BackupFunctionText {
    return $BackupFunctionText.Replace('__BACKUPDIR__', "'" + ($DriverBackupDir -replace "'", "''") + "'").Replace('__KEEP__', [string]$DriverBackupKeep) + "`r`n"
}
# The Save-DeviceDriver line for one device in the Devices list
function Get-DeviceSaveCall($d) {
    $q = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
    return "Save-DeviceDriver $(& $q $d.Inf) $(& $q $d.Name) $(& $q $d.InstanceId) $(& $q $d.HardwareId) $(& $q $d.Version) $(& $q $d.Date) $(& $q $d.Provider)`r`n"
}

# Before Windows Update drivers install: the drivers of the devices they target
$WuBackupStep = @'
foreach ($bu in $coll) { try { Save-DriversFor ([string]$bu.DriverHardwareID) } catch { Say ("Couldn't save the current driver: " + $_.Exception.Message) } }
'@
# Before NVIDIA's installer runs: the graphics driver it replaces
$NvBackupStep = @'
foreach ($gd in @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and "$($_.Manufacturer) $($_.DriverProviderName)" -match 'NVIDIA' })) {
    $gdate = ''; try { $gdate = ([datetime]$gd.DriverDate).ToString('yyyy-MM-dd') } catch { }
    try { Save-DeviceDriver ([string]$gd.InfName) ([string]$gd.DeviceName) ([string]$gd.DeviceID) ([string]$gd.HardWareID) ([string]$gd.DriverVersion) $gdate ([string]$gd.DriverProviderName) } catch { Say ("Couldn't save the current driver: " + $_.Exception.Message) }
}
'@

# The saved drivers, newest first
function Read-DriverBackups {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($dir in @(Get-ChildItem -LiteralPath $DriverBackupDir -Directory -ErrorAction SilentlyContinue)) {
        $m = Join-Path $dir.FullName 'manifest.json'
        if (-not (Test-Path -LiteralPath $m)) { continue }
        try { $j = Get-Content -LiteralPath $m -Raw | ConvertFrom-Json } catch { continue }
        $saved = [datetime]::MinValue; try { $saved = [datetime]$j.Saved } catch { }
        $list.Add([pscustomobject]@{ Dir = $dir.FullName; Device = [string]$j.Device; InstanceId = [string]$j.InstanceId; HardwareId = [string]$j.HardwareId
                Inf = [string]$j.Inf; Version = [string]$j.Version; Provider = [string]$j.Provider; Saved = $saved })
    }
    return , @($list | Sort-Object Saved -Descending)
}

# Gives each device its newest saved driver that differs from the one it uses now
function Update-DeviceBackups {
    $all = Read-DriverBackups
    foreach ($d in $DrvDevices) {
        $b = @($all | Where-Object { ($_.InstanceId -eq $d.InstanceId -or ($_.HardwareId -and $_.HardwareId -eq $d.HardwareId)) -and $_.Version -ne $d.Version }) | Select-Object -First 1
        if ($b -and $d.HardwareId) { $d.BackupVersion = $b.Version; $d.BackupDate = $b.Saved.ToString('yyyy-MM-dd'); $d.BackupPath = $b.Dir }
        else { $d.BackupPath = ''; $d.BackupVersion = ''; $d.BackupDate = '' }
    }
}

function Request-DeviceRollback($d) {
    if (-not $d -or -not $d.CanRollback -or $script:Elev) { return }
    $warn = if ($d.Class -match 'Display|Net|Keyboard|Mouse|HIDClass|DiskDrive|SCSIAdapter|HDC|System') { "`n`nThis is a $($d.Class) device, so it drops out for a moment (the screen may flicker or the network disconnect)." } else { '' }
    $rp = if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." } else { '' }
    Show-Confirm 'drvrollback' @{ Device = $d } "Roll back the driver for $($d.Name)?" "Windows installs the saved driver $($d.BackupVersion) (saved $($d.BackupDate)) in place of $($d.Version). The current one is saved first, so you can go forward again.`n`nWindows Update or the vendor's tool may offer the newer driver again later; leave it unticked there if it caused problems.$warn$rp" 'Roll back'
}
$ConfirmHandlers.drvrollback = { param($Payload) Start-DeviceRollback $Payload.Device }

function Start-DeviceRollback($d) {
    $q = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
    $body = (Get-BackupFunctionText) + (Get-DeviceSaveCall $d) + @"
`$dir = $(& $q $d.BackupPath)
`$inf = @(Get-ChildItem -LiteralPath `$dir -Filter *.inf -Recurse -ErrorAction SilentlyContinue) | Select-Object -First 1
if (-not `$inf) { Say "The saved driver in `$dir has no .inf file."; exit 2 }
Say ('Adding the saved driver ' + `$inf.Name + '$Ellipsis')
`$o = & pnputil.exe /add-driver `$inf.FullName 2>&1; `$o | ForEach-Object { Say ([string]`$_) }
Add-Type -Namespace Wsm -Name NewDev -MemberDefinition '[DllImport("newdev.dll", SetLastError = true, CharSet = CharSet.Unicode)] public static extern bool UpdateDriverForPlugAndPlayDevices(IntPtr hwndParent, string HardwareId, string FullInfPath, uint InstallFlags, out bool bRebootRequired);'
`$reboot = `$false
Say 'Installing it on the device (hardware ID $($d.HardwareId -replace "'", "''"))$Ellipsis'
if (-not [Wsm.NewDev]::UpdateDriverForPlugAndPlayDevices([IntPtr]::Zero, $(& $q $d.HardwareId), `$inf.FullName, 1, [ref]`$reboot)) {
    `$e = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Say ("Windows didn't install the saved driver: " + (New-Object ComponentModel.Win32Exception `$e).Message + " (`$e)"); exit 1
}
`$now = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object { `$_.DeviceID -eq $(& $q $d.InstanceId) }) | Select-Object -First 1
Say ('The device now uses driver ' + `$now.DriverVersion + '.')
if (`$reboot) { Say 'Restart to finish.'; exit 3010 }
exit 0
"@
    $d.State = 'running'; $d.Detail = if ($IsAdmin) { 'Working' + $Ellipsis } else { 'Waiting for approval' + $Ellipsis }
    Start-Elevated 'rollback' "Rolling back the driver for $($d.Name)" $body @() @{ Device = $d; To = $d.BackupVersion; From = $d.Version } -RestorePoint -RestoreText 'Before a driver rollback'
}
$ElevHandlers.rollback = {
    param($Ev, $why, $code, $last, $tag)
    $d = $tag.Device
    if ($why) { $d.State = 'error'; $d.Detail = $why }
    elseif ($code -eq 0) { $d.State = 'ok'; $d.Detail = "Rolled back to $($tag.To)" }
    elseif ($code -eq 3010) { $d.State = 'reboot'; $d.Detail = "Rolled back to $($tag.To). Restart to finish" }
    else { $d.State = 'error'; $d.Detail = "Didn't roll back$(if ($last) { ": $last" }); see the log" }
    Add-History 'drvrollback' $d.Name $d.Inf $tag.From $tag.To $d.State $d.Detail
    $script:LastSummary = "$($d.Name): $($d.Detail)"
    if (-not $why) { $script:DeviceRefreshAt = (Get-Date).AddSeconds(4) }
}

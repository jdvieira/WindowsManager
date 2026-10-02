# Windows Manager - Notifications (part of src\; see Windows_Manager.ps1)

# Apps that Windows or the app itself keeps up to date. winget lists their updates, but updating them through winget
# fails ("the install technology is different") or fights the app's own updater, so they leave the Updates list and
# Update all and automatic updates skip them. More are learned when winget reports that failure
# ($Settings.WindowsUpdated); $Settings.WingetUpdates lists the ones the user wants winget to update after all.
$SelfUpdatingIds = @('Microsoft.Edge', 'Microsoft.Edge.Beta', 'Microsoft.Edge.Dev', 'Microsoft.Edge.Canary', 'Microsoft.EdgeWebView2Runtime',
    'Microsoft.Teams', 'Microsoft.Office')
function Test-SelfUpdating([string]$Id) {
    return ($SelfUpdatingIds -contains $Id -or @($Settings.WindowsUpdated) -contains $Id) -and @($Settings.WingetUpdates) -notcontains $Id
}
function Set-SelfUpdating([string]$Id, [bool]$On) {
    if (-not $Id) { return }
    $learned = @($Settings.WindowsUpdated | Where-Object { $_ -and $_ -ne $Id })
    $winget = @($Settings.WingetUpdates | Where-Object { $_ -and $_ -ne $Id })
    if ($On -and $SelfUpdatingIds -notcontains $Id) { $learned += $Id }
    if (-not $On -and $SelfUpdatingIds -contains $Id) { $winget += $Id }
    $Settings.WindowsUpdated = @($learned | Sort-Object -Unique)
    $Settings.WingetUpdates = @($winget | Sort-Object -Unique)
    Save-Settings
}

# Windows notifications (toasts) for automatic runs. An app without a Start menu shortcut can still send them once
# it registers an AppUserModelID (name and icon) under HKCU; its buttons open a windowsmanager: link, also
# registered under HKCU, which starts this app with -Open.
$ToastAppId = 'JustinVieira.WindowsManager'
$ToastProtocol = 'windowsmanager'
function Register-ToastApp {
    $icon = Join-Path $DataDir 'notification.png'
    try {
        if (-not (Test-Path -LiteralPath $icon)) {
            $frame = Get-AppIcon
            if ($frame) {
                $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($frame))
                $fs = [IO.File]::Create($icon); try { $enc.Save($fs) } finally { $fs.Close() }
            }
        }
    }
    catch { }
    # the registrations this app made while it was called Windows Software Manager
    foreach ($old in 'HKCU:\Software\Classes\AppUserModelId\JustinVieira.WindowsSoftwareManager', 'HKCU:\Software\Classes\windowssoftwaremanager') {
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $key = "HKCU:\Software\Classes\AppUserModelId\$ToastAppId"
    New-Item -Path $key -Force | Out-Null
    Set-ItemProperty -LiteralPath $key -Name DisplayName -Value $AppName
    if (Test-Path -LiteralPath $icon) { Set-ItemProperty -LiteralPath $key -Name IconUri -Value $icon }
    $cmd = if ($IsCompiled) { "`"$ExePath`" -Open `"%1`"" } else { "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$AppScript`" -Open `"%1`"" }
    $p = "HKCU:\Software\Classes\$ToastProtocol"
    # the automatic updates' protected copy leaves the buttons opening the copy you use
    if ($AppFile -eq $TaskCopyFile -and (Test-Path -LiteralPath "$p\shell\open\command")) { return }
    New-Item -Path "$p\shell\open\command" -Force | Out-Null
    Set-ItemProperty -LiteralPath $p -Name '(default)' -Value "URL:$AppName"
    Set-ItemProperty -LiteralPath $p -Name 'URL Protocol' -Value ''
    Set-ItemProperty -LiteralPath "$p\shell\open\command" -Name '(default)' -Value $cmd
}

# Shows a notification with a title, up to two more lines and the Open / View log buttons. Returns $false when
# Windows can't show it (notifications off for the app, or no Windows Runtime), so the caller can use the pop-up.
function Show-Toast([string]$Title, [string]$Line1, [string]$Line2, [switch]$Important) {
    try {
        Register-ToastApp
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $esc = { param($s) [Security.SecurityElement]::Escape([string]$s) }
        $lines = (@($Title, $Line1, $Line2) | Where-Object { $_ } | ForEach-Object { "<text>$(& $esc $_)</text>" }) -join ''
        $xml = "<toast launch=`"${ToastProtocol}:open`" activationType=`"protocol`"$(if ($Important) { ' scenario="reminder"' })>" +
        "<visual><binding template=`"ToastGeneric`">$lines</binding></visual>" +
        "<actions><action content=`"Open $AppName`" activationType=`"protocol`" arguments=`"${ToastProtocol}:open`"/>" +
        "<action content=`"View log`" activationType=`"protocol`" arguments=`"${ToastProtocol}:log`"/>" +
        $(if ($Important) { "<action content=`"Dismiss`" activationType=`"system`" arguments=`"dismiss`"/>" } else { '' }) + "</actions></toast>"
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($ToastAppId)
        # Windows PowerShell can't read the notifier's Setting (it comes back empty), so the switches Settings writes
        # are read instead: notifications off for this app, or off altogether
        $off = ''
        $app = Get-ItemProperty -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\$ToastAppId" -ErrorAction SilentlyContinue
        if ($app -and $app.Enabled -eq 0) { $off = 'for this app' }
        $all = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -ErrorAction SilentlyContinue
        if ($all -and $all.ToastEnabled -eq 0) { $off = 'for all apps' }
        $setting = $notifier.Setting
        if (-not $off -and $null -ne $setting -and [int]$setting -ne 0) { $off = "($setting)" }
        if ($off) { Write-RunLog "Windows notifications are turned off $off; showing the pop-up instead."; return $false }
        $notifier.Show([Windows.UI.Notifications.ToastNotification]::new($doc))
        return $true
    }
    catch { Write-RunLog "Couldn't show a Windows notification: $($_.Exception.Message)"; return $false }
}

# A notification's buttons start the app with -Open windowsmanager:<what>: "log" opens today's log
if ($Open -match ':log') { try { Start-Process notepad.exe -ArgumentList "`"$LogFile`"" } catch { }; exit 0 }

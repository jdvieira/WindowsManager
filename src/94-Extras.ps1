# Windows Manager - Extras (part of src\; see Windows_Manager.ps1)

# The Extras tab. Tweaks: Windows settings kept in the registry, each turned on or off. The first time this app changes
# one, it saves exactly what was there (each value, or that it wasn't there, and any key it had to create), so Restore
# puts it back as it was. Shortcuts: Windows' hidden tools and folders, opened, or added to the desktop (and removed
# again, only if this app added them). What was saved is in tweaks.json.
$ExtrasPath = Join-Path $DataDir 'tweaks.json'
$ExtraItems = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.ExtraItem]'
$ExtraView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($ExtraItems)
# in category order, each category's header row first
$ExtraView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortKey', 'Ascending')))
# Categories are closed to start with; a header row opens or closes one (kept while the app runs). Filtering (or
# Changed by this app) shows each match with its category open.
$script:ExExpanded = @{}
function Test-ExtraFiltering { return [bool]($UI.ExChangedOnly.IsChecked -or $UI.ExSearch.Text.Trim()) }
function Test-ExtraMatch($X) {
    if ($UI.ExChangedOnly.IsChecked -and -not $X.Saved) { return $false }
    $q = $UI.ExSearch.Text.Trim()
    return (-not $q) -or ("$($X.Name) $($X.Description) $($X.SubText) $($X.Group)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$ExtraView.Filter = [Predicate[object]] {
    param($x)
    $kind = if ($UI.ExViewTools.IsChecked) { 'tool' } else { 'tweak' }
    if ($x.IsHeader) {
        if ($x.Kind -ne "${kind}group") { return $false }
        if (-not (Test-ExtraFiltering)) { return $true }
        return @($ExtraItems | Where-Object { $_.Kind -eq $kind -and $_.Group -eq $x.Group -and (Test-ExtraMatch $_) }).Count -gt 0
    }
    if ($x.Kind -ne $kind) { return $false }
    if (Test-ExtraFiltering) { return Test-ExtraMatch $x }
    return [bool]$script:ExExpanded["$kind|$($x.Group)"]
}
$UI.ExList.ItemsSource = $ExtraView

# =====================================================================================================================
# The tweaks. Each value: the registry key (HKCU, HKLM or HKU), the value's name ('' is the key's default value), its
# type, and its data when the tweak is on and when it's off ($null: not there, which is Windows' default). OffKey is a
# key that turning the tweak off removes. After: what it takes to show (explorer, signout, restart).
# =====================================================================================================================
function New-TweakValue([string]$Path, [string]$Name, [string]$Kind, $On, $Off) { return @{ Path = $Path; Name = $Name; Kind = $Kind; On = $On; Off = $Off } }
$ExAdv = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$ExCdm = 'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$ExClassic = 'HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}'
# how much the hibernation file takes here, for its tweak's text
$ExHiberText = ''
try { $hf = Join-Path $env:SystemDrive 'hiberfil.sys'; if (Test-Path -LiteralPath $hf) { $ExHiberText = ' (' + (Format-Size (Get-Item -LiteralPath $hf -Force).Length) + ' here)' } } catch { }
# Some tweaks are commands rather than registry values (Cmd): Read says the state now, On and Off are the states the
# tweak sets, Code sets one (__STATE__), Test says whether this PC has it at all, Show is what the row shows
$ExtraTweaks = @(
    @{ Id = 'classicmenu'; Group = 'File Explorer'; Name = 'Classic right-click menu'; After = 'explorer'; OffKey = $ExClassic
        Text = "The full right-click menu, as in Windows 10, without picking Show more options first."
        Values = @((New-TweakValue "$ExClassic\InprocServer32" '' 'String' '' $null)) }
    @{ Id = 'fileext'; Group = 'File Explorer'; Name = 'Show file name extensions'; After = 'explorer'
        Text = 'Shows the end of every file name (.exe, .pdf, .docx), so you can tell what a file really is.'
        Values = @((New-TweakValue $ExAdv 'HideFileExt' 'DWord' 0 1)) }
    @{ Id = 'hidden'; Group = 'File Explorer'; Name = 'Show hidden files and folders'; After = 'explorer'
        Text = 'Shows the files and folders Windows and apps mark as hidden, such as AppData.'
        Values = @((New-TweakValue $ExAdv 'Hidden' 'DWord' 1 2)) }
    @{ Id = 'superhidden'; Group = 'File Explorer'; Name = 'Show protected Windows files'; After = 'explorer'
        Text = "Also shows the files Windows protects from being changed. Look, but don't delete them."
        Values = @((New-TweakValue $ExAdv 'ShowSuperHidden' 'DWord' 1 0)) }
    @{ Id = 'thispc'; Group = 'File Explorer'; Name = 'Open File Explorer to This PC'; After = 'explorer'
        Text = 'File Explorer opens on your drives instead of Home.'
        Values = @((New-TweakValue $ExAdv 'LaunchTo' 'DWord' 1 $null)) }
    @{ Id = 'fullpath'; Group = 'File Explorer'; Name = 'Full folder path in the title bar'; After = 'explorer'
        Text = "The window's title shows the whole path of the open folder."
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState' 'FullPath' 'DWord' 1 0)) }
    @{ Id = 'compact'; Group = 'File Explorer'; Name = 'Compact view'; After = 'explorer'
        Text = 'Less space between files and folders, so more fit on the screen.'
        Values = @((New-TweakValue $ExAdv 'UseCompactMode' 'DWord' 1 0)) }
    @{ Id = 'nohome'; Group = 'File Explorer'; Name = 'Hide Home in the navigation pane'; After = 'explorer'
        Text = 'Removes Home (recent and favorite files) from the left side of File Explorer.'
        Values = @((New-TweakValue 'HKCU\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}' 'System.IsPinnedToNameSpaceTree' 'DWord' 0 $null)) }
    @{ Id = 'nogallery'; Group = 'File Explorer'; Name = 'Hide Gallery in the navigation pane'; After = 'explorer'
        Text = 'Removes Gallery (your photos) from the left side of File Explorer.'
        Values = @((New-TweakValue 'HKCU\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}' 'System.IsPinnedToNameSpaceTree' 'DWord' 0 $null)) }
    @{ Id = 'shortcutname'; Group = 'File Explorer'; Name = 'No "- Shortcut" on new shortcuts'; After = 'explorer'
        Text = 'New shortcuts are named like what they open, without " - Shortcut" at the end.'
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\NamingTemplates' 'ShortcutNameTemplate' 'String' '%s.lnk' $null)) }
    @{ Id = 'driveletters'; Group = 'File Explorer'; Name = 'Drive letters before drive names'; After = 'explorer'
        Text = 'This PC shows "(C:) Windows" instead of "Windows (C:)", so drives sort and read by letter.'
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowDriveLettersFirst' 'DWord' 4 $null)) }
    @{ Id = 'nosyncads'; Group = 'File Explorer'; Name = 'No OneDrive and Microsoft 365 offers'; After = 'explorer'
        Text = "File Explorer doesn't show offers and tips from OneDrive and Microsoft 365 at the top of folders."
        Values = @((New-TweakValue $ExAdv 'ShowSyncProviderNotifications' 'DWord' 0 1)) }
    @{ Id = 'nohomerecent'; Group = 'File Explorer'; Name = 'No recent and frequent files in Home'; After = 'explorer'
        Text = "Home (and Quick access) doesn't list the files and folders you used recently or often."
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowRecent' 'DWord' 0 1), (New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer' 'ShowFrequent' 'DWord' 0 1)) }

    @{ Id = 'endtask'; Group = 'Taskbar and Start'; Name = 'End task on the taskbar'; After = ''
        Text = "Right-click an app on the taskbar to close it, even when it's not responding."
        Values = @((New-TweakValue "$ExAdv\TaskbarDeveloperSettings" 'TaskbarEndTask' 'DWord' 1 0)) }
    @{ Id = 'taskleft'; Group = 'Taskbar and Start'; Name = 'Taskbar icons on the left'; After = ''
        Text = 'Start and the taskbar icons sit at the left, as in Windows 10.'
        Values = @((New-TweakValue $ExAdv 'TaskbarAl' 'DWord' 0 1)) }
    @{ Id = 'nevercombine'; Group = 'Taskbar and Start'; Name = 'Never combine taskbar buttons'; After = 'explorer'
        Text = "Each open window gets its own taskbar button, with its name, on every screen."
        Values = @((New-TweakValue $ExAdv 'TaskbarGlomLevel' 'DWord' 2 0), (New-TweakValue $ExAdv 'MMTaskbarGlomLevel' 'DWord' 2 0)) }
    @{ Id = 'seconds'; Group = 'Taskbar and Start'; Name = 'Seconds in the taskbar clock'; After = ''
        Text = 'The clock shows seconds. Uses a little more power.'
        Values = @((New-TweakValue $ExAdv 'ShowSecondsInSystemClock' 'DWord' 1 0)) }
    @{ Id = 'notaskview'; Group = 'Taskbar and Start'; Name = 'Hide the Task view button'; After = ''
        Text = 'Removes the Task view button from the taskbar. Windows key + Tab still opens it.'
        Values = @((New-TweakValue $ExAdv 'ShowTaskViewButton' 'DWord' 0 1)) }
    @{ Id = 'nowebsearch'; Group = 'Taskbar and Start'; Name = 'No web results in Start search'; After = 'explorer'
        Text = 'Searching from Start or the taskbar only finds apps, files and settings on this PC, not Bing results.'
        Values = @((New-TweakValue 'HKCU\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'DWord' 1 $null)) }
    @{ Id = 'norecent'; Group = 'Taskbar and Start'; Name = 'No recently opened files in Start'; After = 'explorer'
        Text = "Start, Jump Lists and File Explorer don't list the files you opened recently."
        Values = @((New-TweakValue $ExAdv 'Start_TrackDocs' 'DWord' 0 1)) }
    @{ Id = 'norecommend'; Group = 'Taskbar and Start'; Name = 'No tips and app suggestions in Start'; After = ''
        Text = "Start's Recommended section doesn't suggest tips, shortcuts or new apps."
        Values = @((New-TweakValue $ExAdv 'Start_IrisRecommendations' 'DWord' 0 1)) }
    @{ Id = 'runas'; Group = 'Taskbar and Start'; Name = 'Run as different user in Start'; After = 'explorer'
        Text = 'Right-clicking an app in Start offers to run it as another user.'
        Values = @((New-TweakValue 'HKCU\Software\Policies\Microsoft\Windows\Explorer' 'ShowRunAsDifferentUserInStart' 'DWord' 1 $null)) }
    @{ Id = 'nosnapflyout'; Group = 'Taskbar and Start'; Name = 'No Snap layouts on the maximize button'; After = ''
        Text = "Pointing at a window's maximize button doesn't pop up the Snap layouts. Windows key + Z still shows them."
        Values = @((New-TweakValue $ExAdv 'EnableSnapAssistFlyout' 'DWord' 0 1)) }
    @{ Id = 'nowidgets'; Group = 'Taskbar and Start'; Name = 'Hide Widgets'; After = 'explorer'
        Text = "Removes the Widgets button and its news feed from the taskbar. Windows' own switch for it is locked on newer versions, so this uses a Windows-wide setting."
        Values = @((New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 'DWord' 0 $null)) }
    @{ Id = 'nocopilotbutton'; Group = 'Taskbar and Start'; Name = 'Hide the Copilot button'; After = 'explorer'
        Text = 'Removes the Copilot button from the taskbar, where Windows has one. The Copilot app still works.'
        Values = @((New-TweakValue $ExAdv 'ShowCopilotButton' 'DWord' 0 1)) }
    @{ Id = 'searchicon'; Group = 'Taskbar and Start'; Name = 'Search as an icon on the taskbar'; After = ''
        Text = 'The taskbar shows a search icon instead of the wide search box, leaving more room for apps.'
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' 'DWord' 1 2)) }
    @{ Id = 'morepins'; Group = 'Taskbar and Start'; Name = 'More pins in Start'; After = ''
        Text = 'Start shows more pinned apps and a smaller Recommended section.'
        Values = @((New-TweakValue $ExAdv 'Start_Layout' 'DWord' 1 0)) }

    @{ Id = 'noadid'; Group = 'Privacy and suggestions'; Name = 'Turn off the advertising ID'; After = ''
        Text = "Apps can't use your advertising ID to show you personalized ads."
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'DWord' 0 1)) }
    @{ Id = 'notailored'; Group = 'Privacy and suggestions'; Name = 'No tailored experiences'; After = ''
        Text = "Microsoft doesn't use your diagnostic data for personalized tips, ads and recommendations."
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'DWord' 0 1)) }
    @{ Id = 'notips'; Group = 'Privacy and suggestions'; Name = 'No tips and suggestions'; After = ''
        Text = 'Windows stops showing tips and suggestions as you use it.'
        Values = @((New-TweakValue $ExCdm 'SubscribedContent-338389Enabled' 'DWord' 0 1)) }
    @{ Id = 'nosettingsads'; Group = 'Privacy and suggestions'; Name = 'No suggested content in Settings'; After = ''
        Text = "The Settings app doesn't suggest content and features."
        Values = @((New-TweakValue $ExCdm 'SubscribedContent-338393Enabled' 'DWord' 0 1), (New-TweakValue $ExCdm 'SubscribedContent-353694Enabled' 'DWord' 0 1), (New-TweakValue $ExCdm 'SubscribedContent-353696Enabled' 'DWord' 0 1)) }
    @{ Id = 'nolockads'; Group = 'Privacy and suggestions'; Name = 'No fun facts and tips on the lock screen'; After = ''
        Text = "The lock screen shows only your picture, without Microsoft's facts, tips and offers."
        Values = @((New-TweakValue $ExCdm 'RotatingLockScreenOverlayEnabled' 'DWord' 0 1), (New-TweakValue $ExCdm 'SubscribedContent-338387Enabled' 'DWord' 0 1)) }
    @{ Id = 'nosilentapps'; Group = 'Privacy and suggestions'; Name = "Don't install suggested apps"; After = ''
        Text = "Windows doesn't add suggested apps and games by itself."
        Values = @((New-TweakValue $ExCdm 'SilentInstalledAppsEnabled' 'DWord' 0 1)) }
    @{ Id = 'nofinishsetup'; Group = 'Privacy and suggestions'; Name = 'No "finish setting up your PC" prompts'; After = ''
        Text = "Windows stops asking you to finish setting up the PC with Microsoft's services after updates."
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 'DWord' 0 1)) }
    @{ Id = 'noactivity'; Group = 'Privacy and suggestions'; Name = 'Turn off activity history'; After = ''
        Text = "Windows doesn't keep a history of the apps, files and sites you used on this PC, or send it to Microsoft."
        Values = @((New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' 'DWord' 0 $null), (New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' 'DWord' 0 $null)) }
    @{ Id = 'norecall'; Group = 'Privacy and suggestions'; Name = 'Turn off Recall snapshots'; After = 'signout'
        Text = "On Copilot+ PCs, Recall doesn't save snapshots of your screen. Other PCs don't have Recall, so nothing changes there."
        Values = @((New-TweakValue 'HKCU\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 'DWord' 1 $null)) }
    @{ Id = 'mintelemetry'; Group = 'Privacy and suggestions'; Name = 'Send only required diagnostic data'; After = ''
        Text = "Windows sends Microsoft only the diagnostic data it needs to stay secure and up to date. Settings then says some settings are managed by your organization; that's this."
        Values = @((New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'DWord' 1 $null)) }

    @{ Id = 'nomouseaccel'; Group = 'Mouse, keyboard and games'; Name = 'Turn off mouse acceleration'; After = 'signout'
        Text = 'The pointer moves the same distance however fast you move the mouse (Enhance pointer precision off).'
        Values = @((New-TweakValue 'HKCU\Control Panel\Mouse' 'MouseSpeed' 'String' '0' '1'), (New-TweakValue 'HKCU\Control Panel\Mouse' 'MouseThreshold1' 'String' '0' '6'), (New-TweakValue 'HKCU\Control Panel\Mouse' 'MouseThreshold2' 'String' '0' '10')) }
    @{ Id = 'nostickykeys'; Group = 'Mouse, keyboard and games'; Name = 'No Sticky Keys prompt'; After = 'signout'
        Text = "Pressing Shift five times doesn't ask to turn on Sticky Keys."
        Values = @((New-TweakValue 'HKCU\Control Panel\Accessibility\StickyKeys' 'Flags' 'String' '506' '510')) }
    @{ Id = 'nogamedvr'; Group = 'Mouse, keyboard and games'; Name = 'Turn off background game recording'; After = ''
        Text = "Game Bar doesn't record your games in the background, which can cost some speed."
        Values = @((New-TweakValue 'HKCU\System\GameConfigStore' 'GameDVR_Enabled' 'DWord' 0 1), (New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 'DWord' 0 1)) }
    @{ Id = 'numlock'; Group = 'Mouse, keyboard and games'; Name = 'Num Lock on at the sign-in screen'; After = 'restart'
        Text = 'Num Lock is on when Windows starts, so a PIN or password with numbers types right.'
        Values = @((New-TweakValue 'HKU\.DEFAULT\Control Panel\Keyboard' 'InitialKeyboardIndicators' 'String' '2' '0')) }

    @{ Id = 'nostartupdelay'; Group = 'Speed'; Name = 'No delay for startup apps'; After = 'signout'
        Text = 'Windows waits about 10 seconds after you sign in before it starts your startup apps. This starts them straight away.'
        Values = @((New-TweakValue 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec' 'DWord' 0 $null)) }
    @{ Id = 'noedgebackground'; Group = 'Speed'; Name = "Edge doesn't run in the background"; After = ''
        Text = "Edge doesn't start with Windows (startup boost) or keep running after you close it, which saves memory. Edge's settings then say they're managed by your organization; that's this."
        Values = @((New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' 'DWord' 0 $null), (New-TweakValue 'HKLM\SOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' 'DWord' 0 $null)) }
    @{ Id = 'gpusched'; Group = 'Speed'; Name = 'Hardware-accelerated GPU scheduling'; After = 'restart'
        Text = 'The graphics card schedules its own work, which can lower lag in games. Needs a recent graphics card and driver.'
        Values = @((New-TweakValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 'DWord' 2 1)) }
    @{ Id = 'highperf'; Group = 'Speed'; Name = 'High performance power plan'; After = ''; Admin = $true
        Text = "The processor stays ready at full speed instead of saving power. Uses more power; turning it off goes back to Balanced. Windows 11 hides this plan, so it's added back first; some laptops can't use it at all."
        Cmd = @{ Show = 'powercfg /setactive'; On = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'; Off = '381b4222-f694-41f0-9685-ff5bb260df2e'
            Read = { $m = [regex]::Match([string](& powercfg.exe /getactivescheme), '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'); if ($m.Success) { $m.Value.ToLowerInvariant() } else { '' } }
            # a hidden built-in plan comes back under its own ID (duplicatescheme with the same ID twice)
            Code = 'if ([string](& powercfg.exe /list) -notmatch ''__STATE__'') { $null = & powercfg.exe /duplicatescheme __STATE__ __STATE__ 2>&1; if ($LASTEXITCODE) { throw "This PC doesn''t have that power plan" } }; & powercfg.exe /setactive __STATE__; if ($LASTEXITCODE) { throw ("powercfg stopped with code " + $LASTEXITCODE) }' } }

    @{ Id = 'longpaths'; Group = 'System'; Name = 'Allow long file paths'; After = ''
        Text = 'Apps that support it can use paths longer than 260 characters, such as deep folders from developer tools.'
        Values = @((New-TweakValue 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' 'DWord' 1 0)) }
    @{ Id = 'nofaststartup'; Group = 'System'; Name = 'Turn off Fast Startup'; After = ''
        Text = 'Shut down really shuts down, instead of partly hibernating. Starting takes a little longer, but fixes some driver and dual-boot problems.'
        Values = @((New-TweakValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 'DWord' 0 1)) }
    @{ Id = 'verbose'; Group = 'System'; Name = 'Detailed messages at start and shut down'; After = ''
        Text = 'Instead of "Please wait", Windows says what it is doing, which shows what is slow.'
        Values = @((New-TweakValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'VerboseStatus' 'DWord' 1 $null)) }
    @{ Id = 'bsoddetails'; Group = 'System'; Name = 'Details on blue screens'; After = 'restart'
        Text = 'A blue screen also shows the technical details of the error, to look up what caused it.'
        Values = @((New-TweakValue 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' 'DWord' 1 $null)) }
    @{ Id = 'nohibernate'; Group = 'System'; Name = 'Turn off hibernation'; After = ''; Admin = $true
        Text = "Deletes hiberfil.sys, which takes space equal to a good share of the PC's memory$ExHiberText. Also turns off Hibernate and Fast Startup."
        Cmd = @{ Show = 'powercfg /hibernate'; On = 'off'; Off = 'on'
            Read = { if ([int](Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' -Name HibernateEnabled -ErrorAction SilentlyContinue).HibernateEnabled) { 'on' } else { 'off' } }
            Code = '& powercfg.exe /hibernate __STATE__; if ($LASTEXITCODE) { throw ("powercfg stopped with code " + $LASTEXITCODE) }' } }
)

# =====================================================================================================================
# The shortcuts: Run (and Args) opens it; File, when given, must be there (Group Policy and the like aren't on Windows
# Home). A shortcut on the desktop runs the same.
# =====================================================================================================================
$ExSys = Join-Path $env:SystemRoot 'System32'
$GodModeClsid = '{ED7BA470-8E54-465E-825C-99712043E01C}'
function New-ExtraTool([string]$Id, [string]$Group, [string]$Name, [string]$Text, [string]$Run, [string]$ToolArgs, [string]$File) {
    return @{ Id = $Id; Group = $Group; Name = $Name; Text = $Text; Run = $Run; Args = $ToolArgs; File = $File }
}
$ExtraTools = @(
    (New-ExtraTool 'godmode' 'Hidden classics' 'God Mode' "One folder with every setting from Control Panel, about 200 of them, by topic. On the desktop it's a folder named God Mode." 'explorer.exe' "shell:::$GodModeClsid" '')
    (New-ExtraTool 'netplwiz' 'Hidden classics' 'User accounts (classic)' 'Add users, change account types, and sign in automatically. The same as control userpasswords2.' "$ExSys\netplwiz.exe" '' "$ExSys\netplwiz.exe")
    (New-ExtraTool 'sysdm' 'Hidden classics' 'System Properties' "The PC's name, workgroup or domain, hardware, and remote access." "$ExSys\control.exe" 'sysdm.cpl' "$ExSys\sysdm.cpl")
    (New-ExtraTool 'sysadv' 'Hidden classics' 'Advanced system settings' 'Virtual memory, user profiles, and startup and recovery.' "$ExSys\SystemPropertiesAdvanced.exe" '' "$ExSys\SystemPropertiesAdvanced.exe")
    (New-ExtraTool 'envvars' 'Hidden classics' 'Environment variables' 'PATH and the other variables apps read.' "$ExSys\rundll32.exe" 'sysdm.cpl,EditEnvironmentVariables' "$ExSys\sysdm.cpl")
    (New-ExtraTool 'perfopts' 'Hidden classics' 'Performance options' 'Visual effects (animations, shadows) and processor scheduling.' "$ExSys\SystemPropertiesPerformance.exe" '' "$ExSys\SystemPropertiesPerformance.exe")
    (New-ExtraTool 'sysprot' 'Hidden classics' 'System Protection' 'Turn restore points on or off for each drive, and create one now.' "$ExSys\SystemPropertiesProtection.exe" '' "$ExSys\SystemPropertiesProtection.exe")
    (New-ExtraTool 'rstrui' 'Hidden classics' 'System Restore' 'Take the PC back to an earlier restore point.' "$ExSys\rstrui.exe" '' "$ExSys\rstrui.exe")
    (New-ExtraTool 'credman' 'Hidden classics' 'Credential Manager' 'The passwords Windows saved for websites, network shares and apps.' "$ExSys\control.exe" '/name Microsoft.CredentialManager' '')
    (New-ExtraTool 'deskicons' 'Hidden classics' 'Desktop icon settings' 'Show This PC, Recycle Bin, Control Panel and your user folder on the desktop.' "$ExSys\rundll32.exe" 'shell32.dll,Control_RunDLL desk.cpl,,0' "$ExSys\desk.cpl")
    (New-ExtraTool 'folderopts' 'Hidden classics' 'Folder Options' "File Explorer's classic options: what opens where, and what shows." "$ExSys\control.exe" 'folders' '')

    (New-ExtraTool 'control' 'Control Panel' 'Control Panel' 'All of Control Panel.' "$ExSys\control.exe" '' '')
    (New-ExtraTool 'appwiz' 'Control Panel' 'Programs and Features' 'The classic list of installed programs, with repair and change.' "$ExSys\control.exe" 'appwiz.cpl' "$ExSys\appwiz.cpl")
    (New-ExtraTool 'ncpa' 'Control Panel' 'Network Connections' 'Every network adapter: turn one off, rename it, or set its address and DNS.' "$ExSys\control.exe" 'ncpa.cpl' "$ExSys\ncpa.cpl")
    (New-ExtraTool 'netcenter' 'Control Panel' 'Network and Sharing Center' 'Network status, sharing settings and troubleshooting.' "$ExSys\control.exe" '/name Microsoft.NetworkAndSharingCenter' '')
    (New-ExtraTool 'mmsys' 'Control Panel' 'Sound (classic)' 'Every playback and recording device, its format and enhancements, and system sounds.' "$ExSys\control.exe" 'mmsys.cpl' "$ExSys\mmsys.cpl")
    (New-ExtraTool 'powercfg' 'Control Panel' 'Power Options' 'Power plans and what the power button and lid do.' "$ExSys\control.exe" 'powercfg.cpl' "$ExSys\powercfg.cpl")
    (New-ExtraTool 'mouse' 'Control Panel' 'Mouse properties' 'Buttons, double-click speed, pointers and pointer options.' "$ExSys\control.exe" 'main.cpl' "$ExSys\main.cpl")
    (New-ExtraTool 'inetcpl' 'Control Panel' 'Internet Options' 'Proxy, certificates and security zones that many apps still use.' "$ExSys\control.exe" 'inetcpl.cpl' "$ExSys\inetcpl.cpl")
    (New-ExtraTool 'intl' 'Control Panel' 'Region (classic)' 'Date, time and number formats, and the language for programs that are not Unicode.' "$ExSys\control.exe" 'intl.cpl' "$ExSys\intl.cpl")
    (New-ExtraTool 'timedate' 'Control Panel' 'Date and Time (classic)' 'Extra clocks and the internet time server.' "$ExSys\control.exe" 'timedate.cpl' "$ExSys\timedate.cpl")
    (New-ExtraTool 'wintools' 'Control Panel' 'Windows Tools' "The folder with Windows' administrative tools." "$ExSys\control.exe" 'admintools' '')

    (New-ExtraTool 'compmgmt' 'Management consoles' 'Computer Management' 'Disks, devices, services, event logs, users and shared folders in one window.' "$ExSys\compmgmt.msc" '' "$ExSys\compmgmt.msc")
    (New-ExtraTool 'devmgmt' 'Management consoles' 'Device Manager' 'Every device and its driver.' "$ExSys\devmgmt.msc" '' "$ExSys\devmgmt.msc")
    (New-ExtraTool 'diskmgmt' 'Management consoles' 'Disk Management' 'Partitions and volumes: create, resize, format, change drive letters.' "$ExSys\diskmgmt.msc" '' "$ExSys\diskmgmt.msc")
    (New-ExtraTool 'eventvwr' 'Management consoles' 'Event Viewer' "Windows' logs: errors, warnings and what happened when." "$ExSys\eventvwr.msc" '' "$ExSys\eventvwr.msc")
    (New-ExtraTool 'services' 'Management consoles' 'Services' 'Background services: start, stop, and how each starts.' "$ExSys\services.msc" '' "$ExSys\services.msc")
    (New-ExtraTool 'taskschd' 'Management consoles' 'Task Scheduler' 'Tasks Windows and apps run on a schedule.' "$ExSys\taskschd.msc" '' "$ExSys\taskschd.msc")
    (New-ExtraTool 'perfmon' 'Management consoles' 'Performance Monitor' 'Live counters and reports on how the PC performs.' "$ExSys\perfmon.msc" '' "$ExSys\perfmon.msc")
    (New-ExtraTool 'certmgr' 'Management consoles' 'Certificates (your account)' 'The certificates your account trusts and uses.' "$ExSys\certmgr.msc" '' "$ExSys\certmgr.msc")
    (New-ExtraTool 'wfmsc' 'Management consoles' 'Firewall with Advanced Security' 'Every inbound and outbound firewall rule.' "$ExSys\wf.msc" '' "$ExSys\wf.msc")
    (New-ExtraTool 'fsmgmt' 'Management consoles' 'Shared Folders' 'What this PC shares on the network, and who is connected.' "$ExSys\fsmgmt.msc" '' "$ExSys\fsmgmt.msc")
    (New-ExtraTool 'lusrmgr' 'Management consoles' 'Local Users and Groups' 'Accounts and groups on this PC. Not on Windows Home.' "$ExSys\lusrmgr.msc" '' "$ExSys\lusrmgr.msc")
    (New-ExtraTool 'gpedit' 'Management consoles' 'Group Policy' "Windows' policies for this PC and its users. Not on Windows Home." "$ExSys\gpedit.msc" '' "$ExSys\gpedit.msc")
    (New-ExtraTool 'secpol' 'Management consoles' 'Local Security Policy' 'Password, audit and user rights policies. Not on Windows Home.' "$ExSys\secpol.msc" '' "$ExSys\secpol.msc")

    (New-ExtraTool 'msconfig' 'System tools' 'System Configuration' 'Boot options and safe mode.' "$ExSys\msconfig.exe" '' "$ExSys\msconfig.exe")
    (New-ExtraTool 'msinfo32' 'System tools' 'System Information' 'Everything about the hardware and Windows, in detail.' "$ExSys\msinfo32.exe" '' "$ExSys\msinfo32.exe")
    (New-ExtraTool 'regedit' 'System tools' 'Registry Editor' "Windows' settings database. Changes there take effect right away and can't be undone." "$env:SystemRoot\regedit.exe" '' "$env:SystemRoot\regedit.exe")
    (New-ExtraTool 'resmon' 'System tools' 'Resource Monitor' 'What uses the processor, memory, disk and network, process by process.' "$ExSys\resmon.exe" '' "$ExSys\resmon.exe")
    (New-ExtraTool 'reliability' 'System tools' 'Reliability Monitor' 'A day-by-day history of crashes, failed updates and installs.' "$ExSys\perfmon.exe" '/rel' "$ExSys\perfmon.exe")
    (New-ExtraTool 'dxdiag' 'System tools' 'DirectX Diagnostic Tool' 'Graphics and sound details, often asked for by game support.' "$ExSys\dxdiag.exe" '' "$ExSys\dxdiag.exe")
    (New-ExtraTool 'mdsched' 'System tools' 'Windows Memory Diagnostic' 'Tests the memory for errors. It asks before restarting.' "$ExSys\MdSched.exe" '' "$ExSys\MdSched.exe")
    (New-ExtraTool 'recoverydrive' 'System tools' 'Recovery Drive' 'Makes a USB drive that can repair or reinstall Windows.' "$ExSys\RecoveryDrive.exe" '' "$ExSys\RecoveryDrive.exe")
    (New-ExtraTool 'odbc' 'System tools' 'ODBC Data Sources' 'Database connections that apps use.' "$ExSys\odbcad32.exe" '' "$ExSys\odbcad32.exe")
    (New-ExtraTool 'charmap' 'System tools' 'Character Map' 'Every character in a font, to copy.' "$ExSys\charmap.exe" '' "$ExSys\charmap.exe")
    (New-ExtraTool 'mstsc' 'System tools' 'Remote Desktop Connection' 'Connect to another PC with Remote Desktop.' "$ExSys\mstsc.exe" '' "$ExSys\mstsc.exe")

    (New-ExtraTool 'startupfolder' 'Folders' 'Startup folder' 'Shortcuts here start when you sign in.' 'explorer.exe' 'shell:startup' '')
    (New-ExtraTool 'commonstartup' 'Folders' 'Startup folder (all users)' 'Shortcuts here start when anyone signs in.' 'explorer.exe' '"shell:common startup"' '')
    (New-ExtraTool 'sendto' 'Folders' 'Send to folder' 'What the right-click Send to menu lists.' 'explorer.exe' 'shell:sendto' '')
    (New-ExtraTool 'appsfolder' 'Folders' 'All apps folder' 'Every app, Store apps included, as icons you can drag to the desktop.' 'explorer.exe' 'shell:AppsFolder' '')
    (New-ExtraTool 'fonts' 'Folders' 'Fonts folder' 'The installed fonts.' 'explorer.exe' 'shell:fonts' '')
    (New-ExtraTool 'hosts' 'Folders' 'hosts file folder' 'Where the hosts file is. Changing it needs Notepad run as administrator.' 'explorer.exe' "$ExSys\drivers\etc" "$ExSys\drivers\etc")
)

# =====================================================================================================================
# The registry, through .NET in the 64-bit view (what Windows itself reads, whichever way this app was built)
# =====================================================================================================================
# A list of changes: Do = set (Kind, Data), del (a value), delkey (a key and everything under it). It also runs in the
# administrator script for HKLM and HKU (its text is copied there), so it uses nothing else from this app.
function Invoke-RegOps {
    param($Ops)
    foreach ($o in @($Ops)) {
        # a command tweak's command (powercfg)
        if ($o.Do -eq 'cmd') { & ([scriptblock]::Create([string]$o.Code)); continue }
        $path = [string]$o.Path
        $i = $path.IndexOf('\')
        $hive = switch ($path.Substring(0, $i)) { 'HKLM' { 'LocalMachine' } 'HKU' { 'Users' } default { 'CurrentUser' } }
        $sub = $path.Substring($i + 1)
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
        try {
            if ($o.Do -eq 'delkey') { $base.DeleteSubKeyTree($sub, $false) }
            elseif ($o.Do -eq 'del') {
                $k = $base.OpenSubKey($sub, $true)
                if ($k) { try { $k.DeleteValue([string]$o.Name, $false) } finally { $k.Close() } }
            }
            else {
                $kind = [Microsoft.Win32.RegistryValueKind][string]$o.Kind
                $data = switch ([string]$kind) {
                    'DWord' { [int]$o.Data } 'QWord' { [long]$o.Data } 'MultiString' { [string[]]@($o.Data) } 'Binary' { [byte[]]@($o.Data) } default { [string]$o.Data }
                }
                # CreateSubKey opens a key that's already there as it is
                $k = $base.CreateSubKey($sub)
                try { $k.SetValue([string]$o.Name, $data, $kind) } finally { $k.Close() }
            }
        }
        finally { $base.Close() }
    }
}
function Open-RegKey([string]$Path) {
    $i = $Path.IndexOf('\')
    $hive = switch ($Path.Substring(0, $i)) { 'HKLM' { 'LocalMachine' } 'HKU' { 'Users' } default { 'CurrentUser' } }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
    try { return $base.OpenSubKey($Path.Substring($i + 1)) } finally { $base.Close() }
}
function Test-RegKey([string]$Path) { $k = Open-RegKey $Path; if ($k) { $k.Close(); return $true } return $false }
# A value as it is now: whether it's there, its type and data (a list of numbers for binary data)
function Get-RegValue([string]$Path, [string]$Name) {
    $k = Open-RegKey $Path
    if (-not $k) { return @{ Path = $Path; Name = $Name; Existed = $false } }
    try {
        $v = $k.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $v) { return @{ Path = $Path; Name = $Name; Existed = $false } }
        $kind = [string]$k.GetValueKind($Name)
        if ($v -is [byte[]]) { $v = [int[]]$v }
        return @{ Path = $Path; Name = $Name; Existed = $true; Kind = $kind; Data = $v }
    }
    finally { $k.Close() }
}
# The highest key on the way to Path that isn't there (so that creating Path creates it), or $null
function Get-MissingRegRoot([string]$Path) {
    $parts = $Path.Split('\')
    for ($n = 2; $n -le $parts.Count; $n++) {
        $p = $parts[0..($n - 1)] -join '\'
        if (-not (Test-RegKey $p)) { return $p }
    }
    return $null
}
function Test-RegSame($Now, $Want) {
    if (-not $Now.Existed) { return $null -eq $Want }
    if ($null -eq $Want) { return $false }
    return (@($Now.Data) -join ',') -eq (@($Want) -join ',')
}

# =====================================================================================================================
# What was saved (tweaks.json): per tweak, the values as they were and the keys it created; per shortcut, the file it
# put on the desktop
# =====================================================================================================================
# The plain reason, without PowerShell's "Exception calling ... with 1 argument(s)" around it
function Get-ExtraError($Err) { $e = $Err.Exception; while ($e.InnerException) { $e = $e.InnerException }; return $e.Message }
$script:ExStore = $null
function Read-ExtrasStore {
    if ($script:ExStore) { return }
    $s = @{ Tweaks = @{}; Tools = @{} }
    try {
        if (Test-Path -LiteralPath $ExtrasPath) {
            $j = [IO.File]::ReadAllText($ExtrasPath) | ConvertFrom-Json
            if ($j.Tweaks) { foreach ($p in $j.Tweaks.PSObject.Properties) { $s.Tweaks[$p.Name] = $p.Value } }
            if ($j.Tools) { foreach ($p in $j.Tools.PSObject.Properties) { $s.Tools[$p.Name] = [string]$p.Value } }
        }
    }
    catch { Add-LogLine "Extras: couldn't read ${ExtrasPath}: $($_.Exception.Message)" }
    $script:ExStore = $s
}
function Save-ExtrasStore {
    $o = [pscustomobject]@{ Tweaks = [pscustomobject]$script:ExStore.Tweaks; Tools = [pscustomobject]$script:ExStore.Tools }
    try { New-Item -ItemType Directory -Path $DataDir -Force | Out-Null; [IO.File]::WriteAllText($ExtrasPath, ($o | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false))) }
    catch { Add-LogLine "Extras: couldn't save ${ExtrasPath}: $($_.Exception.Message)" }
}
function Get-ExtraTweak([string]$Id) { return $ExtraTweaks | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }
function Get-ExtraTool([string]$Id) { return $ExtraTools | Where-Object { $_.Id -eq $Id } | Select-Object -First 1 }
function Test-TweakAdmin($T) {
    if ($T.Cmd) { return [bool]$T.Admin }
    return @($T.Values | Where-Object { $_.Path -notlike 'HKCU\*' }).Count -gt 0
}
# A command tweak's state now ('' when it can't be read), and the change that sets one
function Get-TweakState($T) { try { return [string](& $T.Cmd.Read) } catch { return '' } }
function Get-TweakCmdOp($T, [string]$State) { return @{ Do = 'cmd'; Code = $T.Cmd.Code.Replace('__STATE__', $State) } }

# Before the first change: every value the tweak touches, as it is, and the keys turning it on would create (for a
# command tweak, its state and the command that sets it back)
function New-TweakBackup($T) {
    if ($T.Cmd) { $s = Get-TweakState $T; return @{ Time = (Get-Date).ToString('o'); Id = $T.Id; State = $s; Code = $(if ($s) { (Get-TweakCmdOp $T $s).Code } else { '' }); Values = @(); Created = @() } }
    $vals = @(foreach ($v in $T.Values) { Get-RegValue $v.Path $v.Name })
    $created = @($T.Values | ForEach-Object { $_.Path } | Select-Object -Unique | ForEach-Object { Get-MissingRegRoot $_ } | Where-Object { $_ } | Select-Object -Unique)
    return @{ Time = (Get-Date).ToString('o'); Values = $vals; Created = $created }
}
function Get-TweakOps($T, [bool]$On) {
    if ($T.Cmd) { return , @(Get-TweakCmdOp $T $(if ($On) { $T.Cmd.On } else { $T.Cmd.Off })) }
    $ops = @(foreach ($v in $T.Values) {
            $d = if ($On) { $v.On } else { $v.Off }
            if ($null -eq $d) { @{ Do = 'del'; Path = $v.Path; Name = $v.Name } } else { @{ Do = 'set'; Path = $v.Path; Name = $v.Name; Kind = $v.Kind; Data = $d } }
        })
    if (-not $On -and $T.OffKey) { $ops += @{ Do = 'delkey'; Path = $T.OffKey } }
    return , $ops
}
# Back as it was: the keys it created go (with what's in them), the values that were there come back, the rest go
function Get-RestoreOps($Backup) {
    if ($Backup.Code) { return , @(@{ Do = 'cmd'; Code = [string]$Backup.Code }) }
    $ops = @(foreach ($c in @($Backup.Created)) { if ($c) { @{ Do = 'delkey'; Path = [string]$c } } })
    foreach ($v in @($Backup.Values)) {
        if (-not $v) { continue }
        if ($v.Existed) { $ops += @{ Do = 'set'; Path = [string]$v.Path; Name = [string]$v.Name; Kind = [string]$v.Kind; Data = $v.Data } }
        else { $ops += @{ Do = 'del'; Path = [string]$v.Path; Name = [string]$v.Name } }
    }
    return , $ops
}
# Is everything as it was before this app changed it? (then there's nothing to restore)
function Test-TweakAsSaved($Backup) {
    if ($Backup.Id) { $t = Get-ExtraTweak ([string]$Backup.Id); if ($t -and $t.Cmd) { return (Get-TweakState $t) -eq [string]$Backup.State } }
    foreach ($c in @($Backup.Created)) { if ($c -and (Test-RegKey ([string]$c))) { return $false } }
    foreach ($v in @($Backup.Values)) {
        if (-not $v) { continue }
        $now = Get-RegValue ([string]$v.Path) ([string]$v.Name)
        if ([bool]$now.Existed -ne [bool]$v.Existed) { return $false }
        if ($v.Existed -and -not (Test-RegSame $now $v.Data)) { return $false }
    }
    return $true
}
function Test-TweakOn($T) {
    if ($T.Cmd) { return (Get-TweakState $T) -eq $T.Cmd.On }
    foreach ($v in $T.Values) { if (-not (Test-RegSame (Get-RegValue $v.Path $v.Name) $v.On)) { return $false } }
    return $true
}

# The administrator script for HKLM and HKU: this file's Invoke-RegOps, and the changes as JSON
function Get-RegOpsScript($Ops, [string]$Text) {
    $json = ConvertTo-Json -InputObject @($Ops) -Depth 6 -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
    return "function Invoke-RegOps {`r`n$(${function:Invoke-RegOps})`r`n}`r`nSay '$($Text -replace "'", "''")'`r`n" +
    "`$ops = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$b64')) | ConvertFrom-Json`r`nInvoke-RegOps `$ops`r`nSay 'Done.'`r`nexit 0"
}

# =====================================================================================================================
# The rows
# =====================================================================================================================
function Get-DesktopPath([string]$Id) {
    $desk = [Environment]::GetFolderPath('Desktop')
    if ($Id -eq 'godmode') { return Join-Path $desk "God Mode.$GodModeClsid" }
    $t = Get-ExtraTool $Id
    return Join-Path $desk "$($t.Name -replace '[\\/:*?"<>|]', '').lnk"
}
function Update-ExtraItem($X) {
    Read-ExtrasStore
    if ($X.IsTweak) {
        $t = Get-ExtraTweak $X.Id
        $X.On = Test-TweakOn $t
        $X.Saved = $script:ExStore.Tweaks.ContainsKey($X.Id)
    }
    else {
        $p = Get-DesktopPath $X.Id
        $X.On = Test-Path -LiteralPath $p
        $X.Saved = $X.On -and $script:ExStore.Tools[$X.Id] -eq $p
    }
}
function Initialize-Extras {
    if ($ExtraItems.Count) { return }
    # SortKey: the category's place, then 000 for its header row and the item's place after it
    $groups = @{}
    $sortKey = {
        param([string]$Kind, [string]$Group)
        $g = "$Kind|$Group"
        if (-not $groups.ContainsKey($g)) {
            $groups[$g] = $groups.Count + 1
            $h = New-Object WingetUM.ExtraItem
            $h.Kind = "${Kind}group"; $h.Id = $g; $h.Group = $Group; $h.Name = $Group; $h.SortKey = '{0:D2}-000' -f $groups[$g]
            $ExtraItems.Add($h)
        }
        return '{0:D2}-{1:D3}' -f $groups[$g], (++$script:ExSortN)
    }
    $script:ExSortN = 0
    foreach ($t in $ExtraTweaks) {
        $x = New-Object WingetUM.ExtraItem
        $x.Kind = 'tweak'; $x.Id = $t.Id; $x.Group = $t.Group; $x.Name = $t.Name; $x.Description = $t.Text; $x.SortKey = & $sortKey 'tweak' $t.Group
        if ($t.Cmd) {
            $x.SubText = $t.Cmd.Show
            if ($t.Cmd.Test) { $x.Available = try { [bool](& $t.Cmd.Test) } catch { $false } }
        }
        else { $x.SubText = @($t.Values | ForEach-Object { if ($_.Name) { $_.Path + ': ' + $_.Name } else { $_.Path } } | Select-Object -Unique) -join '; ' }
        $x.NeedsAdmin = Test-TweakAdmin $t
        $ExtraItems.Add($x)
    }
    foreach ($t in $ExtraTools) {
        $x = New-Object WingetUM.ExtraItem
        $x.Kind = 'tool'; $x.Id = $t.Id; $x.Group = $t.Group; $x.Name = $t.Name; $x.Description = $t.Text; $x.SortKey = & $sortKey 'tool' $t.Group
        $x.SubText = (@([IO.Path]::GetFileName($t.Run), $t.Args) | Where-Object { $_ }) -join ' '
        $x.Available = (-not $t.File) -or (Test-Path -LiteralPath $t.File)
        $ExtraItems.Add($x)
    }
}
# Each header: what's in its category ("10 tweaks, 3 on, 1 changed by this app"), and its chevron open while filtering
function Update-ExtraHeaders {
    $filtering = Test-ExtraFiltering
    foreach ($h in @($ExtraItems | Where-Object { $_.IsHeader })) {
        $kind = $h.Kind.Replace('group', '')
        $in = @($ExtraItems | Where-Object { $_.Kind -eq $kind -and $_.Group -eq $h.Group })
        $saved = @($in | Where-Object { $_.Saved }).Count
        $parts = if ($kind -eq 'tweak') { @("$($in.Count) tweak$(if ($in.Count -ne 1) { 's' })", "$(@($in | Where-Object { $_.On }).Count) on") }
        else { @("$($in.Count) shortcut$(if ($in.Count -ne 1) { 's' })") }
        if ($saved) { $parts += "$saved changed by this app" }
        $h.HeaderNote = $parts -join ', '
        $h.IsExpanded = $filtering -or [bool]$script:ExExpanded[$h.Id]
    }
}
function Set-ExtraExpanded([string]$Key, [bool]$Open) {
    $script:ExExpanded[$Key] = $Open
    Update-ExtraHeaders
    $ExtraView.Refresh()
}
function Update-ExtraStates {
    $script:ExStore = $null
    Initialize-Extras
    foreach ($x in @($ExtraItems | Where-Object { -not $_.IsHeader })) { if (-not $x.IsBusy) { try { Update-ExtraItem $x } catch { Add-LogLine "Extras: couldn't read $($x.Name): $($_.Exception.Message)" } } }
    $ExtraView.Refresh()
    Update-View
}

$ExAfterText = @{ explorer = '. Restart Explorer to see it'; signout = '. Sign out and in to see it'; restart = '. Restart to finish' }
$script:ExExplorerWaiting = $false
# A change made (or not): save what was there the first time, and forget it once everything is as it was again
function Complete-TweakChange($X, [string]$Mode, $Backup, [string]$Problem) {
    $t = Get-ExtraTweak $X.Id
    Read-ExtrasStore
    if ($Problem) { $X.State = 'error'; $X.Detail = "Didn't change: $Problem" }
    else {
        if ($Mode -eq 'restore') { [void]$script:ExStore.Tweaks.Remove($X.Id) }
        elseif (-not $script:ExStore.Tweaks.ContainsKey($X.Id)) { $script:ExStore.Tweaks[$X.Id] = $Backup }
        $saved = $script:ExStore.Tweaks[$X.Id]
        if ($saved -and (Test-TweakAsSaved $saved)) { [void]$script:ExStore.Tweaks.Remove($X.Id) }
        Save-ExtrasStore
        $after = [string]$t.After
        if ($after -eq 'explorer') { $script:ExExplorerWaiting = $true }
        $X.Detail = $(switch ($Mode) { 'on' { 'Turned on' } 'off' { 'Turned off' } default { 'Restored' } }) + [string]$ExAfterText[$after]
        $X.State = if ($after) { 'reboot' } else { 'ok' }
    }
    Update-ExtraItem $X
    Add-History $(switch ($Mode) { 'on' { 'tweakon' } 'off' { 'tweakoff' } default { 'tweakrestore' } }) $X.Name $X.Id '' '' $X.State $X.Detail
    $script:LastSummary = "$($X.Name): $($X.Detail)"
}

function Start-TweakOps($X, [string]$Mode, $Ops, $Backup) {
    $t = Get-ExtraTweak $X.Id
    if (Test-TweakAdmin $t) {
        if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first"; Update-View; return }
        $X.State = 'running'; $X.Detail = if ($IsAdmin) { 'Working' + $Ellipsis } else { 'Waiting for approval' + $Ellipsis }
        $verb = switch ($Mode) { 'on' { 'Turning on' } 'off' { 'Turning off' } default { 'Restoring' } }
        Start-Elevated 'tweak' "$verb $($X.Name)" (Get-RegOpsScript $Ops "$verb $($X.Name)$Ellipsis") @() @{ Items = @($X); Mode = $Mode; Backups = @{ $X.Id = $Backup } } -RestorePoint -RestoreText 'Before changing Windows settings'
    }
    else {
        $err = $null
        try { Invoke-RegOps $Ops } catch { $err = $(Get-ExtraError $_) }
        Complete-TweakChange $X $Mode $Backup $err
    }
    $ExtraView.Refresh()
    Update-View
}
$ElevHandlers.tweak = {
    param($Ev, $why, $code, $last, $tag)
    $err = if ($why) { $why } elseif ($code -ne 0) { "the administrator step stopped$(if ($last) { ": $last" })" } else { $null }
    foreach ($x in @($tag.Items)) { Complete-TweakChange $x $tag.Mode $tag.Backups[$x.Id] $err }
    $ExtraView.Refresh()
}

function Set-Tweak($X, [bool]$On) {
    $t = Get-ExtraTweak $X.Id
    Read-ExtrasStore
    $backup = if ($script:ExStore.Tweaks.ContainsKey($X.Id)) { $null } else { New-TweakBackup $t }
    Start-TweakOps $X $(if ($On) { 'on' } else { 'off' }) (Get-TweakOps $t $On) $backup
}
function Restore-Tweak($X) {
    Read-ExtrasStore
    $b = $script:ExStore.Tweaks[$X.Id]
    if (-not $b) { return }
    Start-TweakOps $X 'restore' (Get-RestoreOps $b) $null
}

# ---- Shortcuts: open, add to the desktop, and remove what this app added
function Open-ExtraTool($X) {
    $t = Get-ExtraTool $X.Id
    try {
        if ($t.Args) { Start-Process -FilePath $t.Run -ArgumentList $t.Args } else { Start-Process -FilePath $t.Run }
        $script:LastSummary = "Opened $($t.Name)"
    }
    catch { $script:LastSummary = "Couldn't open $($t.Name): $(Get-ExtraError $_)" }
    Update-View
}
function Add-ExtraToolToDesktop($X) {
    $t = Get-ExtraTool $X.Id
    $p = Get-DesktopPath $X.Id
    try {
        if (Test-Path -LiteralPath $p) { throw 'Something with that name is already on the desktop' }
        if ($X.Id -eq 'godmode') { New-Item -ItemType Directory -Path $p -ErrorAction Stop | Out-Null }
        else {
            $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($p)
            $sh.TargetPath = $t.Run
            if ($t.Args) { $sh.Arguments = $t.Args }
            $sh.Description = $t.Text
            $sh.Save()
        }
        Read-ExtrasStore
        $script:ExStore.Tools[$X.Id] = $p
        Save-ExtrasStore
        $X.State = 'ok'; $X.Detail = 'Added to the desktop'
        Add-History 'tweakon' "$($t.Name) (desktop shortcut)" $X.Id '' '' 'ok' 'Added to the desktop'
    }
    catch { $X.State = 'error'; $X.Detail = "Not added: $(Get-ExtraError $_)" }
    Update-ExtraItem $X
    $script:LastSummary = "$($t.Name): $($X.Detail)"
}
function Remove-ExtraToolFromDesktop($X, [switch]$Quiet) {
    $t = Get-ExtraTool $X.Id
    Read-ExtrasStore
    $p = $script:ExStore.Tools[$X.Id]
    if (-not $p) { return }
    try {
        if (Test-Path -LiteralPath $p) {
            if ($X.Id -eq 'godmode') {
                # God Mode is an empty folder that Windows marks read-only (which stops a delete); one with something
                # put in it since isn't removed
                if ([IO.Directory]::GetFileSystemEntries($p).Count) { throw 'Something was put in the God Mode folder; move it out first' }
                $d = New-Object IO.DirectoryInfo $p
                $d.Attributes = $d.Attributes -band (-bnot [IO.FileAttributes]::ReadOnly)
                $d.Delete()
            }
            else { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
        }
        [void]$script:ExStore.Tools.Remove($X.Id)
        Save-ExtrasStore
        $X.State = 'ok'; $X.Detail = 'Removed from the desktop'
        Add-History 'tweakoff' "$($t.Name) (desktop shortcut)" $X.Id '' '' 'ok' 'Removed from the desktop'
    }
    catch { $X.State = 'error'; $X.Detail = "Not removed: $(Get-ExtraError $_)" }
    Update-ExtraItem $X
    if (-not $Quiet) { $script:LastSummary = "$($t.Name): $($X.Detail)" }
}

# ---- Restore all: the desktop shortcuts and the tweaks for your account here, the rest in one administrator step
function Request-RestoreAll {
    Read-ExtrasStore
    $n = $script:ExStore.Tweaks.Count + $script:ExStore.Tools.Count
    if (-not $n) { return }
    if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish first"; Update-View; return }
    $bullet = '  ' + [char]0x2022 + ' '
    $names = @($ExtraItems | Where-Object { $_.Saved } | ForEach-Object { if ($_.IsTweak) { $bullet + $_.Name } else { $bullet + $_.Name + ' (desktop shortcut)' } })
    $text = "Everything this app changed on the Extras tab goes back to how it was before:`n" + (($names | Select-Object -First 14) -join "`n")
    if ($names.Count -gt 14) { $text += "`n  and $($names.Count - 14) more" }
    if (@($ExtraItems | Where-Object { $_.Saved -and $_.NeedsAdmin }).Count) { $text += "`n`nSome are Windows-wide settings, so Windows asks for administrator approval." }
    Show-Confirm 'exrestoreall' $null "Restore $n change$(if ($n -ne 1) { 's' })?" $text 'Restore all'
}
$ConfirmHandlers.exrestoreall = {
    param($Payload)
    Read-ExtrasStore
    foreach ($x in @($ExtraItems | Where-Object { $_.IsTool -and $_.Saved })) { Remove-ExtraToolFromDesktop $x -Quiet }
    $elevItems = New-Object System.Collections.Generic.List[object]
    $ops = @()
    foreach ($x in @($ExtraItems | Where-Object { $_.IsTweak -and $script:ExStore.Tweaks.ContainsKey($_.Id) })) {
        $r = Get-RestoreOps $script:ExStore.Tweaks[$x.Id]
        if ($x.NeedsAdmin) { $elevItems.Add($x); $ops += $r }
        else {
            $err = $null
            try { Invoke-RegOps $r } catch { $err = $(Get-ExtraError $_) }
            Complete-TweakChange $x 'restore' $null $err
        }
    }
    if ($elevItems.Count) {
        foreach ($x in $elevItems) { $x.State = 'running'; $x.Detail = if ($IsAdmin) { 'Working' + $Ellipsis } else { 'Waiting for approval' + $Ellipsis } }
        Start-Elevated 'tweak' 'Restoring Windows settings' (Get-RegOpsScript $ops "Restoring $($elevItems.Count) Windows setting(s)$Ellipsis") @() @{ Items = $elevItems.ToArray(); Mode = 'restore'; Backups = @{} } -RestorePoint -RestoreText 'Before restoring Windows settings'
    }
    $script:LastSummary = 'Restored what this app changed on the Extras tab'
    $ExtraView.Refresh()
    Update-View
}

# ---- Restart Explorer: Windows starts it again by itself; if it hasn't after a few seconds, this app does
$ConfirmHandlers.exrestartexplorer = {
    param($Payload)
    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
        $script:ExExplorerWaiting = $false
        $script:LastSummary = 'Restarted File Explorer'
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(4)
        $timer.Add_Tick({ $timer.Stop(); if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { try { Start-Process explorer.exe } catch { } } }.GetNewClosure())
        $timer.Start()
    }
    catch { $script:LastSummary = "Couldn't restart File Explorer: $(Get-ExtraError $_)" }
    foreach ($x in @($ExtraItems | Where-Object { $_.State -eq 'reboot' -and $_.Detail -like '*Restart Explorer*' })) { $x.Detail = $x.Detail.Replace($ExAfterText.explorer, ''); $x.State = 'ok' }
    Update-View
}

function Update-ExtrasView {
    $tools = [bool]$UI.ExViewTools.IsChecked
    Update-ExtraHeaders
    $heads = @($ExtraItems | Where-Object { $_.Kind -eq $(if ($tools) { 'toolgroup' } else { 'tweakgroup' }) })
    $allOpen = $heads.Count -and -not @($heads | Where-Object { -not $script:ExExpanded[$_.Id] }).Count
    $UI.ExExpandAllText.Text = if ($allOpen) { 'Collapse all' } else { 'Expand all' }
    $UI.ExExpandAll.IsEnabled = -not (Test-ExtraFiltering)
    $tw = @($ExtraItems | Where-Object { $_.IsTweak })
    $on = @($tw | Where-Object { $_.On }).Count
    $toolCount = @($ExtraItems | Where-Object { $_.IsTool -and $_.Available }).Count
    $saved = @($ExtraItems | Where-Object { $_.Saved }).Count
    $UI.ExViewTweaksText.Text = if ($tw.Count) { "Tweaks ($on of $($tw.Count) on)" } else { 'Tweaks' }
    $UI.ExViewToolsText.Text = if ($toolCount) { "Shortcuts ($toolCount)" } else { 'Shortcuts' }
    $UI.ExHeadName.Text = if ($tools) { 'SHORTCUT' } else { 'TWEAK' }
    $UI.ExHeadStatus.Text = if ($tools) { '' } else { 'STATUS' }
    $UI.ExText.Text = if ($tools) { "Windows' hidden tools and folders: open one, or add it to the desktop. Remove from desktop takes away only what this app added." }
    else { "Windows settings with no switch in Settings. The first time one changes, what was there is saved: Restore puts it back exactly, and Restore all undoes everything here.$(if ($script:ExExplorerWaiting) { ' Restart Explorer to see the changes to File Explorer and the taskbar.' })" }
    $UI.ExRestoreAll.IsEnabled = $saved -gt 0 -and -not $script:Elev
    $UI.ExRestoreAllText.Text = if ($saved) { "Restore all ($saved)" } else { 'Restore all' }
    $UI.ExRestartExplorer.Style = $Window.FindResource($(if ($script:ExExplorerWaiting) { 'Primary' } else { 'Ghost' }))
    $msg = $null
    if (-not @($ExtraView).Count) {
        $msg = if ($UI.ExChangedOnly.IsChecked -and -not $UI.ExSearch.Text.Trim()) { @{ Title = 'Nothing changed here yet'; Text = "What this app changes shows here, ready to restore." } } else { @{ Title = 'Nothing matches'; Text = '' } }
    }
    $UI.ExHeader.Visibility = ConvertTo-Visibility (-not $msg)
    $UI.ExList.Visibility = if ($msg) { 'Collapsed' } else { 'Visible' }
    $UI.ExMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) { $UI.ExMsgTitle.Text = $msg.Title; $UI.ExMsgText.Text = $msg.Text }
}

# Tweaks or Shortcuts: the other list, from its top
function Show-ExtraView {
    $ExtraView.Refresh()
    $first = @($ExtraView) | Select-Object -First 1
    if ($first) { $UI.ExList.ScrollIntoView($first) }
    Update-View
}

$Panels.extras = @{
    Panel   = 'ExtrasPanel'
    Update  = { Update-ExtrasView }
    Status  = {
        $on = @($ExtraItems | Where-Object { $_.IsTweak -and $_.On }).Count
        $saved = @($ExtraItems | Where-Object { $_.Saved }).Count
        if ($ExtraItems.Count) { "$on tweak$(if ($on -ne 1) { 's' }) on"; if ($saved) { "$saved changed by this app" } }
    }
    Open    = { if (-not $ExtraItems.Count) { Update-ExtraStates } }
    Refresh = { Update-ExtraStates }
}

$UI.TabExtras.Add_Checked({ Set-Section 'extras' })
$UI.ExRefresh.Add_Click({ Update-ExtraStates })
$UI.ExRestoreAll.Add_Click({ Request-RestoreAll })
$UI.ExRestartExplorer.Add_Click({ Show-Confirm 'exrestartexplorer' $null 'Restart File Explorer?' "File Explorer and the taskbar close and start again, so changes to them show. Open File Explorer windows close; your files and other apps aren't affected." 'Restart Explorer' })
$UI.ExViewTweaks.Add_Click({ Show-ExtraView })
$UI.ExViewTools.Add_Click({ Show-ExtraView })
$UI.ExChangedOnly.Add_Click({ $ExtraView.Refresh(); Update-View })
$UI.ExExpandAll.Add_Click({
        $open = $UI.ExExpandAllText.Text -eq 'Expand all'
        $kind = if ($UI.ExViewTools.IsChecked) { 'toolgroup' } else { 'tweakgroup' }
        foreach ($h in @($ExtraItems | Where-Object { $_.Kind -eq $kind })) { $script:ExExpanded[$h.Id] = $open }
        Update-ExtraHeaders
        Show-ExtraView
    })
$script:ExSearchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:ExSearchTimer.Interval = [TimeSpan]::FromMilliseconds(180)
$script:ExSearchTimer.Add_Tick({ $script:ExSearchTimer.Stop(); $ExtraView.Refresh(); Update-View })
$UI.ExSearch.Add_TextChanged({ $script:ExSearchTimer.Stop(); $script:ExSearchTimer.Start() })
$UI.ExList.AddHandler([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent, [System.Windows.RoutedEventHandler] {
        param($s, $e)
        $src = $e.OriginalSource
        if ($src -isnot [System.Windows.Controls.Button]) { return }
        $x = $src.DataContext
        # a category's header: open or close it (while filtering, every match already shows in its open category)
        if ($src.Tag -eq 'exgroup') {
            if (-not (Test-ExtraFiltering)) { Set-ExtraExpanded $x.Id (-not $script:ExExpanded[$x.Id]) }
        }
        elseif ($src.Tag -eq 'exaction') {
            if ($x.IsTweak) { Set-Tweak $x (-not $x.On) } else { Open-ExtraTool $x }
        }
        elseif ($src.Tag -eq 'exaction2') {
            if ($x.IsTweak) { Restore-Tweak $x }
            elseif ($x.On) { Remove-ExtraToolFromDesktop $x }
            else { Add-ExtraToolToDesktop $x }
        }
        $ExtraView.Refresh()
        Update-View
    })

# Windows Manager - Settings (part of src\; see Windows_Manager.ps1)

$DataDir = Join-Path $env:LOCALAPPDATA 'WindowsManager'
# Earlier names of this app kept their settings and logs here; the newest one found moves across once
foreach ($old in @((Join-Path $env:LOCALAPPDATA 'WindowsSoftwareManager'), (Join-Path $env:LOCALAPPDATA 'WindowsPackageManager'), (Join-Path $env:LOCALAPPDATA 'WingetManager'), (Join-Path $env:LOCALAPPDATA 'WingetPackageManager'), (Join-Path $env:LOCALAPPDATA 'WingetUpdateManager'))) {
    if (-not (Test-Path -LiteralPath $DataDir) -and (Test-Path -LiteralPath $old)) { try { Move-Item -LiteralPath $old -Destination $DataDir } catch { } }
}
New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
$SettingsPath = Join-Path $DataDir 'settings.json'
$LastRunPath = Join-Path $DataDir 'lastrun.json'
$DefaultLogDir = Join-Path $DataDir 'Logs'

# Every option, with its default (the default's type is how a saved value is read back).
#   Packages:       Source ('' = all, 'winget', 'msstore'), InstallScope ('' = installer default, 'user', 'machine'), Silent, IncludeUnknown, UninstallPrevious, ScanOnOpen,
#                   Hidden (IDs kept at their version: not listed on Updates, and pinned so nothing updates them),
#                   Excluded (the old "skip in automatic updates" list, folded into Hidden when settings load)
#   Automatic runs: AutoMode ('install' = install updates, 'notify' = only list them in a notification),
#                   NotifyReboot / NotifyAlways (notifications beyond failures), AutoRetry, RestorePoint,
#                   RequireNetwork, RequireAC, RandomDelayMin, MaxRunHours (task conditions), AutoDismissMin (0 = never)
#   Logs:           LogRetentionDays, LogDir ('' = default), VerboseLogs
#   Notifications:  NotifyStyle ('toast' = a Windows notification, 'window' = this app's own pop-up)
#   Windows-updated apps: WindowsUpdated (IDs found to be updated by Windows or by themselves rather than winget,
#                   learned from failed updates), WingetUpdates (IDs on the built-in list that winget may update anyway)
#   Drivers:        DriverRestorePoint (a restore point before driver and Windows Update changes)
#   App updates:    AppUpdateCheck (look for a newer GitHub release on start), AppUpdateAuto (install it without asking),
#                   AppUpdateSkip (a version the user said Not now to), AppUpdateBeta (also offer pre-releases)
#   Health:         HealthAlerts (automatic runs check the PC's health and notify about problems)
#   Task copy:      TaskCopyAsked ('<need> <version>': the protected copy offer the user said Not now to)
function New-DefaultSettings {
    return @{
        Source = ''; InstallScope = ''; Silent = $true; IncludeUnknown = $false; UninstallPrevious = $false; ScanOnOpen = $true; Excluded = @(); Hidden = @()
        AutoMode = 'install'; NotifyReboot = $false; NotifyAlways = $false; AutoRetry = $true; RestorePoint = $false
        RequireNetwork = $true; RequireAC = $false; RandomDelayMin = 0; MaxRunHours = 4; AutoDismissMin = 0
        LogRetentionDays = 30; LogDir = ''; VerboseLogs = $false
        NotifyStyle = 'toast'; WindowsUpdated = @(); WingetUpdates = @(); DriverRestorePoint = $true
        AppUpdateCheck = $true; AppUpdateAuto = $false; AppUpdateSkip = ''; AppUpdateBeta = $false; HealthAlerts = $true
        TaskCopyAsked = ''
    }
}
function ConvertTo-Setting($Default, $Value) {
    if ($Default -is [bool]) { return [bool]$Value }
    if ($Default -is [int]) { return [int]$Value }
    if ($Default -is [array]) { return @($Value | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
    return [string]$Value
}
# Copies known keys from a saved object (settings.json or an export) onto $Target
function Merge-Settings($Target, $Saved) {
    foreach ($k in @($Target.Keys)) {
        if ($null -eq $Saved.$k) { continue }
        try { $Target[$k] = ConvertTo-Setting $Target[$k] $Saved.$k } catch { }
    }
}
$Settings = New-DefaultSettings
try { if (Test-Path -LiteralPath $SettingsPath) { Merge-Settings $Settings (Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json) } } catch { }
if ($Settings.AutoMode -notin 'install', 'notify') { $Settings.AutoMode = 'install' }
if ($Settings.NotifyStyle -notin 'toast', 'window') { $Settings.NotifyStyle = 'toast' }
function Get-SettingsCopy {
    $copy = @{}
    foreach ($k in $Settings.Keys) { $copy[$k] = $Settings[$k] }
    $copy.Excluded = [string[]]@($Settings.Excluded)
    $copy.Hidden = [string[]]@($Settings.Hidden)
    $copy.WindowsUpdated = [string[]]@($Settings.WindowsUpdated)
    $copy.WingetUpdates = [string[]]@($Settings.WingetUpdates)
    return $copy
}
function Save-Settings {
    try { Get-SettingsCopy | ConvertTo-Json | Set-Content -LiteralPath $SettingsPath -Encoding UTF8 } catch { }
}
# 5.1 made Hide the one way to keep an app out of updates; apps skipped by automatic updates become hidden apps
if (@($Settings.Excluded).Count) {
    $Settings.Hidden = @(@($Settings.Hidden) + @($Settings.Excluded) | Where-Object { $_ } | Sort-Object -Unique)
    $Settings.Excluded = @()
    Save-Settings
}

# Logs go to the chosen folder (or the default); a folder that cannot be created falls back to the default
function Set-LogLocation {
    $dir = if ($Settings.LogDir) { [Environment]::ExpandEnvironmentVariables($Settings.LogDir) } else { $DefaultLogDir }
    try { New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null }
    catch { $dir = $DefaultLogDir; New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:LogDir = $dir
    $script:LogFile = Join-Path $dir ('{0:yyyy-MM-dd}.log' -f (Get-Date))
    if ($script:Sync) { $script:Sync.LogFile = $script:LogFile }
}
# Deletes daily logs older than the retention period, and the app's error log once it is that old (or over 1 MB)
function Remove-OldLogs {
    $cutoff = (Get-Date).AddDays(-[Math]::Max(1, $Settings.LogRetentionDays))
    try { Get-ChildItem -LiteralPath $LogDir -Filter '*.log' | Where-Object { $_.LastWriteTime -lt $cutoff } | Remove-Item -Force } catch { }
    try {
        $crash = Get-Item -LiteralPath $StartupLog -ErrorAction Stop
        if ($crash.LastWriteTime -lt $cutoff -or $crash.Length -gt 1MB) { Remove-Item -LiteralPath $StartupLog -Force }
    }
    catch { }
}
Set-LogLocation
Remove-OldLogs

# History: one JSON line per change (update, install, uninstall, hold, release), from the window and automatic runs.
# The newest 2,000 entries from the last year are kept.
$HistoryPath = Join-Path $DataDir 'history.jsonl'
function Add-History([string]$Action, [string]$Name, [string]$Id, [string]$From, [string]$To, [string]$State, [string]$Detail, [string]$Origin = 'app') {
    $entry = [pscustomobject][ordered]@{ Time = (Get-Date).ToString('o'); Action = $Action; Name = $Name; Id = $Id; From = $From; To = $To; State = $State; Detail = $Detail; Origin = $Origin }
    try { [IO.File]::AppendAllText($HistoryPath, ($entry | ConvertTo-Json -Compress) + "`r`n", (New-Object Text.UTF8Encoding($false))) } catch { }
}
function Read-HistoryLines {
    if (-not (Test-Path -LiteralPath $HistoryPath)) { return , @() }
    return , @([IO.File]::ReadAllLines($HistoryPath, [Text.Encoding]::UTF8) | Where-Object { $_.Trim() })
}
function Limit-History {
    try {
        $lines = Read-HistoryLines
        $cutoff = (Get-Date).AddDays(-365)
        $keep = @($lines | Where-Object { try { [datetime]($_ | ConvertFrom-Json).Time -ge $cutoff } catch { $false } } | Select-Object -Last 2000)
        if ($keep.Count -ne $lines.Count) { [IO.File]::WriteAllLines($HistoryPath, [string[]]$keep, (New-Object Text.UTF8Encoding($false))) }
    }
    catch { }
}

# Build-Exe.ps1 fills these with assets\icon.ico and assets\logo.jpg (base64), so the exe needs no other files.
$EmbeddedIcon = ''
$EmbeddedLogo = ''
$AssetsDir = if ($AppRoot) { Join-Path $AppRoot 'assets' } else { $null }
function Get-AssetBytes([string]$Embedded, [string]$FileName) {
    if ($Embedded) { return , [Convert]::FromBase64String($Embedded) }
    if ($AssetsDir) {
        $file = Join-Path $AssetsDir $FileName
        if (Test-Path -LiteralPath $file) { return , [IO.File]::ReadAllBytes($file) }
    }
    return $null
}
function Get-AppIcon {
    try {
        $bytes = Get-AssetBytes $EmbeddedIcon 'icon.ico'
        if ($bytes) { return [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object IO.MemoryStream(, $bytes)), 'None', 'OnLoad') }
    }
    catch { }
    return $null
}

# winget is normally on PATH through its App Execution Alias; an elevated or unusual session may only see the package folder.
function Find-Winget {
    $cmd = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $pkg = Get-ChildItem -Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($pkg) { return $pkg.FullName }
    return $null
}
$WingetPath = Find-Winget

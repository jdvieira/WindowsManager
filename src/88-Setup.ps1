# Windows Manager - Setup (part of src\; see Windows_Manager.ps1)

# Setting up a new or reset PC: one backup file holds the apps (winget's export format, so winget import reads it
# too), plus a "WindowsManager" section with the options, hidden apps and automatic update schedule.
# Opening it lists the apps on Discover with the missing ones ticked, then offers to fill in the options.

# The backup folder: OneDrive when it's set up (so the file is there on the next PC), else Documents
function Get-SetupFolder {
    $root = @($env:OneDriveConsumer, $env:OneDrive, $env:OneDriveCommercial) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $root) { $root = [Environment]::GetFolderPath('MyDocuments') }
    return (Join-Path $root 'Windows Manager')
}

# The options section, as Options > Maintenance > Export writes it
function Get-SettingsExport {
    $s = Get-AutoSchedule
    return [ordered]@{
        App = $AppName; Version = $AppVersion; Exported = (Get-Date).ToString('o'); Computer = $env:COMPUTERNAME
        Settings = Get-SettingsCopy
        Schedule = $(if ($s) { [ordered]@{ Enabled = $s.Enabled; Frequency = $s.Frequency; Days = @($s.Days); Time = $s.Time; Elevated = $s.Elevated; CatchUp = $s.CatchUp } } else { $null })
    }
}

function Open-SetupBackup {
    if (-not $script:InstalledKnown) {
        if (-not $script:Lister) { Start-InstalledScan }
        $script:LastSummary = 'Reading the installed apps first; try again in a moment.'
        Update-View
        return
    }
    $seen = @{}
    $apps = @($InstalledItems | Where-Object { $_.Source -and -not $_.Truncated } | Sort-Object Name, Id | Where-Object {
            if ($seen.ContainsKey($_.Id)) { $false } else { $seen[$_.Id] = $true; $true } })
    Show-Pick 'setup' "Back up this PC's setup" "Choose the apps to include. The file also holds your hidden apps, options and automatic update schedule. On the new PC, open it with Options > Maintenance > Set up from a backup (or Import list on Discover)." "Save backup$Ellipsis" $apps
}

function Save-SetupFile($Apps) {
    $dir = Get-SetupFolder
    try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = 'Setup backup (*.json)|*.json'
    $dlg.FileName = "Setup-$env:COMPUTERNAME-$(Get-Date -Format 'yyyy-MM-dd').json"
    if (Test-Path -LiteralPath $dir) { $dlg.InitialDirectory = $dir }
    if (-not $dlg.ShowDialog($Window)) { return }
    try {
        Write-SetupFile $Apps $dlg.FileName
        $UI.PickOverlay.Visibility = 'Collapsed'
        Add-LogLine "Saved a setup backup with $(@($Apps).Count) apps, the options and the schedule to $($dlg.FileName)."
        $script:LastSummary = "Saved this PC's setup ($(@($Apps).Count) apps) to $([IO.Path]::GetFileName($dlg.FileName))"
        Update-View
    }
    catch { $UI.PickCount.Text = "Couldn't save the backup: $($_.Exception.Message)" }
}

# winget's export format, with this app's section added (winget import ignores it)
function Write-SetupFile($Apps, [string]$File) {
    Write-AppList $Apps $File
    $doc = [IO.File]::ReadAllText($File) | ConvertFrom-Json
    $doc | Add-Member -NotePropertyName WindowsManager -NotePropertyValue ([pscustomobject](Get-SettingsExport))
    [IO.File]::WriteAllText($File, ($doc | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
}

# Opens an app list or a setup backup (Import list on Discover, and Set up from a backup)
function Open-AppListFile([string]$File) {
    $entries = Read-AppList $File
    $data = $null
    try { $raw = [IO.File]::ReadAllText($File); if ($raw.TrimStart().StartsWith('{')) { $data = ($raw | ConvertFrom-Json).WindowsManager } } catch { }
    if (-not $entries.Count -and -not $data) { throw 'there are no package IDs in it.' }
    $UI.TabDiscover.IsChecked = $true
    if ($entries.Count) { Show-ImportedList $entries ([IO.Path]::GetFileName($File)) }
    if ($data -and $data.Settings) {
        $missing = @($DiscoverItems | Where-Object { $_.CanUpdate }).Count
        Show-Confirm 'setupoptions' @{ Data = $data; File = [IO.Path]::GetFileName($File) } 'Use the options from this backup too?' "This backup from $(if ($data.Computer) { $data.Computer } else { 'another PC' }) also has its options, hidden apps$(if ($data.Schedule -and $data.Schedule.Enabled) { ' and automatic update schedule' }). Options opens with them filled in; nothing changes until you click Save there.$(if ($entries.Count) { "`n`nDiscover lists the backup's $($entries.Count) apps$(if ($missing) { ", with the $missing that aren't on this PC ticked: click Install selected to install them" })." })" 'Review options'
    }
}
$ConfirmHandlers.setupoptions = {
    param($Payload)
    $data = $Payload.Data
    Open-Options
    $imported = New-DefaultSettings
    Merge-Settings $imported $data.Settings
    Set-OptionControls $imported
    $script:ImportedSchedule = if ($data.Schedule -and $data.Schedule.Enabled -and $data.Schedule.Time) { $data.Schedule } else { $null }
    $what = if ($script:ImportedSchedule) { "options and schedule ($(Format-Schedule $script:ImportedSchedule))" } else { 'options' }
    Set-OptionMessage "Filled in the $what from $($Payload.File). Review them, then click Save to apply."
}

function Open-SetupFile {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = 'Setup backups and app lists (*.json;*.txt)|*.json;*.txt|All files (*.*)|*.*'
    $dir = Get-SetupFolder
    if (Test-Path -LiteralPath $dir) { $dlg.InitialDirectory = $dir }
    if (-not $dlg.ShowDialog($Window)) { return }
    try { Open-AppListFile $dlg.FileName }
    catch { $script:LastSummary = "Couldn't open that file: $($_.Exception.Message)"; Update-View }
}

$UI.OptSetupSave.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed'; Open-SetupBackup })
$UI.OptSetupLoad.Add_Click({ $UI.OptionsOverlay.Visibility = 'Collapsed'; Open-SetupFile })

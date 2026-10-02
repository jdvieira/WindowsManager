# Windows Manager - Diagnostics (part of src\; see Windows_Manager.ps1)

# Save diagnostics: a zip on the desktop with what's needed to see why something went wrong on a PC: this app's logs
# and error log, the administrator runs' scripts and logs (Dell Command | Update's too), winget's own logs, the
# settings, history and last automatic run, and a system.txt with this PC and what the app found on it.
$script:DiagRun = $null

function Get-NewestFiles([string]$Dir, [string[]]$Patterns, [int]$Count) {
    if (-not $Dir -or -not (Test-Path -LiteralPath $Dir)) { return @() }
    return @(foreach ($p in $Patterns) { Get-ChildItem -LiteralPath $Dir -Filter $p -File -ErrorAction SilentlyContinue }) | Sort-Object LastWriteTime -Descending | Select-Object -First $Count
}

function Save-Diagnostics([string]$Zip) {
    if ($script:DiagRun) { return }
    $zip = if ($Zip) { $Zip } else { Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows Manager diagnostics - $env:COMPUTERNAME - $(Get-Date -Format 'yyyyMMdd-HHmmss').zip" }
    $files = New-Object System.Collections.Generic.List[object]
    foreach ($f in @(@{ From = $SettingsPath; To = 'settings.json' }, @{ From = $LastRunPath; To = 'lastrun.json' }, @{ From = $HistoryPath; To = 'history.jsonl' }, @{ From = $StartupLog; To = 'app-errors.log' })) { $files.Add($f) }
    foreach ($f in Get-NewestFiles $LogDir @('*.log') 7) { $files.Add(@{ From = $f.FullName; To = "logs\$($f.Name)" }) }
    foreach ($f in Get-NewestFiles $DrvWorkDir @('*.log', '*.ps1') 40) { $files.Add(@{ From = $f.FullName; To = "admin-runs\$($f.Name)" }) }
    foreach ($f in Get-NewestFiles $WingetLogDir @('*.log') 5) { $files.Add(@{ From = $f.FullName; To = "winget-logs\$($f.Name)" }) }
    # (Read-DriverBackups returns its list as one object, so it is stored before it is enumerated)
    $saved = Read-DriverBackups
    foreach ($b in @($saved | Select-Object -First 20)) { $files.Add(@{ From = (Join-Path $b.Dir 'manifest.json'); To = "saved-drivers\$(Split-Path -Leaf $b.Dir).json" }) }

    $t = New-Object System.Collections.Generic.List[string]
    $t.Add("Windows Manager $AppVersion  ($(if ($IsCompiled) { "exe: $ExePath" } else { "script: $AppScript" }))")
    $t.Add("Saved:       $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
    $t.Add("Running as:  $CurrentUser$(if ($IsAdmin) { ' (administrator)' } else { ' (standard user)' })   PowerShell $($PSVersionTable.PSVersion)")
    $t.Add("winget:      $(if ($WingetPath) { "$WingetPath, $(if ($script:WingetVersion) { $script:WingetVersion } else { 'version not read' })" } else { 'not found' })")
    $t.Add("Sources:     $((@($script:Sources) | ForEach-Object { "$($_.Name) ($($_.Arg))" }) -join '; ')")
    $t.Add("Updates:     $($Packages.Count) listed, mode $($script:Mode); hidden: $(@($Settings.Hidden) -join ', ')")
    $t.Add("Windows-updated apps: learned $(@($Settings.WindowsUpdated) -join ', '); set back to winget $(@($Settings.WingetUpdates) -join ', ')")
    try {
        $s = Get-AutoSchedule
        $copy = if ($s -and $s.Elevated) { ', protected copy ' + $(if ($v = Get-TaskCopyVersion) { $v } else { 'missing' }) } else { '' }
        $t.Add("Schedule:    $(if ($s) { "$(Format-Schedule $s), elevated $($s.Elevated)$copy, jobs $((@(Get-AutoJobs | ForEach-Object { "$($_.Key) $($_.Mode)/$($_.Every)" })) -join ', '), notifications $($Settings.NotifyStyle)" } else { 'none' })$(if (Test-LegacyTask) { '; an old-name task exists' })")
    }
    catch { $t.Add("Schedule:    couldn't read it ($($_.Exception.Message))") }
    if ($script:DrvSys) {
        $tool = Get-VendorTool
        $t.Add("Vendor:      $(Get-MakerName) ($((Get-PcIdentity) -replace '\s*\|\s*', ' / '))")
        $t.Add("Vendor tool: $(if ($tool) { "$($tool.Name), installed $($tool.Installed), path $($tool.Path), version $($tool.Version), command line $($tool.Cli)" } else { 'none known' })")
        $t.Add("Chips:       $($script:DrvSys.Chips)")
        foreach ($c in @(Get-ComponentTools)) { $t.Add("Component:   $($c.Name), installed $($c.Installed)") }
    }
    else { $t.Add('Vendor:      the Drivers tab was not opened') }
    $t.Add("Driver checks: Windows Update $($script:WuState) (managed: $(if ($script:WuManaged) { $script:WuManaged } else { 'no' })$(if ($script:WuNote) { "; $($script:WuNote)" })); NVIDIA $($script:NvState) $($script:NvNote); AMD $($script:AmdState) $($script:AmdNote); Dell $($script:DrvScan) $($script:DrvScanNote)")
    $t.Add("Devices:     $($DrvDevices.Count) read, $(@($DrvDevices | Where-Object { $_.HasProblem }).Count) with a problem; $($DrvUpdates.Count) driver updates listed")
    foreach ($d in @($DrvDevices | Where-Object { $_.HasProblem })) { $t.Add("  problem:   $($d.Name) ($($d.InstanceId)): $($d.Problem)") }
    $t.Add("Windows Update tab: $($script:WinState)$(if ($script:WinInfo) { ", $($WinUpdates.Count) updates, managed: $(if ($script:WinInfo.Managed) { $script:WinInfo.Managed } else { 'no' }), restart waiting: $($script:WinInfo.Reboot)" })")

    $script:LastSummary = "Saving diagnostics$Ellipsis"
    $script:DiagRun = Start-Tracked 'diag' @{ Zip = $zip; Files = $files.ToArray(); Text = $t.ToArray() } { $script:DiagRun = $null }
    Update-View
}
$EventHandlers.diag = {
    param($Ev)
    if ($Ev.Error) { $script:LastSummary = "Couldn't save diagnostics: $($Ev.Error)"; Update-View; return }
    Add-LogLine "Saved diagnostics: $($Ev.Zip)"
    $script:LastSummary = "Saved diagnostics: $($Ev.Zip)"
    if (-not $SelfTest) { try { Start-Process explorer.exe -ArgumentList "/select,`"$($Ev.Zip)`"" } catch { } }
    Update-View
}

$UI.BtnDiag.Add_Click({ Save-Diagnostics })
$UI.OptDiag.Add_Click({ Save-Diagnostics })

# Windows Manager - Actions (part of src\; see Windows_Manager.ps1)

function Invoke-RowAction($p, [switch]$Interactive, [string]$Scope) {
    if (-not $p -or -not $p.CanUpdate) { return }
    if ($p.Action -eq 'uninstall') {
        $how = if ($Interactive) { "winget opens the app's own uninstaller." } elseif ($Settings.Silent) { "winget runs the app's uninstaller silently." } else { "winget runs the app's uninstaller." }
        Show-Confirm 'uninstall' @{ Item = $p; Interactive = [bool]$Interactive } "Uninstall $($p.Name)?" "$how Settings and files the app keeps in your profile may stay behind.`n`n$($p.Id)" 'Uninstall' -Danger
        return
    }
    Add-Job @($p) -Interactive:$Interactive -Scope $Scope
}

function Add-Job {
    param([object[]]$Items, [switch]$Interactive, [string]$Scope, [string]$Version, [switch]$PinAfter)
    foreach ($p in $Items) {
        if (-not $p -or -not $p.CanUpdate) { continue }
        $p.State = 'queued'; $p.Detail = 'Queued'; $p.Progress = -1
        $Sync.Jobs.Enqueue(@{
                Key = $p.Key; Id = $p.Id; Name = $p.Name; Source = $p.Source; Action = $p.Action; Explicit = $p.ExplicitTarget
                Interactive = [bool]$Interactive; Silent = $Settings.Silent; UninstallPrevious = $Settings.UninstallPrevious; Verbose = $Settings.VerboseLogs
                Scope = $(if ($Scope) { $Scope } else { $Settings.InstallScope })
                # A chosen version to install, or one of several installed copies of a package to uninstall
                Version = $(if ($Version) { $Version } elseif ($p.Section -eq 'installed' -and @($InstalledItems | Where-Object { $_.Id -eq $p.Id }).Count -gt 1) { $p.Version } else { '' })
                PinAfter = [bool]$PinAfter
            })
        $script:Batch.Total++
    }
    Start-QueuedWork
    Update-View
}
function Add-UpdateJob { param([object[]]$Items, [switch]$Interactive) Add-Job $Items -Interactive:$Interactive }

function Start-QueuedWork {
    if (-not $script:Worker -and -not $script:Scanner -and $Sync.Jobs.Count -gt 0) {
        $script:LastSummary = $null
        $script:Worker = Start-Background 'upgrade' $null
    }
}

function Stop-Queue {
    $job = $null
    while ($Sync.Jobs.TryDequeue([ref]$job)) {
        $p = $ByKey[$job.Key]
        if ($p) { $p.State = 'cancelled'; $p.Detail = 'Cancelled' }
        $script:Batch.Done++
    }
    Update-View
}

# After a successful job: keep the three lists consistent with what changed on the PC
function Complete-Job($p) {
    $p.Selected = $false
    switch ($p.Section) {
        'updates' { $p.Version = $p.Available }
        'discover' {
            [void]$script:InstalledIds.Add($p.Id)
            $p.IsInstalled = $true
            $script:InstalledStale = $true
        }
        'installed' {
            if (@($InstalledItems | Where-Object { $_.Id -eq $p.Id -and -not $_.IsDone }).Count) { return }
            [void]$script:InstalledIds.Remove($p.Id)
            # Includes a Discover row still showing an install from earlier in this session, so it offers Install again
            foreach ($d in $DiscoverItems) { if ($d.Id -eq $p.Id -and -not $d.IsBusy) { $d.State = ''; $d.IsInstalled = $false; $d.Detail = '' } }
            foreach ($u in @($Packages | Where-Object { $_.Id -eq $p.Id -and -not $_.IsBusy })) { $ByKey.Remove($u.Key); [void]$Packages.Remove($u) }
        }
    }
}

function Show-Confirm([string]$Kind, $Payload, [string]$Title, [string]$Text, [string]$OkText, [switch]$Danger) {
    $script:Confirm = @{ Kind = $Kind; Payload = $Payload }
    $UI.ConfirmTitle.Text = $Title
    $UI.ConfirmText.Text = $Text
    $UI.ConfirmYes.Content = $OkText
    $UI.ConfirmYes.Style = $Window.FindResource($(if ($Danger) { 'Danger' } else { 'Primary' }))
    $UI.ConfirmYes.Margin = '0'
    $UI.ConfirmOverlay.Visibility = 'Visible'
}

function Complete-Confirm([bool]$Yes) {
    $c = $script:Confirm
    $script:Confirm = $null
    $UI.ConfirmOverlay.Visibility = 'Collapsed'
    if (-not $Yes -or -not $c) { return }
    switch ($c.Kind) {
        'uninstall' { Add-Job @($c.Payload.Item) -Interactive:$c.Payload.Interactive }
        'migrate' { Move-LegacyTask }
        'clearhistory' { try { Remove-Item -LiteralPath $HistoryPath -Force -ErrorAction Stop } catch { }; Open-History }
        'drvapply' { Start-DellApply $c.Payload.Types $c.Payload.Count $c.Payload.Wu $c.Payload.DellCount $c.Payload.Nv }
        'vendorinstall' { Install-VendorTool }
        'drvinstall' { Start-DellDriverInstall }
        'drvreinstall' { Start-DeviceAction $c.Payload.Device 'reinstall' }
        'drvremove' { Start-DeviceAction $c.Payload.Device 'remove' }
        'srcremove' { Invoke-SourceChange @('source', 'remove', '--name', $c.Payload.Name, '--disable-interactivity') "Removing the source $($c.Payload.Name)" }
        default { $h = $ConfirmHandlers[[string]$c.Kind]; if ($h) { & $h $c.Payload } }
    }
}

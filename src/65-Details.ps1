# Windows Manager - Details (part of src\; see Windows_Manager.ps1)

function Show-Details($p) {
    if (-not $p -or -not $p.Source) { return }
    $script:DetailsItem = $p
    $UI.DetName.Text = $p.Name
    $UI.DetSub.Text = "$($p.Id)  $Dot  $($p.Source)"
    $UI.DetDesc.Text = ''
    $UI.DetFields.Children.Clear(); $UI.DetFields.RowDefinitions.Clear()
    $UI.DetLoading.Visibility = 'Visible'
    $UI.DetHomepage.Visibility = 'Collapsed'
    Update-DetailsAction
    $UI.DetailsOverlay.Visibility = 'Visible'
    $script:Showers.Add((Start-Background 'show' @{ Id = $p.Id; Source = $p.Source; Key = $p.Key }))
}

function Update-DetailsAction {
    $p = $script:DetailsItem
    $UI.DetAction.Content = $p.ActionText
    $UI.DetAction.IsEnabled = $p.CanUpdate
    $UI.DetAction.Style = $Window.FindResource($(if ($p.Action -eq 'uninstall') { 'Danger' } else { 'Primary' }))
    $UI.DetAction.Margin = '0'
}

function Add-DetailField([string]$Label, [string]$Value) {
    $row = $UI.DetFields.RowDefinitions.Count
    $UI.DetFields.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
    $l = New-Object System.Windows.Controls.TextBlock
    $l.Text = $Label; $l.Foreground = $Window.FindResource('Muted'); $l.FontSize = 12.5; $l.Margin = '0,0,12,10'
    $v = New-Object System.Windows.Controls.TextBlock
    $v.TextWrapping = 'Wrap'; $v.Margin = '0,0,0,10'
    if ($Value -match '^https?://\S+$') {
        $link = New-Object System.Windows.Documents.Hyperlink (New-Object System.Windows.Documents.Run $Value)
        $link.NavigateUri = [Uri]$Value
        $link.Foreground = $Window.FindResource('Highlight')
        $link.Add_RequestNavigate({ param($s, $e) try { Start-Process $e.Uri.AbsoluteUri } catch { }; $e.Handled = $true })
        [void]$v.Inlines.Add($link)
    }
    else { $v.Text = $Value; $v.Foreground = [System.Windows.Media.Brushes]::Gainsboro }
    [System.Windows.Controls.Grid]::SetRow($l, $row); [System.Windows.Controls.Grid]::SetRow($v, $row); [System.Windows.Controls.Grid]::SetColumn($v, 1)
    [void]$UI.DetFields.Children.Add($l); [void]$UI.DetFields.Children.Add($v)
}

function Complete-Show($Ev) {
    # A description asked for from the list: fill in the row (and the cache), nothing else
    if ($Ev.Purpose -eq 'describe') {
        $p = $ByKey[$Ev.Key]
        if ($Ev.Ok -and $p) {
            $info = ConvertFrom-ShowOutput $Ev.Lines
            Set-Description $p.Id $p.Source $info.Description $info.Name
            if ($p -and -not $p.Version -and $info.Fields['Version']) { $p.Version = $info.Fields['Version'] }
        }
        elseif ($p) { $p.DescState = 'none'; $p.Description = '' }
        return
    }
    if ($Ev.Purpose -eq 'versions') { Complete-VersionList $Ev; return }
    if ($Ev.Purpose -eq 'notes') {
        $p = $ByKey[$Ev.Key]
        if ($Ev.Ok -and $p) {
            $info = ConvertFrom-ShowOutput $Ev.Lines
            $notes = ([string]$info.Fields['Release Notes']).Trim()
            $url = [string]$info.Fields['Release Notes Url']
            if ($url -notmatch '^https?://\S+$') { $url = '' }
            $script:NotesCache["$($p.Id)|$($p.Available)"] = @{ Notes = $notes; Url = $url }
            $p.Notes = $notes; $p.NotesUrl = $url
        }
        return
    }
    $p = $script:DetailsItem
    if (-not $p -or $Ev.Key -ne $p.Key -or $UI.DetailsOverlay.Visibility -ne 'Visible') { return }
    $UI.DetLoading.Visibility = 'Collapsed'
    if (-not $Ev.Ok) { $UI.DetDesc.Text = "winget has no details for this package. $(@($Ev.Lines) | Select-Object -Last 1)"; return }
    $info = ConvertFrom-ShowOutput $Ev.Lines
    if ($info.Name) { $UI.DetName.Text = $info.Name }
    $fields = $info.Fields
    $UI.DetDesc.Text = if ($info.Description) { $info.Description } else { 'No description.' }
    if ($p.Section -eq 'discover') { Set-Description $p.Id $p.Source $info.Description $info.Name }
    foreach ($k in 'Version', 'Publisher', 'Author', 'Homepage', 'Publisher Url', 'License', 'License Url', 'Release Notes Url', 'Installer Type', 'Moniker') {
        if ($fields[$k]) { Add-DetailField $k $fields[$k] }
    }
    if ($info.Tags.Count) { Add-DetailField 'Tags' ($info.Tags -join ', ') }
    $homeUrl = if ($fields['Homepage']) { $fields['Homepage'] } else { $fields['Publisher Url'] }
    if ($homeUrl -match '^https?://') { $UI.DetHomepage.Tag = $homeUrl; $UI.DetHomepage.Visibility = 'Visible' }
}#endregion

function Invoke-WorkerEvent($Ev) {
    switch ($Ev.T) {
        'log' { Add-LogLine $Ev.Text }
        'scan' { Complete-Scan $Ev; Update-View }
        'search' { Complete-Search $Ev; Update-View }
        'list' { Complete-List $Ev; Update-View }
        'show' { Complete-Show $Ev }
        'versions' { Complete-Versions $Ev }
        'sources' { Complete-Sources $Ev }
        'devices' { Complete-Devices $Ev; Update-View }
        'elevlog' {
            $script:ElevLast = $Ev.Text
            $script:ElevActivity = Get-Date; $script:ElevStalled = $false
            # the line that explains a failure, for the message afterwards
            if ($Ev.Text -match '^(Error: |Not found: |dcu-cli\.exe did not start)') { $script:ElevError = $Ev.Text }
            if ($Panels[$script:Section]) { Update-View }
        }
        'elevdone' { Complete-Elevated $Ev }
        'wusearch' { Complete-WuSearch $Ev; Update-View }
        'nvlookup' { Complete-NvLookup $Ev; Update-View }
        'size' { Complete-Size $Ev }
        'sizesdone' { Save-SizeCache; Update-View }
        'pinned' { Complete-Pinned $Ev; Update-View }
        'progress' { $p = $ByKey[$Ev.Key]; if ($p) { $p.Progress = $Ev.Value } }
        'command' { Complete-Maintenance $Ev }
        'state' {
            $p = $ByKey[$Ev.Key]
            if (-not $p) { return }
            if ($Ev.State -eq 'running' -and $p.State -ne 'running') { $p.Progress = -1; $script:CurrentName = $p.Name; $script:CurrentVerb = $Verbs[$p.Action] }
            $p.State = $Ev.State
            if ($Ev.Detail) { $p.Detail = $Ev.Detail }
            # winget can't update it because Windows (or the app) does: remember that, and stop offering the update
            if ($Ev.SelfUpdating) { Set-SelfUpdating $p.Id $true; $p.SelfUpdating = $true; Add-LogLine "$($p.Name) is updated by Windows or by itself, not winget: Update all and automatic updates leave it alone from now on." }
            if ($Ev.State -in $TerminalStates) {
                # History, before Complete-Job moves the row on to its new version
                $from = if ($p.Action -in 'update', 'uninstall') { $p.Version } else { '' }
                $to = switch ($p.Action) { 'update' { $p.Available } 'install' { $p.Version } default { '' } }
                Add-History $p.Action $p.Name $p.Id $from $to $Ev.State $p.Detail 'app'
                $b = $script:Batch
                $b.Done++
                if ($Ev.State -eq 'error') { $b.Failed++ }
                if ($Ev.State -eq 'reboot') { $b.Reboot++ }
                if ($p.IsDone) {
                    switch ($p.Action) { 'install' { $b.Installed++ } 'uninstall' { $b.Uninstalled++ } default { $b.Updated++ } }
                    Complete-Job $p
                    # what the app left behind, offered to remove
                    if ($p.Action -eq 'uninstall') { Start-LeftoverScan $p }
                }
            }
            Update-View
        }
        default { $h = $EventHandlers[[string]$Ev.T]; if ($h) { & $h $Ev } }
    }
}

function Receive-WorkerEvents {
    $ev = $null
    while ($Sync.Events.TryDequeue([ref]$ev)) {
        try { Invoke-WorkerEvent $ev } catch { Add-LogLine "UI error: $($_.Exception.Message)" }
    }
}

# Collects a finished runspace: its events, any errors it raised, and the batch summary.
function Complete-Background($Bg) {
    Receive-WorkerEvents
    try { [void]$Bg.PS.EndInvoke($Bg.Handle) } catch { Add-LogLine "Worker error: $($_.Exception.Message)" }
    foreach ($e in $Bg.PS.Streams.Error) { Add-LogLine "Worker error: $($e.Exception.Message)" }
    $Bg.PS.Dispose()
}

function Complete-Batch {
    foreach ($p in @($Packages) + @($DiscoverItems) + @($InstalledItems)) { if ($p.State -eq 'running') { $p.State = 'error'; $p.Detail = 'This stopped unexpectedly; see the log' } }
    $b = $script:Batch
    $parts = @()
    if ($b.Updated) { $parts += "$($b.Updated) updated" }
    if ($b.Installed) { $parts += "$($b.Installed) installed" }
    if ($b.Uninstalled) { $parts += "$($b.Uninstalled) uninstalled" }
    if ($b.Reboot) { $parts += "$($b.Reboot) need a restart" }
    if ($b.Failed) { $parts += "$($b.Failed) failed" }
    $script:LastSummary = if ($parts) { 'Last run: ' + ($parts -join ', ') } else { $null }
    # Installs and uninstalls change what is on the PC: read the installed list again in the background, so Discover
    # and Installed match it (winget list, the same as Refresh on the Installed tab)
    if ($b.Installed -or $b.Uninstalled) { $script:InstalledRefresh = $true }
    $script:CurrentName = $null
    $script:Batch = New-Batch
    if ($b.Failed) { Add-LogLine 'Something failed. Right-click the app and choose the "interactively" option to watch its installer.' }
    try { if (-not $Window.IsActive) { $Window.TaskbarItemInfo.ProgressState = 'None' } } catch { }
}

function Update-SortGlyphs {
    $v = Get-SectionView
    $first = if ($v.SortDescriptions.Count) { $v.SortDescriptions[0] } else { $null }
    $glyph = if ($first -and $first.Direction -eq 'Descending') { [string][char]0xE70E } else { [string][char]0xE70D }
    $UI.SortNameGlyph.Text = if ($first -and $first.PropertyName -eq 'Name') { $glyph } else { '' }
    $UI.SortSourceGlyph.Text = if ($first -and $first.PropertyName -eq 'Source') { $glyph } else { '' }
    $UI.SortSizeGlyph.Text = if ($first -and $first.PropertyName -eq 'SizeKB') { $glyph } else { '' }
}

function Set-Sort([string]$Property) {
    $v = Get-SectionView
    # Size sorts largest first; a second click reverses either way
    $first = if ($Property -eq 'SizeKB') { 'Descending' } else { 'Ascending' }
    $other = if ($first -eq 'Ascending') { 'Descending' } else { 'Ascending' }
    $dir = $first
    if ($v.SortDescriptions.Count -and $v.SortDescriptions[0].PropertyName -eq $Property -and $v.SortDescriptions[0].Direction -eq $first) { $dir = $other }
    $v.SortDescriptions.Clear()
    $v.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription($Property, $dir)))
    if ($Property -ne 'Name') { $v.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending'))) }
    Update-SortGlyphs
}

function Get-WingetCommand($p) {
    $verb = @{ update = 'upgrade'; install = 'install'; uninstall = 'uninstall' }[$p.Action]
    $cmd = "winget $verb --id `"$($p.Id)`" --exact"
    if ($p.Source) { $cmd += " --source $($p.Source)" }
    return $cmd
}

# Moving the scheduled task from one of the app's earlier names to the current one
function Get-LegacyTaskName {
    foreach ($n in $LegacyTaskNames) { if (Get-AutoTask $n) { return $n } }
    return $null
}
function Test-LegacyTask { return (-not (Get-AutoTask)) -and [bool](Get-LegacyTaskName) }
function Request-TaskMove {
    $legacy = Get-LegacyTaskName
    $s = if ($legacy) { Get-AutoSchedule $legacy } else { $null }
    if (-not $s) { return }
    $approval = if ($s.Elevated -and -not $IsAdmin) { ' Windows will ask for administrator approval.' } else { '' }
    Show-Confirm 'migrate' $null 'Move automatic maintenance to the new name' "Your automatic maintenance ($(Format-Schedule $s)) are set up under the old name, $legacy, and still point at the old exe. Moving them keeps the same schedule and settings for $AppName and removes the old task.$approval" 'Move task'
}
function Move-LegacyTask {
    $legacy = Get-LegacyTaskName
    $s = if ($legacy) { Get-AutoSchedule $legacy } else { $null }
    if (-not $s) { return }
    $spec = New-RegisterSpec $s
    $spec.Op = 'migrate'
    $spec.Legacy = $legacy
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        Invoke-TaskAction $spec
        Add-LogLine "Automatic maintenance moved to the task `"$TaskName`" ($(Format-Schedule $s))."
        if (Get-AutoTask $legacy) { Add-LogLine "The old task `"$legacy`" could not be removed; delete it in Task Scheduler." }
    }
    catch { $UI.StatusText.Text = "The scheduled task was not moved: $($_.Exception.Message)" }
    finally { $Window.Cursor = $null }
    Update-ScheduleSummary
}

# An elevated task that runs the app from a folder other programs can change, or runs an older protected copy, is
# offered the protected copy once per version (Not now, or the Automatic maintenance panel, can still do it later)
function Request-TaskCopy {
    if ($script:Confirm) { return }   # another question is open; ask next time
    $s = Get-AutoSchedule
    if (-not $s -or -not $s.Enabled) { return }
    $need = Get-TaskCopyNeed $s
    if (-not $need -or $Settings.TaskCopyAsked -eq "$need $AppVersion") { return }
    $approval = if ($IsAdmin) { '' } else { ' Windows will ask for administrator approval.' }
    if ($need -eq 'protect') {
        Show-Confirm 'taskcopy' $need 'Protect automatic maintenance' "Your automatic maintenance ($(Format-Schedule $s)) run $AppName as administrator from $(Split-Path -Parent $s.Execute), a folder other programs can change. A program could swap the app there and get administrator rights without asking you. Protecting it copies $AppName to $TaskCopyDir, which only administrators can change, and the task runs that copy. The schedule and settings stay the same.$approval" 'Protect it'
    }
    else {
        Show-Confirm 'taskcopy' $need 'Update the copy automatic maintenance uses' "Your automatic maintenance ($(Format-Schedule $s)) run a protected copy of $AppName in $TaskCopyDir. $(if ($v = Get-TaskCopyVersion) { "It is version $v; this is $AppVersion. Updating it copies this version there, so automatic runs work like this one; until then they keep using the older copy." } else { 'The copy is missing, so automatic runs fail. Updating it copies this version there.' })$approval" 'Update it'
    }
    $UI.ConfirmNo.Content = 'Not now'
}
function Update-TaskCopy {
    $s = Get-AutoSchedule
    if (-not $s) { return }
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        Invoke-TaskAction (New-RegisterSpec $s)
        Add-LogLine "Automatic maintenance ($(Format-Schedule $s)) runs a protected copy of $AppName $AppVersion in $TaskCopyDir."
    }
    catch { $UI.StatusText.Text = "Automatic maintenance was not changed: $($_.Exception.Message)" }
    finally { $Window.Cursor = $null }
    Update-ScheduleSummary
}
$ConfirmHandlers.taskcopy = { param($Payload) Update-TaskCopy }
$ConfirmDeclined.taskcopy = { param($Payload) $Settings.TaskCopyAsked = "$Payload $AppVersion"; Save-Settings }

function Restart-Elevated {
    # the elevated copy is a new window, so this one lets go of "one window at a time" first
    Exit-AppMutex
    try {
        if ($IsCompiled) { Start-Process -FilePath $ExePath -Verb RunAs }
        else { Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$AppScript`"") }
        $Window.Close()
    }
    catch { $script:AppMutex = Get-AppMutex 1; $UI.StatusText.Text = 'Administrator approval was declined.' }
}

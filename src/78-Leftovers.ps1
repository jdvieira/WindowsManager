# Windows Manager - Leftovers (part of src\; see Windows_Manager.ps1)

# After an uninstall from Installed Software: what the app left behind (folders named after it, its scheduled tasks,
# startup entries pointing at it), offered in a list to tick. Folders go to the Recycle Bin, so a wrong guess can be
# brought back. Leftovers in your own profile go straight away; Program Files, ProgramData, other users' startup
# entries and scheduled tasks need one administrator approval.
$script:LeftoverQueue = New-Object System.Collections.Generic.Queue[object]
$script:LeftoverScan = $null
$script:LeftoverApp = ''

function Start-LeftoverScan($p) {
    if (-not $p) { return }
    $script:LeftoverQueue.Enqueue(@{ Name = $p.Name; Id = $p.Id })
    Step-LeftoverScan
}
function Step-LeftoverScan {
    if ($script:LeftoverScan -or -not $script:LeftoverQueue.Count) { return }
    $a = $script:LeftoverQueue.Dequeue()
    $script:LeftoverScan = Start-Tracked 'leftovers' $a { $script:LeftoverScan = $null }
}

$EventHandlers.leftovers = {
    param($Ev)
    $items = @($Ev.Items)
    Add-LogLine "Leftovers of $($Ev.Name): $(if ($items.Count) { ($items | ForEach-Object { $_.Path }) -join '; ' } else { 'none found' })"
    if (-not $items.Count) { Step-LeftoverScan; return }
    # the pick list shows Name, then "Id - Source" under it
    $rows = foreach ($i in $items) {
        $where = switch ($i.Kind) { 'folder' { 'Folder' } 'task' { 'Scheduled task' } default { 'Startup entry' } }
        [pscustomobject]@{ Name = $i.Path; Id = "$where$(if ($i.Size -gt 0) { ", $(Format-Size $i.Size)" })"; Source = $(if ($i.Admin) { 'needs administrator approval' } else { 'yours' }); Item = $i }
    }
    if ($UI.PickOverlay.Visibility -eq 'Visible' -or $UI.ConfirmOverlay.Visibility -eq 'Visible') { $script:LeftoverQueue.Enqueue(@{ Name = $Ev.Name; Id = $Ev.Id }); return }
    $script:LeftoverApp = $Ev.Name
    Show-Pick 'leftovers' "Remove what $($Ev.Name) left behind?" "These look like they belong to $($Ev.Name), which is uninstalled now. Untick anything you want to keep. Folders go to the Recycle Bin, so you can get them back from there." 'Remove ticked' @($rows)
}

function Remove-Leftovers($Rows) {
    $UI.PickOverlay.Visibility = 'Collapsed'
    $all = @($Rows | ForEach-Object { $_.Item })
    $mine = @($all | Where-Object { -not $_.Admin })
    $admin = @($all | Where-Object { $_.Admin })
    $script:LeftoverDone = 0; $script:LeftoverFailed = 0
    if ($mine.Count) { $script:Showers.Add((Start-Background 'removeleftovers' @{ Items = $mine })) }
    if ($admin.Count) {
        $q = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
        $body = "Add-Type -AssemblyName Microsoft.VisualBasic`r`n`$fail = 0`r`n"
        foreach ($i in $admin) {
            $body += switch ($i.Kind) {
                'folder' { "try { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($(& $q $i.Path), 'OnlyErrorDialogs', 'SendToRecycleBin'); Say ('Moved to the Recycle Bin: ' + $(& $q $i.Path)) } catch { `$fail++; Say ('Not removed: ' + $(& $q $i.Path) + ': ' + `$_.Exception.Message) }`r`n" }
                'task' { "`$o = & schtasks.exe /Delete /TN $(& $q $i.Path) /F 2>&1; if (`$LASTEXITCODE) { `$fail++ }; `$o | ForEach-Object { Say ([string]`$_) }`r`n" }
                default { "try { `$b = [Microsoft.Win32.RegistryKey]::OpenBaseKey($(& $q $i.Hive), 'Registry64'); `$r = `$b.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', `$true); `$r.DeleteValue($(& $q $i.Value)); `$r.Close(); Say ('Removed the startup entry ' + $(& $q $i.Value)) } catch { `$fail++; Say ('Not removed: ' + `$_.Exception.Message) }`r`n" }
            }
        }
        $body += "if (`$fail) { exit 1 } else { exit 0 }"
        if ($script:Elev) { $script:LastSummary = "Wait for $($script:ElevTitle) to finish; the leftovers that need approval weren't removed" }
        else { Start-Elevated 'leftovers' "Removing what $($script:LeftoverApp) left behind" $body @() @{ App = $script:LeftoverApp; Count = $admin.Count } }
    }
    Add-History 'cleanup' "Leftovers of $($script:LeftoverApp)" '' '' '' 'ok' "$($all.Count) item$(if ($all.Count -ne 1) { 's' }) chosen for removal (folders to the Recycle Bin)"
    Update-View
}
$EventHandlers.leftoverdone = { param($Ev) if ($Ev.Ok) { $script:LeftoverDone++ } else { $script:LeftoverFailed++; Add-LogLine "Not removed: $($Ev.Path): $($Ev.Error)" } }
$EventHandlers.leftoversdone = { param($Ev) $script:LastSummary = "Removed $($script:LeftoverDone) leftover$(if ($script:LeftoverDone -ne 1) { 's' }) of $($script:LeftoverApp)$(if ($script:LeftoverFailed) { "; $($script:LeftoverFailed) couldn't be removed (see the log)" })"; Update-View; Step-LeftoverScan }
$ElevHandlers.leftovers = {
    param($Ev, $why, $code, $last, $tag)
    $script:LastSummary = if ($why) { "Leftovers of $($tag.App): $why" } elseif ($code -eq 0) { "Removed what $($tag.App) left behind" } else { "Some leftovers of $($tag.App) couldn't be removed; see the log" }
    Step-LeftoverScan
}

# Windows Manager - AutoJobs (part of src\; see Windows_Manager.ps1)

# What an automatic run does, one job each: app updates (winget), Windows updates, cleanup and the health check. A
# job is off, "tell me" ('notify': nothing changes, the notification says what's waiting) or "do it" ('install'),
# and runs every time the task runs, once a week or once a month; autojobs.json keeps when each last ran. Automatic
# runs exit before the window's parts load, so everything a job needs is defined here or earlier.
$AutoJobsPath = Join-Path $DataDir 'autojobs.json'
$TerminalStates = 'ok', 'reboot', 'skipped', 'error', 'cancelled'
# a little short of a week or a month, so a task that runs at the same time each week isn't held back a whole week
$AutoEveryDays = @{ run = 0; week = 6.5; month = 27.5 }
$AutoEveryText = @{ run = 'every run'; week = 'once a week'; month = 'once a month' }
# "Tell me" about cleanup only once this much can be freed
$AutoCleanNotifyBytes = 1GB

function Get-AutoJobs {
    return @(
        @{ Key = 'apps'; Name = 'App updates'; Mode = $Settings.AutoMode; Every = $Settings.AutoAppsEvery }
        @{ Key = 'win'; Name = 'Windows updates'; Mode = $Settings.AutoWin; Every = $Settings.AutoWinEvery }
        @{ Key = 'clean'; Name = 'Cleanup'; Mode = $Settings.AutoClean; Every = $Settings.AutoCleanEvery }
        @{ Key = 'health'; Name = 'Health check'; Mode = $(if ($Settings.HealthAlerts) { 'notify' } else { 'off' }); Every = $Settings.AutoHealthEvery }
    )
}

function Read-AutoJobTimes {
    $t = @{}
    try { if (Test-Path -LiteralPath $AutoJobsPath) { foreach ($p in (Get-Content -LiteralPath $AutoJobsPath -Raw | ConvertFrom-Json).PSObject.Properties) { $t[$p.Name] = [datetime]$p.Value } } } catch { }
    return $t
}
function Save-AutoJobTime([string]$Key) {
    $t = Read-AutoJobTimes
    $t[$Key] = Get-Date
    $o = [ordered]@{}
    foreach ($k in $t.Keys) { $o[$k] = $t[$k].ToString('o') }
    try { [IO.File]::WriteAllText($AutoJobsPath, ([pscustomobject]$o | ConvertTo-Json), (New-Object Text.UTF8Encoding($false))) } catch { }
}
# Due every run, or when it last ran long enough ago (or never)
function Test-AutoJobDue($Job, $Times) {
    $days = $AutoEveryDays[[string]$Job.Every]
    if (-not $days -or -not $Times.ContainsKey($Job.Key)) { return $true }
    return ((Get-Date) - $Times[$Job.Key]).TotalDays -ge $days
}

# A job's result. Listed: it only reported what's waiting (tell me, or do it without the rights to do it).
function New-AutoJobResult($Job) {
    return [ordered]@{ Key = $Job.Key; Name = $Job.Name; Mode = $Job.Mode; Listed = $false; Error = $null; Note = ''; Items = @()
        Available = 0; Updated = 0; Reboot = 0; Failed = 0; Skipped = 0; Bytes = [long]0; Freed = [long]0
    }
}

# Whether a job only listed things and found something worth telling you about (cleanup: enough to free)
function Test-AutoJobWaiting($R) {
    if (-not $R.Listed -or $R.Error) { return $false }
    if ($R.Key -eq 'clean') { return $R.Bytes -ge $AutoCleanNotifyBytes }
    return $R.Available -gt 0
}

# A job's result in a few words, for the log, the notification and the panel's "Last run"
function Format-AutoJobSummary($R, [bool]$Dry) {
    $n = { param([int]$Count, [string]$One, [string]$Many) "$Count $(if ($Count -eq 1) { $One } else { $Many })" }
    if ($R.Error) { return "couldn't run ($($R.Error))" }
    $text = switch ($R.Key) {
        'apps' {
            if ($Dry -or $R.Listed) { if ($R.Available) { "$(& $n $R.Available 'update' 'updates') $(if ($Dry -and -not $R.Listed) { 'would install' } else { 'available' })" } else { 'up to date' } }
            else {
                $p = @()
                if ($R.Updated) { $p += "$($R.Updated) updated" }
                if ($R.Reboot) { $p += "$($R.Reboot) need a restart" }
                if ($R.Failed) { $p += "$($R.Failed) failed" }
                if ($p.Count) { $p -join ', ' } else { 'up to date' }
            }
        }
        'win' {
            if ($Dry -or $R.Listed) { if ($R.Available) { "$(& $n $R.Available 'update' 'updates') $(if ($Dry -and -not $R.Listed) { 'would install' } else { 'available' })" } else { 'up to date' } }
            else {
                $p = @()
                if ($R.Updated + $R.Reboot) { $p += "$($R.Updated + $R.Reboot) installed" }
                if ($R.Reboot) { $p += 'restart to finish' }
                if ($R.Failed) { $p += "$($R.Failed) failed" }
                if ($p.Count) { $p -join ', ' } else { 'up to date' }
            }
        }
        'clean' {
            if ($Dry -or $R.Listed) { if ($R.Bytes -gt 0) { "$(Format-Size $R.Bytes) $(if ($Dry -and -not $R.Listed) { 'would be freed' } else { 'can be freed' })" } else { 'nothing to clean up' } }
            elseif ($R.Freed -gt 0) { "freed $(Format-Size $R.Freed)" } else { 'nothing to clean up' }
        }
        'health' {
            if ($Dry) { 'checked after a real run, not in a test' }
            elseif ($R.Available) { "$(& $n $R.Available 'thing needs' 'things need') a look" } else { 'nothing needs attention' }
        }
    }
    return [string]$text
}

# Restore point before a run's first change (app or Windows updates). Needs administrator rights (an elevated task)
# and System Protection on the system drive; Windows also creates at most one every 24 hours. A missing restore
# point never stops the run.
$script:RunRestorePoint = $false
function New-RunRestorePoint {
    if ($script:RunRestorePoint) { return }
    $script:RunRestorePoint = $true
    if (-not $IsAdmin) { Write-RunLog 'Restore point skipped: turn on "Run elevated" for the scheduled task to create one.'; return }
    try {
        $warn = $null
        Checkpoint-Computer -Description 'Before Windows Manager automatic maintenance' -RestorePointType APPLICATION_INSTALL -WarningAction SilentlyContinue -WarningVariable warn
        if ($warn) { Write-RunLog "Restore point not created: $($warn -join ' ')" } else { Write-RunLog 'Restore point created.' }
    }
    catch { Write-RunLog "Restore point not created: $($_.Exception.Message)" }
}

function Format-Size([double]$Bytes) {
    if ($Bytes -ge 1TB) { return '{0:0.0} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 10GB) { return '{0:0} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1GB) { return '{0:0.0} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:0} MB' -f ($Bytes / 1MB) }
    return '{0:0} KB' -f [Math]::Max(0, $Bytes / 1KB)
}

# The Downloads folder, wherever it has been moved to
function Get-DownloadsFolder {
    try { $p = (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path; if ($p) { return $p } } catch { }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

# What Clean up offers (the Cleanup tab and automatic runs). Admin items need administrator rights; Special ones
# need more than deleting (Windows Update's service stops while its download folder empties; Delivery Optimization
# has its own cmdlet).
function Get-CleanCatalog {
    $sd = $env:SystemDrive; $win = $env:SystemRoot; $pd = $env:ProgramData; $lad = $env:LOCALAPPDATA
    return @(
        @{ Key = 'temp'; Name = 'Temporary files'; About = 'Files in your temporary folder older than two days, left behind by apps and installers.'; Paths = @($env:TEMP); OlderDays = 2; Skip = @('WinGet'); On = $true }
        @{ Key = 'winget'; Name = 'winget downloads'; About = "Installers winget downloaded; they aren't needed once the app is installed."; Paths = @((Join-Path $env:TEMP 'WinGet')); On = $true }
        @{ Key = 'downloads'; Name = 'Old downloads'; About = "Files in your Downloads folder you haven't changed in 90 days. Look first: they may include things you want to keep."; Paths = @((Get-DownloadsFolder)); OlderDays = 90; On = $false }
        @{ Key = 'recycle'; Name = 'Recycle Bin'; About = "Files you deleted. Emptying it can't be undone."; Recycle = $true; On = $false; Always = $true }
        @{ Key = 'crash'; Name = 'App crash dumps'; About = 'Memory dumps apps wrote when they crashed.'; Paths = @((Join-Path $lad 'CrashDumps')); On = $true }
        @{ Key = 'wer'; Name = 'Your error reports'; About = 'Windows Error Reporting files about apps that stopped working.'; Paths = @((Join-Path $lad 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $lad 'Microsoft\Windows\WER\ReportQueue')); On = $true }
        @{ Key = 'appdrv'; Name = "This app's old driver files"; About = "Logs, scan reports and installers in this app's Drivers folder older than 30 days."; Paths = @((Join-Path $DataDir 'Drivers')); OlderDays = 30; On = $true }
        @{ Key = 'backups'; Name = 'Saved drivers'; About = 'Drivers saved for Roll back on the Drivers tab. Once deleted, those devices can''t be rolled back.'; Paths = @((Join-Path $DataDir 'DriverBackups')); On = $false }
        @{ Key = 'wintemp'; Name = 'Windows temporary files'; About = "Files in Windows' own temporary folder older than two days."; Paths = @((Join-Path $win 'Temp')); OlderDays = 2; Admin = $true; On = $true }
        @{ Key = 'wudl'; Name = 'Windows Update downloads'; About = 'Update files Windows has already installed. Windows downloads them again if it needs them; the update service restarts while they go.'; Paths = @((Join-Path $win 'SoftwareDistribution\Download')); Admin = $true; Special = 'wu'; On = $false }
        @{ Key = 'do'; Name = 'Delivery Optimization files'; About = 'Pieces of updates Windows keeps to share with other PCs.'; Admin = $true; Special = 'do'; On = $false; Always = $true }
        @{ Key = 'dumps'; Name = 'Windows crash dumps'; About = "Memory dumps from blue screens (MEMORY.DMP and minidumps). Keep them if someone is looking into why Windows crashed."; Paths = @((Join-Path $win 'Minidump'), (Join-Path $win 'MEMORY.DMP')); Admin = $true; On = $false }
        @{ Key = 'wersys'; Name = 'Windows error reports'; About = 'Error reports Windows keeps for every user and for itself.'; Paths = @((Join-Path $pd 'Microsoft\Windows\WER\ReportArchive'), (Join-Path $pd 'Microsoft\Windows\WER\ReportQueue')); Admin = $true; On = $true }
        @{ Key = 'dell'; Name = 'Dell Command | Update downloads'; About = 'Updates Dell Command | Update downloaded and has finished with.'; Paths = @((Join-Path $pd 'Dell\UpdateService\Downloads')); Admin = $true; On = $true }
        @{ Key = 'nvidia'; Name = 'NVIDIA installer files'; About = "What NVIDIA's driver installers unpacked to $sd\NVIDIA."; Paths = @((Join-Path $sd 'NVIDIA')); Admin = $true; On = $true }
        @{ Key = 'amd'; Name = 'AMD installer files'; About = "What AMD's driver installers unpacked to $sd\AMD."; Paths = @((Join-Path $sd 'AMD')); Admin = $true; On = $true }
    )
}

# ---- App updates: everything winget offers, except hidden (or pinned), explicit and shortened-ID apps -------------
# One pass over the given rows; results land in $Items (keyed Id|Source)
function Invoke-AutoPass($Rows, $Items) {
    foreach ($r in $Rows) { $Sync.Jobs.Enqueue(@{ Key = "$($r.Id)|$($r.Source)"; Id = $r.Id; Name = $r.Name; Source = $r.Source; Explicit = $false; Interactive = $false; Silent = $true; UninstallPrevious = $Settings.UninstallPrevious; Verbose = $Settings.VerboseLogs }) }
    foreach ($ev in (Invoke-WorkerNow 'upgrade' $null)) {
        if ($ev.T -eq 'state' -and $ev.SelfUpdating) { Set-SelfUpdating $ev.Id $true; Write-RunLog "$($ev.Id) is updated by Windows or by itself; automatic updates leave it alone from now on." }
        if ($ev.T -eq 'state' -and $ev.State -in $TerminalStates -and $Items.Contains($ev.Key)) {
            $Items[$ev.Key].State = $ev.State
            $Items[$ev.Key].Detail = if ($ev.State -in 'ok', 'reboot') { "$($ev.Detail): $($Items[$ev.Key].From) to $($Items[$ev.Key].To)" } else { $ev.Detail }
        }
    }
}

function Invoke-AutoApps($R) {
    if (-not $WingetPath) { $R.Error = 'winget is not installed'; return }
    $scan = @(Invoke-WorkerNow 'scan' (Get-ScanArg)) | Where-Object { $_.T -eq 'scan' } | Select-Object -Last 1
    if (-not $scan) { $R.Error = 'the update check stopped unexpectedly'; return }
    if ($scan.Error) { $R.Error = ($scan.Error -split "`n")[0]; return }
    # An empty list can arrive as $null, and $null | Where-Object would pass one empty row through
    $rows = @($scan.Rows | Where-Object { $_ -and $_.Id })
    $todo = @($rows | Where-Object { -not $_.Explicit -and -not $_.Truncated -and -not $_.Pin -and $Settings.Hidden -notcontains $_.Id -and -not (Test-SelfUpdating $_.Id) })
    $left = $rows.Count - $todo.Count
    if ($left) { Write-RunLog "Skipping $left app(s) that are hidden (kept at their version), updated by Windows, or need an explicit upgrade." }
    $items = [ordered]@{}
    foreach ($r in $todo) { $items["$($r.Id)|$($r.Source)"] = [ordered]@{ Name = $r.Name; Id = $r.Id; From = $r.Version; To = $r.Available; State = 'pending'; Detail = "$($r.Version) to $($r.Available)" } }
    $R.Available = $todo.Count
    $R.Listed = $R.Mode -eq 'notify'
    if ($DryRun) { foreach ($i in $items.Values) { $i.Detail = "Would $(if ($R.Listed) { 'list' } else { 'update' }) $($i.From) to $($i.To)" } }
    elseif ($R.Listed) { Write-RunLog "$($todo.Count) app update(s) available; nothing was installed (tell me)." }
    elseif ($todo.Count) {
        if ($Settings.RestorePoint) { New-RunRestorePoint }
        $byKey = @{}
        foreach ($r in $todo) { $byKey["$($r.Id)|$($r.Source)"] = $r }
        Invoke-AutoPass $todo $items
        # One more try for failures that may be temporary (app in use, download hiccup); policy and approval failures are final
        $retry = @($items.Keys | Where-Object { $items[$_].State -in 'error', 'pending' -and $items[$_].Detail -notmatch 'policy|declined|shortened' } | ForEach-Object { $byKey[$_] })
        if ($Settings.AutoRetry -and $retry.Count) {
            Write-RunLog "Retrying $($retry.Count) failed update(s) in 30 seconds."
            Start-Sleep -Seconds 30
            Invoke-AutoPass $retry $items
            foreach ($r in $retry) { $i = $items["$($r.Id)|$($r.Source)"]; if ($i.State -in 'ok', 'reboot') { $i.Detail += ' (second try)' } }
        }
        foreach ($i in $items.Values) {
            switch ($i.State) { 'ok' { $R.Updated++ } 'reboot' { $R.Reboot++ } 'error' { $R.Failed++ } 'pending' { $i.State = 'error'; $i.Detail = 'Did not finish; see the log'; $R.Failed++ } default { $R.Skipped++ } }
            Add-History 'update' $i.Name $i.Id $i.From $i.To $i.State $i.Detail 'auto'
        }
    }
    $R.Items = @($items.Values | ForEach-Object { [pscustomobject]$_ })
}

# ---- Windows updates: security, cumulative, .NET and Defender updates, through Windows Update ----------------------
# Feature updates (a new version of Windows) and optional ones only when chosen. Installing needs administrator
# rights; a task that isn't elevated lists the updates instead. Restarts are never started: the notification says
# when one is needed.
function Invoke-AutoWindows($R) {
    $s = New-Object -ComObject Microsoft.Update.Session
    $s.ClientApplicationID = 'Windows Manager'
    try { $found = $s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Software' and IsHidden=0") }
    catch { $R.Error = "Windows Update couldn't be checked: $($_.Exception.Message)"; return }
    $todo = New-Object System.Collections.Generic.List[object]
    foreach ($u in $found.Updates) {
        $cats = @($u.Categories | ForEach-Object { [string]$_.Name })
        if (($cats -contains 'Upgrades' -or $u.Title -match 'Feature update') -and -not $Settings.AutoWinFeature) { $R.Skipped++; continue }
        if ($u.BrowseOnly -and -not $Settings.AutoWinOptional) { $R.Skipped++; continue }
        $todo.Add($u)
    }
    if ($R.Skipped) { Write-RunLog "Windows Update: $($R.Skipped) optional or feature update(s) are left for you to choose on the Windows Update tab." }
    $R.Available = $todo.Count
    $R.Listed = $R.Mode -eq 'notify'
    if ($R.Mode -eq 'install' -and -not $IsAdmin -and $todo.Count) {
        $R.Listed = $true
        $R.Note = 'Installing Windows updates needs the task to run elevated, so they were only listed.'
        Write-RunLog $R.Note
    }
    $items = @(foreach ($u in $todo) {
            [ordered]@{ Name = [string]$u.Title; Id = [string]$u.Identity.UpdateID; State = 'pending'
                Detail = $(if ($DryRun) { "Would $(if ($R.Listed) { 'list' } else { 'install' }) it" } else { 'Available' })
            }
        })
    if ($DryRun -or $R.Listed -or -not $todo.Count) {
        if (-not $DryRun -and $todo.Count) { Write-RunLog "Windows Update: $($todo.Count) update(s) available; nothing was installed." }
        $R.Items = @($items | ForEach-Object { [pscustomobject]$_ })
        return
    }
    if ($Settings.RestorePoint) { New-RunRestorePoint }
    for ($k = 0; $k -lt $todo.Count; $k++) {
        $u = $todo[$k]; $i = $items[$k]
        try {
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            $one = New-Object -ComObject Microsoft.Update.UpdateColl
            [void]$one.Add($u)
            if (-not $u.IsDownloaded) {
                Write-RunLog "Windows Update: downloading $($u.Title)"
                $dl = $s.CreateUpdateDownloader(); $dl.Updates = $one; $dr = $dl.Download()
                if ($dr.ResultCode -notin 2, 3) { throw ('the download failed (result {0}, 0x{1:X8})' -f $dr.ResultCode, $dr.HResult) }
            }
            Write-RunLog "Windows Update: installing $($u.Title)"
            $in = $s.CreateUpdateInstaller(); $in.Updates = $one
            $ir = $in.Install(); $res = $ir.GetUpdateResult(0)
            if ($res.ResultCode -notin 2, 3) { throw ('it did not install (result {0}, 0x{1:X8})' -f $res.ResultCode, $res.HResult) }
            if ($ir.RebootRequired) { $i.State = 'reboot'; $i.Detail = 'Installed. Restart to finish'; $R.Reboot++ }
            else { $i.State = 'ok'; $i.Detail = 'Installed'; $R.Updated++ }
        }
        catch { $i.State = 'error'; $i.Detail = "Not installed: $($_.Exception.Message)"; $R.Failed++ }
        Write-RunLog "Windows Update: $($i.Name): $($i.Detail)"
        Add-History 'winupdate' $i.Name 'Windows Update' '' '' $i.State $i.Detail 'auto'
    }
    $R.Items = @($items | ForEach-Object { [pscustomobject]$_ })
}

# ---- Cleanup: the Cleanup tab's items chosen for automatic runs ----------------------------------------------------
# Items in Windows' folders need administrator rights; a task that isn't elevated leaves them out. "Tell me" only
# notifies once at least $AutoCleanNotifyBytes can be freed.
function Get-AutoCleanItems {
    $cat = Get-CleanCatalog
    $keys = @($Settings.AutoCleanItems)
    if (-not $keys.Count) { $keys = @($cat | Where-Object { $_.On } | ForEach-Object { $_.Key }) }
    return @($cat | Where-Object { $keys -contains $_.Key })
}

function Set-AutoCleanResult($Item, [long]$Freed, [int]$Failed, $R) {
    $Item.State = 'ok'
    if ($Freed -gt 0) { $R.Freed += $Freed }
    $R.Updated++
    $Item.Detail = "$(if ($Freed -gt 0) { "Freed $(Format-Size $Freed)" } else { 'Nothing to free' })$(if ($Failed) { "; $Failed in use or protected, left alone" })"
}

function Invoke-AutoClean($R) {
    $chosen = Get-AutoCleanItems
    $admin = @($chosen | Where-Object { $_.Admin })
    if ($admin.Count -and -not $IsAdmin) {
        $chosen = @($chosen | Where-Object { -not $_.Admin })
        $R.Note = "$($admin.Count) item$(if ($admin.Count -ne 1) { 's' }) in Windows' folders need$(if ($admin.Count -eq 1) { 's' }) the task to run elevated, so $(if ($admin.Count -ne 1) { 'they were' } else { 'it was' }) left out."
        Write-RunLog $R.Note
    }
    if (-not $chosen.Count) { return }
    $arg = { param($List) , @($List | ForEach-Object { @{ Key = $_.Key; Paths = @($_.Paths); OlderDays = [int]$_.OlderDays; Skip = @($_.Skip); Recycle = [bool]$_.Recycle } }) }
    $items = [ordered]@{}
    foreach ($c in $chosen) { $items[$c.Key] = [ordered]@{ Name = $c.Name; Id = $c.Key; State = 'pending'; Detail = ''; Bytes = [long]0 } }
    # how much each item takes (Delivery Optimization's cache is measured by Windows, below)
    $measure = @($chosen | Where-Object { $_.Special -ne 'do' })
    if ($measure.Count) { foreach ($ev in (Invoke-WorkerNow 'cleanscan' @{ Items = (& $arg $measure) })) { if ($ev.T -eq 'cleansize' -and $items.Contains($ev.Key)) { $items[$ev.Key].Bytes = [long]$ev.Bytes } } }
    if ($items.Contains('do')) { try { $items['do'].Bytes = [long](Get-DeliveryOptimizationStatus -ErrorAction Stop | Measure-Object -Property FileSizeInCache -Sum).Sum } catch { $items['do'].Bytes = [long]-1 } }
    foreach ($i in $items.Values) { if ($i.Bytes -gt 0) { $R.Bytes += $i.Bytes } }
    $R.Listed = $R.Mode -eq 'notify'
    if ($DryRun -or $R.Listed) {
        foreach ($i in $items.Values) {
            $i.Detail = if ($i.Bytes -gt 0) { "$(if ($DryRun -and -not $R.Listed) { 'Would free' } else { 'Can free' }) $(Format-Size $i.Bytes)" } elseif ($i.Bytes -lt 0) { 'Size unknown' } else { 'Nothing to free' }
        }
        if (-not $DryRun) { Write-RunLog "Cleanup: $(Format-Size $R.Bytes) can be freed; nothing was deleted (tell me)." }
    }
    else {
        $plain = @($chosen | Where-Object { -not $_.Special })
        if ($plain.Count) { foreach ($ev in (Invoke-WorkerNow 'clean' @{ Items = (& $arg $plain) })) { if ($ev.T -eq 'cleaned' -and $items.Contains($ev.Key)) { Set-AutoCleanResult $items[$ev.Key] ([long]$ev.Freed) ([int]$ev.Failed) $R } } }
        $special = @($chosen | Where-Object { $_.Special })
        if ($special.Count) {
            . ([scriptblock]::Create($CleanFunctions))
            foreach ($c in $special) {
                $freed = [long]0; $failed = 0
                if ($c.Special -eq 'wu') {
                    Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
                    foreach ($p in @($c.Paths)) { $x = Remove-CleanPath $p 0 @(); $freed += $x.Freed; $failed += $x.Failed }
                    Start-Service -Name bits, wuauserv -ErrorAction SilentlyContinue
                }
                elseif ($c.Special -eq 'do') {
                    try { $freed = [Math]::Max([long]0, $items['do'].Bytes); Delete-DeliveryOptimizationCache -Force -ErrorAction Stop }
                    catch { $freed = [long]0; $failed++; Write-RunLog "Delivery Optimization: $($_.Exception.Message)" }
                }
                Set-AutoCleanResult $items[$c.Key] $freed $failed $R
            }
        }
        foreach ($i in @($items.Values | Where-Object { $_.State -eq 'pending' })) { $i.State = 'error'; $i.Detail = 'Did not finish; see the log'; $R.Failed++ }
        $done = @($items.Values | Where-Object { $_.State -eq 'ok' } | ForEach-Object { $_.Name })
        if ($done.Count) {
            $what = (@($done) | Select-Object -First 4) -join ', '
            if ($done.Count -gt 4) { $what += ", and $($done.Count - 4) more" }
            Add-History 'cleanup' $what '' '' '' 'ok' "Freed $(Format-Size $R.Freed)" 'auto'
        }
    }
    # what can be (or was) freed, and what went wrong; items with nothing to free only go in the log
    foreach ($i in $items.Values) { Write-RunLog "Cleanup: $($i.Name): $($i.Detail)" }
    $R.Items = @($items.Values | Where-Object { $_.Detail -notlike 'Nothing to free' } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Id = $_.Id; State = $_.State; Detail = $_.Detail } })
}

# ---- Health check: a reading for Device Health's trends, and a notification about any new problem -----------------
# Problems get their own notification (Invoke-HealthAlerts), each once and again after a week if still there.
function Invoke-AutoHealth($R) {
    $R.Listed = $true
    if ($DryRun) { return }
    $hev = @(Invoke-WorkerNow 'health' @{}) | Where-Object { $_.T -eq 'health' } | Select-Object -Last 1
    if (-not $hev) { $R.Error = 'the health check stopped unexpectedly'; return }
    Add-HealthSnapshot $hev
    $alerts = @(Get-HealthAlerts $hev)
    $R.Available = $alerts.Count
    $R.Items = @($alerts | ForEach-Object { [pscustomobject]@{ Name = $_.Text; Id = $_.Key; State = 'warn'; Detail = '' } })
    Invoke-HealthAlerts $hev
}

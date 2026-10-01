# Windows Manager - HealthHistory (part of src\; see Windows_Manager.ps1)

# Device Health over time: one reading a day (the latest of the day wins) in health-history.jsonl, from the app and
# from automatic runs, kept for 400 days. Device Health draws its trends from it. Automatic runs also look the
# reading over and notify about problems (Settings.HealthAlerts): each problem once, and again after a week if it is
# still there.
$HealthHistoryPath = Join-Path $DataDir 'health-history.jsonl'
$HealthAlertsPath = Join-Path $DataDir 'health-alerts.json'

function Add-HealthSnapshot($h) {
    if (-not $h -or -not $h.Sys) { return }
    $sys = @($h.Volumes | Where-Object { $_.Letter -eq $env:SystemDrive }) | Select-Object -First 1
    $b = $h.Battery
    $p = $h.Perf
    $r = $h.Reliability
    $snap = [ordered]@{
        Date        = (Get-Date).ToString('yyyy-MM-dd')
        Battery     = $(if ($b -and $b.Design -gt 0 -and $b.Full -gt 0) { [Math]::Round(100.0 * $b.Full / $b.Design, 1) } else { $null })
        Cycles      = $(if ($b) { $b.Cycles } else { $null })
        SysFreeGB   = $(if ($sys) { [Math]::Round($sys.Free / 1GB, 1) } else { $null })
        SysSizeGB   = $(if ($sys) { [Math]::Round($sys.Size / 1GB, 1) } else { $null })
        MemUsedPct  = $(if ($p -and $p.MemTotal) { [Math]::Round(100.0 * ($p.MemTotal - $p.MemFree) / $p.MemTotal) } else { $null })
        Stability   = $(if ($r -and $null -ne $r.Index) { [Math]::Round($r.Index, 2) } else { $null })
        Crashes7    = $(if ($r) { $r.Crashes } else { $null })
        Shutdowns30 = $(if ($r) { $r.Shutdowns } else { $null })
        BlueScreens30 = $(if ($r) { $r.BlueScreens } else { $null })
        DiskWear    = $(@($h.Disks | Where-Object { $null -ne $_.Wear } | ForEach-Object { [int]$_.Wear }) | Measure-Object -Maximum).Maximum
        LatencyMs   = $(if ($h.Quality -and $h.Quality.Internet -and $null -ne $h.Quality.Internet.Ms) { [Math]::Round($h.Quality.Internet.Ms) } else { $null })
    }
    try {
        $keep = @(Read-HealthHistory | Where-Object { $_.Date -ne $snap.Date -and [datetime]$_.Date -ge (Get-Date).AddDays(-400) } | ForEach-Object { $_ | ConvertTo-Json -Compress })
        $keep += ([pscustomobject]$snap | ConvertTo-Json -Compress)
        [IO.File]::WriteAllLines($HealthHistoryPath, [string[]]$keep, (New-Object Text.UTF8Encoding($false)))
    }
    catch { }
}

# The readings, oldest first
function Read-HealthHistory {
    if (-not (Test-Path -LiteralPath $HealthHistoryPath)) { return }
    $list = foreach ($l in [IO.File]::ReadAllLines($HealthHistoryPath)) { if ($l.Trim()) { try { $l | ConvertFrom-Json } catch { } } }
    # one object per reading (callers pipe it)
    $list | Sort-Object Date
}

# What in a health reading needs attention, each with a key (to mention it once) and a sentence
function Get-HealthAlerts($h) {
    $alerts = New-Object System.Collections.Generic.List[object]
    if (-not $h -or -not $h.Sys) { return , $alerts.ToArray() }
    $add = { param($Key, $Text) $alerts.Add(@{ Key = $Key; Text = $Text }) }
    $s = $h.Security
    if ($s) {
        if (-not @($s.Av | Where-Object { $_.On }).Count) { & $add 'av-off' 'No antivirus is turned on.' }
        if ($s.Defender -and $s.Defender.On -and -not $s.Defender.Realtime) { & $add 'rtp-off' "Microsoft Defender's real-time protection is off." }
        if ($s.Defender -and $s.Defender.On -and $s.Defender.SigAge -gt 7) { & $add 'sig-old' "Virus definitions are $($s.Defender.SigAge) days old." }
        $offFw = @($s.Firewall | Where-Object { -not $_.On } | ForEach-Object { $_.Name })
        if ($offFw.Count) { & $add "fw-$($offFw -join '-')" "The firewall is off for $($offFw -join ', ') networks." }
    }
    foreach ($v in @($h.Volumes)) { if ($v.Size -and $v.Free / $v.Size -lt 0.1) { & $add "full-$($v.Letter)" ("Drive $($v.Letter) is nearly full: {0:0.0} GB free." -f ($v.Free / 1GB)) } }
    foreach ($d in @($h.Disks)) { if ($d.Health -and $d.Health -ne 'Healthy') { & $add "disk-$($d.Name)" "The disk $($d.Name) reports $($d.Health): back up your files." } }
    $b = $h.Battery
    if ($b -and $b.Design -gt 0 -and $b.Full -gt 0 -and $b.Full / $b.Design -lt 0.6) { & $add 'battery' ("The battery holds {0:0}% of what it did new." -f (100.0 * $b.Full / $b.Design)) }
    if ($h.Reliability -and $h.Reliability.BlueScreens) { & $add "bsod-$($h.Reliability.BlueScreens)" "Windows had $($h.Reliability.BlueScreens) blue screen$(if ($h.Reliability.BlueScreens -ne 1) { 's' }) in the last 30 days." }
    if ($h.Reboot -and $h.Sys.Boot -and ((Get-Date) - [datetime]$h.Sys.Boot).TotalDays -ge 3) { & $add 'restart' 'A restart has been waiting to finish updates for days.' }
    return , $alerts.ToArray()
}

# Automatic runs: notify about problems that are new, or still there after a week
function Invoke-HealthAlerts($h) {
    $alerts = Get-HealthAlerts $h
    $seen = @{}
    try { if (Test-Path -LiteralPath $HealthAlertsPath) { $j = Get-Content -LiteralPath $HealthAlertsPath -Raw | ConvertFrom-Json; foreach ($p in $j.PSObject.Properties) { $seen[$p.Name] = [datetime]$p.Value } } } catch { }
    $due = @($alerts | Where-Object { -not $seen.ContainsKey($_.Key) -or ((Get-Date) - $seen[$_.Key]).TotalDays -ge 7 })
    # remember what was mentioned when; problems that went away are forgotten, so they're mentioned again if they return
    $now = [ordered]@{}
    foreach ($a in $alerts) { $now[$a.Key] = $(if ($due -contains $a) { (Get-Date).ToString('o') } else { $seen[$a.Key].ToString('o') }) }
    try { [pscustomobject]$now | ConvertTo-Json | Set-Content -LiteralPath $HealthAlertsPath -Encoding UTF8 } catch { }
    Write-RunLog "Health check: $(if ($alerts.Count) { ($alerts | ForEach-Object { $_.Text }) -join ' ' } else { 'nothing needs attention.' })"
    if (-not $due.Count) { return }
    $title = if ($due.Count -eq 1) { 'Your PC needs a look' } else { "$($due.Count) things on your PC need a look" }
    $shown = Show-Toast $title $due[0].Text $(if ($due.Count -gt 1) { (@($due | Select-Object -Skip 1 | ForEach-Object { $_.Text }) -join ' ') } else { 'Open Windows Manager > Device Health for details.' }) -Important
    if (-not $shown) { Write-RunLog 'The health notification could not be shown.' }
}

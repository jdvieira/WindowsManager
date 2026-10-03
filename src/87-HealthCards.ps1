# Windows Manager - HealthCards (part of src\; see Windows_Manager.ps1)

# Device Health's check cards: Security, Performance, Reliability, Updates, Network, Cleanup and Temperatures. Each
# line is a HealthCheck (a dot that is green, amber, red or grey, what it is, and its value). Update-HealthCards returns
# how many lines need attention, for the summary at the top.
function New-Check([string]$Label, [string]$Value, [string]$Level = 'ok', [string]$Tip = '') {
    $c = New-Object WingetUM.HealthCheck
    $c.Label = $Label; $c.Value = $Value; $c.Level = $Level; $c.Tip = $(if ($Tip) { $Tip } else { "$Label`: $Value" })
    return $c
}
# A blue screen's stop code in plain words (the common ones): Windows' own name, a few words for the card, and a sentence
$StopCodes = @{
    0x0A = 'IRQL_NOT_LESS_OR_EQUAL|driver memory error|a driver used memory it shouldn''t have'
    0x1A = 'MEMORY_MANAGEMENT|memory error|memory management failed, often faulty memory'
    0x1E = 'KMODE_EXCEPTION_NOT_HANDLED|driver error|a driver hit an error it didn''t handle'
    0x19 = 'BAD_POOL_HEADER|damaged memory|Windows found damaged data in memory'
    0x3B = 'SYSTEM_SERVICE_EXCEPTION|system service error|a system service or driver hit an error'
    0x50 = 'PAGE_FAULT_IN_NONPAGED_AREA|memory error|missing memory, from a driver or faulty memory'
    0x7A = 'KERNEL_DATA_INPAGE_ERROR|drive read error|Windows couldn''t read from the drive'
    0x7E = 'SYSTEM_THREAD_EXCEPTION_NOT_HANDLED|driver error|a driver hit an error it didn''t handle'
    0x7F = 'UNEXPECTED_KERNEL_MODE_TRAP|processor error|the processor hit an error (hardware or overclocking)'
    0x9F = 'DRIVER_POWER_STATE_FAILURE|driver sleep or wake error|a driver didn''t respond to sleep or wake'
    0xC2 = 'BAD_POOL_CALLER|driver memory error|a driver damaged memory'
    0xD1 = 'DRIVER_IRQL_NOT_LESS_OR_EQUAL|driver memory error|a driver used memory it shouldn''t have'
    0xEF = 'CRITICAL_PROCESS_DIED|Windows process stopped|a critical Windows process stopped'
    0xF4 = 'CRITICAL_OBJECT_TERMINATION|Windows process stopped|a critical process stopped, often the system drive'
    0x101 = 'CLOCK_WATCHDOG_TIMEOUT|processor stopped responding|a processor core stopped responding (hardware or overclocking)'
    0x116 = 'VIDEO_TDR_FAILURE|graphics driver stopped|the graphics driver stopped responding'
    0x119 = 'VIDEO_SCHEDULER_INTERNAL_ERROR|graphics error|the graphics driver or card hit an error'
    0x124 = 'WHEA_UNCORRECTABLE_ERROR|hardware error|a hardware error (processor, memory or overheating)'
    0x133 = 'DPC_WATCHDOG_VIOLATION|driver took too long|a driver took too long, often storage or graphics'
    0x139 = 'KERNEL_SECURITY_CHECK_FAILURE|damaged data|Windows found damaged data, from a driver or faulty memory'
    0x154 = 'UNEXPECTED_STORE_EXCEPTION|storage error|a storage error, from the drive or its driver'
    0x20001 = 'HYPERVISOR_ERROR|virtualization error|virtualization (Hyper-V) hit an error'
}
function Get-StopCodeText([string]$Code) {
    $n = try { [Convert]::ToUInt32($Code, 16) } catch { $null }
    if ($null -ne $n -and $StopCodes.ContainsKey([int]$n)) { $p = $StopCodes[[int]$n].Split('|'); return @{ Name = $p[0]; Short = $p[1]; Text = $p[2] } }
    $s = if ($Code) { "stop code $Code" } else { 'reason not recorded' }; return @{ Name = ''; Short = $s; Text = $s }
}
# A link speed ("1 Gbps", "866.7 Mbps") as a dot: wired 1 Gbps and up green, 100 Mbps amber, slower red; Wi-Fi's
# speeds run lower, so 200 Mbps and up is green there and under 50 Mbps red
function Get-LinkSpeedLevel([string]$Speed, [bool]$Wireless) {
    $m = [regex]::Match($Speed, '([\d.,]+)\s*([KMG])bps', 'IgnoreCase')
    if (-not $m.Success) { return 'info' }
    $mbps = [double]($m.Groups[1].Value -replace ',', '.') * $(switch ($m.Groups[2].Value.ToUpperInvariant()) { 'G' { 1000 } 'K' { 0.001 } default { 1 } })
    if ($Wireless) { if ($mbps -ge 200) { return 'ok' } elseif ($mbps -ge 50) { return 'warn' } else { return 'bad' } }
    if ($mbps -ge 1000) { return 'ok' } elseif ($mbps -ge 100) { return 'warn' } else { return 'bad' }
}
function Format-Days([int]$Days) { if ($Days -le 0) { 'today' } elseif ($Days -eq 1) { 'yesterday' } else { "$Days days ago" } }
function Format-Ms($Ms) { if ($Ms -lt 1) { 'under 1 ms' } else { '{0:0} ms' -f $Ms } }

# The Network card's connection quality lines, from the worker's round trips (h.Quality): the router, the internet
# (time, lost replies, how much the times vary) and DNS. A line is amber or red when it would make the connection
# feel slow: calls and games stutter past about 100 ms or 30 ms of jitter, pages hang when replies go missing.
function Get-NetQualityChecks($q, [bool]$Internet) {
    $list = New-Object System.Collections.Generic.List[object]
    if (-not $q) { return , $list.ToArray() }
    $g = $q.Gateway
    if ($g) {
        if ($null -eq $g.Ms) { $list.Add((New-Check 'Router' "No reply from $($g.Target)" 'info' "The router ($($g.Target)) didn't answer ping. Many don't, so this alone isn't a problem")) }
        else { $list.Add((New-Check 'Router' "$(Format-Ms $g.Ms)$(if ($g.Loss) { ", $($g.Loss)% lost" })" $(if ($g.Ms -ge 100 -or $g.Loss -gt 25) { 'bad' } elseif ($g.Ms -ge 20 -or $g.Loss) { 'warn' } else { 'ok' }) "Round trip to your router ($($g.Target)). Slow or lost replies here point at Wi-Fi signal or the cable, not your internet provider")) }
    }
    $i = $q.Internet
    if ($i -and $null -ne $i.Ms) {
        $how = if ($i.Method -eq 'tcp') { ' (ping is blocked, so timed by connecting)' } else { '' }
        $list.Add((New-Check 'Latency' (Format-Ms $i.Ms) $(if ($i.Ms -gt 200) { 'bad' } elseif ($i.Ms -gt 100) { 'warn' } else { 'ok' }) "Average round trip to the internet ($($i.Target))$how. Under 100 ms is good; over 200 ms makes calls and games lag"))
        if ($null -ne $i.Loss) { $list.Add((New-Check 'Packet loss' "$($i.Loss)%" $(if ($i.Loss -gt 20) { 'bad' } elseif ($i.Loss) { 'warn' } else { 'ok' }) 'Replies from the internet that never came back. Any loss makes pages hang and calls break up')) }
        if ($null -ne $i.Jitter) { $list.Add((New-Check 'Jitter' (Format-Ms $i.Jitter) $(if ($i.Jitter -gt 30) { 'warn' } else { 'ok' }) 'How much the round trip varies from one reply to the next. Over 30 ms makes calls and video stutter')) }
    }
    elseif ($i -and $Internet) { $list.Add((New-Check 'Latency' "No reply from $($i.Target)" 'bad' "Windows says there's internet access, but $($i.Target) didn't answer ping or a connection")) }
    $d = $q.Dns
    if ($d) {
        $from = if ($d.Server) { " from $($d.Server)" } else { '' }
        if ($null -eq $d.Ms) { $list.Add((New-Check 'DNS lookup' 'Failed' $(if ($Internet) { 'bad' } else { 'warn' }) "Looking up web addresses$from didn't work, so websites won't open by name")) }
        else { $list.Add((New-Check 'DNS lookup' "$(Format-Ms $d.Ms)$(if ($d.Failed) { ", $($d.Failed) of 2 failed" })" $(if ($d.Ms -gt 500) { 'bad' } elseif ($d.Ms -gt 150 -or $d.Failed) { 'warn' } else { 'ok' }) "How long looking up a web address takes$from. Slow lookups make every new website slow to start")) }
    }
    return , $list.ToArray()
}

# The Temperatures card (h.Temps): a block per processor and graphics card with each of its sensors. With
# LibreHardwareMonitor (or OpenHardwareMonitor) running that's every core, the package, and the GPU's core, hot spot
# and memory; without it, what Windows itself reports: one reading per graphics card and the ACPI thermal zone.
# Cores and GPU cores are amber from 85 C and red from 95 C, where most start slowing themselves down to cool off;
# hot spot and memory sensors run hotter by design, so 95 C and 105 C. Returns how many blocks need attention.
function New-TempGroup([string]$Name, $Items) {
    $g = New-Object WingetUM.HealthTempGroup
    $g.Name = $Name; $g.Items = [WingetUM.HealthCheck[]]@($Items)
    return $g
}
function Update-TempCard($t) {
    $deg = "$([char]0x00B0)C"
    $groups = New-Object System.Collections.Generic.List[object]
    $issues = 0
    $UI.HlTempGet.Visibility = 'Collapsed'
    if (-not $t) { $UI.HlTempNote.Text = "Reading temperatures$Ellipsis"; $UI.HlTempGroups.ItemsSource = $null; return 0 }
    $check = {
        param([string]$Label, $C, $Max, [string]$Tip)
        $hot = $Label -match 'Hot ?Spot|Memory|Junction'
        $lv = if ($C -ge $(if ($hot) { 105 } else { 95 })) { 'bad' } elseif ($C -ge $(if ($hot) { 95 } else { 85 })) { 'warn' } else { 'ok' }
        New-Check $Label "$C $deg$(if ($null -ne $Max -and $Max -gt $C) { "   (max $Max)" })" $lv $(if ($Tip) { $Tip } else { "$Label`: $C $deg now$(if ($null -ne $Max) { ", $Max $deg at most since $($t.Monitor) started" })" })
    }
    $detail = @($t.Detail)
    $cpus = @($detail | Where-Object { $_.Kind -eq 'cpu' })
    $gpus = @($detail | Where-Object { $_.Kind -eq 'gpu' })
    foreach ($d in $cpus + $gpus) { $groups.Add((New-TempGroup $d.Name @($d.Sensors | ForEach-Object { & $check $_.Name $_.C $_.Max '' }))) }
    if (-not $cpus.Count) {
        $groups.Insert(0, $(if ($t.Zone) { New-TempGroup 'Processor (Windows thermal zone)' @(& $check 'Thermal zone' $t.Zone.C $null "Windows' ACPI thermal zone ($($t.Zone.Name)). On laptops it usually follows the processor; on many desktops it's the motherboard") }
                else { New-TempGroup 'Processor' @(New-Check 'Cores' 'Not reported' 'info' "Windows doesn't read the processor's own sensors") }))
    }
    if (-not $gpus.Count) { foreach ($g in @($t.Gpus)) { $groups.Add((New-TempGroup $g.Name @(& $check 'GPU' $g.C $null "$($g.Name), as its driver reports it to Windows"))) } }
    foreach ($g in $groups) { if (@($g.Items | Where-Object { $_.Level -in 'warn', 'bad' }).Count) { $issues++ } }
    $UI.HlTempGroups.ItemsSource = $groups.ToArray()
    if ($t.Monitor) { $UI.HlTempNote.Text = "Every sensor, from $($t.Monitor). Max is the highest since it started." }
    else {
        $UI.HlTempNote.Text = "Windows reports one temperature per graphics card and none for the processor's cores. For every core, the package, and the GPU's hot spot and memory, keep LibreHardwareMonitor running (it's free, and asks for administrator rights)." +
        $(if ($t.MonitorRunning) { " It's running but hasn't reported yet: refresh in a few seconds." } elseif ($t.MonitorExe) { " It's installed but not running." } else { '' })
        if (-not $t.MonitorRunning) {
            $UI.HlTempGet.Content = if ($t.MonitorExe) { 'Start LibreHardwareMonitor' } else { 'Get LibreHardwareMonitor' }
            $UI.HlTempGet.ToolTip = if ($t.MonitorExe) { "Start it (Windows asks for administrator approval); this card refreshes once it's reading" } else { 'Find it on Discover to install it with winget' }
            $UI.HlTempGet.Tag = [string]$t.MonitorExe
            $UI.HlTempGet.Visibility = 'Visible'
        }
    }
    return $issues
}

function Update-HealthCards($h) {
    $issues = 0
    # ---- Security
    $s = $h.Security
    $sec = New-Object System.Collections.Generic.List[object]
    if ($s) {
        $on = @($s.Av | Where-Object { $_.On })
        if ($on.Count) { $sec.Add((New-Check 'Antivirus' (($on | ForEach-Object { $_.Name }) -join ', ') $(if (@($on | Where-Object { -not $_.Current }).Count) { 'warn' } else { 'ok' }))) }
        elseif (@($s.Av).Count) { $sec.Add((New-Check 'Antivirus' "$(@($s.Av)[0].Name) is off" 'bad')) }
        else { $sec.Add((New-Check 'Antivirus' 'None reported' 'bad')) }
        if ($s.Defender -and $s.Defender.On) {
            $sec.Add((New-Check 'Real-time protection' $(if ($s.Defender.Realtime) { 'On' } else { 'Off' }) $(if ($s.Defender.Realtime) { 'ok' } else { 'bad' })))
            $sec.Add((New-Check 'Virus definitions' "Updated $(Format-Days $s.Defender.SigAge)" $(if ($s.Defender.SigAge -gt 3) { 'warn' } else { 'ok' })))
            $sec.Add((New-Check 'Last quick scan' $(if ($s.Defender.ScanAge -gt 30000) { 'Never' } else { Format-Days $s.Defender.ScanAge }) $(if ($s.Defender.ScanAge -gt 14) { 'warn' } else { 'ok' })))
        }
        $fw = @($s.Firewall)
        if ($fw.Count) {
            $offFw = @($fw | Where-Object { -not $_.On } | ForEach-Object { $_.Name })
            $sec.Add((New-Check 'Firewall' $(if ($offFw.Count) { "Off for $($offFw -join ', ')" } else { 'On' }) $(if ($offFw.Count) { 'bad' } else { 'ok' })))
        }
        $bl = switch ([string]$s.BitLocker) { { $_ -in '1', '6' } { @('On', 'ok') } '2' { @('Off', 'warn') } '3' { @('Encrypting', 'info') } '4' { @('Decrypting', 'warn') } '5' { @('Suspended', 'warn') } default { @('Not available', 'info') } }
        $sec.Add((New-Check "BitLocker ($env:SystemDrive)" $bl[0] $bl[1] 'Drive encryption: if the PC is lost or stolen, the files on it stay unreadable'))
        $sec.Add((New-Check 'Secure Boot' $(if ($s.SecureBoot -eq 1) { 'On' } elseif ($null -ne $s.SecureBoot) { 'Off' } else { 'Not reported' }) $(if ($s.SecureBoot -eq 1) { 'ok' } elseif ($null -ne $s.SecureBoot) { 'warn' } else { 'info' })))
        $sec.Add((New-Check 'TPM' $(if ($s.Tpm -match '(\d\.\d)') { "Version $($Matches[1])" } elseif ($s.Tpm) { 'Present' } else { 'Not found' }) $(if ($s.Tpm) { 'ok' } else { 'warn' })))
        if ($null -ne $s.License) { $sec.Add((New-Check 'Windows activation' $(if ($s.License -eq 1) { 'Activated' } else { 'Not activated' }) $(if ($s.License -eq 1) { 'ok' } else { 'warn' }))) }
    }
    $UI.HlSecItems.ItemsSource = $sec.ToArray()
    $bad = @($sec | Where-Object { $_.Level -in 'warn', 'bad' }).Count; $issues += $bad
    $UI.HlSecTitle.Text = if (-not $s) { $Ellipsis } elseif ($bad) { "$bad thing$(if ($bad -ne 1) { 's' }) to check" } else { 'Protected' }

    # ---- Performance
    $p = $h.Perf
    $perf = New-Object System.Collections.Generic.List[object]
    if ($p -and $p.MemTotal) {
        $used = 100.0 * ($p.MemTotal - $p.MemFree) / $p.MemTotal
        $UI.HlPerfTitle.Text = "Memory {0:0}% in use" -f $used
        $UI.HlMemBar.Value = $used
        $UI.HlMemBar.Foreground = if ($used -ge 90) { $Window.FindResource('Bad') } elseif ($used -ge 80) { $Window.FindResource('Warn') } else { $Window.FindResource('BarGradient') }
        $perf.Add((New-Check 'Memory' "$(Format-Size $p.MemFree) free of $(Format-Size $p.MemTotal)" $(if ($used -ge 90) { 'bad' } elseif ($used -ge 80) { 'warn' } else { 'ok' })))
        if ($null -ne $p.Cpu) { $perf.Add((New-Check 'Processor' "$($p.Cpu)% busy right now" $(if ($p.Cpu -ge 85) { 'warn' } else { 'ok' }))) }
        $perf.Add((New-Check 'Programs running' "$($p.Processes) processes" 'info'))
        if ($script:StartupState -eq 'ready') { $on = @($StartupItems | Where-Object { $_.Enabled }).Count; $perf.Add((New-Check 'Start with Windows' "$on apps" $(if ($on -gt 20) { 'warn' } else { 'info' }) 'Fewer startup apps make sign-in quicker: see the Startup tab')) }
    }
    else { $UI.HlPerfTitle.Text = $Ellipsis; $UI.HlMemBar.Value = 0 }
    $UI.HlPerfItems.ItemsSource = $perf.ToArray()
    # the apps using the most memory, in their own section: each bar is against the biggest of them
    $top = @($p.Top | Where-Object { $_ -and $_.Bytes -gt 0 })
    # (the worker's entries are hashtables, which Measure-Object -Property can't read)
    $most = [double]0; foreach ($t in $top) { if ([double]$t.Bytes -gt $most) { $most = [double]$t.Bytes } }
    $UI.HlTopMem.ItemsSource = @(foreach ($t in $top) { $v = New-Object WingetUM.HealthVolume; $v.Name = [string]$t.Name; $v.Detail = Format-Size $t.Bytes; $v.UsedPct = 100.0 * $t.Bytes / $most; $v.Level = 'info'; $v })
    $UI.HlTopMemPanel.Visibility = ConvertTo-Visibility ([bool]$top.Count)
    $issues += @($perf | Where-Object { $_.Level -in 'warn', 'bad' }).Count

    # ---- Reliability
    $r = $h.Reliability
    $rel = New-Object System.Collections.Generic.List[object]
    if ($r) {
        if ($null -ne $r.Shutdowns) { $rel.Add((New-Check 'Unexpected shutdowns' "$($r.Shutdowns) in 30 days" $(if ($r.Shutdowns) { 'warn' } else { 'ok' }) 'Times Windows stopped without shutting down properly (power loss, a hang, a forced power-off)')) }
        if ($null -ne $r.BlueScreens) { $rel.Add((New-Check 'Blue screens' "$($r.BlueScreens) in 30 days" $(if ($r.BlueScreens) { 'bad' } else { 'ok' }))) }
        if ($r.LastBsod) {
            $why = Get-StopCodeText ([string]$r.LastBsod.Code)
            $when = ([datetime]$r.LastBsod.Time).ToString('MMM d')
            $rel.Add((New-Check 'Last blue screen' "$when, $($why.Short)" $(if (((Get-Date) - [datetime]$r.LastBsod.Time).TotalDays -le 7) { 'bad' } else { 'warn' }) "Last blue screen: $(([datetime]$r.LastBsod.Time).ToString('g')). $($why.Text) (stop code $($r.LastBsod.Code)$(if ($why.Name) { ', ' + $why.Name }))"))
        }
        $hwText = if (-not $r.Hardware) { 'None in 30 days' } elseif ($r.HardwareFatal) { [string]$r.Hardware + ' in 30 days, ' + $r.HardwareFatal + ' serious' } else { [string]$r.Hardware + ' in 30 days' }
        if ($null -ne $r.Hardware) { $rel.Add((New-Check 'Hardware errors' $hwText $(if ($r.HardwareFatal -or $r.Hardware -ge 10) { 'bad' } elseif ($r.Hardware) { 'warn' } else { 'ok' }) 'Errors the processor, memory or other hardware reported to Windows (WHEA). With blue screens, they often point at the hardware, its BIOS settings or overclocking')) }
        if ($null -ne $r.DiskErrors) { $rel.Add((New-Check 'Disk errors' $(if ($r.DiskErrors) { "$($r.DiskErrors) in 30 days" } else { 'None in 30 days' }) $(if ($r.DiskErrors) { 'bad' } else { 'ok' }) 'Bad blocks, failed reads and file system errors Windows logged. Any at all: back up, and check the drive')) }
        if ($null -ne $r.Crashes) {
            $rel.Add((New-Check 'App crashes' "$($r.Crashes) in 7 days" $(if ($r.Crashes -ge 10) { 'bad' } elseif ($r.Crashes) { 'warn' } else { 'ok' }) 'Apps that stopped working in the last 7 days: amber with any, red with 10 or more'))
            if (@($r.CrashApps).Count) { $rel.Add((New-Check 'Crashed most' (@($r.CrashApps) -join ', ') 'info')) }
        }
        if ($null -ne $r.Hangs) { $rel.Add((New-Check 'Apps not responding' "$($r.Hangs) in 7 days" $(if ($r.Hangs -ge 5) { 'warn' } else { 'ok' }) 'Apps Windows had to close because they stopped responding: amber from 5')) }
        if ($null -ne $r.UpdateFails) { $rel.Add((New-Check 'Failed updates' $(if ($r.UpdateFails) { "$($r.UpdateFails) in 30 days" } else { 'None in 30 days' }) $(if ($r.UpdateFails) { 'warn' } else { 'ok' }) 'Windows updates that failed to install. Fix my PC or the Windows Update tab can try them again')) }
        if ($null -ne $r.Devices) { $rel.Add((New-Check 'Device problems' $(if ($r.Devices) { "$($r.Devices) device$(if ($r.Devices -ne 1) { 's' })" } else { 'None' }) $(if ($r.Devices) { 'warn' } else { 'ok' }) 'Devices Windows reports a problem for: see Drivers > Devices')) }
        $UI.HlRelTitle.Text = if ($null -ne $r.Index) { "Stability {0:0.0} of 10" -f $r.Index } else { 'Reliability' }
    }
    else { $UI.HlRelTitle.Text = $Ellipsis }
    $UI.HlRelItems.ItemsSource = $rel.ToArray()
    $issues += @($rel | Where-Object { $_.Level -in 'warn', 'bad' }).Count

    # ---- Updates (from the other tabs' checks)
    $upd = New-Object System.Collections.Generic.List[object]
    $waiting = 0
    $soft = @($Packages | Where-Object { -not $_.IsDone -and -not $_.IsConcealed }).Count
    $upd.Add($(switch ($script:Mode) {
                'ready' { $waiting += $soft; New-Check 'Software' $(if ($soft) { "$soft update$(if ($soft -ne 1) { 's' })" } else { 'Up to date' }) $(if ($soft) { 'warn' } else { 'ok' }) }
                'loading' { New-Check 'Software' "Checking$Ellipsis" 'info' }
                'error' { New-Check 'Software' "Couldn't check" 'warn' }
                default { New-Check 'Software' 'Not checked yet' 'info' }
            }))
    $win = @($WinUpdates | Where-Object { -not $_.Optional }).Count
    $upd.Add($(switch ($script:WinState) {
                'ready' { $waiting += $win; New-Check 'Windows' $(if ($win) { "$win update$(if ($win -ne 1) { 's' })" } else { 'Up to date' }) $(if ($win) { 'warn' } else { 'ok' }) }
                'running' { New-Check 'Windows' "Checking$Ellipsis" 'info' }
                'error' { New-Check 'Windows' "Couldn't check" 'warn' }
                default { New-Check 'Windows' 'Not checked yet' 'info' }
            }))
    $drv = @($DrvUpdates | Where-Object { -not $_.HasAction -or $_.Kind -eq 'amd' }).Count
    $upd.Add($(if ($script:WuState -eq 'ready' -or $script:DrvScan -in 'ready', 'uptodate') { $waiting += $drv; New-Check 'Drivers' $(if ($drv) { "$drv update$(if ($drv -ne 1) { 's' })" } else { 'Up to date' }) $(if ($drv) { 'warn' } else { 'ok' }) }
            elseif ($script:WuState -eq 'running') { New-Check 'Drivers' "Checking$Ellipsis" 'info' } else { New-Check 'Drivers' 'Open the Drivers tab to check' 'info' }))
    $restart = $h.Reboot -or ($script:WinInfo -and $script:WinInfo.Reboot)
    if ($restart) { $upd.Add((New-Check 'Restart' 'Waiting to finish updates' 'warn')) }
    $UI.HlUpdItems.ItemsSource = $upd.ToArray()
    $UI.HlUpdTitle.Text = if ($waiting) { "$waiting update$(if ($waiting -ne 1) { 's' }) waiting" } elseif (@($upd | Where-Object { $_.Value -like 'Checking*' }).Count) { "Checking$Ellipsis" } else { 'Up to date' }
    $issues += [int][bool]$waiting + [int][bool]$restart

    # ---- Network
    $nets = @($h.Network)
    $net = New-Object System.Collections.Generic.List[object]
    $main = @($nets | Where-Object { $_.Internet }) + @($nets | Where-Object { -not $_.Internet }) | Select-Object -First 1
    if ($main) {
        $UI.HlNetTitle.Text = if ($main.Internet) { 'Connected to the internet' } else { 'No internet access' }
        foreach ($a in $nets) {
            $kind = if ($a.Wireless) { 'Wi-Fi' } else { 'Wired' }
            $net.Add((New-Check $kind "$($a.Description)" $(if ($a.Internet) { 'ok' } else { 'warn' }) "$($a.Name): $($a.Description)"))
            # a connected adapter's network and address are green; an address the router never gave (169.254.x.x) is red
            if ($a.Ssid) { $net.Add((New-Check 'Network' $a.Ssid 'ok')) } elseif ($a.Network) { $net.Add((New-Check 'Network' $a.Network 'ok')) }
            if ($null -ne $a.Signal) { $net.Add((New-Check 'Signal' "$($a.Signal)%" $(if ($a.Signal -lt 40) { 'warn' } else { 'ok' }))) }
            if ($a.Speed) { $net.Add((New-Check 'Link speed' $a.Speed (Get-LinkSpeedLevel $a.Speed ([bool]$a.Wireless)) $(if ($a.Wireless) { 'Wi-Fi link speed: green from 200 Mbps, amber from 50 Mbps' } else { 'Wired link speed: green at 1 Gbps or more, amber at 100 Mbps, red at 10 Mbps' }))) }
            if ($a.Ip) {
                $apipa = $a.Ip -like '169.254.*'
                $net.Add((New-Check 'Address' $(if ($apipa) { "$($a.Ip) (none from the router)" } else { $a.Ip }) $(if ($apipa) { 'bad' } else { 'ok' }) $(if ($apipa) { "The router didn't give this PC an address, so it can't reach the network: restart the router or check the cable" } else { '' })))
            }
        }
        if (-not $main.Internet) { $issues++ }
        $issues += @($net | Where-Object { $_.Label -in 'Link speed', 'Address' -and $_.Level -in 'warn', 'bad' }).Count
        $quality = Get-NetQualityChecks $h.Quality ([bool]$main.Internet)
        foreach ($c in $quality) { $net.Add($c) }
        $issues += @($quality | Where-Object { $_.Level -in 'warn', 'bad' }).Count
        if ($main.Internet -and $quality.Count) {
            $UI.HlNetTitle.Text = if (@($quality | Where-Object { $_.Level -eq 'bad' }).Count) { 'Poor connection' } elseif (@($quality | Where-Object { $_.Level -eq 'warn' }).Count) { 'Fair connection' } else { 'Good connection' }
        }
    }
    elseif ($h.ContainsKey('Network')) { $UI.HlNetTitle.Text = 'Not connected'; $net.Add((New-Check 'Network' 'No connected adapter' 'bad')); $issues++ }
    else { $UI.HlNetTitle.Text = $Ellipsis }
    $UI.HlNetItems.ItemsSource = $net.ToArray()

    # ---- Cleanup (measured by the Cleanup tab's list)
    $all = [long]0; foreach ($i in $CleanItems) { if ($i.Bytes -gt 0) { $all += $i.Bytes } }
    $sys = @($h.Volumes | Where-Object { $_.Letter -eq $env:SystemDrive }) | Select-Object -First 1
    $UI.HlCleanSumTitle.Text = if ($script:CleanReader) { "Measuring$Ellipsis" } elseif ($all -gt 0) { "$(Format-Size $all) can be freed" } else { 'Nothing much to clean' }
    $UI.HlCleanSumText.Text = "Leftover files from apps, installers and Windows." + $(if ($sys) { " $env:SystemDrive has $(Format-Size $sys.Free) free of $(Format-Size $sys.Size)." } else { '' }) + " Cleanup also lists your largest files and the apps that take the most space."
    if ($sys -and $sys.Size -and $sys.Free / $sys.Size -lt 0.15) { $issues++ }
    $issues += Update-TempCard $h.Temps
    return $issues
}

$UI.HlSecOpen.Add_Click({ try { Start-Process 'windowsdefender:' } catch { } })
$UI.HlPerfOpen.Add_Click({ try { Start-Process taskmgr.exe } catch { } })
$UI.HlRelOpen.Add_Click({ try { Start-Process perfmon.exe -ArgumentList '/rel' } catch { } })
$UI.HlNetOpen.Add_Click({ try { Start-Process 'ms-settings:network' } catch { } })
# Temperatures: start LibreHardwareMonitor and read the page again once it has had time to publish its sensors (about
# 12 seconds, then twice more if it hasn't yet), or find it on Discover to install it
$script:TempWaits = 0
$script:TempTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:TempTimer.Interval = [TimeSpan]::FromSeconds(12)
$script:TempTimer.Add_Tick({
        $t = if ($script:HealthInfo) { $script:HealthInfo.Temps } else { $null }
        if (($t -and $t.Monitor) -or $script:TempWaits -ge 3) { $script:TempTimer.Stop(); return }
        $script:TempWaits++
        Start-HealthScan
    })
$UI.HlTempGet.Add_Click({
        $exe = [string]$UI.HlTempGet.Tag
        if ($exe) {
            try { Start-Process -FilePath $exe -WorkingDirectory (Split-Path -Parent $exe) } catch { $script:LastSummary = "Couldn't start LibreHardwareMonitor: $($_.Exception.Message)"; Update-View; return }
            $UI.HlTempNote.Text = "Starting LibreHardwareMonitor$Ellipsis This card refreshes once it's reading."
            $UI.HlTempGet.Visibility = 'Collapsed'
            $script:TempWaits = 0; $script:TempTimer.Stop(); $script:TempTimer.Start()
        }
        else {
            $UI.TabDiscover.IsChecked = $true
            $UI.Search.Text = 'LibreHardwareMonitor'
            Start-Search
        }
    })
$UI.HlCleanOpen.Add_Click({ $UI.TabCleanup.IsChecked = $true })
$UI.HlUpdOpen.Add_Click({
        $soft = @($Packages | Where-Object { -not $_.IsDone -and -not $_.IsConcealed }).Count
        $tab = if ($soft) { 'TabUpdates' } elseif (@($WinUpdates | Where-Object { -not $_.Optional }).Count) { 'TabWindows' } elseif ($DrvUpdates.Count) { 'TabDrivers' } else { 'TabUpdates' }
        $UI[$tab].IsChecked = $true
    })

# ---- Trends: one sparkline per reading, from health-history.jsonl ------------------------------------------------
# Each is a single series: a 2px line in the accent colour over a faint wash of it, a hairline baseline, and a marker
# on the latest reading. Hovering anywhere on it snaps a crosshair to the nearest day, with that day's value. Beside
# it, the latest value and its change (an arrow, green when the change is good news and red when it isn't); text
# never takes the line's colour.
$TrendMetrics = @(
    @{ Key = 'Battery'; Label = 'Battery health'; Unit = '%'; Format = '{0:0}%'; Good = 'up' }
    @{ Key = 'SysFreeGB'; Label = "Free space on $env:SystemDrive"; Unit = 'GB'; Format = '{0:0.0} GB'; Good = 'up' }
    @{ Key = 'Stability'; Label = 'Stability index'; Unit = ''; Format = '{0:0.0} of 10'; Good = 'up' }
    @{ Key = 'Crashes7'; Label = 'App crashes (7 days)'; Unit = ''; Format = '{0:0}'; Good = 'down' }
    @{ Key = 'MemUsedPct'; Label = 'Memory in use'; Unit = '%'; Format = '{0:0}%'; Good = 'down' }
    @{ Key = 'DiskWear'; Label = 'Drive wear'; Unit = '%'; Format = '{0:0}%'; Good = 'down' }
    @{ Key = 'LatencyMs'; Label = 'Internet latency'; Unit = 'ms'; Format = '{0:0} ms'; Good = 'down' }
)

function New-Sparkline($Points, [double]$Width = 330, [double]$Height = 40) {
    $bc = New-Object System.Windows.Media.BrushConverter
    $accent = $Window.FindResource('Highlight').Color
    $card = $bc.ConvertFrom('#232323')
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = $Width; $c.Height = $Height; $c.Background = [System.Windows.Media.Brushes]::Transparent; $c.ClipToBounds = $false
    $vals = @($Points | ForEach-Object { [double]$_.Value })
    $min = ($vals | Measure-Object -Minimum).Minimum; $max = ($vals | Measure-Object -Maximum).Maximum
    $span = $max - $min
    $t0 = ([datetime]$Points[0].Date).Ticks; $t1 = ([datetime]$Points[-1].Date).Ticks
    $pad = 5; $base = $Height - 0.5
    $line = New-Object System.Windows.Shapes.Polyline
    $line.Stroke = $Window.FindResource('Highlight'); $line.StrokeThickness = 2
    $line.StrokeLineJoin = 'Round'; $line.StrokeStartLineCap = 'Round'; $line.StrokeEndLineCap = 'Round'
    $xy = @(foreach ($p in $Points) {
            $x = if ($t1 -gt $t0) { $pad + ($Width - 2 * $pad) * (([datetime]$p.Date).Ticks - $t0) / ($t1 - $t0) } else { $Width / 2 }
            $y = if ($span -gt 0) { $pad + ($Height - 2 * $pad - 4) * (1 - ([double]$p.Value - $min) / $span) } else { $Height / 2 }
            $line.Points.Add((New-Object System.Windows.Point($x, $y)))
            @{ X = $x; Y = $y; P = $p }
        })
    # a faint wash of the line's colour under it, fading to nothing at the baseline
    $area = New-Object System.Windows.Shapes.Polygon
    foreach ($pt in $line.Points) { $area.Points.Add($pt) }
    $area.Points.Add((New-Object System.Windows.Point($xy[-1].X, $base))); $area.Points.Add((New-Object System.Windows.Point($xy[0].X, $base)))
    $wash = New-Object System.Windows.Media.LinearGradientBrush
    $wash.StartPoint = '0,0'; $wash.EndPoint = '0,1'
    $wash.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(40, $accent.R, $accent.G, $accent.B)), 0))
    $wash.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.Color]::FromArgb(0, $accent.R, $accent.G, $accent.B)), 1))
    $area.Fill = $wash
    [void]$c.Children.Add($area)
    # the baseline: a hairline one step off the card
    $axis = New-Object System.Windows.Shapes.Line
    $axis.X1 = 0; $axis.X2 = $Width; $axis.Y1 = $base; $axis.Y2 = $base; $axis.Stroke = $bc.ConvertFrom('#333333'); $axis.StrokeThickness = 1
    [void]$c.Children.Add($axis)
    [void]$c.Children.Add($line)
    # the latest reading, with a ring of the card's colour so it stands off the line
    $last = $xy[-1]
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 10; $dot.Height = 10; $dot.Fill = $Window.FindResource('Highlight'); $dot.Stroke = $card; $dot.StrokeThickness = 2
    [System.Windows.Controls.Canvas]::SetLeft($dot, $last.X - 5); [System.Windows.Controls.Canvas]::SetTop($dot, $last.Y - 5)
    [void]$c.Children.Add($dot)
    # Hover: a crosshair snaps to the nearest day, with a dot on the line and that day's value (value first, then
    # the date). The whole chart is the target, so nobody has to aim at a 2px line.
    $cross = New-Object System.Windows.Shapes.Line
    $cross.Y1 = 0; $cross.Y2 = $base; $cross.Stroke = $bc.ConvertFrom('#5A5A5A'); $cross.StrokeThickness = 1; $cross.Visibility = 'Hidden'
    [void]$c.Children.Add($cross)
    $hdot = New-Object System.Windows.Shapes.Ellipse
    $hdot.Width = 10; $hdot.Height = 10; $hdot.Fill = $Window.FindResource('Highlight'); $hdot.Stroke = $card; $hdot.StrokeThickness = 2; $hdot.Visibility = 'Hidden'
    [void]$c.Children.Add($hdot)
    $tipValue = New-Object System.Windows.Documents.Run; $tipValue.FontWeight = 'SemiBold'
    $tipDate = New-Object System.Windows.Documents.Run; $tipDate.Foreground = $Window.FindResource('Muted')
    $tipText = New-Object System.Windows.Controls.TextBlock
    [void]$tipText.Inlines.Add($tipValue); [void]$tipText.Inlines.Add($tipDate)
    $tip = New-Object System.Windows.Controls.ToolTip
    $tip.Content = $tipText; $tip.PlacementTarget = $c; $tip.Placement = 'Relative'
    $hit = New-Object System.Windows.Shapes.Rectangle
    $hit.Width = $Width; $hit.Height = $Height + 8; $hit.Fill = [System.Windows.Media.Brushes]::Transparent
    [System.Windows.Controls.Canvas]::SetTop($hit, -4)
    $hit.Tag = @{ XY = $xy; Cross = $cross; Dot = $hdot; Tip = $tip; Value = $tipValue; Date = $tipDate; Width = $Width }
    $hit.Add_MouseMove({
            param($s, $e)
            $t = $s.Tag
            $mx = $e.GetPosition($s).X
            $q = $t.XY | Sort-Object { [Math]::Abs($_.X - $mx) } | Select-Object -First 1
            $t.Cross.X1 = $q.X; $t.Cross.X2 = $q.X; $t.Cross.Visibility = 'Visible'
            [System.Windows.Controls.Canvas]::SetLeft($t.Dot, $q.X - 5); [System.Windows.Controls.Canvas]::SetTop($t.Dot, $q.Y - 5); $t.Dot.Visibility = 'Visible'
            $t.Value.Text = [string]$q.P.Text
            $t.Date.Text = '  ' + ([datetime]$q.P.Date).ToString('MMM d, yyyy')
            # beside the crosshair, flipping to its left near the right edge
            $t.Tip.HorizontalOffset = if ($q.X -gt $t.Width - 150) { $q.X - 150 } else { $q.X + 12 }
            $t.Tip.VerticalOffset = -30
            $t.Tip.IsOpen = $true
        })
    $hit.Add_MouseLeave({
            param($s, $e)
            $t = $s.Tag
            $t.Cross.Visibility = 'Hidden'; $t.Dot.Visibility = 'Hidden'; $t.Tip.IsOpen = $false
        })
    [void]$c.Children.Add($hit)
    return $c
}

function Update-HealthTrends {
    $hist = @(Read-HealthHistory | Where-Object { [datetime]$_.Date -ge (Get-Date).AddDays(-90) })
    $UI.HlTrends.Children.Clear()
    $days = @($hist | ForEach-Object { $_.Date } | Select-Object -Unique).Count
    $UI.HlTrendsLabel.Text = if ($days -ge 2) { "TRENDS (LAST $([Math]::Min(90, [int]((Get-Date) - [datetime]$hist[0].Date).TotalDays + 1)) DAYS)" } else { 'TRENDS' }
    if ($days -lt 2) {
        $UI.HlTrendsNote.Text = "Trends appear once there are readings from two days or more$(if ($days -eq 1) { ' (the first was saved today)' }). A reading is saved each day the app reads this page, and after each automatic run."
        $UI.HlTrendsNote.Visibility = 'Visible'
        return
    }
    $UI.HlTrendsNote.Visibility = 'Collapsed'
    $muted = $Window.FindResource('Muted')
    # two to a row (HlTrends is a two-column grid); a PC without a battery has no battery line, even if earlier
    # readings (from before placeholder batteries were ignored) have one
    $noBattery = $script:HealthInfo -and $script:HealthInfo.Sys -and -not $script:HealthInfo.Battery
    foreach ($m in $TrendMetrics) {
        if ($m.Key -eq 'Battery' -and $noBattery) { continue }
        $pts = @($hist | Where-Object { $null -ne $_.($m.Key) } | ForEach-Object { @{ Date = $_.Date; Value = [double]$_.($m.Key); Text = ($m.Format -f [double]$_.($m.Key)) } })
        if ($pts.Count -lt 2) { continue }
        $first = $pts[0].Value; $last = $pts[-1].Value; $d = $last - $first
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,7,28,7'
        foreach ($w in 130, 240, 0) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = if ($w) { New-Object System.Windows.GridLength $w } else { New-Object System.Windows.GridLength(1, 'Star') }; $row.ColumnDefinitions.Add($cd) }
        $lab = New-Object System.Windows.Controls.TextBlock
        $lab.Text = $m.Label; $lab.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom('#BDBDBD'); $lab.VerticalAlignment = 'Center'; $lab.TextWrapping = 'Wrap'; $lab.Margin = '0,0,10,0'
        [void]$row.Children.Add($lab)
        $spark = New-Sparkline $pts 236
        [System.Windows.Controls.Grid]::SetColumn($spark, 1)
        [void]$row.Children.Add($spark)
        $val = New-Object System.Windows.Controls.TextBlock
        $val.VerticalAlignment = 'Center'; $val.Margin = '14,0,0,0'; $val.TextWrapping = 'Wrap'
        $r1 = New-Object System.Windows.Documents.Run ($m.Format -f $last); $r1.Foreground = [System.Windows.Media.Brushes]::White; $r1.FontWeight = 'SemiBold'
        [void]$val.Inlines.Add($r1)
        $since = New-Object System.Windows.Documents.Run; $since.Foreground = $muted; $since.FontSize = 12.5
        if ([Math]::Abs($d) -lt 0.05) { $since.Text = '   no change' }
        else {
            # the arrow says which way, green or red says whether that's good news: never colour alone
            $good = ($d -gt 0) -eq ($m.Good -eq 'up')
            $r2 = New-Object System.Windows.Documents.Run ("   $([char]$(if ($d -gt 0) { 0x25B2 } else { 0x25BC })) $(($m.Format -f [Math]::Abs($d)) -replace ' of 10$', '')")
            $r2.Foreground = $Window.FindResource($(if ($good) { 'Good' } else { 'Bad' })); $r2.FontSize = 12.5
            [void]$val.Inlines.Add($r2)
            $since.Text = " since $(([datetime]$pts[0].Date).ToString('MMM d'))"
        }
        [void]$val.Inlines.Add($since)
        [System.Windows.Controls.Grid]::SetColumn($val, 2)
        [void]$row.Children.Add($val)
        [void]$UI.HlTrends.Children.Add($row)
    }
}

# ---- Save report: Device Health and what's on the PC, as one web page ----------------------------------------------
function Save-HealthReport([string]$File) {
    $h = $script:HealthInfo
    if (-not $h -or -not $h.Sys) { $script:LastSummary = "Wait for Device Health to finish reading, then save the report"; Update-View; return }
    if (-not $File) { $File = Join-Path ([Environment]::GetFolderPath('Desktop')) "Windows Manager report - $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HHmm').html" }
    $e = { param($s) [Net.WebUtility]::HtmlEncode([string]$s) }
    $dot = @{ ok = '#2e9e5b'; warn = '#c98a00'; bad = '#d04a3a'; info = '#9a9a9a' }
    $checks = {
        param($title, $items, $head)
        $rows = foreach ($i in @($items)) { "<tr><td><span class='dot' style='background:$($dot[[string]$i.Level])'></span>$(& $e $i.Label)</td><td>$(& $e $i.Value)</td></tr>" }
        "<section><h2>$(& $e $title)</h2><p class='lead'>$(& $e $head)</p><table>$($rows -join '')</table></section>"
    }
    $s = $h.Sys
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append(@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Windows Manager report: $(& $e $env:COMPUTERNAME)</title>
<style>
body{font-family:'Segoe UI',system-ui,sans-serif;color:#1f1f1f;background:#fafafa;margin:0;padding:32px;line-height:1.45}
main{max-width:960px;margin:0 auto}h1{font-size:26px;margin:0 0 4px}h2{font-size:16px;margin:0 0 6px;text-transform:uppercase;letter-spacing:.04em;color:#555}
.sub{color:#666;margin:0 0 24px}section{background:#fff;border:1px solid #e3e3e3;border-radius:10px;padding:16px 20px;margin:0 0 16px}
.lead{margin:0 0 10px;font-weight:600}table{border-collapse:collapse;width:100%;font-size:14px}td,th{text-align:left;padding:5px 8px;border-top:1px solid #f0f0f0;vertical-align:top}
th{color:#666;font-weight:600;border-top:0}td:last-child{text-align:right}.wide td:last-child{text-align:left}.dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:9px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:16px}.grid section{margin:0}pre{white-space:pre-wrap;font:inherit;margin:0;color:#333}
@media print{body{background:#fff;padding:0}section{break-inside:avoid}}
</style></head><body><main>
<h1>$(& $e $UI.HlSysTitle.Text)</h1>
<p class="sub">$(& $e $env:COMPUTERNAME)  &middot;  $(& $e "$($s.Os) $($s.Display), build $($s.Build)")  &middot;  serial $(& $e $s.Serial)  &middot;  report saved $(Get-Date -Format 'MMM d, yyyy h:mm tt') by Windows Manager $AppVersion</p>
<section><h2>Summary</h2><p class="lead">$(& $e $UI.HlSummary.Text)</p></section>
<div class="grid">
<section><h2>This PC</h2><pre>$(& $e $UI.HlSysText.Text)</pre></section>
<section><h2>BIOS and firmware</h2><p class="lead">$(& $e $UI.HlBiosTitle.Text)</p><pre>$(& $e $UI.HlBiosText.Text)</pre></section>
<section><h2>Battery</h2><p class="lead">$(& $e $UI.HlBatTitle.Text)</p><pre>$(& $e $UI.HlBatText.Text)</pre></section>
</div><br>
"@)
    [void]$sb.Append('<div class="grid">')
    foreach ($c in @(@('Security', 'HlSecItems', 'HlSecTitle'), @('Performance', 'HlPerfItems', 'HlPerfTitle'), @('Reliability', 'HlRelItems', 'HlRelTitle'), @('Updates', 'HlUpdItems', 'HlUpdTitle'), @('Network', 'HlNetItems', 'HlNetTitle'))) {
        $cardItems = @($UI[$c[1]].ItemsSource)
        # the report lists the apps using the most memory with Performance's lines
        if ($c[0] -eq 'Performance') { $cardItems += @($UI.HlTopMem.ItemsSource | ForEach-Object { New-Check $_.Name "$($_.Detail) of memory" 'info' }) }
        [void]$sb.Append((& $checks $c[0] $cardItems $UI[$c[2]].Text))
    }
    [void]$sb.Append('</div><br>')
    $vols = foreach ($v in @($UI.HlVolumes.ItemsSource)) { "<tr><td>$(& $e $v.Name)</td><td>$(& $e $v.Detail) ({0:0}% used)</td></tr>" -f $v.UsedPct }
    $disks = foreach ($d in @($UI.HlDisks.ItemsSource)) { "<tr><td>$(& $e $d.Name)</td><td>$(& $e $d.Detail)  &middot;  $(& $e $d.Health)</td></tr>" }
    [void]$sb.Append("<section><h2>Drives</h2><table>$($vols -join '')$($disks -join '')</table></section>")
    if (@($UI.HlTempGroups.ItemsSource).Count) {
        [void]$sb.Append("<div class='grid'>")
        foreach ($g in @($UI.HlTempGroups.ItemsSource)) { [void]$sb.Append((& $checks $g.Name $g.Items '')) }
        [void]$sb.Append("</div><p class='sub'>$(& $e $UI.HlTempNote.Text)</p>")
    }
    $pending = @($Packages | Where-Object { -not $_.IsDone }) | ForEach-Object { "<tr><td>$(& $e $_.Name)</td><td>$(& $e "$($_.Version) to $($_.Available)")</td></tr>" }
    $pending += @($WinUpdates) | ForEach-Object { "<tr><td>$(& $e $_.Title)</td><td>Windows Update</td></tr>" }
    $pending += @($DrvUpdates) | ForEach-Object { "<tr><td>$(& $e $_.Name)</td><td>$(& $e "$($_.Version) ($($_.Source))")</td></tr>" }
    [void]$sb.Append("<section><h2>Waiting updates</h2>$(if (@($pending).Count) { "<table>$($pending -join '')</table>" } else { '<p>None found by the last checks.</p>' })</section>")
    if ($StartupItems.Count) {
        $st = foreach ($i in @($StartupItems | Sort-Object { -not $_.Enabled }, Name)) { "<tr><td>$(& $e $i.Name)</td><td>$(& $e "$(if ($i.Enabled) { 'On' } else { 'Off' })  $([char]0x00B7)  $($i.LocationText)")</td></tr>" }
        [void]$sb.Append("<section><h2>Apps that start with Windows</h2><table>$($st -join '')</table></section>")
    }
    if ($InstalledItems.Count) {
        $apps = foreach ($p in @($InstalledItems | Sort-Object Name)) { "<tr><td>$(& $e $p.Name)</td><td>$(& $e $p.Version)</td><td>$(& $e $p.Source)</td><td>$(& $e $p.SizeText)</td></tr>" }
        [void]$sb.Append("<section class='wide'><h2>Installed software ($($InstalledItems.Count))</h2><table><tr><th>App</th><th>Version</th><th>Source</th><th>Size</th></tr>$($apps -join '')</table></section>")
    }
    [void]$sb.Append('</main></body></html>')
    try {
        [IO.File]::WriteAllText($File, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
        Add-LogLine "Saved the health report: $File"
        $script:LastSummary = "Saved the report: $([IO.Path]::GetFileName($File))"
        if (-not $SelfTest) { try { Start-Process $File } catch { } }
    }
    catch { $script:LastSummary = "Couldn't save the report: $($_.Exception.Message)" }
    Update-View
}
$UI.HlReport.Add_Click({ Save-HealthReport })

# Windows Manager - HealthCards (part of src\; see Windows_Manager.ps1)

# Device Health's check cards: Security, Performance, Reliability, Updates, Network and Cleanup. Each line is a
# HealthCheck (a dot that is green, amber, red or grey, what it is, and its value). Update-HealthCards returns how
# many lines need attention, for the summary at the top.
function New-Check([string]$Label, [string]$Value, [string]$Level = 'ok', [string]$Tip = '') {
    $c = New-Object WingetUM.HealthCheck
    $c.Label = $Label; $c.Value = $Value; $c.Level = $Level; $c.Tip = $(if ($Tip) { $Tip } else { "$Label`: $Value" })
    return $c
}
function Format-Days([int]$Days) { if ($Days -le 0) { 'today' } elseif ($Days -eq 1) { 'yesterday' } else { "$Days days ago" } }

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
        $n = 0
        foreach ($t in @($p.Top)) { $n++; $perf.Add((New-Check $(if ($n -eq 1) { 'Most memory' } else { '' }) "$($t.Name)  $(Format-Size $t.Bytes)" 'info')) }
        $perf.Add((New-Check 'Programs running' "$($p.Processes) processes" 'info'))
        if ($script:StartupState -eq 'ready') { $on = @($StartupItems | Where-Object { $_.Enabled }).Count; $perf.Add((New-Check 'Start with Windows' "$on apps" $(if ($on -gt 20) { 'warn' } else { 'info' }) 'Fewer startup apps make sign-in quicker: see the Startup tab')) }
    }
    else { $UI.HlPerfTitle.Text = $Ellipsis; $UI.HlMemBar.Value = 0 }
    $UI.HlPerfItems.ItemsSource = $perf.ToArray()
    $issues += @($perf | Where-Object { $_.Level -in 'warn', 'bad' }).Count

    # ---- Reliability
    $r = $h.Reliability
    $rel = New-Object System.Collections.Generic.List[object]
    if ($r) {
        if ($null -ne $r.Shutdowns) { $rel.Add((New-Check 'Unexpected shutdowns' "$($r.Shutdowns) in 30 days" $(if ($r.Shutdowns) { 'warn' } else { 'ok' }) 'Times Windows stopped without shutting down properly (power loss, a hang, a forced power-off)')) }
        if ($null -ne $r.BlueScreens) { $rel.Add((New-Check 'Blue screens' "$($r.BlueScreens) in 30 days" $(if ($r.BlueScreens) { 'bad' } else { 'ok' }))) }
        if ($null -ne $r.Crashes) {
            $rel.Add((New-Check 'App crashes' "$($r.Crashes) in 7 days" $(if ($r.Crashes -ge 10) { 'warn' } elseif ($r.Crashes) { 'info' } else { 'ok' })))
            if (@($r.CrashApps).Count) { $rel.Add((New-Check 'Crashed most' (@($r.CrashApps) -join ', ') 'info')) }
        }
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
            if ($a.Ssid) { $net.Add((New-Check 'Network' $a.Ssid 'info')) } elseif ($a.Network) { $net.Add((New-Check 'Network' $a.Network 'info')) }
            if ($null -ne $a.Signal) { $net.Add((New-Check 'Signal' "$($a.Signal)%" $(if ($a.Signal -lt 40) { 'warn' } else { 'ok' }))) }
            if ($a.Speed) { $net.Add((New-Check 'Link speed' $a.Speed 'info')) }
            if ($a.Ip) { $net.Add((New-Check 'Address' $a.Ip 'info')) }
        }
        if (-not $main.Internet) { $issues++ }
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
    return $issues
}

$UI.HlSecOpen.Add_Click({ try { Start-Process 'windowsdefender:' } catch { } })
$UI.HlPerfOpen.Add_Click({ try { Start-Process taskmgr.exe } catch { } })
$UI.HlRelOpen.Add_Click({ try { Start-Process perfmon.exe -ArgumentList '/rel' } catch { } })
$UI.HlNetOpen.Add_Click({ try { Start-Process 'ms-settings:network' } catch { } })
$UI.HlCleanOpen.Add_Click({ $UI.TabCleanup.IsChecked = $true })
$UI.HlUpdOpen.Add_Click({
        $soft = @($Packages | Where-Object { -not $_.IsDone -and -not $_.IsConcealed }).Count
        $tab = if ($soft) { 'TabUpdates' } elseif (@($WinUpdates | Where-Object { -not $_.Optional }).Count) { 'TabWindows' } elseif ($DrvUpdates.Count) { 'TabDrivers' } else { 'TabUpdates' }
        $UI[$tab].IsChecked = $true
    })

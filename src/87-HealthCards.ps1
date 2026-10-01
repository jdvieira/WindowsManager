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

# ---- Trends: one sparkline per reading, from health-history.jsonl ------------------------------------------------
# Each is a single series: a 2px line in the accent colour, a marker on the latest reading, a tooltip on every point,
# and the latest value with its change in plain text beside it (text never takes the line's colour).
$TrendMetrics = @(
    @{ Key = 'Battery'; Label = 'Battery health'; Unit = '%'; Format = '{0:0}%'; Good = 'up' }
    @{ Key = 'SysFreeGB'; Label = "Free space on $env:SystemDrive"; Unit = 'GB'; Format = '{0:0.0} GB'; Good = 'up' }
    @{ Key = 'Stability'; Label = 'Stability index'; Unit = ''; Format = '{0:0.0} of 10'; Good = 'up' }
    @{ Key = 'Crashes7'; Label = 'App crashes (7 days)'; Unit = ''; Format = '{0:0}'; Good = 'down' }
    @{ Key = 'MemUsedPct'; Label = 'Memory in use'; Unit = '%'; Format = '{0:0}%'; Good = 'down' }
    @{ Key = 'DiskWear'; Label = 'Drive wear'; Unit = '%'; Format = '{0:0}%'; Good = 'down' }
)

function New-Sparkline($Points, [double]$Width = 320, [double]$Height = 34) {
    $c = New-Object System.Windows.Controls.Canvas
    $c.Width = $Width; $c.Height = $Height; $c.Background = [System.Windows.Media.Brushes]::Transparent
    $vals = @($Points | ForEach-Object { [double]$_.Value })
    $min = ($vals | Measure-Object -Minimum).Minimum; $max = ($vals | Measure-Object -Maximum).Maximum
    $span = $max - $min
    $t0 = ([datetime]$Points[0].Date).Ticks; $t1 = ([datetime]$Points[-1].Date).Ticks
    $pad = 5
    $line = New-Object System.Windows.Shapes.Polyline
    $line.Stroke = $Window.FindResource('Highlight'); $line.StrokeThickness = 2
    $line.StrokeLineJoin = 'Round'; $line.StrokeStartLineCap = 'Round'; $line.StrokeEndLineCap = 'Round'
    $xy = foreach ($p in $Points) {
        $x = if ($t1 -gt $t0) { $pad + ($Width - 2 * $pad) * (([datetime]$p.Date).Ticks - $t0) / ($t1 - $t0) } else { $Width / 2 }
        $y = if ($span -gt 0) { $pad + ($Height - 2 * $pad) * (1 - ([double]$p.Value - $min) / $span) } else { $Height / 2 }
        $line.Points.Add((New-Object System.Windows.Point($x, $y)))
        @{ X = $x; Y = $y; P = $p }
    }
    [void]$c.Children.Add($line)
    # the latest reading, with a ring of the card's colour so it stands off the line
    $last = @($xy)[-1]
    $dot = New-Object System.Windows.Shapes.Ellipse
    $dot.Width = 9; $dot.Height = 9; $dot.Fill = $Window.FindResource('Highlight'); $dot.Stroke = (New-Object System.Windows.Media.BrushConverter).ConvertFrom('#232323'); $dot.StrokeThickness = 2
    [System.Windows.Controls.Canvas]::SetLeft($dot, $last.X - 4.5); [System.Windows.Controls.Canvas]::SetTop($dot, $last.Y - 4.5)
    [void]$c.Children.Add($dot)
    # hover targets, bigger than the line, one per reading
    foreach ($q in $xy) {
        $hit = New-Object System.Windows.Shapes.Ellipse
        $hit.Width = 14; $hit.Height = 14; $hit.Fill = [System.Windows.Media.Brushes]::Transparent
        $hit.ToolTip = "$(([datetime]$q.P.Date).ToString('MMM d, yyyy')): $($q.P.Text)"
        [System.Windows.Controls.Canvas]::SetLeft($hit, $q.X - 7); [System.Windows.Controls.Canvas]::SetTop($hit, $q.Y - 7)
        [void]$c.Children.Add($hit)
    }
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
    foreach ($m in $TrendMetrics) {
        $pts = @($hist | Where-Object { $null -ne $_.($m.Key) } | ForEach-Object { @{ Date = $_.Date; Value = [double]$_.($m.Key); Text = ($m.Format -f [double]$_.($m.Key)) } })
        if ($pts.Count -lt 2) { continue }
        $first = $pts[0].Value; $last = $pts[-1].Value; $d = $last - $first
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,6,0,6'
        foreach ($w in 200, 340, 0) { $cd = New-Object System.Windows.Controls.ColumnDefinition; $cd.Width = if ($w) { New-Object System.Windows.GridLength $w } else { New-Object System.Windows.GridLength(1, 'Star') }; $row.ColumnDefinitions.Add($cd) }
        $lab = New-Object System.Windows.Controls.TextBlock
        $lab.Text = $m.Label; $lab.Foreground = (New-Object System.Windows.Media.BrushConverter).ConvertFrom('#BDBDBD'); $lab.VerticalAlignment = 'Center'
        [void]$row.Children.Add($lab)
        $spark = New-Sparkline $pts
        [System.Windows.Controls.Grid]::SetColumn($spark, 1)
        [void]$row.Children.Add($spark)
        $val = New-Object System.Windows.Controls.TextBlock
        $val.VerticalAlignment = 'Center'; $val.Margin = '16,0,0,0'
        $r1 = New-Object System.Windows.Documents.Run ($m.Format -f $last); $r1.Foreground = [System.Windows.Media.Brushes]::White
        $change = if ([Math]::Abs($d) -lt 0.05) { 'no change' } else { "$(if ($d -gt 0) { 'up' } else { 'down' }) $(($m.Format -f [Math]::Abs($d)) -replace ' of 10$', '') since $(([datetime]$pts[0].Date).ToString('MMM d'))" }
        $r2 = New-Object System.Windows.Documents.Run "   $change"; $r2.Foreground = $muted; $r2.FontSize = 12.5
        [void]$val.Inlines.Add($r1); [void]$val.Inlines.Add($r2)
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
        [void]$sb.Append((& $checks $c[0] $UI[$c[1]].ItemsSource $UI[$c[2]].Text))
    }
    [void]$sb.Append('</div><br>')
    $vols = foreach ($v in @($UI.HlVolumes.ItemsSource)) { "<tr><td>$(& $e $v.Name)</td><td>$(& $e $v.Detail) ({0:0}% used)</td></tr>" -f $v.UsedPct }
    $disks = foreach ($d in @($UI.HlDisks.ItemsSource)) { "<tr><td>$(& $e $d.Name)</td><td>$(& $e $d.Detail)  &middot;  $(& $e $d.Health)</td></tr>" }
    [void]$sb.Append("<section><h2>Drives</h2><table>$($vols -join '')$($disks -join '')</table></section>")
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

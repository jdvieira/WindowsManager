# Windows Manager - History (part of src\; see Windows_Manager.ps1)

function Open-History {
    $entries = New-Object 'System.Collections.Generic.List[WingetUM.HistoryEntry]'
    foreach ($line in (Read-HistoryLines)) {
        try {
            $o = $line | ConvertFrom-Json
            $e = New-Object WingetUM.HistoryEntry
            $e.Time = [datetime]$o.Time
            $e.Action = [string]$o.Action; $e.Name = [string]$o.Name; $e.Id = [string]$o.Id; $e.From = [string]$o.From; $e.To = [string]$o.To
            $e.State = [string]$o.State; $e.Detail = [string]$o.Detail; $e.Origin = [string]$o.Origin
            $entries.Add($e)
        }
        catch { }
    }
    $entries.Reverse()
    $script:HistCount = $entries.Count
    $script:HistView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($entries)
    $script:HistView.Filter = [Predicate[object]] {
        param($e)
        if ($UI.HistAutoOnly.IsChecked -and -not $e.IsAuto) { return $false }
        if ($UI.HistFailed.IsChecked -and $e.State -ne 'error') { return $false }
        $q = $UI.HistSearch.Text.Trim()
        return (-not $q) -or ($e.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($e.Id.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    }
    $UI.HistList.ItemsSource = $script:HistView
    Update-HistoryView
    $UI.HistoryOverlay.Visibility = 'Visible'
}

function Update-HistoryView {
    if (-not $script:HistView) { return }
    $script:HistView.Refresh()
    $shown = $script:HistView.Count
    $n = $script:HistCount
    $UI.HistSub.Text = if ($n) { "$n change$(if ($n -ne 1) { 's' }) recorded$(if ($shown -ne $n) { ", $shown shown" }), from this app and from automatic updates. Kept for a year." }
    else { 'Nothing recorded yet.' }
    $UI.HistEmpty.Visibility = ConvertTo-Visibility ($shown -eq 0)
    $UI.HistList.Visibility = if ($shown) { 'Visible' } else { 'Hidden' }
    $UI.HistEmptyText.Text = if ($n) { 'Nothing matches.' } else { 'Installs, updates, uninstalls and held apps show up here, from this app and from automatic updates.' }
    $UI.HistClear.IsEnabled = $n -gt 0
}

function Start-AutoProcess([string[]]$Extra) {
    if ($IsCompiled) { Start-Process -FilePath $ExePath -ArgumentList (@('-Auto') + $Extra) }
    else { Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$AppScript`"", '-Auto') + $Extra) }
}

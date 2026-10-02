# Windows Manager - Drivers (part of src\; see Windows_Manager.ps1)

$DrvDevices = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.DeviceDriver]'
$DrvUpdates = New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.DriverUpdate]'
$DrvDevicesView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DrvDevices)
$DrvDevicesView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('HasProblem', 'Descending')))
$DrvDevicesView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('SortClass', 'Ascending')))
$DrvDevicesView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
$DrvDevicesView.Filter = [Predicate[object]] {
    param($d)
    if ($UI.DrvProblemsOnly.IsChecked -and -not $d.HasProblem) { return $false }
    $q = $UI.DrvSearch.Text.Trim()
    return (-not $q) -or ($d.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ("$($d.Class) $($d.Manufacturer) $($d.Provider)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$DrvUpdatesView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DrvUpdates)
$DrvUpdatesView.Filter = [Predicate[object]] {
    param($u)
    $q = $UI.DrvSearch.Text.Trim()
    return (-not $q) -or ("$($u.Name) $($u.Category) $($u.Type)".IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$UI.DrvDevices.ItemsSource = $DrvDevicesView
$UI.DrvUpdates.ItemsSource = $DrvUpdatesView

$DrvWorkDir = Join-Path $DataDir 'Drivers'
$script:DrvSys = $null
$script:DrvDevicesRead = $false
$script:DrvDeviceError = $null
$script:DeviceScanner = $null
$script:DrvScan = 'none'           # Dell Command | Update's check: none | running | ready | uptodate | error
$script:WuState = 'none'           # Windows Update's driver check: none | running | ready | error
$script:WuNote = ''
$script:WuSearcher = $null
$script:WuManaged = ''              # '' | wufb (Intune driver management) | wsus | excluded (drivers kept out of Windows Update)
$script:NvState = 'none'            # NVIDIA's driver lookup: none | running | ready | error | nogpu
$script:NvNote = ''
$script:NvSearcher = $null
$script:NvTest = $null              # tests only: a card name and installed driver version to look up instead of this PC's
$script:DrvScanNote = ''
$script:Elev = $null               # the elevated run in progress (Dell Command | Update or pnputil)
$script:ElevTitle = ''
$script:ElevLast = ''
$script:VendorRow = $null          # the winget install of the vendor's tool

# Problem codes Windows gives devices (Device Manager's "This device ..." messages), in short
$DeviceProblems = @{ 1 = 'Not configured correctly'; 3 = 'Driver may be corrupted'; 10 = "Can't start"; 12 = 'Not enough free resources'
    14 = 'Needs a restart'; 18 = 'Drivers need reinstalling'; 19 = 'Settings in the registry are damaged'; 21 = 'Being removed'; 22 = 'Disabled'
    24 = 'Not present or not working'; 28 = 'No driver installed'; 29 = 'Disabled by the firmware'; 31 = 'Not working properly'; 32 = 'Driver service disabled'
    37 = "Driver couldn't start"; 39 = 'Driver missing or damaged'; 43 = 'Stopped after reporting a problem'; 48 = 'Driver blocked'; 52 = "Driver signature can't be verified"
}

# PC vendors, first match wins. Each names the vendor's own driver tool (the winget or Microsoft Store package that
# installs it, and how to find it once installed) and the vendor's driver download page ({serial} is filled in).
# Dell Command | Update is also driven from this tab (scan, install, reinstall all); the other tools are installed
# and opened. Match is tested against the PC's maker, model, family and product name, or its motherboard maker on a
# home-built PC.
$VendorCatalog = @(
    @{ Vendor = 'Dell'; Match = 'Dell|Alienware'; Tool = 'Dell Command | Update'; Id = 'Dell.CommandUpdate.Universal'; Source = 'winget'; Cli = $true
        Exe = 'dcu-cli.exe'; Entry = 'Dell Command*Update*'; Names = @('Dell Command | Update*')
        Paths = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe")
        Gui = @("$env:ProgramFiles\Dell\CommandUpdate\DellCommandUpdate.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\DellCommandUpdate.exe")
        Url = 'https://www.dell.com/support/home/product-support/servicetag/{serial}/drivers'; UrlPlain = 'https://www.dell.com/support/home/drivers' }
    @{ Vendor = 'HP'; Match = '^(HP|Hewlett)'; Models = 'EliteBook|ProBook|ZBook|Elite|ProDesk|ProOne|Engage|Z\d|Workstation|mt\d\d'; Tool = 'HP Image Assistant'; Id = 'HP.ImageAssistant'; Source = 'winget'
        Exe = 'HPImageAssistant.exe'; Entry = 'HP Image Assistant*'; Names = @('HP Image Assistant*')
        Paths = @('C:\SWSetup\HPImageAssistant\HPImageAssistant.exe', "$env:ProgramFiles\HP\HPIA\HPImageAssistant.exe", "${env:ProgramFiles(x86)}\HP\HPIA\HPImageAssistant.exe")
        Url = 'https://support.hp.com/drivers' }
    @{ Vendor = 'HP'; Match = '^(HP|Hewlett)'; Tool = 'HP Support Assistant'; ToolUrl = 'https://support.hp.com/us-en/help/hp-support-assistant'; Names = @('HP Support Assistant*'); Url = 'https://support.hp.com/drivers' }
    @{ Vendor = 'Lenovo'; Match = 'Lenovo'; Models = 'Think'; Tool = 'Lenovo System Update'; Id = 'Lenovo.SystemUpdate'; Source = 'winget'
        Exe = 'tvsu.exe'; Entry = 'Lenovo System Update*'; Names = @('Lenovo System Update*')
        Paths = @("${env:ProgramFiles(x86)}\Lenovo\System Update\tvsu.exe", "$env:ProgramFiles\Lenovo\System Update\tvsu.exe"); Url = 'https://pcsupport.lenovo.com/' }
    @{ Vendor = 'Lenovo'; Match = 'Lenovo'; Tool = 'Lenovo Vantage'; Id = '9WZDNCRFJ4MV'; Source = 'msstore'; Names = @('Lenovo Vantage*'); Url = 'https://pcsupport.lenovo.com/' }
    @{ Vendor = 'ASUS'; Match = 'ASUS'; Tool = 'MyASUS'; Id = '9N7R5S6B0ZZH'; Source = 'msstore'; Names = @('MyASUS*'); Url = 'https://www.asus.com/support/download-center/' }
    @{ Vendor = 'MSI'; Match = 'Micro-Star|^MSI'; Tool = 'MSI Center'; Id = '9NVMNJCR03XV'; Source = 'msstore'; Names = @('MSI Center*'); Url = 'https://www.msi.com/support/download' }
    @{ Vendor = 'Acer'; Match = 'Acer|Predator'; Tool = 'Acer Care Center'; ToolUrl = 'https://www.acer.com/us-en/support/drivers-and-manuals'; Names = @('Acer Care Center*', 'Care Center*'); Url = 'https://www.acer.com/us-en/support/drivers-and-manuals' }
    @{ Vendor = 'Samsung'; Match = 'Samsung'; Tool = 'Samsung Update'; Id = '9NQ3HDB99VBF'; Source = 'msstore'; Names = @('Samsung Update*'); Url = 'https://www.samsung.com/us/support/computing/' }
    @{ Vendor = 'Microsoft'; Match = 'Microsoft'; Models = 'Surface'; Tool = 'Surface'; Id = 'Microsoft.SurfaceApp'; Source = 'winget'; Names = @('Surface'); Url = 'https://support.microsoft.com/surface/download-drivers-and-firmware-for-surface'
        Note = 'Surface drivers and firmware come through Windows Update.' }
    @{ Vendor = 'Razer'; Match = 'Razer'; Tool = 'Razer Synapse'; Id = 'RazerInc.RazerInstaller.Synapse4'; Source = 'winget'; Names = @('Razer Synapse*'); Url = 'https://mysupport.razer.com/app/software' }
    @{ Vendor = 'Gigabyte'; Match = 'Gigabyte|AORUS'; Tool = 'GIGABYTE Control Center'; ToolUrl = 'https://www.gigabyte.com/Support/Utility'; Names = @('GIGABYTE Control Center*', 'GCC*'); Url = 'https://www.gigabyte.com/Support' }
    @{ Vendor = 'ASRock'; Match = 'ASRock'; Url = 'https://www.asrock.com/support/index.asp' }
    @{ Vendor = 'Dynabook'; Match = 'Dynabook|Toshiba'; Tool = 'dynabook Support Utility'; Id = '9PLV5DTB04KD'; Source = 'msstore'; Names = @('dynabook Support Utility*'); Url = 'https://support.dynabook.com/' }
    @{ Vendor = 'Framework'; Match = 'Framework'; Url = 'https://knowledgebase.frame.work/' }
)

# Component vendors, offered when this PC has their chips (from any PC vendor, or a home-built PC)
$ComponentCatalog = @(
    @{ Vendor = 'Intel'; Chips = 'Intel'; Tool = 'Intel Driver & Support Assistant'; Id = 'Intel.IntelDriverAndSupportAssistant'; Source = 'winget'
        Names = @('Intel*Driver*Support Assistant*'); Url = 'https://www.intel.com/content/www/us/en/support/detect.html' }
    @{ Vendor = 'NVIDIA'; Chips = 'NVIDIA'; Tool = 'NVIDIA App'; Id = 'XP8CLZL93F5Z4P'; Source = 'msstore'; Names = @('NVIDIA App*', 'NVIDIA GeForce Experience*'); Url = 'https://www.nvidia.com/en-us/software/nvidia-app/' }
    @{ Vendor = 'AMD'; Chips = '\bAMD\b|Advanced Micro|Radeon|AuthenticAMD'; Tool = 'AMD Software: Adrenalin Edition'; ToolUrl = 'https://www.amd.com/en/support/download/drivers.html'
        Names = @('AMD Software*', 'AMD Radeon Software*'); Url = 'https://www.amd.com/en/support/download/drivers.html' }
)

# The PC as the tabs name it: its vendor, or its motherboard's vendor when the PC has no real maker (home-built)
function Get-PcIdentity {
    $s = $script:DrvSys
    if (-not $s) { return '' }
    $maker = [string]$s.Maker
    if (-not $maker -or $maker -match '^(System manufacturer|To Be Filled|Default string|OEM|Not Applicable|Unknown)') { $maker = [string]$s.Board }
    return "$maker | $($s.Model) | $($s.Family) | $($s.Product)"
}

function Get-VendorEntry {
    $id = Get-PcIdentity
    if (-not $id) { return $null }
    $maker = $id.Split('|')[0]
    foreach ($e in $VendorCatalog) {
        if ($maker -notmatch $e.Match) { continue }
        if ($e.Models -and $id -notmatch $e.Models) { continue }
        return $e
    }
    return $null
}

# The vendor as people say it: Dell rather than "Dell Inc.", Lenovo rather than "LENOVO", Alienware as itself
function Get-MakerName {
    $s = $script:DrvSys
    $m = if ($s) { ((Get-PcIdentity).Split('|')[0]).Trim() } else { '' }
    if ($m -match 'Alienware') { return 'Alienware' }
    $e = Get-VendorEntry
    if ($e) { return $e.Vendor }
    return ($m -replace '(?i),?\s+(inc\.?|corporation|corp\.?|co\.,? ltd\.?|ltd\.?|gmbh|computer)$', '').Trim()
}

# The install folder a program recorded in its uninstall entry (for tools installed somewhere unusual)
function Find-InstallLocation([string]$Pattern) {
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            $v = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if ($v.DisplayName -like $Pattern -and $v.InstallLocation) { return [string]$v.InstallLocation }
        }
    }
    return $null
}

# A catalogue entry, resolved on this PC: is the tool installed (its folder, its winget ID, or its name in the
# installed list, which includes Store apps), where is it, and what can the tab do with it
function Resolve-Tool($e) {
    if (-not $e) { return $null }
    $path = $null
    if ($e.Paths) { $path = @($e.Paths | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) | Select-Object -First 1 }
    if (-not $path -and $e.Entry -and $e.Exe) {
        $loc = Find-InstallLocation $e.Entry
        if ($loc -and (Test-Path -LiteralPath (Join-Path $loc $e.Exe))) { $path = Join-Path $loc $e.Exe }
    }
    $named = $false
    foreach ($n in @($e.Names)) { if ($n -and @($InstalledItems | Where-Object { $_.Name -like $n }).Count) { $named = $true; break } }
    $installed = [bool]$path -or ($e.Id -and $script:InstalledIds.Contains($e.Id)) -or $named
    $ver = if ($path) { try { (Get-Item -LiteralPath $path).VersionInfo.ProductVersion } catch { '' } } else { '' }
    $gui = if ($e.Gui) { @($e.Gui | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) | Select-Object -First 1 } else { $null }
    $serial = if ($script:DrvSys) { [string]$script:DrvSys.Serial } else { '' }
    $url = if ($e.Url -match '\{serial\}') { $(if ($serial -and $serial -notmatch '^(To Be Filled|Default|0+$|System Serial)') { $e.Url.Replace('{serial}', [Uri]::EscapeDataString($serial)) } else { $e.UrlPlain }) } else { $e.Url }
    return @{ Vendor = $e.Vendor; Name = $e.Tool; Id = $e.Id; Source = $e.Source; ToolUrl = $e.ToolUrl; Url = $url; Note = $e.Note; Names = $e.Names
        Cli = [bool]$e.Cli -and [bool]$path; Path = $path; Gui = $gui; Installed = $installed; Version = $ver; Paths = $e.Paths
        CanInstall = [bool]$e.Id -and [bool]$e.Tool }
}

# Detection runs on every view refresh, so it is remembered for a few seconds (and forgotten after an install)
$script:VendorCache = $null
function Get-VendorTool {
    if ($script:VendorCache -and ((Get-Date) - $script:VendorCache.At).TotalSeconds -lt 5) { return $script:VendorCache.Tool }
    $tool = Resolve-Tool (Get-VendorEntry)
    $parts = @()
    $chips = if ($script:DrvSys) { [string]$script:DrvSys.Chips } else { '' }
    foreach ($c in $ComponentCatalog) { if ($chips -match $c.Chips) { $parts += Resolve-Tool $c } }
    $script:VendorCache = @{ At = Get-Date; Tool = $tool; Components = $parts }
    return $tool
}
function Get-ComponentTools { [void](Get-VendorTool); return , @($script:VendorCache.Components) }

function Start-DeviceScan {
    if ($script:DeviceScanner) { return }
    $script:DrvDeviceError = $null
    $script:DeviceScanner = Start-Background 'devices' @{}
    Update-View
}

function Complete-Devices($Ev) {
    if ($Ev.Error) { $script:DrvDeviceError = $Ev.Error; return }
    $script:DrvSys = $Ev.Sys
    $DrvDevices.Clear()
    foreach ($d in @($Ev.Devices)) {
        $x = New-Object WingetUM.DeviceDriver
        $x.Name = $d.Name; $x.Class = $d.Class; $x.Manufacturer = $d.Manufacturer; $x.Provider = $d.Provider; $x.Version = $d.Version
        $x.Date = $d.Date; $x.Inf = $d.Inf; $x.InstanceId = $d.InstanceId; $x.HardwareId = [string]$d.HardwareId
        $x.Problem = if ($d.Code) { $(if ($DeviceProblems.ContainsKey([int]$d.Code)) { $DeviceProblems[[int]$d.Code] } else { "Problem (code $($d.Code))" }) } else { '' }
        $DrvDevices.Add($x)
    }
    $script:DrvDevicesRead = $true
    try { Update-DeviceBackups } catch { Add-LogLine "Couldn't read the saved drivers: $($_.Exception.Message)" }
    $script:VendorCache = $null
    if ($script:Section -eq 'drivers') { Request-VendorInstall; if ($script:WuState -eq 'none') { Start-WuCheck; Start-NvLookup; Start-AmdLookup } }
}

# The vendor's tool when it isn't installed: offered once per session when the tab opens (and always by its button).
# The installed list must be read first, or a tool that is there would look missing. Dell Command | Update's check
# starts by itself once it is installed.
$script:VendorOffered = $false
$script:CheckAfterInstall = $false
function Request-VendorInstall {
    if ($script:VendorOffered -or -not $script:InstalledKnown) { return }
    $tool = Get-VendorTool
    if (-not $tool -or $tool.Installed -or -not $tool.CanInstall -or -not $WingetPath -or ($script:VendorRow -and $script:VendorRow.IsBusy)) { return }
    if ($UI.ConfirmOverlay.Visibility -eq 'Visible') { return }
    $script:VendorOffered = $true
    $maker = Get-MakerName
    Show-Confirm 'vendorinstall' $null "Install $($tool.Name)?" "$($tool.Name) isn't installed on this PC. It's $($tool.Vendor)'s tool for this $maker PC's BIOS, firmware and driver updates$(if ($tool.Cli -or $tool.Vendor -eq 'Dell') { ', and the Drivers tab uses it to check for and install them' }).`n`nwinget installs it ($($tool.Id)$(if ($tool.Source -eq 'msstore') { ', from the Microsoft Store' })); Windows may ask for administrator approval.$(if ($tool.Vendor -eq 'Dell') { ' The check for updates starts once it is installed.' })" 'Install'
}

# After a vendor or component tool's install finishes: forget the old detection, and check for updates when it can
function Complete-VendorInstall {
    $row = $script:VendorRow
    if (-not $script:CheckAfterInstall -or -not $row -or $row.IsBusy -or -not $row.State) { return }
    $script:CheckAfterInstall = $false
    $script:VendorCache = $null
    $tool = Get-VendorTool
    if (-not $row.IsDone) { return }
    if ($tool -and $tool.Cli -and $row.Id -eq $tool.Id) { Start-DriverCheck }
    elseif ($tool -and $tool.Vendor -eq 'Dell' -and $row.Id -eq $tool.Id) { $script:LastSummary = "Dell Command | Update installed, but dcu-cli.exe wasn't found in $(($tool.Paths | ForEach-Object { Split-Path $_ }) -join ' or '). Restart this app, or open Dell Command | Update from the Start menu." }
    else { $script:LastSummary = "$($row.Name) is installed. Open it from the Drivers tab." }
    Update-View
}

# Types the chips select, in Dell Command | Update's words
function Get-DrvTypes {
    $t = @()
    if ($UI.DrvTypeDriver.IsChecked) { $t += 'driver' }
    if ($UI.DrvTypeFirmware.IsChecked) { $t += 'firmware' }
    if ($UI.DrvTypeBios.IsChecked) { $t += 'bios' }
    if ($UI.DrvTypeApp.IsChecked) { $t += 'application'; $t += 'utility' }
    if ($UI.DrvTypeDriver.IsChecked) { $t += 'others' }
    return , $t
}
function Update-DrvIncluded {
    $types = Get-DrvTypes
    foreach ($u in $DrvUpdates) { if ($u.IsDell) { $u.Included = $types -contains $u.Kind } }
}

# The component tools line (Intel, NVIDIA, AMD): rebuilt only when something about it changed
$script:ExtrasKey = ''
function Update-DrvExtras {
    $parts = Get-ComponentTools
    $key = (@($parts | ForEach-Object { "$($_.Name)=$($_.Installed)" }) + @("busy=$($script:VendorRow -and $script:VendorRow.IsBusy)")) -join ';'
    $UI.DrvExtras.Visibility = ConvertTo-Visibility ($parts.Count -gt 0)
    if ($key -eq $script:ExtrasKey) { return }
    $script:ExtrasKey = $key
    $UI.DrvExtras.Children.Clear()
    $muted = $Window.FindResource('Muted')
    $label = New-Object System.Windows.Controls.TextBlock
    $label.Text = 'For this PC''s chips:'; $label.Foreground = $muted; $label.FontSize = 12.5; $label.VerticalAlignment = 'Center'; $label.Margin = '0,0,10,0'
    [void]$UI.DrvExtras.Children.Add($label)
    foreach ($p in $parts) {
        $b = New-Object System.Windows.Controls.Button
        $b.Style = $Window.FindResource('Ghost'); $b.Padding = '10,4'; $b.Margin = '0,0,6,0'; $b.BorderBrush = $Window.FindResource('InputBg'); $b.FontSize = 12.5
        $b.Content = if ($p.Installed) { "Open $($p.Name)" } elseif ($p.CanInstall) { "Install $($p.Name)" } else { "Get $($p.Name)" }
        $b.ToolTip = if ($p.Installed) { "$($p.Vendor)'s own driver tool for its chips in this PC" } elseif ($p.CanInstall) { "winget installs it ($($p.Id))" } else { "Opens $($p.Vendor)'s download page" }
        $b.Tag = $p
        $b.Add_Click({ param($s, $e) Invoke-ToolButton $s.Tag })
        [void]$UI.DrvExtras.Children.Add($b)
    }
}

# What a tool's button does: open it, install it with winget, or open the vendor's page to get it
function Invoke-ToolButton($p) {
    if (-not $p) { return }
    if ($p.Installed) { Open-VendorTool $p }
    elseif ($p.CanInstall) { Install-VendorTool $p }
    elseif ($p.ToolUrl) { try { Start-Process $p.ToolUrl } catch { } }
}

function Update-DriversView {
    $tool = Get-VendorTool
    $sys = $script:DrvSys
    $busy = [bool]$script:Elev
    $maker = Get-MakerName
    # a home-built PC has placeholder maker and model names; its motherboard says more
    $homeBuilt = $sys -and (-not $sys.Maker -or $sys.Maker -match '^(System manufacturer|To Be Filled|Default string|OEM|Not Applicable|Unknown)')
    $UI.DrvMaker.Text = if ($homeBuilt) { "Home-built PC  $Dot  $maker $($sys.BoardModel) motherboard".Trim() } elseif ($sys) { $(if ($sys.Model -like "$maker*") { $sys.Model } else { "$maker $($sys.Model)".Trim() }) } elseif ($script:DrvDeviceError) { "Couldn't read this PC's hardware" } else { "Reading your PC's hardware$Ellipsis" }
    $UI.DrvModel.Text = if ($sys) { (@($(if ($sys.Serial) { "Serial $($sys.Serial)" }), $(if ($sys.Bios) { "BIOS $($sys.Bios)" }), $env:COMPUTERNAME) | Where-Object { $_ }) -join "  $Dot  " } else { '' }
    $row = $script:VendorRow
    $installing = $row -and $row.IsBusy -and $tool -and $row.Id -eq $tool.Id
    foreach ($b in 'DrvToolAction', 'DrvOpenTool', 'DrvReinstallAll', 'DrvSupport') { $UI[$b].Visibility = 'Collapsed' }
    if ($sys) { Update-DrvExtras } else { $UI.DrvExtras.Visibility = 'Collapsed' }
    $entry = Get-VendorEntry
    if ($entry -and $entry.Url) { $UI.DrvSupport.Visibility = 'Visible'; $UI.DrvSupport.Tag = $(if ($tool) { $tool.Url } else { $entry.Url }) }
    if (-not $sys) { $UI.DrvToolText.Text = '' }
    elseif (-not $tool -or -not $tool.Name) {
        $UI.DrvToolText.Text = "$(if ($entry) { "$($entry.Vendor) has no driver tool this app can install." } else { "This app doesn't know a driver tool from $maker." }) Driver Updates lists what Windows Update offers for this PC$(if ($entry -and $entry.Url) { ", and Driver downloads opens $($entry.Vendor)'s support site" })."
    }
    elseif (-not $tool.Installed) {
        $UI.DrvToolText.Text = if ($installing) { "Installing $($tool.Name)$Ellipsis $($row.Detail)" } elseif ($row -and $row.Id -eq $tool.Id -and $row.State -eq 'error') { "$($tool.Name) didn't install: $($row.Detail)" }
        else { "$($tool.Vendor)'s driver tool, $($tool.Name), isn't installed. $(if ($tool.Cli -or $tool.Vendor -eq 'Dell') { 'Install it to add Dell''s BIOS, firmware and driver updates to Driver Updates.' } else { "It handles $($tool.Vendor)'s own BIOS, firmware and driver updates." }) Windows Update's drivers are listed either way." }
        $UI.DrvToolAction.Content = if ($tool.CanInstall) { "Install $($tool.Name)" } else { "Get $($tool.Name)" }
        $UI.DrvToolAction.IsEnabled = -not $installing -and ([bool]$WingetPath -or -not $tool.CanInstall)
        $UI.DrvToolAction.Visibility = 'Visible'
    }
    else {
        $UI.DrvToolText.Text = if ($tool.Cli) { "$($tool.Name)$(if ($tool.Version) { " $($tool.Version)" }) is installed. Driver Updates lists its updates and Windows Update's; installing asks for administrator approval once." }
        else { "$($tool.Name) is installed. Open it for $($tool.Vendor)'s own updates; Driver Updates lists what Windows Update offers.$(if ($tool.Note) { " $($tool.Note)" })" }
        $UI.DrvOpenTool.Content = "Open $($tool.Name)"; $UI.DrvOpenTool.Visibility = 'Visible'
        if ($tool.Cli) {
            $UI.DrvToolAction.Content = 'Check for updates'; $UI.DrvToolAction.Visibility = 'Visible'; $UI.DrvToolAction.IsEnabled = -not $busy
            $UI.DrvReinstallAll.Visibility = 'Visible'; $UI.DrvReinstallAll.IsEnabled = -not $busy
        }
    }

    $showUpd = [bool]$UI.DrvViewUpdates.IsChecked
    $checking = $script:WuState -eq 'running' -or $script:DrvScan -eq 'running' -or $script:NvState -eq 'running' -or $script:AmdState -eq 'running'
    $dellRows = @($DrvUpdates | Where-Object { $_.IsDell }).Count
    $UI.DrvViewDevicesText.Text = if ($script:DrvDevicesRead) { "Devices ($($DrvDevices.Count))" } else { 'Devices' }
    $UI.DrvViewUpdatesText.Text = if ($DrvUpdates.Count) { "Driver Updates ($($DrvUpdates.Count))" } elseif ($checking) { "Driver Updates$Ellipsis" } else { 'Driver Updates' }
    $UI.DrvUpdateTools.Visibility = ConvertTo-Visibility ($showUpd -and $dellRows -gt 0)
    $UI.DrvProblemsOnly.Visibility = ConvertTo-Visibility (-not $showUpd)
    $UI.DrvRefreshText.Text = if ($showUpd) { 'Check again' } else { 'Refresh' }
    $UI.DrvRefresh.IsEnabled = if ($showUpd) { -not $checking -and -not $busy } else { -not $script:DeviceScanner }
    $UI.DrvRefresh.Visibility = 'Visible'
    $n = @($DrvUpdates | Where-Object { $_.Included -and -not $_.HasAction }).Count
    $UI.DrvApply.Visibility = ConvertTo-Visibility ($showUpd -and @($DrvUpdates | Where-Object { -not $_.HasAction }).Count -gt 0)
    $UI.DrvApplyText.Text = if ($n) { "Install $n update$(if ($n -ne 1) { 's' })" } else { 'Install updates' }
    $UI.DrvApply.IsEnabled = $n -gt 0 -and -not $busy -and -not $checking

    # The note strip: an administrator run that has gone quiet (on either view), or else why managed driver updates
    # start unticked
    $wuRows = @($DrvUpdates | Where-Object { $_.IsWu }).Count
    $stalled = $script:Elev -and $script:ElevStalled
    $UI.DrvNote.Visibility = ConvertTo-Visibility ($stalled -or ($showUpd -and $script:WuManaged -and $wuRows -gt 0))
    $UI.DrvNoteAction.Visibility = ConvertTo-Visibility $stalled
    $UI.DrvNoteText.Text = if ($stalled) { "$($script:ElevTitle) hasn't made progress for $([int]((Get-Date) - $script:ElevActivity).TotalMinutes) minutes (last message: $($script:ElevLast.TrimEnd('.'))). Another Dell update tool or Dell's background update service may be holding it. Keep waiting, or stop waiting: it carries on in the background, and a restart clears it if it never finishes." }
    else { switch ($script:WuManaged) {
        'wufb' { "Your organization manages this PC's driver updates (Windows Update for Business, set through Intune). Windows Update offers these drivers for this hardware, but your IT department approves which ones install, so Settings > Windows Update may not show them. They start unticked: installing one here goes around that approval." }
        'wsus' { "This PC gets its updates from your organization's update server, which decides which drivers it offers. Windows Update lists these for this hardware, but your IT department may not have approved them. They start unticked: installing one here goes around that approval." }
        'excluded' { "Your organization has turned off driver updates from Windows Update on this PC, so Settings won't offer these. They start unticked: installing one here goes around that policy." }
        default { '' }
    } }

    # What fills the list card
    $UI.DrvDevHeader.Visibility = ConvertTo-Visibility (-not $showUpd)
    $UI.DrvUpdHeader.Visibility = ConvertTo-Visibility ($showUpd -and $DrvUpdates.Count)
    $msg = $null
    if (-not $showUpd) {
        if ($script:DeviceScanner -and -not $script:DrvDevicesRead) { $msg = @{ Bar = $true; Title = 'Reading devices'; Text = 'Windows is listing every device and its driver.' } }
        elseif ($script:DrvDeviceError) { $msg = @{ Title = "Couldn't read the devices"; Text = $script:DrvDeviceError } }
        elseif ($script:DrvDevicesRead -and -not @($DrvDevicesView).Count) { $msg = @{ Title = $(if ($UI.DrvProblemsOnly.IsChecked -and -not $UI.DrvSearch.Text) { 'No device problems' } else { 'No devices match' }); Text = $(if ($UI.DrvProblemsOnly.IsChecked) { 'Windows reports every device as working.' } else { '' }) } }
    }
    elseif ($DrvUpdates.Count) {
        if (-not @($DrvUpdatesView).Count) { $msg = @{ Title = 'No updates match'; Text = '' } }
    }
    elseif ($checking) {
        $what = @(); if ($script:WuState -eq 'running') { $what += 'Windows Update' }; if ($script:NvState -eq 'running') { $what += 'NVIDIA' }; if ($script:AmdState -eq 'running') { $what += 'AMD' }; if ($script:DrvScan -eq 'running') { $what += 'Dell Command | Update' }
        $msg = @{ Bar = $true; Title = 'Checking for driver updates'; Text = "Asking $($what -join ' and ')$Ellipsis$(if ($script:DrvScan -eq 'running' -and $script:ElevLast) { " $($script:ElevLast)" })" }
        if ($script:ElevStalled -and $script:DrvScan -eq 'running') {
            $mins = [int]((Get-Date) - $script:ElevActivity).TotalMinutes
            $msg = @{ Bar = $true; Title = "Dell Command | Update hasn't made progress for $mins minutes"; Action = 'Stop waiting'
                Text = "Last message: $($script:ElevLast). Dell's background update service or another Dell tool may be holding it. You can keep waiting, or stop waiting (the check carries on in the background; restart Windows if it never finishes)." }
        }
    }
    elseif ($script:WuState -eq 'none' -and $script:DrvScan -eq 'none') {
        $msg = @{ Title = 'Check for driver updates'; Text = "Windows Update has certified drivers from every vendor$(if ($tool -and $tool.Cli) { ', and Dell Command | Update adds Dell''s BIOS, firmware and driver updates' })."; Action = 'Check for updates' }
    }
    else {
        $notes = @()
        if ($script:WuState -eq 'error') { $notes += "Windows Update couldn't be checked: $($script:WuNote)" } elseif ($script:WuState -eq 'ready') { $notes += 'Windows Update has no newer drivers for this PC.' }
        if ($script:NvState -eq 'ready' -and $script:NvNote) { $notes += $script:NvNote } elseif ($script:NvState -eq 'error') { $notes += "NVIDIA's driver lookup didn't answer ($($script:NvNote)); the NVIDIA App can still check." }
        if ($script:AmdState -eq 'ready' -and $script:AmdNote) { $notes += $script:AmdNote } elseif ($script:AmdState -eq 'error') { $notes += "AMD's driver page didn't answer ($($script:AmdNote)); AMD Software can still check." }
        if ($script:DrvScan -in 'uptodate', 'error') { $notes += $script:DrvScanNote }
        if ($tool -and $tool.Installed -and -not $tool.Cli) { $notes += "$($tool.Name) may still have $($tool.Vendor)-only updates: use Open $($tool.Name) above." }
        $msg = @{ Title = $(if ($script:WuState -eq 'error' -or $script:DrvScan -eq 'error') { 'Some checks didn''t finish' } else { 'Everything is up to date' }); Text = $notes -join ' '; Action = 'Check again' }
    }
    $UI.DrvDevices.Visibility = if (-not $showUpd -and -not $msg) { 'Visible' } else { 'Collapsed' }
    $UI.DrvUpdates.Visibility = if ($showUpd -and -not $msg) { 'Visible' } else { 'Collapsed' }
    $UI.DrvMsgPanel.Visibility = ConvertTo-Visibility ([bool]$msg)
    if ($msg) {
        $UI.DrvMsgBar.Visibility = ConvertTo-Visibility ([bool]$msg.Bar)
        $UI.DrvMsgTitle.Text = $msg.Title; $UI.DrvMsgText.Text = $msg.Text
        $UI.DrvMsgAction.Visibility = ConvertTo-Visibility ([bool]$msg.Action -and (-not $busy -or $msg.Action -eq 'Stop waiting'))
        if ($msg.Action) { $UI.DrvMsgAction.Content = $msg.Action }
    }
}

# Installs a vendor or component tool through the job queue (winget, or the Microsoft Store through winget)
function Install-VendorTool($p) {
    if (-not $p) { $p = Get-VendorTool }
    if (-not $p -or $p.Installed -or -not $p.CanInstall) { return }
    $script:CheckAfterInstall = $true
    $row = Get-Row 'discover' @{ Id = $p.Id; Source = $p.Source; Name = $p.Name; Version = '' }
    $ByKey[$row.Key] = $row
    $script:VendorRow = $row
    $script:ExtrasKey = ''
    Add-Job @($row)
}

function Open-VendorTool($p) {
    if (-not $p) { $p = Get-VendorTool }
    if (-not $p) { return }
    # Store-style apps (Dell Command | Update for Windows Universal, MyASUS, Lenovo Vantage) start from their Start menu entry
    try {
        $apps = @(Get-StartApps)
        $app = $null
        foreach ($n in @($p.Names) + @($p.Name)) { if (-not $app -and $n) { $app = @($apps | Where-Object { $_.Name -like $n -or $_.Name -like ($n -replace ' \| ', '*') }) | Select-Object -First 1 } }
        if ($app) { Start-Process "shell:AppsFolder\$($app.AppID)"; return }
    }
    catch { }
    $exe = if ($p.Gui) { $p.Gui } elseif ($p.Path -and $p.Path -notmatch 'cli\.exe$') { $p.Path } else { $null }
    if ($exe) { try { Start-Process -FilePath $exe; return } catch { } }
    $script:LastSummary = "Couldn't find $($p.Name) in the Start menu; open it from there."
    Update-View
}

# Driver Updates: Windows Update's drivers (no approval needed to look) and, on a Dell, Dell Command | Update's
function Start-WuCheck {
    if ($script:WuSearcher) { return }
    $script:WuState = 'running'
    $script:WuSearcher = Start-Background 'wusearch' @{}
    Update-View
}
function Complete-WuSearch($Ev) {
    foreach ($u in @($DrvUpdates | Where-Object { $_.IsWu })) { [void]$DrvUpdates.Remove($u) }
    if ($Ev.Error) { $script:WuState = 'error'; $script:WuNote = $Ev.Error; return }
    $script:WuManaged = [string]$Ev.Managed
    foreach ($w in @($Ev.Updates)) {
        $u = New-Object WingetUM.DriverUpdate
        $u.Source = 'Windows Update'; $u.UpdateId = $w.Id; $u.Kind = 'wu'
        $u.Name = ($w.Title -replace '\s*\([\d.]+\)\s*$', '')
        $u.Version = if ($w.Title -match '\(([\d.]+)\)\s*$') { $Matches[1] } else { '' }
        $u.Type = if (-not $w.Class -or $w.Class -eq 'OtherHardware') { 'Driver' } elseif ($w.Class -match '^Firmware') { 'Firmware' } elseif ($w.Class -match '^Net') { 'Network' } elseif ($w.Class -match 'Media|Audio') { 'Audio' } else { $w.Class }
        $u.Category = @($w.Maker, $w.Model | Where-Object { $_ }) -join "  $Dot  "
        $u.Severity = ''
        $u.SizeText = if ($w.Size -ge 1GB) { '{0:0.0} GB' -f ($w.Size / 1GB) } elseif ($w.Size -ge 1MB) { '{0:0} MB' -f ($w.Size / 1MB) } elseif ($w.Size -gt 0) { '{0:0} KB' -f ($w.Size / 1KB) } else { '' }
        $u.Released = $w.Date
        # on a PC whose drivers the organization manages, installing one here would go around its approval
        $u.Included = -not $script:WuManaged
        $DrvUpdates.Add($u)
    }
    $script:WuState = 'ready'
}
# NVIDIA graphics only; the lookup needs no approval
function Start-NvLookup {
    if ($script:NvSearcher) { return }
    $chips = if ($script:DrvSys) { [string]$script:DrvSys.Chips } else { '' }
    if (-not $script:NvTest -and $chips -notmatch 'NVIDIA') { $script:NvState = 'nogpu'; return }
    $script:NvState = 'running'
    $script:NvSearcher = Start-Background 'nvlookup' $(if ($script:NvTest) { $script:NvTest } else { @{} })
    Update-View
}
function Complete-NvLookup($Ev) {
    foreach ($u in @($DrvUpdates | Where-Object { $_.Source -eq 'NVIDIA' })) { [void]$DrvUpdates.Remove($u) }
    if ($Ev.None) { $script:NvState = 'nogpu'; return }
    if ($Ev.Error) { $script:NvState = 'error'; $script:NvNote = $Ev.Error; Add-LogLine "NVIDIA driver lookup: $($Ev.Error)"; return }
    $script:NvState = 'ready'
    $newer = $false
    try { $newer = -not $Ev.Installed -or ([version]$Ev.Latest -gt [version]$Ev.Installed) } catch { $newer = $Ev.Latest -ne $Ev.Installed }
    $script:NvNote = if ($newer) { '' } else { "NVIDIA's newest Game Ready driver for the $($Ev.Gpu) is $($Ev.Latest), which is installed." }
    Add-LogLine "NVIDIA driver lookup: $($Ev.Gpu) has $($Ev.Installed); newest is $($Ev.Latest) ($($Ev.Date))."
    if (-not $newer) { return }
    $u = New-Object WingetUM.DriverUpdate
    $u.Source = 'NVIDIA'; $u.Kind = 'nvidia'; $u.Url = $Ev.Url; $u.UpdateId = $Ev.Latest
    $u.Name = if ($Ev.Title) { $Ev.Title } else { 'NVIDIA Game Ready Driver' }
    $u.Version = $Ev.Latest
    $u.Type = 'Display'
    $u.Category = "$($Ev.Gpu)$(if ($Ev.Installed) { "  $Dot  installed $($Ev.Installed)" })"
    $u.Severity = 'Game Ready'
    $u.SizeText = ($Ev.Size -replace '\s*MB$', ' MB')
    $u.Released = $Ev.Date
    $u.Included = $true
    $DrvUpdates.Insert(0, $u)   # first in the list: it's the one most people look for
}

function Start-DriverCheck {
    $UI.DrvViewUpdates.IsChecked = $true
    Start-WuCheck
    Start-NvLookup
    Start-AmdLookup
    $tool = Get-VendorTool
    if ($tool -and $tool.Cli -and -not $script:Elev) { Start-DellScan }
    Update-View
}
# One elevated run at a time. The script gets $log (write progress there with Say) and may write its own logs,
# listed in -Logs so the window follows them too. Runs that change the PC pass -RestorePoint: with "Restore point
# first" on (a saved setting), one is made before anything else.
function Start-Elevated([string]$Name, [string]$Title, [string]$Body, [string[]]$ExtraLogs, $Tag, [switch]$RestorePoint, [string]$RestoreText = 'Before driver changes', [int]$StallMinutes = $ElevStallMinutes) {
    if ($script:Elev) { return }
    # how long it may stay quiet before the window offers to stop waiting (Windows Update installs can be slow)
    $script:ElevStallLimit = $StallMinutes
    New-Item -ItemType Directory -Path $DrvWorkDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $log = Join-Path $DrvWorkDir "$Name-$stamp.log"
    $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
    $prelude = "`$ErrorActionPreference = 'Continue'`r`n`$log = $(& $q $log)`r`nfunction Say([string]`$Text) { Add-Content -LiteralPath `$log -Value `$Text -Encoding UTF8 }`r`n"
    $head = ''
    if ($RestorePoint -and $Settings.DriverRestorePoint) {
        # Windows makes at most one restore point a day unless SystemRestorePointCreationFrequency says otherwise, so
        # it is set to 0 for this one and put back afterwards
        $head += @"
Say 'Creating a restore point first$Ellipsis'
`$srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
`$srOld = (Get-ItemProperty -LiteralPath `$srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
try {
    Set-ItemProperty -LiteralPath `$srKey -Name SystemRestorePointCreationFrequency -Value 0 -Type DWord -ErrorAction SilentlyContinue
    `$w = `$null; Checkpoint-Computer -Description '$($RestoreText -replace "'", "''") (Windows Manager)' -RestorePointType MODIFY_SETTINGS -WarningAction SilentlyContinue -WarningVariable w -ErrorAction Stop
    if (`$w) { Say ('Restore point not created: ' + (`$w -join ' ')) } else { Say 'Restore point created.'; Say 'RESTOREPOINT|ok' }
}
catch {
    `$m = `$_.Exception.Message
    if (`$m -match 'disabled|protection|0x80070422|turned off') { `$m = 'System Protection is off for the system drive (turn it on in Control Panel > System > System Protection). ' + `$m }
    Say ('Restore point not created: ' + `$m); Say 'RESTOREPOINT|failed'
}
finally {
    if (`$null -eq `$srOld) { Remove-ItemProperty -LiteralPath `$srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
    else { Set-ItemProperty -LiteralPath `$srKey -Name SystemRestorePointCreationFrequency -Value `$srOld -Type DWord -ErrorAction SilentlyContinue }
}

"@
    }
    # Every run is a script file next to its log, so a failure can be read (or run again by hand) afterwards. It
    # says who it runs as, and any error it hits ends up in the log with exit code 99.
    $who = "Say ('{0:G}  Windows Manager ${AppVersion}: $($Title -replace "'", "''")' -f (Get-Date))`r`nSay ('Running as ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)`r`n"
    $script = $prelude + "try {`r`n" + $who + $head + $Body.Replace('__DIR__', (& $q $DrvWorkDir)).Replace('__STAMP__', $stamp) +
    "`r`n}`r`ncatch { Say ('Error: ' + (`$_.Exception.Message -replace '(?s)\s*At [A-Za-z]:\\.*`$', '')); Say (`$_.InvocationInfo.PositionMessage); exit 99 }`r`n"
    $scriptPath = Join-Path $DrvWorkDir "$Name-$stamp.ps1"
    [byte[]]$bytes = (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($script)   # + gives object[]
    [IO.File]::WriteAllBytes($scriptPath, $bytes)
    # Any program the user runs can change files in $DrvWorkDir, so the script could be swapped between being
    # written here and the approval. The elevated copy is told the script's SHA-256 on its command line (which
    # nothing else can change), reads the file once, checks it and runs what it read; a changed script doesn't run.
    $hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($bytes) | ForEach-Object { $_.ToString('X2') })
    $boot = "`$b = [IO.File]::ReadAllBytes($(& $q $scriptPath))`r`n" +
    "`$h = -join ([Security.Cryptography.SHA256]::Create().ComputeHash(`$b) | ForEach-Object { `$_.ToString('X2') })`r`n" +
    "if (`$h -ne '$hash') { try { Add-Content -LiteralPath $(& $q $log) -Value 'Not run: the script was changed after Windows Manager wrote it.' -Encoding UTF8 } catch { }; exit 96 }`r`n" +
    "& ([scriptblock]::Create([Text.Encoding]::UTF8.GetString(`$b).TrimStart([char]0xFEFF)))`r`nexit 0"
    $bootArg = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($boot))
    $logs = @($log) + @($ExtraLogs | Where-Object { $_ } | ForEach-Object { $_.Replace('__STAMP__', $stamp) })
    $tagAll = $(if ($Tag) { $Tag } else { @{} }) + @{ Stamp = $stamp; Log = $log }
    Add-LogLine ''
    Add-LogLine "---- $Title (as administrator) ----"
    Add-LogLine "Script: $scriptPath"
    Add-LogLine "Log:    $log"
    $script:ElevTitle = $Title
    $script:ElevError = ''
    $script:ElevLast = if ($IsAdmin) { '' } else { 'Waiting for administrator approval' }
    Update-View
    # Started here, on the window's thread: Windows shows the approval prompt reliably from it (not always from a
    # background thread)
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    try {
        $proc = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -WindowStyle Hidden -PassThru `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $bootArg"
    }
    catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        $declined = ($ex -is [ComponentModel.Win32Exception] -and $ex.NativeErrorCode -eq 1223) -or $ex.Message -match 'cancel'
        Add-LogLine "Couldn't start as administrator: $($ex.Message)"
        Complete-Elevated @{ Name = $Name; Tag = $tagAll; Code = -1; Declined = $declined; Error = $ex.Message }
        return
    }
    finally { $Window.Cursor = $null }
    $script:ElevLast = 'Starting' + $Ellipsis
    $script:ElevName = $Name; $script:ElevTag = $tagAll
    $script:ElevActivity = Get-Date; $script:ElevStalled = $false
    $script:Elev = Start-Background 'elevated' @{ Name = $Name; Process = $proc; Logs = $logs; Tag = $tagAll }
    Update-View
}

# Dell Command | Update (dcu-cli, 5.x): /scan writes the applicable updates as XML under -report; /applyUpdates and
# /driverInstall install; -reboot=disable leaves the restart to you
$DcuResults = @{ 0 = 'Done'; 1 = 'Done. Restart to finish'; 2 = 'Dell Command | Update hit an unexpected error'; 3 = 'Dell Command | Update hit an error'
    4 = 'Dell Command | Update needs administrator rights'; 5 = 'Restart Windows, then check again'; 6 = 'Dell Command | Update is already running'
    7 = "This PC model isn't supported by Dell Command | Update"; 8 = 'No update types are selected'; 500 = 'No updates were found for this PC'
    501 = "Couldn't work out which updates apply"; 502 = 'The check was cancelled'; 503 = "Couldn't download the update list"
    1000 = "Couldn't read the install result"; 1001 = 'The install was cancelled'; 1002 = "Couldn't download the updates"
    97 = "Dell Command | Update's command-line tool didn't start"; 98 = "Dell Command | Update's command-line tool (dcu-cli.exe) wasn't found"; 99 = 'The administrator step hit an error' }
function Get-DcuText([int]$Code) { if ($DcuResults.ContainsKey($Code)) { return $DcuResults[$Code] } return "Dell Command | Update exited with code $Code; see the log" }

# dcu-cli says in its log when a scan's results came from its cache instead of a fresh check against Dell's catalogue
function Test-DcuCached([string]$Stamp) {
    $f = Join-Path $DrvWorkDir "dcu-scan-$Stamp.log"
    if (-not $Stamp -or -not (Test-Path -LiteralPath $f)) { return $false }
    return [bool](Select-String -LiteralPath $f -Pattern 'RESULTS_FROM_CACHE|returned from the cache' -Quiet)
}

# =====================================================================================================================
# 3. Only one Dell Command | Update can work at a time: a check (dcu-cli) that is still running, or Dell's window
# =====================================================================================================================
function Get-DellBusy {
    $cli = @(Get-Process -Name 'dcu-cli' -ErrorAction SilentlyContinue)
    if ($cli.Count) {
        $since = try { ' since {0:t}' -f $cli[0].StartTime } catch { '' }
        return "An earlier Dell Command | Update check is still running (dcu-cli.exe$since). Only one can run at a time: wait for it, or end dcu-cli.exe in Task Manager (or restart Windows), then check again."
    }
    $gui = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^Dell\.?CommandUpdate' })
    if ($gui.Count) { return "Dell Command | Update's own window is open. Close it first: only one can check or install at a time." }
    return $null
}

function Start-DellScan {
    $tool = Get-VendorTool
    if (-not $tool -or -not $tool.Cli) { return }
    $UI.DrvViewUpdates.IsChecked = $true
    $busyText = Get-DellBusy
    if ($busyText) { $script:DrvScan = 'error'; $script:DrvScanNote = $busyText; Update-View; return }
    $script:DrvScan = 'running'
    foreach ($u in @($DrvUpdates | Where-Object { $_.IsDell })) { [void]$DrvUpdates.Remove($u) }
    $body = "`$dcu = '$($tool.Path -replace "'", "''")'`r`nif (-not (Test-Path -LiteralPath `$dcu)) { Say `"Not found: `$dcu`"; exit 98 }`r`nSay ('dcu-cli ' + (Get-Item -LiteralPath `$dcu).VersionInfo.ProductVersion + ': ' + `$dcu)`r`n`$dir = Join-Path __DIR__ 'scan-__STAMP__'`r`nNew-Item -ItemType Directory -Path `$dir -Force | Out-Null`r`nSay 'Asking Dell which updates apply to this PC$Ellipsis'`r`n`$global:LASTEXITCODE = `$null; & `$dcu /scan -silent `"-report=`$dir`" `"-outputLog=`$(Join-Path __DIR__ 'dcu-scan-__STAMP__.log')`" 2>&1 | ForEach-Object { Say ([string]`$_) }`r`n`$c = `$LASTEXITCODE`r`nif (`$null -eq `$c) { Say 'dcu-cli.exe did not start (the line above says why).'; exit 97 }`r`nSay `"Dell Command | Update finished with code `$c`"`r`nexit `$c"
    Start-Elevated 'scan' "Checking Dell for updates" $body @((Join-Path $DrvWorkDir 'dcu-scan-__STAMP__.log'))
}

# Reads the scan report: each <update> element's children (name, version, date, urgency, type, category, size)
function Read-DellReport([string]$Stamp) {
    foreach ($u in @($DrvUpdates | Where-Object { $_.IsDell })) { [void]$DrvUpdates.Remove($u) }
    $script:DellFound = 0
    $dir = Join-Path $DrvWorkDir "scan-$Stamp"
    $file = @(Get-ChildItem -LiteralPath $dir -Filter *.xml -ErrorAction SilentlyContinue) | Select-Object -First 1
    if (-not $file) { return $false }
    [xml]$x = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($n in @($x.SelectNodes('//*[local-name()="update"]'))) {
        $f = @{}
        foreach ($c in $n.ChildNodes) { if ($c.NodeType -eq 'Element') { $f[$c.LocalName.ToLowerInvariant()] = $c.InnerText.Trim() } }
        foreach ($a in $n.Attributes) { if (-not $f.ContainsKey($a.LocalName.ToLowerInvariant())) { $f[$a.LocalName.ToLowerInvariant()] = $a.Value } }
        $u = New-Object WingetUM.DriverUpdate
        $u.Source = 'Dell Command | Update'
        $u.Name = @($f.name, $f.displayname, $f.title, 'Update' | Where-Object { $_ })[0]
        $type = [string]@($f.type, $f.updatetype, $f.componenttype | Where-Object { $_ })[0]
        $u.Kind = switch -Regex ($type) { 'bios' { 'bios' } 'firm' { 'firmware' } 'driver' { 'driver' } 'app' { 'application' } 'util' { 'utility' } default { 'others' } }
        $u.Type = if ($type) { (Get-Culture).TextInfo.ToTitleCase($type.ToLowerInvariant()) } else { 'Other' }
        if ($u.Kind -eq 'bios') { $u.Type = 'BIOS' }
        $u.Category = [string]@($f.category, $f.devicecategory | Where-Object { $_ })[0]
        $u.Version = [string]@($f.version, $f.vendorversion | Where-Object { $_ })[0]
        $u.Severity = [string]@($f.urgency, $f.criticality, $f.severity, $f.importance | Where-Object { $_ })[0]
        $bytes = [long]0; [void][long]::TryParse([string]@($f.bytes, $f.size, $f.filesize | Where-Object { $_ })[0], [ref]$bytes)
        $u.SizeText = if ($bytes -ge 1GB) { '{0:0.0} GB' -f ($bytes / 1GB) } elseif ($bytes -ge 1MB) { '{0:0} MB' -f ($bytes / 1MB) } elseif ($bytes -gt 0) { '{0:0} KB' -f ($bytes / 1KB) } else { '' }
        $d = [string]@($f.date, $f.releasedate | Where-Object { $_ })[0]
        $dt = [datetime]::MinValue
        $u.Released = if ($d -and [datetime]::TryParse($d, [ref]$dt)) { $dt.ToString('yyyy-MM-dd') } else { $d }
        $DrvUpdates.Add($u)
        $script:DellFound++
    }
    Update-DrvIncluded
    return $true
}

function Request-DellApply {
    $wu = @($DrvUpdates | Where-Object { $_.IsWu -and $_.Included })
    $dell = @($DrvUpdates | Where-Object { $_.IsDell -and $_.Included })
    $nv = @($DrvUpdates | Where-Object { $_.Source -eq 'NVIDIA' -and $_.Included }) | Select-Object -First 1
    $n = $wu.Count + $dell.Count + [int][bool]$nv
    if (-not $n) { return }
    $types = if ($dell.Count) { Get-DrvTypes } else { @() }
    $bios = @($dell | Where-Object { $_.Kind -eq 'bios' }).Count
    $from = @(); if ($wu.Count) { $from += "$($wu.Count) from Windows Update" }; if ($nv) { $from += "NVIDIA's $($nv.Version) driver ($($nv.SizeText) download)" }; if ($dell.Count) { $from += "$($dell.Count) from Dell Command | Update" }
    $text = "$($from -join ' and '). They download and install silently; Windows asks for administrator approval once. Some need a restart, which is left to you." +
    $(if ($wu.Count -and $script:WuManaged) { "`n`nYour organization manages driver updates on this PC, and these Windows Update drivers may not be approved by your IT department." } else { '' }) +
    $(if ($bios) { "`n`nThe BIOS update runs during the next restart: keep the laptop plugged in. BitLocker is suspended for that one restart." } else { '' }) +
    $(if ($nv) { "`n`nNVIDIA's installer only runs once its NVIDIA signature checks out. The screen may go black for a moment while the graphics driver changes, so save your work in games or video apps first." } else { '' }) +
    $(if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." } else { '' })
    $nvArg = if ($nv) { @{ Url = $nv.Url; Version = $nv.Version; Name = $nv.Name } } else { $null }
    Show-Confirm 'drvapply' @{ Types = $types; Count = $n; Wu = @($wu | ForEach-Object { @{ Id = $_.UpdateId; Name = $_.Name; Version = $_.Version } }); DellCount = $dell.Count; Nv = $nvArg } "Install $n driver update$(if ($n -ne 1) { 's' })?" $text 'Install'
}

# The script ends with exit 0 (done), 3010 (done, restart needed) or 1 (something failed); each update's result is
# a "RESULT|source|id|code|name" line in its log, read back for History
function Start-DellApply($Types, [int]$Count, $Wu, [int]$DellCount, $Nv) {
    $tool = Get-VendorTool
    if ($DellCount) { $busyText = Get-DellBusy; if ($busyText) { $script:LastSummary = $busyText; Update-View; return } }
    $body = "`$fail = 0; `$reboot = `$false`r`n"
    # the drivers that Windows Update's and NVIDIA's updates replace are saved first, for Roll back
    if (@($Wu).Count -or $Nv) { $body += Get-BackupFunctionText }
    if (@($Wu).Count) {
        $ids = (@($Wu) | ForEach-Object { "'" + ($_.Id -replace "'", "''") + "'" }) -join ', '
        $body += @"
Say 'Installing $(@($Wu).Count) driver update(s) from Windows Update$Ellipsis'
`$ids = @($ids)
`$s = New-Object -ComObject Microsoft.Update.Session
`$s.ClientApplicationID = 'Windows Manager'
`$found = `$s.CreateUpdateSearcher().Search("IsInstalled=0 and Type='Driver'")
`$coll = New-Object -ComObject Microsoft.Update.UpdateColl
foreach (`$u in `$found.Updates) { if (`$ids -contains `$u.Identity.UpdateID) { if (-not `$u.EulaAccepted) { `$u.AcceptEula() }; [void]`$coll.Add(`$u) } }
Say "Found `$(`$coll.Count) of `$(`$ids.Count). Downloading$Ellipsis"
if (`$coll.Count) {
$($WuBackupStep)    `$d = `$s.CreateUpdateDownloader(); `$d.Updates = `$coll; `$dr = `$d.Download(); Say "Download finished (result `$(`$dr.ResultCode))"
    Say 'Installing$Ellipsis'
    `$i = `$s.CreateUpdateInstaller(); `$i.Updates = `$coll; `$ir = `$i.Install()
    for (`$k = 0; `$k -lt `$coll.Count; `$k++) { `$rc = `$ir.GetUpdateResult(`$k).ResultCode; Say ('RESULT|wu|' + `$coll.Item(`$k).Identity.UpdateID + '|' + `$rc + '|' + `$coll.Item(`$k).Title); if (`$rc -ne 2 -and `$rc -ne 3) { `$fail++ } }
    if (`$ir.RebootRequired) { `$reboot = `$true; Say 'Windows says a restart is needed to finish.' }
}
if (`$coll.Count -lt `$ids.Count) { `$fail += `$ids.Count - `$coll.Count; Say 'Some updates were no longer offered by Windows Update.' }

"@
    }
    if ($Nv -and $Nv.Url -match '^https://[\w.-]+\.nvidia\.com/') {
        $nvUrl = $Nv.Url -replace "'", "''"; $nvVer = $Nv.Version -replace "[^\d.]", ''
        $body += @"
# NVIDIA: download the driver package, check it is signed by NVIDIA, install it silently, read the version back
Say 'Downloading the NVIDIA $nvVer driver$Ellipsis'
`$nvFile = Join-Path __DIR__ 'nvidia-$nvVer.exe'
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    `$req = [Net.HttpWebRequest]::Create('$nvUrl'); `$req.UserAgent = 'Windows Manager'
    `$resp = `$req.GetResponse(); `$total = `$resp.ContentLength; `$in = `$resp.GetResponseStream(); `$out = [IO.File]::Create(`$nvFile)
    `$buf = New-Object byte[] 1048576; `$done = [long]0; `$next = 10
    while ((`$n = `$in.Read(`$buf, 0, `$buf.Length)) -gt 0) { `$out.Write(`$buf, 0, `$n); `$done += `$n; if (`$total -gt 0 -and (`$done * 100 / `$total) -ge `$next) { Say ("Downloaded `$next% (" + [int](`$done / 1MB) + ' MB)'); `$next += 10 } }
    `$out.Close(); `$in.Close(); `$resp.Close()
    `$sig = Get-AuthenticodeSignature -LiteralPath `$nvFile
    if (`$sig.Status -ne 'Valid' -or `$sig.SignerCertificate.Subject -notmatch 'NVIDIA') { Say "The download isn't signed by NVIDIA (`$(`$sig.Status)), so it was not installed."; Say 'RESULT|nvidia|$nvVer|98|NVIDIA $nvVer driver'; `$fail++ }
    else {
$($NvBackupStep)        Say "Signed by `$(`$sig.SignerCertificate.Subject -replace '^CN=([^,]+).*', '`$1'). Installing silently (the screen may go black for a moment)$Ellipsis"
        `$p = Start-Process -FilePath `$nvFile -ArgumentList '-s -noreboot -noeula' -Wait -PassThru
        `$g = @(Get-CimInstance Win32_VideoController | Where-Object { "`$(`$_.AdapterCompatibility) `$(`$_.Name)" -match 'NVIDIA' }) | Select-Object -First 1
        `$dg = ([string]`$g.DriverVersion -replace '\D', ''); `$now = if (`$dg.Length -ge 5) { `$d5 = `$dg.Substring(`$dg.Length - 5); "`$([int]`$d5.Substring(0, 3)).`$(`$d5.Substring(3))" } else { '' }
        Say "NVIDIA's installer finished with code `$(`$p.ExitCode); the driver is now `$now"
        `$rc = if (`$now -eq '$nvVer') { 0 } elseif (`$p.ExitCode -eq 0) { 3010 } else { `$p.ExitCode }
        Say ('RESULT|nvidia|$nvVer|' + `$rc + '|NVIDIA $nvVer driver')
        if (`$rc -eq 3010) { `$reboot = `$true; Say 'Restart to finish switching to the new driver.' } elseif (`$rc -ne 0) { `$fail++ }
    }
}
catch { Say ('NVIDIA download or install failed: ' + `$_.Exception.Message); Say 'RESULT|nvidia|$nvVer|99|NVIDIA $nvVer driver'; `$fail++ }
finally { if (Test-Path -LiteralPath `$nvFile) { Remove-Item -LiteralPath `$nvFile -Force -ErrorAction SilentlyContinue } }

"@
    }
    if ($DellCount -and $tool -and $tool.Cli) {
        $body += "`$dcu = '$($tool.Path -replace "'", "''")'`r`nif (-not (Test-Path -LiteralPath `$dcu)) { Say `"Not found: `$dcu`"; `$fail++ }`r`nelse {`r`n    Say ('dcu-cli ' + (Get-Item -LiteralPath `$dcu).VersionInfo.ProductVersion + ': ' + `$dcu)`r`n    Say 'Installing Dell updates ($($Types -join ', '))$Ellipsis'`r`n    `$global:LASTEXITCODE = `$null; & `$dcu /applyUpdates -silent -reboot=disable -autoSuspendBitLocker=enable `"-updateType=$($Types -join ',')`" `"-outputLog=`$(Join-Path __DIR__ 'dcu-apply-__STAMP__.log')`" 2>&1 | ForEach-Object { Say ([string]`$_) }`r`n    `$c = `$LASTEXITCODE`r`n    if (`$null -eq `$c) { Say 'dcu-cli.exe did not start (the line above says why).'; `$c = 97 }`r`n    Say ('RESULT|dell|' + `$c + '|' + `$c + '|Dell Command | Update')`r`n    if (`$c -eq 1 -or `$c -eq 5) { `$reboot = `$true } elseif (`$c -ne 0) { `$fail++ }`r`n}`r`n"
    }
    $body += "if (`$fail) { Say `"`$fail update(s) did not install.`"; exit 1 } elseif (`$reboot) { exit 3010 } else { Say 'All done.'; exit 0 }"
    Start-Elevated 'apply' "Installing $Count driver update$(if ($Count -ne 1) { 's' })" $body @((Join-Path $DrvWorkDir 'dcu-apply-__STAMP__.log')) @{ Count = $Count; Types = $Types; Wu = $Wu; DellCount = $DellCount } -RestorePoint
}
function Request-DellDriverInstall {
    Show-Confirm 'drvinstall' $null 'Reinstall all drivers?' "Dell Command | Update's driver restore downloads and reinstalls every base driver for this $($script:DrvSys.Model). It takes a while, the screen or network may drop out briefly, and a restart is usually needed afterwards.$(if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." })" 'Reinstall drivers'
}

function Start-DellDriverInstall {
    $tool = Get-VendorTool
    $busyText = Get-DellBusy
    if ($busyText) { $script:LastSummary = $busyText; Update-View; return }
    if (-not $tool -or -not $tool.Cli) { return }
    $body = "`$dcu = '$($tool.Path -replace "'", "''")'`r`nif (-not (Test-Path -LiteralPath `$dcu)) { Say `"Not found: `$dcu`"; exit 98 }`r`nSay ('dcu-cli ' + (Get-Item -LiteralPath `$dcu).VersionInfo.ProductVersion + ': ' + `$dcu)`r`nSay 'Reinstalling all base drivers for this model$Ellipsis'`r`n`$global:LASTEXITCODE = `$null; & `$dcu /driverInstall -silent -reboot=disable `"-outputLog=`$(Join-Path __DIR__ 'dcu-drivers-__STAMP__.log')`" 2>&1 | ForEach-Object { Say ([string]`$_) }`r`n`$c = `$LASTEXITCODE`r`nif (`$null -eq `$c) { Say 'dcu-cli.exe did not start (the line above says why).'; exit 97 }`r`nSay `"Dell Command | Update finished with code `$c`"`r`nexit `$c"
    Start-Elevated 'driverinstall' 'Reinstalling all drivers' $body @((Join-Path $DrvWorkDir 'dcu-drivers-__STAMP__.log')) -RestorePoint
}

# Per device, with pnputil: reinstall = remove the device and scan for hardware, so Windows sets it up again with
# the best driver it has; remove = uninstall the third-party driver package (the device falls back to another)
function Request-DeviceAction($d, [string]$Action) {
    if (-not $d -or -not $d.CanAct -or $script:Elev) { return }
    if ($Action -eq 'remove' -and -not $d.IsOem) { return }
    $warn = if ($d.Class -match 'Display|Net|Keyboard|Mouse|HIDClass|DiskDrive|SCSIAdapter|HDC|System') { "`n`nThis is a $($d.Class) device, so it drops out for a moment (the screen may flicker or the network disconnect)." } else { '' }
    $rp = if ($Settings.DriverRestorePoint) { "`n`nA restore point is created first." } else { '' }
    if ($Action -eq 'reinstall') {
        Show-Confirm 'drvreinstall' @{ Device = $d } "Reinstall the driver for $($d.Name)?" "Windows removes the device and finds it again straight away, setting it up with the best driver it has.$warn$rp" 'Reinstall'
    }
    else {
        Show-Confirm 'drvremove' @{ Device = $d } "Remove the driver for $($d.Name)?" "This uninstalls $($d.Provider) driver $($d.Version) ($($d.Inf)) from Windows. The device falls back to another driver, often Windows' basic one, until you install a new driver.$warn$rp" 'Remove driver' -Danger
    }
}

function Start-DeviceAction($d, [string]$Action) {
    $id = $d.InstanceId -replace "'", "''"
    $name = $d.Name -replace "'", "''"
    $body = if ($Action -eq 'reinstall') {
        "Say 'Removing $name so Windows sets it up again$Ellipsis'`r`n`$o = & pnputil.exe /remove-device '$id' 2>&1; `$c = `$LASTEXITCODE; `$o | ForEach-Object { Say ([string]`$_) }`r`nif (`$c -ne 0) { exit `$c }`r`nStart-Sleep -Seconds 2`r`nSay 'Scanning for hardware$Ellipsis'`r`n`$o = & pnputil.exe /scan-devices 2>&1; `$c = `$LASTEXITCODE; `$o | ForEach-Object { Say ([string]`$_) }`r`nexit `$c"
    }
    else {
        $inf = $d.Inf -replace "'", "''"
        "Say 'Removing driver $inf$Ellipsis'`r`n`$o = & pnputil.exe /delete-driver '$inf' /uninstall /force 2>&1; `$c = `$LASTEXITCODE; `$o | ForEach-Object { Say ([string]`$_) }`r`nif (`$c -ne 0 -and `$c -ne 3010) { exit `$c }`r`nSay 'Scanning for hardware$Ellipsis'`r`n`$o = & pnputil.exe /scan-devices 2>&1; `$o | ForEach-Object { Say ([string]`$_) }`r`nexit `$c"
    }
    # the driver is saved first, so Roll back can bring it back
    if ($d.IsOem) { $body = (Get-BackupFunctionText) + (Get-DeviceSaveCall $d) + $body }
    $d.State = 'running'; $d.Detail = if ($IsAdmin) { 'Working' + $Ellipsis } else { 'Waiting for approval' + $Ellipsis }
    Start-Elevated $(if ($Action -eq 'reinstall') { 'reinstall' } else { 'remove' }) "$(if ($Action -eq 'reinstall') { 'Reinstalling' } else { 'Removing' }) the driver for $($d.Name)" $body @() @{ Device = $d; Action = $Action } -RestorePoint
}

# Stops following a run that has gone quiet. The run itself carries on as administrator (this app can't end it);
# the tab becomes usable again, and says so.
$ElevStallMinutes = 5
$script:ElevStallLimit = $ElevStallMinutes
function Stop-ElevatedWait {
    $bg = $script:Elev
    if (-not $bg) { return }
    try { $bg.PS.Stop() } catch { }
    Add-LogLine "Stopped waiting for: $($script:ElevTitle) (no progress for $($script:ElevStallLimit) minutes or more)."
    Complete-Elevated @{ Name = $script:ElevName; Tag = $script:ElevTag; Code = -2; Declined = $false; Abandoned = $true }
}

function Complete-Elevated($Ev) {
    if ($script:Elev) { $script:Showers.Add($script:Elev) }
    $script:Elev = $null
    # the last thing the run said, for the message when it went wrong
    $last = if ($script:ElevError) { $script:ElevError } elseif ($script:ElevLast -and $script:ElevLast -notmatch '^(Waiting for administrator approval|Starting|\+|At )') { $script:ElevLast } else { '' }
    $script:ElevError = ''
    $script:ElevLast = ''
    $script:ElevStalled = $false
    $why = if ($Ev.Declined) { 'Administrator approval was declined' } elseif ($Ev.Error) { "Couldn't start as administrator: $($Ev.Error)" }
    elseif ($Ev.Abandoned) { "Stopped waiting after it made no progress for $($script:ElevStallLimit) minutes$(if ($last) { " (last message: $($last.TrimEnd('.')))" }). It may still be running in the background; another Dell update tool may have been busy. Restart Windows if it doesn't finish" } else { '' }
    $tag = $Ev.Tag
    $code = [int]$Ev.Code
    # runs started by other parts (Windows Update, Startup, Clean up, driver backups) finish in their own handler
    $h = $ElevHandlers[[string]$Ev.Name]
    if ($h) { & $h $Ev $why $code $last $tag; Update-View; return }
    switch ($Ev.Name) {
        'scan' {
            if ($why) { $script:DrvScan = 'error'; $script:DrvScanNote = $(if ($Ev.Abandoned) { "Dell's check: $why." } else { "$why, so Dell Command | Update did not run." }) }
            elseif ($code -eq 500) {
                $script:DrvScan = 'uptodate'
                $script:DrvScanNote = "Dell has no newer BIOS, firmware, drivers or apps for this $($script:DrvSys.Model) ({0:t})." -f (Get-Date)
                if (Test-DcuCached $tag.Stamp) { $script:DrvScanNote += " Dell Command | Update answered from its saved results rather than checking Dell again; if its own window finds something after its Check, click Check again here." }
            }
            elseif ($code -in 0, 1, 5) {
                $ok = $false; try { $ok = Read-DellReport $tag.Stamp } catch { Add-LogLine "Couldn't read the Dell report: $($_.Exception.Message)" }
                if (-not $ok) { $script:DrvScan = 'error'; $script:DrvScanNote = "The check finished, but its report wasn't found in $DrvWorkDir. Show the log for what Dell Command | Update said." }
                elseif (-not $script:DellFound) { $script:DrvScan = 'uptodate'; $script:DrvScanNote = "Dell has nothing newer for this $($script:DrvSys.Model) ({0:t})." -f (Get-Date) }
                else { $script:DrvScan = 'ready' }
            }
            else { $script:DrvScan = 'error'; $script:DrvScanNote = "$(Get-DcuText $code).$(if ($last) { " Last message: $($last.TrimEnd('.'))." }) The full log is in Show log and in $DrvWorkDir." }
        }
        'apply' {
            $state = if ($why -or $code -notin 0, 3010) { 'error' } elseif ($code -eq 3010) { 'reboot' } else { 'ok' }
            $text = if ($why) { $why } elseif ($code -eq 0) { 'Installed' } elseif ($code -eq 3010) { 'Installed. Restart to finish' } else { "Some didn't install$(if ($last) { ": $last" })" }
            # one History line per Windows Update driver, and one for Dell's run, from the RESULT lines in the log
            $wuCodes = @{ 2 = 'Installed'; 3 = 'Installed, with errors'; 4 = 'Failed'; 5 = 'Cancelled' }
            $lines = if ($tag.Log -and (Test-Path -LiteralPath $tag.Log)) { @(Get-Content -LiteralPath $tag.Log -Encoding UTF8 | Where-Object { $_ -like 'RESULT|*' }) } else { @() }
            foreach ($l in $lines) {
                $f = $l.Split('|', 5)
                $rc = [int]$f[3]
                if ($f[1] -eq 'nvidia') { Add-History 'drvupdate' $f[4] 'NVIDIA' '' $f[2] $(if ($rc -eq 0) { 'ok' } elseif ($rc -eq 3010) { 'reboot' } else { 'error' }) $(switch ($rc) { 0 { 'Installed' } 3010 { 'Installed. Restart to finish' } 98 { 'Not installed: the download was not signed by NVIDIA' } default { "Failed (code $rc)" } }) }
                elseif ($f[1] -eq 'wu') { Add-History 'drvupdate' $f[4] 'Windows Update' '' '' $(if ($rc -in 2, 3) { 'ok' } else { 'error' }) $(if ($wuCodes.ContainsKey($rc)) { $wuCodes[$rc] } else { "Result $rc" }) }
                else { Add-History 'drvupdate' "$($tag.DellCount) Dell update$(if ($tag.DellCount -ne 1) { 's' }) ($(@($tag.Types | Where-Object { $_ -ne 'utility' -and $_ -ne 'others' }) -join ', '))" 'Dell Command | Update' '' '' $(if ($rc -eq 0) { 'ok' } elseif ($rc -in 1, 5) { 'reboot' } else { 'error' }) (Get-DcuText $rc) }
            }
            if (-not $lines.Count) { Add-History 'drvupdate' "$($tag.Count) driver update$(if ($tag.Count -ne 1) { 's' })" '' '' '' $state $text }
            $script:LastSummary = "Driver updates: $text"
            if (-not $why) {
                $script:DrvScan = 'none'
                foreach ($u in @($DrvUpdates | Where-Object { $_.IsDell })) { [void]$DrvUpdates.Remove($u) }
                $script:WuState = 'none'
                Start-WuCheck
                Start-NvLookup
                Start-AmdLookup
                Start-DeviceScan
            }
        }
        'driverinstall' {
            $text = if ($why) { $why } else { Get-DcuText $code }
            if (-not $why -and $code -notin 0, 1, 5 -and $last) { $text += " ($last)" }
            $state = if ($why -or $code -notin 0, 1, 5) { 'error' } elseif ($code -in 1, 5) { 'reboot' } else { 'ok' }
            Add-History 'drvinstall' "$($script:DrvSys.Model)" 'Dell Command | Update' '' '' $state $text
            $script:LastSummary = "Driver reinstall: $text"
            if (-not $why) { Start-DeviceScan }
        }
        { $_ -in 'reinstall', 'remove' } {
            $d = $tag.Device
            if ($why) { $d.State = 'error'; $d.Detail = $why }
            elseif ($code -eq 0) { $d.State = 'ok'; $d.Detail = if ($Ev.Name -eq 'reinstall') { 'Reinstalled' } else { 'Driver removed' } }
            elseif ($code -eq 3010) { $d.State = 'reboot'; $d.Detail = 'Done. Restart to finish' }
            else { $d.State = 'error'; $d.Detail = "pnputil failed (exit code $code)$(if ($last) { ": $last" }); see the log" }
            Add-History $(if ($Ev.Name -eq 'reinstall') { 'drvreinstall' } else { 'drvremove' }) $d.Name $d.Inf $d.Version '' $d.State $d.Detail
            $script:LastSummary = "$($d.Name): $($d.Detail)"
            # the list is read again once the change settles; a finished row keeps its result until then
            if (-not $why) { $script:DeviceRefreshAt = (Get-Date).AddSeconds(4) }
        }
    }
    Update-View
}

# The Drivers tab as a panel section (see $Panels)
$Panels.drivers = @{
    Panel   = 'DriversPanel'
    Update  = { Update-DriversView }
    Status  = {
        if ($script:DeviceScanner) { "Reading devices$Ellipsis" }
        elseif ($script:DrvDevicesRead) {
            "$($DrvDevices.Count) devices"
            $pc = @($DrvDevices | Where-Object { $_.HasProblem }).Count
            if ($pc) { "$pc with a problem" }
            if ($DrvUpdates.Count) { "$($DrvUpdates.Count) driver update$(if ($DrvUpdates.Count -ne 1) { 's' })" }
        }
    }
    Open    = {
        if (-not $script:DrvDevicesRead -and -not $script:DeviceScanner) { Start-DeviceScan }
        elseif ($script:DrvDevicesRead) { Request-VendorInstall; if ($script:WuState -eq 'none') { Start-WuCheck; Start-NvLookup; Start-AmdLookup } }
    }
    Refresh = { if ($UI.DrvRefresh.IsEnabled) { if ($UI.DrvViewUpdates.IsChecked) { Start-DriverCheck } else { Start-DeviceScan } } }
}

# "Restore point first" is a saved setting, shared with the Windows Update tab's chip
function Set-RestorePointSetting([bool]$On) {
    $Settings.DriverRestorePoint = $On
    Save-Settings
    foreach ($c in @('DrvRestore', 'WinRestore')) { if ($UI[$c]) { $UI[$c].IsChecked = $On } }
}

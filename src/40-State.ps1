# Windows Manager - State (part of src\; see Windows_Manager.ps1)

try {
    $icon = Get-AppIcon
    if ($icon) { $Window.Icon = $icon }
    $bytes = Get-AssetBytes $EmbeddedLogo 'logo.jpg'
    if ($bytes) {
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit(); $img.CacheOption = 'OnLoad'; $img.StreamSource = New-Object IO.MemoryStream(, $bytes); $img.EndInit(); $img.Freeze()
        $brush = New-Object System.Windows.Media.ImageBrush($img)
        $brush.Stretch = 'UniformToFill'
        $brush.Viewbox = New-Object System.Windows.Rect(0.185, 0.14, 0.63, 0.70)   # crop the black margin down to the symbol
        $UI.HeaderLogo.Background = $brush
        $UI.AboutLogo.Background = $brush
    }
}
catch { }
function New-PackageList { return , (New-Object 'System.Collections.ObjectModel.ObservableCollection[WingetUM.Package]') }
$Packages = New-PackageList          # Updates
$DiscoverItems = New-PackageList     # Discover: the starter list or search results
$InstalledItems = New-PackageList    # Installed
$ByKey = @{}                         # every row of every list by Section|Id|Source; worker events carry this key

function Test-SearchMatch($Item, [string]$Query) {
    if (-not $Query) { return $true }
    return ($Item.Name.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($Item.Id.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$View = [System.Windows.Data.CollectionViewSource]::GetDefaultView($Packages)
$View.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
$View.Filter = [Predicate[object]] {
    param($item)
    if ($item.IsConcealed -and -not $script:ShowHidden) { return $false }
    $q = $UI.Search.Text.Trim()
    return (-not $q) -or ($item.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($item.Id.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
# Discover: typing filters what is shown; the text of the last winget search shows all its results (tag matches too)
$DiscoverView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($DiscoverItems)
$DiscoverView.Filter = [Predicate[object]] {
    param($item)
    $q = $UI.Search.Text.Trim()
    if (-not $q -or $q -eq $script:DiscoverQuery) { return $true }
    return ($item.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($item.Id.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$InstalledView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($InstalledItems)
$InstalledView.SortDescriptions.Add((New-Object System.ComponentModel.SortDescription('Name', 'Ascending')))
$InstalledView.Filter = [Predicate[object]] {
    param($item)
    if ($UI.ChkWingetOnly.IsChecked -and -not $item.Source) { return $false }
    $q = $UI.Search.Text.Trim()
    return (-not $q) -or ($item.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($item.Id.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0)
}
$UI.List.ItemsSource = $View

# Discover's starter list (category|package ID|name); every ID was checked against the winget source
$StarterApps = @(
    'Browsers|Google.Chrome|Google Chrome', 'Browsers|Mozilla.Firefox|Mozilla Firefox', 'Browsers|Brave.Brave|Brave', 'Browsers|Vivaldi.Vivaldi|Vivaldi', 'Browsers|Opera.Opera|Opera'
    'Communication|Zoom.Zoom|Zoom Workplace', 'Communication|Microsoft.Teams|Microsoft Teams', 'Communication|SlackTechnologies.Slack|Slack', 'Communication|Discord.Discord|Discord'
    'Developer|Microsoft.VisualStudioCode|Visual Studio Code', 'Developer|Git.Git|Git', 'Developer|GitHub.GitHubDesktop|GitHub Desktop', 'Developer|Microsoft.WindowsTerminal|Windows Terminal'
    'Developer|Microsoft.PowerShell|PowerShell 7', 'Developer|Python.Python.3.13|Python 3.13', 'Developer|OpenJS.NodeJS.LTS|Node.js (LTS)', 'Developer|Docker.DockerDesktop|Docker Desktop'
    'Developer|Postman.Postman|Postman', 'Developer|Microsoft.AzureCLI|Azure CLI', 'Developer|Hashicorp.Terraform|Terraform', 'Developer|WinSCP.WinSCP|WinSCP', 'Developer|PuTTY.PuTTY|PuTTY'
    'Media|VideoLAN.VLC|VLC media player', 'Media|Spotify.Spotify|Spotify', 'Media|OBSProject.OBSStudio|OBS Studio', 'Media|Audacity.Audacity|Audacity', 'Media|GIMP.GIMP.3|GIMP'
    'Media|HandBrake.HandBrake|HandBrake', 'Media|IrfanSkiljan.IrfanView|IrfanView'
    'Productivity|Adobe.Acrobat.Reader.64-bit|Adobe Acrobat Reader', 'Productivity|TheDocumentFoundation.LibreOffice|LibreOffice', 'Productivity|Obsidian.Obsidian|Obsidian', 'Productivity|Notion.Notion|Notion'
    'Productivity|Notepad++.Notepad++|Notepad++', 'Productivity|Bitwarden.Bitwarden|Bitwarden', 'Productivity|KeePassXCTeam.KeePassXC|KeePassXC'
    'Cloud and network|Microsoft.OneDrive|Microsoft OneDrive', 'Cloud and network|Dropbox.Dropbox|Dropbox', 'Cloud and network|Google.GoogleDrive|Google Drive', 'Cloud and network|Tailscale.Tailscale|Tailscale', 'Cloud and network|WireGuard.WireGuard|WireGuard'
    'Utilities|7zip.7zip|7-Zip', 'Utilities|Microsoft.PowerToys|PowerToys', 'Utilities|voidtools.Everything|Everything', 'Utilities|WinDirStat.WinDirStat|WinDirStat', 'Utilities|ShareX.ShareX|ShareX'
    'Utilities|Greenshot.Greenshot|Greenshot', 'Utilities|WinMerge.WinMerge|WinMerge', 'Utilities|CPUID.CPU-Z|CPU-Z', 'Utilities|REALiX.HWiNFO|HWiNFO'
    'Utilities|Microsoft.Sysinternals.ProcessExplorer|Process Explorer', 'Utilities|Microsoft.Sysinternals.Autoruns|Autoruns'
)

$script:Section = 'health'            # the tab the app opens on: updates | discover | installed | a panel section (see $Panels)
$script:SectionSearch = @{ updates = ''; discover = ''; installed = ''; drivers = '' }

# Sections with their own panel in place of the app list and its toolbar (Drivers, Startup, Windows Update, Health).
# Each part that adds one registers it here: Panel (its x:Name), Update (refreshes it; called by Update-View while it
# is shown), Status (returns the status line's parts), Open (when the tab is opened), Refresh (F5).
$Panels = [ordered]@{}
# Worker events (by their T) and elevated runs (by their name) that later parts handle
$EventHandlers = @{}
$ElevHandlers = @{}
# Yes in the confirmation panel, by its kind (for kinds that later parts add)
$ConfirmHandlers = @{}
# Background runspaces with something to do when they finish: @{ Bg; Done = { param($Bg) ... } }
$script:Tracked = New-Object System.Collections.Generic.List[object]
function Start-Tracked([string]$Op, $Arg, [scriptblock]$Done) {
    $bg = Start-Background $Op $Arg
    $script:Tracked.Add(@{ Bg = $bg; Done = $Done })
    return $bg
}
$script:Mode = 'loading'              # Updates: loading | ready | error | idle (not checked yet)
$script:DiscoverMode = 'ready'
$script:DiscoverQuery = $null         # $null: the starter list is shown
$script:InstalledMode = 'idle'
$script:InstalledChecked = $null
$script:InstalledStale = $false       # an install or uninstall happened since the list was read
$script:InstalledKnown = $false
$script:InstalledIds = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$script:ErrorInfo = @{ updates = @{}; discover = @{}; installed = @{} }
$script:Scanner = $null               # background runspaces: update check, search, installed list, details
$script:Searcher = $null
$script:Lister = $null
$script:Showers = New-Object System.Collections.Generic.List[object]
$script:Worker = $null                # the job queue (updates, installs, uninstalls)
$script:LastChecked = $null
$script:ShowHidden = $false
$script:CurrentName = $null
$script:CurrentVerb = 'Updating'
$script:LastSummary = $null
$script:DetailsItem = $null
$script:Confirm = $null
$script:InstalledRefresh = $false      # re-read the installed list once the current installs/uninstalls finish
$script:Pins = @{}                    # winget pins: package ID -> pin type (from the update check and installed list)
$script:DiscoverImport = $null        # Discover: the name of the opened app list, when one is shown
$script:Sources = @()                 # winget source export: Name, Arg, Type, Identifier, Explicit
$script:SourceError = $null
$script:SourceReading = $false
$script:NotesCache = @{}              # release notes by Id|version
$script:NotesItem = $null
$script:VersionItem = $null
$script:Pick = $null
$script:HistView = $null
$script:HistCount = 0
function New-Batch { return @{ Total = 0; Done = 0; Failed = 0; Reboot = 0; Updated = 0; Installed = 0; Uninstalled = 0 } }
$script:Batch = New-Batch
$TerminalStates = 'ok', 'reboot', 'skipped', 'error', 'cancelled'
$Verbs = @{ update = 'Updating'; install = 'Installing'; uninstall = 'Uninstalling' }

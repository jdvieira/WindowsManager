#Requires -Version 5.1
<#
.SYNOPSIS
Writes the winget manifest for a published release (for a pull request to microsoft/winget-pkgs).

.DESCRIPTION
Writes the three manifest files (version, installer, defaultLocale) for jdvieira.WindowsManager as a portable app:
winget downloads the release's exe into its own packages folder and adds a "windows-manager" command. The checksum
is read from the release on GitHub (the file GitHub serves), or from -ExePath when given.

Then check them with: winget validate --manifest <folder>
and try them with:    winget install --manifest <folder>   (needs: winget settings --enable LocalManifestFiles)

.PARAMETER Version
The release version (e.g. 2.3.0.0). Defaults to $AppVersion in src\00-Startup.ps1.

.PARAMETER ExePath
Hash this file instead of the release asset (it must be the same file as the one on the release).

.PARAMETER OutputDir
Defaults to dist\winget. The files go in manifests\j\jdvieira\WindowsManager\<version> under it, the same layout as
the winget-pkgs repository.

.EXAMPLE
.\tools\New-WingetManifest.ps1 -Version 2.3.0.0

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
[CmdletBinding()]
param([string]$Version, [string]$ExePath, [string]$OutputDir)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Version) {
    $m = Select-String -LiteralPath (Join-Path $root 'src\00-Startup.ps1') -Pattern "^\`$AppVersion = '([\d.]+)'" | Select-Object -First 1
    $Version = $m.Matches[0].Groups[1].Value
}
$Version = $Version.TrimStart('v')
if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist\winget' }
$repo = 'jdvieira/WindowsManager'
$id = 'jdvieira.WindowsManager'
$url = "https://github.com/$repo/releases/download/v$Version/Windows.Manager.exe"
$released = Get-Date

if ($ExePath) {
    $sha = [IO.File]::OpenRead((Resolve-Path -LiteralPath $ExePath))
    try { $hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($sha) | ForEach-Object { $_.ToString('X2') }) } finally { $sha.Close() }
}
else {
    $rel = Invoke-RestMethod "https://api.github.com/repos/$repo/releases/tags/v$Version" -Headers @{ 'User-Agent' = 'WindowsManager-manifest' }
    $asset = @($rel.assets | Where-Object { $_.name -eq 'Windows.Manager.exe' }) | Select-Object -First 1
    if (-not $asset) { throw "Release v$Version has no Windows.Manager.exe" }
    if ($asset.digest -notmatch '^sha256:([0-9a-f]{64})$') { throw "GitHub gave no sha256 for the asset; pass -ExePath" }
    $hash = $Matches[1].ToUpperInvariant()
    $url = $asset.browser_download_url
    if ($rel.published_at) { $released = [datetime]$rel.published_at }
}

$notes = try { & (Join-Path $PSScriptRoot 'Get-ReleaseNotes.ps1') $Version } catch { '' }
# winget allows up to 10000 characters
if ($notes.Length -gt 9000) { $notes = $notes.Substring(0, $notes.LastIndexOf("`n", 9000)) + "`n`n(More in the release notes on GitHub.)" }
$dir = Join-Path $OutputDir "manifests\j\jdvieira\WindowsManager\$Version"
New-Item -ItemType Directory -Path $dir -Force | Out-Null
$schema = '1.6.0'
$enc = New-Object Text.UTF8Encoding($false)
function Write-Manifest([string]$Name, [string]$Type, [string]$Body) {
    $text = "# yaml-language-server: `$schema=https://aka.ms/winget-manifest.$Type.$schema.schema.json`n`n$Body`nManifestType: $Type`nManifestVersion: $schema`n"
    [IO.File]::WriteAllText((Join-Path $dir $Name), $text, $enc)
}
Write-Manifest "$id.yaml" 'version' @"
PackageIdentifier: $id
PackageVersion: $Version
DefaultLocale: en-US
"@
Write-Manifest "$id.installer.yaml" 'installer' @"
PackageIdentifier: $id
PackageVersion: $Version
InstallerType: portable
Commands:
- windows-manager
ReleaseDate: $($released.ToString('yyyy-MM-dd'))
Installers:
- Architecture: x64
  InstallerUrl: $url
  InstallerSha256: $hash
"@
# block scalar: each line of the notes indented two spaces
$noteBlock = if ($notes) { "ReleaseNotes: |-`n" + (($notes -split "`r?`n" | ForEach-Object { "  $_".TrimEnd() }) -join "`n") + "`n" } else { '' }
Write-Manifest "$id.locale.en-US.yaml" 'defaultLocale' @"
PackageIdentifier: $id
PackageVersion: $Version
PackageLocale: en-US
Publisher: Justin Vieira
PublisherUrl: https://github.com/jdvieira
PublisherSupportUrl: https://github.com/$repo/issues
Author: Justin Vieira
PackageName: Windows Manager
PackageUrl: https://github.com/$repo
License: GPL-3.0
LicenseUrl: https://github.com/$repo/blob/main/LICENSE
ShortDescription: Keeps a Windows PC's software, drivers and Windows updates current, and shows its health.
Description: |-
  A desktop app for winget updates and installs, installed software, startup apps, Dell and Windows Update drivers,
  Windows Update, built-in apps and optional features, cleanup and device health, with scheduled automatic updates.
Moniker: windows-manager
Tags:
- winget
- updates
- drivers
- windows-update
- startup
- cleanup
ReleaseNotesUrl: https://github.com/$repo/releases/tag/v$Version
$noteBlock
"@
Write-Host "Wrote $dir"
Get-ChildItem -LiteralPath $dir | ForEach-Object { "  $($_.Name)" }

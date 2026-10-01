#Requires -Version 5.1
<#
.SYNOPSIS
Compiles Windows Manager into a single exe.

.DESCRIPTION
1. Joins src\*.ps1 (in name order) into one script and embeds assets\icon.ico and assets\logo.jpg (base64) in it, so
   the exe needs no other files.
2. Compiles the app with PS2EXE as a windowless, STA WPF app, with assets\icon.ico as the exe icon.
3. Optionally signs the exe with a code-signing certificate (strongly recommended: unsigned PS2EXE executables are
   often flagged by antivirus / EDR products).

Requires the ps2exe module (Install-Module ps2exe -Scope CurrentUser) and Windows PowerShell 5.1.

.PARAMETER OutputDir
Where the exe is written. Defaults to .\dist next to this script.

.PARAMETER Version
File and product version stamped on the exe. Defaults to $AppVersion in src\00-Startup.ps1.

.PARAMETER RequireAdmin
Builds the exe with a manifest that always asks for administrator rights at launch.

.PARAMETER CertificateThumbprint
Thumbprint of a code-signing certificate in Cert:\CurrentUser\My (or LocalMachine\My) to sign the exe with.

.EXAMPLE
.\Build-Exe.ps1
.\Build-Exe.ps1 -RequireAdmin -CertificateThumbprint 0123456789ABCDEF0123456789ABCDEF01234567

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
[CmdletBinding()]
param(
    [string]$OutputDir,
    [string]$Version,    # default: $AppVersion in the app
    [switch]$RequireAdmin,
    [string]$CertificateThumbprint,
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$ProjectDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $OutputDir) { $OutputDir = Join-Path $ProjectDir 'dist' }

# PS2EXE and WPF icon rendering need Windows PowerShell 5.1 on an STA thread
if ($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath)
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
        if ($p.Value -is [switch]) { if ($p.Value) { $forward += "-$($p.Key)" } }
        else { $forward += "-$($p.Key)"; $forward += "$($p.Value)" }
    }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @forward
    exit $LASTEXITCODE
}

if (-not (Get-Module -ListAvailable ps2exe)) { throw 'The ps2exe module is not installed. Run: Install-Module ps2exe -Scope CurrentUser' }
Import-Module ps2exe
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$buildDir = Join-Path $OutputDir 'build'
$exePath = Join-Path $OutputDir 'Windows Manager.exe'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

# The app is src\*.ps1 joined in name order, the same way Windows_Manager.ps1 joins them to run from source
$parts = @(Get-ChildItem -LiteralPath (Join-Path $ProjectDir 'src') -Filter '*.ps1')
# ordinal: the numbers in the names set the order, whatever the culture's sorting rules
[Array]::Sort($parts, [Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
if (-not $parts.Count) { throw 'No source files found in src\.' }
$app = ($parts | ForEach-Object {
        $body = [IO.File]::ReadAllText($_.FullName)
        if ($_.Name -like '00-*') { $body } else { "# ==== src\$($_.Name) ====`r`n$body" }
    }) -join "`r`n"
if ($app -match '[^\x00-\x7F]') { throw 'The source has non-ASCII characters (Windows PowerShell 5.1 reads BOM-less files as ANSI); use [char] codes.' }
if (-not $Version) {
    $Version = [regex]::Match($app, '(?m)^\$AppVersion = ''([\d.]+)''').Groups[1].Value   # single quotes: $AppVersion is literal here
    if (-not $Version) { throw 'Could not read $AppVersion from the app; pass -Version.' }
}

Write-Host 'Embedding the icon and logo...' -ForegroundColor Cyan
$assetsDir = Join-Path $ProjectDir 'assets'
$iconPath = Join-Path $assetsDir 'icon.ico'
$logoPath = Join-Path $assetsDir 'logo.jpg'
foreach ($f in $iconPath, $logoPath) { if (-not (Test-Path -LiteralPath $f)) { throw "Missing $f" } }
$combined = $app
foreach ($asset in @(@('$EmbeddedIcon', $iconPath), @('$EmbeddedLogo', $logoPath))) {
    $placeholder = "$($asset[0]) = ''"
    $count = ([regex]::Matches($combined, [regex]::Escape($placeholder))).Count
    if ($count -ne 1) { throw "Expected exactly one '$placeholder' line in the app, found $count." }
    $combined = $combined.Replace($placeholder, "$($asset[0]) = '$([Convert]::ToBase64String([IO.File]::ReadAllBytes($asset[1])))'")
}
$combinedPath = Join-Path $buildDir 'Windows_Manager.combined.ps1'
[IO.File]::WriteAllText($combinedPath, $combined, (New-Object Text.UTF8Encoding($true)))

Write-Host "Compiling $exePath ..." -ForegroundColor Cyan
if (Test-Path -LiteralPath $exePath) { Remove-Item -LiteralPath $exePath -Force }
$ps2exe = @{
    inputFile    = $combinedPath
    outputFile   = $exePath
    noConsole    = $true      # WPF app, no console window
    STA          = $true
    noOutput     = $true      # never turn stray output into message boxes
    noError      = $true
    DPIAware     = $true
    requireAdmin = [bool]$RequireAdmin
    iconFile     = $iconPath
    title        = 'Windows Manager'
    description  = 'Install, update and remove apps, and keep drivers current'
    product      = 'Windows Manager'
    copyright    = "Copyright (c) $((Get-Date).Year) Justin Vieira"
    version      = $Version
}
Invoke-ps2exe @ps2exe
if (-not (Test-Path -LiteralPath $exePath)) { throw 'PS2EXE did not produce the exe.' }

if ($CertificateThumbprint) {
    Write-Host 'Signing...' -ForegroundColor Cyan
    $cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert | Where-Object { $_.Thumbprint -eq $CertificateThumbprint } | Select-Object -First 1
    if (-not $cert) { throw "Code-signing certificate $CertificateThumbprint not found in CurrentUser\My or LocalMachine\My." }
    $sig = Set-AuthenticodeSignature -FilePath $exePath -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256
    if ($sig.Status -ne 'Valid') { throw "Signing failed: $($sig.StatusMessage)" }
}

$item = Get-Item -LiteralPath $exePath
$hash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash
Write-Host ''
Write-Host "Built:   $($item.FullName)" -ForegroundColor Green
Write-Host ("Size:    {0:N0} KB   Version: {1}   Admin: {2}   Signed: {3}" -f ($item.Length / 1KB), $Version, [bool]$RequireAdmin, [bool]$CertificateThumbprint)
Write-Host "SHA256:  $hash"

#Requires -Version 5.1
<#
.SYNOPSIS
Prints one version's section of CHANGELOG.md (the release notes on GitHub).

.EXAMPLE
.\tools\Get-ReleaseNotes.ps1 2.3.0.0 | Set-Content notes.md

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
param([Parameter(Mandatory)][string]$Version)

$file = Join-Path (Split-Path -Parent $PSScriptRoot) 'CHANGELOG.md'
$v = $Version.TrimStart('v')
$out = New-Object System.Collections.Generic.List[string]
$in = $false
foreach ($line in [IO.File]::ReadAllLines($file)) {
    if ($line -match '^## (\S+)') {
        if ($in) { break }
        $in = $Matches[1] -eq $v
        continue
    }
    if ($in) { $out.Add($line) }
}
if (-not $in -and -not $out.Count) { throw "CHANGELOG.md has no section for $v" }
($out -join "`n").Trim()

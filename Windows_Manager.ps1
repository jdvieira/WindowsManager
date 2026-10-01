#Requires -Version 5.1
<#
.SYNOPSIS
Runs Windows Manager from its source files.

.DESCRIPTION
The app's code lives in src\*.ps1. This script joins those parts, in name order, into one script
(dist\build\Windows_Manager.dev.ps1) and runs it with the same arguments, so a run from source behaves
exactly like the exe, which Build-Exe.ps1 compiles from the same joined parts. Error messages and line numbers refer
to the joined file; each part in it starts with a "# ==== src\<part>.ps1" line.

Arguments (-Auto, -DryRun, -SelfTest, -Screenshot, ...) are described in src\00-Startup.ps1.

.EXAMPLE
.\Windows_Manager.ps1
.\Windows_Manager.ps1 -SelfTest -Screenshot C:\Temp\wsm.png

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>

$WsmEntry = $PSCommandPath   # read by the joined script: relaunches and the scheduled task come back here
$srcDir = Join-Path $PSScriptRoot 'src'
$parts = @(Get-ChildItem -LiteralPath $srcDir -Filter '*.ps1')
# ordinal: the numbers in the names set the order, whatever the culture's sorting rules
[Array]::Sort($parts, [Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
if (-not $parts.Count) { throw "No source files found in $srcDir." }
$text = ($parts | ForEach-Object {
        $body = [IO.File]::ReadAllText($_.FullName)
        if ($_.Name -like '00-*') { $body } else { "# ==== src\$($_.Name) ====`r`n$body" }
    }) -join "`r`n"

$buildDir = Join-Path $PSScriptRoot 'dist\build'
$joined = Join-Path $buildDir 'Windows_Manager.dev.ps1'
try {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
    $same = (Test-Path -LiteralPath $joined) -and ([IO.File]::ReadAllText($joined) -ceq $text)
    if (-not $same) { [IO.File]::WriteAllText($joined, $text, (New-Object Text.UTF8Encoding($true))) }
}
catch { if (-not (Test-Path -LiteralPath $joined)) { throw } }   # another copy may be writing the same text

& $joined @args
exit $LASTEXITCODE

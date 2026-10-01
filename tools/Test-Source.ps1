#Requires -Version 5.1
<#
.SYNOPSIS
Checks the source the way the build and the app read it.

.DESCRIPTION
1. Joins src\*.ps1 in ordinal name order (as Build-Exe.ps1 and Windows_Manager.ps1 do).
2. Fails on non-ASCII characters (Windows PowerShell 5.1 reads BOM-less files as ANSI).
3. Fails on parse errors in the joined script.
4. Fails if a temporary test driver (src\94-zTest.ps1) is still there.
5. With -SelfTest, runs the app's own self-test (Windows_Manager.ps1 -SelfTest) and fails if it errors or its summary
   is missing.

Used by .github\workflows\ci.yml; run it locally before a pull request.

.EXAMPLE
.\tools\Test-Source.ps1 -SelfTest

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$failed = 0
function Fail([string]$Text) { Write-Host "FAIL  $Text" -ForegroundColor Red; $script:failed++ }
function Pass([string]$Text) { Write-Host "ok    $Text" }

$parts = @(Get-ChildItem -LiteralPath (Join-Path $root 'src') -Filter '*.ps1')
[Array]::Sort($parts, [Comparison[object]] { param($a, $b) [string]::CompareOrdinal($a.Name, $b.Name) })
if (-not $parts.Count) { throw 'No source files found in src\.' }
Pass "$($parts.Count) source files"

if (Test-Path -LiteralPath (Join-Path $root 'src\94-zTest.ps1')) { Fail 'src\94-zTest.ps1 is a temporary test driver; delete it' }

$before = $failed
foreach ($p in $parts) {
    $text = [IO.File]::ReadAllText($p.FullName)
    $bad = [regex]::Matches($text, '[^\x00-\x7F]')
    if ($bad.Count) {
        $line = ($text.Substring(0, $bad[0].Index) -split "`n").Count
        Fail "$($p.Name): $($bad.Count) non-ASCII character(s), the first on line $line"
    }
}
if ($failed -eq $before) { Pass 'ASCII only' }

$joined = ($parts | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`r`n"
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($joined, [ref]$null, [ref]$errors)
if ($errors.Count) { foreach ($e in $errors | Select-Object -First 10) { Fail "parse: line $($e.Extent.StartLineNumber): $($e.Message)" } }
else { Pass 'parses' }

if ($SelfTest) {
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'Windows_Manager.ps1') -SelfTest 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host $out
    if ($code) { Fail "self-test exited with $code" }
    elseif ($out -notmatch '(?m)^Installed:\s+mode=') { Fail 'self-test summary missing' }
    elseif ($out -match '(?m)^\s*(At line|Exception|.*: The term .* is not recognized)') { Fail 'self-test printed an error' }
    else { Pass 'self-test' }
}

if ($failed) { Write-Host "$failed check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All checks passed' -ForegroundColor Green

#Requires -Version 5.1
<#
.SYNOPSIS
Checks a branch's version bump before it is merged, so the Release run after the merge doesn't fail or skip.

.DESCRIPTION
Compares $AppVersion in src\00-Startup.ps1 with the base branch (origin/main by default):
1. When the app changed (src\, assets\ or Build-Exe.ps1) and $AppVersion didn't, warns: merging it publishes
   nothing.
2. When $AppVersion changed, fails unless:
   - it is a version (major.minor.patch.build) higher than the base branch's,
   - CHANGELOG.md's first section is "## <version> - <yyyy-mm-dd>" and has text (the release notes),
   - with the GitHub CLI signed in (or GH_TOKEN set, as in CI): it is higher than every release, and its tag
     v<version> isn't taken yet.

Used by .github\workflows\ci.yml on pull requests; run it locally before opening one.

.PARAMETER Base
The git ref to compare with. Defaults to origin/main (run git fetch first).

.EXAMPLE
.\tools\Test-Version.ps1
.\tools\Test-Version.ps1 -Base origin/main

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
[CmdletBinding()]
param([string]$Base = 'origin/main')

# native commands (git, gh) report failures on stderr: go by their exit codes instead
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$failed = 0
function Fail([string]$Text) { Write-Host "FAIL  $Text" -ForegroundColor Red; $script:failed++ }
function Pass([string]$Text) { Write-Host "ok    $Text" }
function Warn([string]$Text) { Write-Host "warn  $Text" -ForegroundColor Yellow; if ($env:GITHUB_ACTIONS) { Write-Host "::warning::$Text" } }
function Get-AppVersion([string]$Text) { [regex]::Match($Text, '(?m)^\$AppVersion = ''([^'']*)''').Groups[1].Value }

Push-Location $root
try {
    $mergeBase = git merge-base HEAD $Base 2>$null
    if ($LASTEXITCODE -or -not $mergeBase) { Write-Host "FAIL  Can't find where this branch left $Base (git fetch, or fetch-depth: 0 in CI)" -ForegroundColor Red; exit 1 }
    $new = Get-AppVersion ([IO.File]::ReadAllText((Join-Path $root 'src\00-Startup.ps1')))
    $old = Get-AppVersion ((git show "${mergeBase}:src/00-Startup.ps1" 2>$null) -join "`n")
    if (-not $new) { Fail 'No $AppVersion line in src\00-Startup.ps1'; exit 1 }
    $changed = @(git diff --name-only $mergeBase HEAD 2>$null)
    $appChanged = @($changed | Where-Object { $_ -like 'src/*' -or $_ -like 'assets/*' -or $_ -eq 'Build-Exe.ps1' })

    if ($new -eq $old) {
        if ($appChanged.Count) { Warn "The app changed ($($appChanged.Count) file(s)) but `$AppVersion is still $new, so merging releases nothing. Bump it if users should get this." }
        else { Pass "`$AppVersion stays $new (the app didn't change)" }
    }
    else {
        $v = $null; $vOld = $null
        if ($new -notmatch '^\d+\.\d+\.\d+\.\d+$' -or -not [version]::TryParse($new, [ref]$v)) { Fail "`$AppVersion $new isn't major.minor.patch.build" }
        elseif ($old -and [version]::TryParse($old, [ref]$vOld) -and $v -le $vOld) { Fail "`$AppVersion $new isn't higher than $old on $Base" }
        else { Pass "`$AppVersion $old -> $new" }

        # the first section is the one the release takes its notes from
        $first = $null; $notes = 0
        foreach ($line in [IO.File]::ReadAllLines((Join-Path $root 'CHANGELOG.md'))) {
            if ($line -match '^## ') { if ($first) { break }; $first = $line; continue }
            if ($first -and $line.Trim()) { $notes++ }
        }
        if ($first -notmatch '^## (\S+) - (\d{4}-\d{2}-\d{2})$') { Fail "CHANGELOG.md's first section should be '## $new - <yyyy-mm-dd>', not '$first'" }
        elseif ($Matches[1] -ne $new) { Fail "CHANGELOG.md's first section is $($Matches[1]), not $new" }
        elseif (-not $notes) { Fail "CHANGELOG.md's $new section is empty (it becomes the release notes)" }
        else { Pass "CHANGELOG.md starts with $new" }

        if ($v -and (Get-Command gh -ErrorAction SilentlyContinue)) {
            $tags = @(gh release list --limit 100 --json tagName -q '.[].tagName' 2>$null)
            if ($LASTEXITCODE) { Warn "Couldn't list the releases on GitHub (gh auth login?), so they weren't compared" }
            else {
                $newest = @($tags | Where-Object { $_ -notlike '*-*' } | ForEach-Object { $t = $null; if ([version]::TryParse(($_ -replace '^v', ''), [ref]$t)) { $t } } | Sort-Object -Descending)[0]
                if ($tags -contains "v$new") { Fail "v$new is already released; bump to the next version" }
                elseif ($newest -and $v -le $newest) { Fail "$new isn't higher than the newest release ($newest)" }
                else { Pass "$new is newer than every release$(if ($newest) { " ($newest)" })" }
            }
        }
        else { Warn 'The GitHub CLI is not installed, so the releases were not compared' }
    }
}
finally { Pop-Location }

if ($failed) { Write-Host "$failed check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'Version checks passed' -ForegroundColor Green

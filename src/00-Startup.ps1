#Requires -Version 5.1
<#
.SYNOPSIS
Windows Manager - a WPF front end for winget and Windows drivers: update, discover and install, and uninstall
apps, and keep the PC's drivers current.

.DESCRIPTION
  - Lists every app that winget can upgrade (winget upgrade), with installed and available versions and the source.
  - Updates one app, the selected apps, or all apps at once. Updates run one at a time from a queue, so more apps can
    be queued while an update is running, and the queue can be stopped after the current app.
  - Shows per-app status and download progress, a live winget log, and a daily log file under
    %LOCALAPPDATA%\WindowsManager\Logs.
  - Runs as the interactive user. Installers that need administrator rights ask for approval (UAC) one by one;
    "Restart as administrator" runs the whole session elevated instead.
  - "Automatic updates" creates a scheduled task that runs this app with -Auto: it updates everything silently and
    only shows a notification when something fails (optionally also for restarts or after every run), or, in
    notify-only mode, installs nothing and lists the waiting updates.
  - Keeps apps at their current version (winget pin), installs a chosen version, shows release notes, keeps a history
    of every change, exports and imports app lists (winget's own format) and manages winget's sources.

.PARAMETER Auto
Unattended run (what the scheduled task starts): no window, silent updates of every app that is not pinned or
hidden, a result in lastrun.json, and a notification only when needed. Exit code 1 when anything failed.

.PARAMETER DryRun
With -Auto: checks for updates and shows the notification with what would be updated, without installing anything.

.PARAMETER TaskOp
Internal: performs a scheduled-task change (base64 JSON) in an elevated copy of the app.

.PARAMETER SelfTest
Builds the UI and runs one real update check without showing the window (validation only). Prints the parsed list.

.PARAMETER Screenshot
With -SelfTest: also renders the window, with sample row states, to this PNG file. With -Auto -DryRun: renders the
notification to this PNG file instead of showing it.

.PARAMETER Open
Internal: a windowsmanager: link from a notification's button (open = the window, log = today's log).

.NOTES
Version:            2.3.0.0 (see CHANGELOG.md)
Created By:         Justin Vieira (jdvieira@icloud.com)
Source:             src\*.ps1, joined in name order by Windows_Manager.ps1 (to run it) and Build-Exe.ps1 (to
                    compile the exe). This file, 00-Startup.ps1, is the start of the joined script.
#>
[CmdletBinding()]
param(
    [switch]$Auto,
    [switch]$DryRun,
    [string]$TaskOp,
    [switch]$SelfTest,
    [string]$Screenshot,
    [string]$Open
)

$ErrorActionPreference = 'Stop'
$AppVersion = '2.4.0.0'   # also the exe version (Build-Exe.ps1 reads it); record changes in CHANGELOG.md
$AppName = 'Windows Manager'
$Dot = [string][char]0x00B7
$Ellipsis = [string][char]0x2026

# Windows_Manager.ps1 sets $WsmEntry when it starts the joined script: relaunches and the scheduled task go
# back to it, and the assets folder sits next to it.
$AppScript = if ($WsmEntry) { $WsmEntry } else { $PSCommandPath }
$AppRoot = if ($WsmEntry) { Split-Path -Parent $WsmEntry } else { $PSScriptRoot }

# Script or compiled exe? A compiled exe has no script path.
$ExePath = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
$IsCompiled = [IO.Path]::GetFileNameWithoutExtension($ExePath) -notmatch '^(powershell|pwsh|powershell_ise)$'
$IsAdmin = (New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# WPF needs an STA thread; the exe is compiled as STA, a script run may need a relaunch.
if (-not $SelfTest -and -not $TaskOp -and -not $IsCompiled -and [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$AppScript`"")
    foreach ($p in $PSBoundParameters.GetEnumerator()) {
        if ($p.Value -is [switch]) { if ($p.Value) { $forward += "-$($p.Key)" } }
        else { $forward += "-$($p.Key)"; $forward += "`"$($p.Value)`"" }
    }
    Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList $forward
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# One window at a time: a second start (a shortcut, a notification's Open button) brings the open window forward and
# exits. Automatic runs, task changes and tests aren't windows, so they don't take part. A copy that is restarting
# itself (after an update, or as administrator) lets go first.
$script:AppMutex = $null
function Get-AppMutex([int]$WaitSeconds) {
    $created = $false
    $m = New-Object Threading.Mutex($true, 'Local\JustinVieira.WindowsManager', [ref]$created)
    if ($created) { return $m }
    try { if ($m.WaitOne([TimeSpan]::FromSeconds($WaitSeconds))) { return $m } }
    catch [Threading.AbandonedMutexException] { return $m }
    $m.Dispose()
    return $null
}
function Exit-AppMutex {
    if (-not $script:AppMutex) { return }
    try { $script:AppMutex.ReleaseMutex() } catch { }
    $script:AppMutex.Dispose()
    $script:AppMutex = $null
}
if (-not $Auto -and -not $TaskOp -and -not $SelfTest -and $Open -notmatch ':log') {
    $script:AppMutex = Get-AppMutex 3
    if (-not $script:AppMutex) {
        try {
            Add-Type -Namespace WingetUM -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd); [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);'
            $other = @(Get-Process | Where-Object { $_.Id -ne $PID -and $_.MainWindowTitle -eq 'Windows Manager' -and $_.MainWindowHandle -ne [IntPtr]::Zero }) | Select-Object -First 1
            if ($other) {
                [void][WingetUM.Win]::ShowWindowAsync($other.MainWindowHandle, $(if ([WingetUM.Win]::IsIconic($other.MainWindowHandle)) { 9 } else { 5 }))
                [void][WingetUM.Win]::SetForegroundWindow($other.MainWindowHandle)
            }
        }
        catch { }
        exit 0
    }
}

# The window runs without a console, so any unhandled error is written to a log and shown in a message box.
$StartupLog = Join-Path ([IO.Path]::GetTempPath()) 'Windows_Manager.log'
function Write-StartupError {
    param($ErrorRecord)
    $text = "$(Get-Date -Format 's') $($ErrorRecord.Exception.Message)`r`n$($ErrorRecord.InvocationInfo.PositionMessage)`r`n$($ErrorRecord.ScriptStackTrace)`r`n$($ErrorRecord.Exception.ToString())`r`n"
    try { Add-Content -LiteralPath $StartupLog -Value $text } catch { }
    if (-not $SelfTest) {
        [void][System.Windows.MessageBox]::Show("$AppName hit an unexpected error:`n`n$($ErrorRecord.Exception.Message)`n`nDetails were written to:`n$StartupLog", $AppName, 'OK', 'Error')
    }
}
trap { Write-StartupError $_; exit 1 }

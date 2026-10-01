# Windows Manager - ScheduledTask (part of src\; see Windows_Manager.ps1)

# One task in the root folder, running as the signed-in user (winget needs a user session), interactive so the
# notification can appear. "Run elevated" uses the highest run level, so installers never ask for approval.
$TaskName = 'Windows Manager'
# The task's names under the app's earlier names (Windows Package Manager, Winget Manager, Winget Package Manager,
# Winget Update Manager); the app offers to move one it finds
$LegacyTaskNames = @('Windows Software Manager', 'Windows Package Manager', 'Winget Manager', 'Winget Package Manager', 'Winget Update Manager')
$CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

function Invoke-TaskOperation($Spec) {
    switch ($Spec.Op) {
        { $_ -in 'register', 'migrate' } {
            $trig = @{ At = [datetime]::Today.Add([TimeSpan]::Parse($Spec.Time)) }
            if ([int]$Spec.RandomDelayMin -gt 0) { $trig.RandomDelay = New-TimeSpan -Minutes ([int]$Spec.RandomDelayMin) }
            $trigger = if ($Spec.Frequency -eq 'Weekly') { New-ScheduledTaskTrigger -Weekly -DaysOfWeek ([DayOfWeek[]]@($Spec.Days)) @trig }
            else { New-ScheduledTaskTrigger -Daily @trig }
            $action = New-ScheduledTaskAction -Execute $Spec.Execute -Argument $Spec.Arguments
            $hours = if ([int]$Spec.MaxRunHours -gt 0) { [int]$Spec.MaxRunHours } else { 4 }
            $set = @{ StartWhenAvailable = [bool]$Spec.CatchUp; ExecutionTimeLimit = (New-TimeSpan -Hours $hours); MultipleInstances = 'IgnoreNew'
                RunOnlyIfNetworkAvailable = [bool]$Spec.RequireNetwork
            }
            if (-not $Spec.RequireAC) { $set.AllowStartIfOnBatteries = $true; $set.DontStopIfGoingOnBatteries = $true }
            $options = New-ScheduledTaskSettingsSet @set
            $principal = New-ScheduledTaskPrincipal -UserId $Spec.User -LogonType Interactive -RunLevel $(if ($Spec.Elevated) { 'Highest' } else { 'Limited' })
            $null = Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $action -Trigger $trigger -Settings $options -Principal $principal `
                -Description 'Installs app updates from winget silently. Created by Windows Manager.' -Force
            # Moving from the old name: the new task exists now, so the old one can go
            if ($Spec.Op -eq 'migrate' -and $Spec.Legacy) { Unregister-ScheduledTask -TaskName $Spec.Legacy -TaskPath '\' -Confirm:$false -ErrorAction SilentlyContinue }
        }
        'unregister' { Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false }
        'start' { Start-ScheduledTask -TaskName $TaskName -TaskPath '\' }
    }
}

# Elevated helper: this app started with -TaskOp and administrator rights performs the change and reports back in a file
if ($TaskOp) {
    $msg = 'OK'
    $spec = $null
    try {
        $spec = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($TaskOp)) | ConvertFrom-Json
        Invoke-TaskOperation $spec
    }
    catch { $msg = $_.Exception.Message }
    if ($spec -and $spec.Result) { try { Set-Content -LiteralPath $spec.Result -Value $msg -Encoding UTF8 } catch { } }
    exit ([int]($msg -ne 'OK'))
}

function Test-AccessDenied($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    if ($ex.HResult -eq -2147024891) { return $true }                                                     # E_ACCESSDENIED
    if ($ex.PSObject.Properties['NativeErrorCode'] -and "$($ex.NativeErrorCode)" -eq 'AccessDenied') { return $true }
    return "$($ex.Message) $($ErrorRecord.FullyQualifiedErrorId)" -match 'Access is denied|AccessDenied|0x80070005'
}

function Invoke-TaskOperationElevated($Spec) {
    $result = Join-Path ([IO.Path]::GetTempPath()) ('wum_task_{0}.txt' -f [guid]::NewGuid().ToString('N'))
    $Spec.Result = $result
    $payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Spec | ConvertTo-Json -Compress)))
    if ($IsCompiled) { $file = $ExePath; $argList = @('-TaskOp', $payload) }
    else { $file = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"; $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$AppScript`"", '-TaskOp', $payload) }
    try { $proc = Start-Process -FilePath $file -ArgumentList $argList -Verb RunAs -PassThru -Wait }
    catch { throw 'Administrator approval was declined, so the task was not changed.' }
    $msg = ''
    if (Test-Path -LiteralPath $result) { $msg = (Get-Content -LiteralPath $result -Raw).Trim(); Remove-Item -LiteralPath $result -Force }
    if ($msg -ne 'OK') { throw $(if ($msg) { $msg } else { "The elevated helper exited with code $($proc.ExitCode)." }) }
}

# Tries the change as the current user first; creating an elevated task (or changing one) may need administrator rights.
function Invoke-TaskAction($Spec) {
    try { Invoke-TaskOperation $Spec }
    catch {
        if (-not $IsAdmin -and (Test-AccessDenied $_)) { Invoke-TaskOperationElevated $Spec }
        else { throw }
    }
}

# Reading the task goes through the Task Scheduler COM API: the ScheduledTasks cmdlets (CIM) take about two seconds per
# call on some PCs, which froze the window. Creating and changing the task still uses the cmdlets.
function Get-TaskService {
    if (-not $script:TaskService) {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        $script:TaskService = $svc
    }
    return $script:TaskService
}

function Get-AutoTask([string]$Name = $TaskName) {
    try { return (Get-TaskService).GetFolder('\').GetTask($Name) } catch { return $null }
}

function ConvertFrom-TaskDuration([string]$Value, [string]$Unit) {
    if (-not $Value) { return 0 }
    try { $span = [Xml.XmlConvert]::ToTimeSpan($Value) } catch { return 0 }
    if ($Unit -eq 'Hours') { return [int]$span.TotalHours } else { return [int]$span.TotalMinutes }
}

# Reads the task back into the same shape the panel edits
function Get-AutoSchedule([string]$Name = $TaskName) {
    $task = Get-AutoTask $Name
    if (-not $task) { return $null }
    $def = $task.Definition
    $set = $def.Settings
    $s = @{ Enabled = [bool]$task.Enabled; Frequency = 'Daily'; Days = @(); Time = '03:00'; Execute = ''; Arguments = ''
        Elevated = [int]$def.Principal.RunLevel -eq 1; CatchUp = [bool]$set.StartWhenAvailable; NextRun = $null; LastRun = $null
        # Run conditions as the task has them (tasks made by 1.2 predate these options)
        RequireNetwork = [bool]$set.RunOnlyIfNetworkAvailable; RequireAC = [bool]$set.DisallowStartIfOnBatteries
        RandomDelayMin = 0; MaxRunHours = 4
    }
    $h = ConvertFrom-TaskDuration $set.ExecutionTimeLimit 'Hours'
    if ($h -gt 0) { $s.MaxRunHours = $h }
    $trigger = $null
    foreach ($tr in $def.Triggers) { $trigger = $tr; break }
    if ($trigger) {
        $m = [regex]::Match("$($trigger.StartBoundary)", 'T(\d{2}:\d{2})')
        if ($m.Success) { $s.Time = $m.Groups[1].Value }
        if ([int]$trigger.Type -eq 3) {   # TASK_TRIGGER_WEEKLY
            $s.Frequency = 'Weekly'
            $mask = [int]$trigger.DaysOfWeek
            $s.Days = @(0..6 | Where-Object { $mask -band (1 -shl $_) } | ForEach-Object { [string][DayOfWeek]$_ })
        }
        try { $s.RandomDelayMin = ConvertFrom-TaskDuration $trigger.RandomDelay 'Minutes' } catch { }
    }
    foreach ($act in $def.Actions) { $s.Execute = "$($act.Path)".Trim('"'); $s.Arguments = "$($act.Arguments)"; break }
    try { if ($task.NextRunTime.Year -gt 2000) { $s.NextRun = $task.NextRunTime } } catch { }
    try { if ($task.LastRunTime.Year -gt 2000) { $s.LastRun = $task.LastRunTime } } catch { }
    return $s
}
# What the task runs: the exe itself, or Windows PowerShell with this script when it is not compiled
function Get-AutoCommand {
    if ($IsCompiled) { return @{ Execute = $ExePath; Arguments = '-Auto' } }
    return @{ Execute = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"; Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$AppScript`" -Auto" }
}

# A register request: the schedule itself (from the panel, the existing task or an import) plus the run conditions from Options
function New-RegisterSpec($S) {
    $cmd = Get-AutoCommand
    return @{
        Op = 'register'; User = $CurrentUser; Execute = $cmd.Execute; Arguments = $cmd.Arguments
        Frequency = $S.Frequency; Days = @($S.Days); Time = $S.Time; Elevated = [bool]$S.Elevated; CatchUp = [bool]$S.CatchUp
        RequireNetwork = $Settings.RequireNetwork; RequireAC = $Settings.RequireAC; RandomDelayMin = $Settings.RandomDelayMin; MaxRunHours = $Settings.MaxRunHours
    }
}

function Format-Schedule($S) {
    $time = [datetime]::Today.Add([TimeSpan]::Parse($S.Time)).ToString('t')
    if ($S.Frequency -eq 'Weekly') {
        $names = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday') | Where-Object { $S.Days -contains $_ } | ForEach-Object { $_.Substring(0, 3) }
        return "$($names -join ', ') at $time"
    }
    return "Daily at $time"
}

function Get-LastRun {
    try { if (Test-Path -LiteralPath $LastRunPath) { return Get-Content -LiteralPath $LastRunPath -Raw | ConvertFrom-Json } } catch { }
    return $null
}

function Format-LastRun($Run) {
    if (-not $Run) { return $null }
    $when = "$($Run.Time)"
    try { $when = ([datetime]$Run.Time).ToString('ddd M/d, h:mm tt') } catch { }
    if ($Run.Error) { return "Last run $when failed: $($Run.Error)" }
    if ($Run.Mode -eq 'notify' -and -not $Run.DryRun) {
        $n = [int]$Run.Available
        return "Last check $when" + ': ' + $(if ($n) { "$n update$(if ($n -ne 1) { 's' }) available (not installed)" } else { 'nothing to update' })
    }
    $parts = @()
    if ($Run.Updated) { $parts += "$($Run.Updated) updated" }
    if ($Run.Reboot) { $parts += "$($Run.Reboot) need a restart" }
    if ($Run.Failed) { $parts += "$($Run.Failed) failed" }
    if (-not $parts) { $parts += 'nothing to update' }
    $text = "Last run $when" + ': ' + ($parts -join ', ')
    if ($Run.DryRun) { $text += ' (dry run)' }
    return $text
}

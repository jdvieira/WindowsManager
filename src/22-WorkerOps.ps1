# Windows Manager - WorkerOps (part of src\; see Windows_Manager.ps1)

# Background operations added in 2.0, appended to the worker script: each is its own "if ($Op -eq ...)" block and
# talks to the window through Send, like the ones in 20-Worker.ps1.

# Measuring and deleting for Clean up. The same functions run in the worker (your own files) and, as text, in the
# administrator script (Windows' folders), so both clean the same way.
$CleanFunctions = @'
# Bytes in a folder (or one file), counting files older than $OlderDays (0 = all) and skipping the folder names in
# $Skip; -1 when the folder can't be read
function Measure-CleanPath([string]$Path, [int]$OlderDays, [string[]]$Skip) {
    # Test-Path throws for a folder under one you can't read: it may be there, but can't be measured
    try { if (-not (Test-Path -LiteralPath $Path)) { return [long]0 } } catch { return [long]-1 }
    $cut = if ($OlderDays -gt 0) { (Get-Date).AddDays(-$OlderDays) } else { [datetime]::MaxValue }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $f = New-Object IO.FileInfo $Path; if ($f.LastWriteTime -lt $cut) { return [long]$f.Length } else { return [long]0 } }
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count) {
        $d = $stack.Pop()
        try { foreach ($f in (New-Object IO.DirectoryInfo $d).GetFiles()) { if ($f.LastWriteTime -lt $cut) { $total += $f.Length } } }
        catch { if ($d -eq $Path) { return [long]-1 } }
        try {
            foreach ($s in (New-Object IO.DirectoryInfo $d).GetDirectories()) {
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($d -eq $Path -and $Skip -contains $s.Name) { continue }
                $stack.Push($s.FullName)
            }
        }
        catch { }
    }
    return $total
}
# Deletes those files, then the folders left empty below $Path (not $Path itself). Files in use are skipped.
function Remove-CleanPath([string]$Path, [int]$OlderDays, [string[]]$Skip) {
    $r = @{ Freed = [long]0; Failed = 0 }
    try { if (-not (Test-Path -LiteralPath $Path)) { return $r } } catch { $r.Failed++; return $r }
    $cut = if ($OlderDays -gt 0) { (Get-Date).AddDays(-$OlderDays) } else { [datetime]::MaxValue }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $f = New-Object IO.FileInfo $Path
        if ($f.LastWriteTime -lt $cut) { try { $len = $f.Length; $f.Attributes = 'Normal'; $f.Delete(); $r.Freed += $len } catch { $r.Failed++ } }
        return $r
    }
    $dirs = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    while ($stack.Count) {
        $d = $stack.Pop()
        try {
            foreach ($f in (New-Object IO.DirectoryInfo $d).GetFiles()) {
                if ($f.LastWriteTime -ge $cut) { continue }
                try { $len = $f.Length; if ($f.Attributes -band [IO.FileAttributes]::ReadOnly) { $f.Attributes = 'Normal' }; $f.Delete(); $r.Freed += $len } catch { $r.Failed++ }
            }
        }
        catch { $r.Failed++ }
        try {
            foreach ($s in (New-Object IO.DirectoryInfo $d).GetDirectories()) {
                if ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                if ($d -eq $Path -and $Skip -contains $s.Name) { continue }
                $dirs.Add($s.FullName); $stack.Push($s.FullName)
            }
        }
        catch { }
    }
    for ($i = $dirs.Count - 1; $i -ge 0; $i--) { try { if (-not [IO.Directory]::EnumerateFileSystemEntries($dirs[$i]).GetEnumerator().MoveNext()) { [IO.Directory]::Delete($dirs[$i]) } } catch { } }
    return $r
}
'@

$WorkerScript += "`r`n" + $CleanFunctions + "`r`n" + @'

if ($Op -eq 'amdlookup') {
    # AMD's newest recommended Radeon driver. AMD's driver page links its auto-detect installer, whose file name
    # carries the version and date (amd-software-adrenalin-edition-26.8.1-minimalsetup-260818_web.exe). The installed
    # version comes from AMD Software's own registry key, or its uninstall entry.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $gpu = @(Get-CimInstance Win32_VideoController | Where-Object { "$($_.AdapterCompatibility) $($_.Name)" -match 'Advanced Micro|\bAMD\b|Radeon|\bATI\b' }) | Select-Object -First 1
        $name = if ($Arg.Gpu) { [string]$Arg.Gpu } elseif ($gpu) { [string]$gpu.Name } else { '' }
        if (-not $name) { Send @{ T = 'amdlookup'; None = $true }; return }
        $installed = ''
        if ($Arg.ContainsKey('Installed')) { $installed = [string]$Arg.Installed }
        else {
            try { $installed = [string](Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\AMD\CN' -ErrorAction Stop).RadeonSoftwareVersion } catch { }
            if (-not $installed) {
                foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
                    foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
                        $v = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                        if ($v.DisplayName -like 'AMD Software*' -and $v.DisplayVersion) { $installed = [string]$v.DisplayVersion; break }
                    }
                    if ($installed) { break }
                }
            }
        }
        $wc = New-Object Net.WebClient
        $wc.Headers['User-Agent'] = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Windows Manager'
        $html = $wc.DownloadString('https://www.amd.com/en/support/download/drivers.html')
        $m = [regex]::Match($html, 'https://drivers\.amd\.com/[^"''\s<>]*?adrenalin-edition-(\d+\.\d+\.\d+)-minimalsetup-(\d{6})[^"''\s<>]*?\.exe')
        if (-not $m.Success) { Send @{ T = 'amdlookup'; Gpu = $name; Installed = $installed; Error = "AMD's driver page no longer links its installer where this app looks for it" }; return }
        $date = ''; try { $date = [datetime]::ParseExact($m.Groups[2].Value, 'yyMMdd', [Globalization.CultureInfo]::InvariantCulture).ToString('yyyy-MM-dd') } catch { }
        Send @{ T = 'amdlookup'; Gpu = $name; Installed = $installed; Latest = $m.Groups[1].Value; Url = $m.Value; Date = $date; Error = $null }
    }
    catch { Send @{ T = 'amdlookup'; Error = $_.Exception.Message } }
}

if ($Op -eq 'appupdate') {
    # This app's newest release on GitHub: its tag (v<version>), notes, date and the exe to download, with GitHub's
    # SHA-256 checksum of it
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object Net.WebClient
        $wc.Encoding = [Text.Encoding]::UTF8   # GitHub sends UTF-8; WebClient would read it as the ANSI code page
        $wc.Headers['User-Agent'] = 'WindowsManager-Updater'
        $wc.Headers['Accept'] = 'application/vnd.github+json'
        if ($Arg.Beta) {
            # pre-releases too: the highest version among the recent releases that aren't drafts
            $all = @($wc.DownloadString("https://api.github.com/repos/$($Arg.Repo)/releases?per_page=20") | ConvertFrom-Json | Where-Object { -not $_.draft })
            $j = $all | Sort-Object { $v = $null; if ([version]::TryParse((([string]$_.tag_name -replace '^[vV]', '') -replace '-.*$', ''), [ref]$v)) { $v } else { [version]'0.0' } } -Descending | Select-Object -First 1
            if (-not $j) { throw 'there are no releases on GitHub yet' }
        }
        else { $j = $wc.DownloadString("https://api.github.com/repos/$($Arg.Repo)/releases/latest") | ConvertFrom-Json }
        $asset = @($j.assets | Where-Object { $_.name -like '*.exe' }) | Select-Object -First 1
        Send @{ T = 'appupdate'; Manual = [bool]$Arg.Manual; Tag = [string]$j.tag_name; Name = [string]$j.name; Notes = [string]$j.body; Published = [string]$j.published_at
            Page = [string]$j.html_url; Prerelease = [bool]$j.prerelease; Url = $(if ($asset) { [string]$asset.browser_download_url } else { '' }); Size = $(if ($asset) { [long]$asset.size } else { 0 })
            Digest = $(if ($asset) { [string]$asset.digest } else { '' }); Error = $null }
    }
    catch {
        $m = $_.Exception.Message
        if ($m -match '\(404\)') { $m = 'there are no releases on GitHub yet' }
        Send @{ T = 'appupdate'; Manual = [bool]$Arg.Manual; Error = $m }
    }
}

if ($Op -eq 'download') {
    # A download with progress, kept only when it is signed by the expected publisher (Arg.Signer, a regex on the
    # certificate subject) and, when Arg.Sha256 is given, matches that checksum. Some servers (AMD's) need the page
    # the link was on as the referrer.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $req = [Net.HttpWebRequest]::Create($Arg.Url)
        $req.UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Windows Manager'
        if ($Arg.Referer) { $req.Referer = $Arg.Referer }
        $resp = $req.GetResponse()
        try {
            if ($resp.ContentType -match 'text/html') { throw 'the server sent a web page instead of the file' }
            $total = $resp.ContentLength
            New-Item -ItemType Directory -Path (Split-Path -Parent $Arg.File) -Force | Out-Null
            $in = $resp.GetResponseStream(); $out = [IO.File]::Create($Arg.File)
            try {
                $buf = New-Object byte[] 262144; $done = [long]0; $last = -1
                while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $n); $done += $n
                    if ($total -gt 0) { $pct = [int]($done * 100 / $total); if ($pct -ne $last) { $last = $pct; Send @{ T = 'dlprogress'; Key = $Arg.Key; Value = $pct; Done = $done; Total = $total } } }
                }
            }
            finally { $out.Close(); $in.Close() }
        }
        finally { $resp.Close() }
        if ($Arg.Total -and (Get-Item -LiteralPath $Arg.File).Length -ne $Arg.Total) {
            Remove-Item -LiteralPath $Arg.File -Force -ErrorAction SilentlyContinue
            throw 'the download stopped before the end, so it was deleted'
        }
        # .NET's SHA256 (Get-FileHash comes from a script module that the compiled exe's runspaces don't load)
        $hash = ''
        if ($Arg.Sha256) { $hs = [IO.File]::OpenRead($Arg.File); try { $hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash($hs) | ForEach-Object { $_.ToString('X2') }) } finally { $hs.Close() } }
        if ($Arg.Sha256 -and $hash -ne $Arg.Sha256) {
            Remove-Item -LiteralPath $Arg.File -Force -ErrorAction SilentlyContinue
            throw "the download doesn't match the checksum GitHub published for it, so it was deleted"
        }
        $signer = ''
        if ($Arg.Signer) {
            $sig = Get-AuthenticodeSignature -LiteralPath $Arg.File
            if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch $Arg.Signer) {
                Remove-Item -LiteralPath $Arg.File -Force -ErrorAction SilentlyContinue
                throw "the download isn't signed by $($Arg.SignerName) ($($sig.Status)), so it was deleted"
            }
            $signer = $sig.SignerCertificate.Subject -replace '^CN=("?)([^,"]+)\1.*', '$2'
        }
        Send @{ T = 'download'; Key = $Arg.Key; File = $Arg.File; Signer = $signer; Error = $null }
    }
    catch { Send @{ T = 'download'; Key = $Arg.Key; Error = $_.Exception.Message } }
}

if ($Op -eq 'wusoftware') {
    # Windows Update's own updates for this PC (security and cumulative updates, .NET, Defender, ...: everything that
    # isn't a driver), its recent history, a waiting restart, and who manages updates. Needs no administrator rights.
    $res = @{ T = 'wusoftware'; Updates = @(); History = @(); Error = $null; Reboot = $false; Managed = '' }
    $s = $null; $searcher = $null
    try {
        $s = New-Object -ComObject Microsoft.Update.Session
        $s.ClientApplicationID = 'Windows Manager'
        $searcher = $s.CreateUpdateSearcher()
        $r = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
        $list = New-Object Collections.Generic.List[object]
        foreach ($u in $r.Updates) {
            $date = ''; try { $date = ([datetime]$u.LastDeploymentChangeTime).ToString('yyyy-MM-dd') } catch { }
            $list.Add(@{ Id = [string]$u.Identity.UpdateID; Title = [string]$u.Title; Kb = (@($u.KBArticleIDs | ForEach-Object { "KB$_" }) -join ', ')
                    Categories = @($u.Categories | ForEach-Object { [string]$_.Name }); Severity = [string]$u.MsrcSeverity; Size = [long]$u.MaxDownloadSize
                    Date = $date; Description = [string]$u.Description; Url = [string](@($u.MoreInfoUrls) | Select-Object -First 1); BrowseOnly = [bool]$u.BrowseOnly
                    Downloaded = [bool]$u.IsDownloaded })
        }
        $res.Updates = $list.ToArray()
    }
    catch { $res.Error = $_.Exception.Message }
    try {
        if (-not $searcher) { $s = New-Object -ComObject Microsoft.Update.Session; $searcher = $s.CreateUpdateSearcher() }
        $count = $searcher.GetTotalHistoryCount()
        $hist = New-Object Collections.Generic.List[object]
        if ($count -gt 0) {
            foreach ($e in $searcher.QueryHistory(0, [Math]::Min($count, 80))) {
                if ($e.Operation -ne 1 -or -not $e.Title) { continue }   # installs only
                $when = ''; try { $when = ([datetime]$e.Date).ToLocalTime().ToString('yyyy-MM-dd HH:mm') } catch { }
                $hist.Add(@{ Title = [string]$e.Title; When = $when; Code = [int]$e.ResultCode; HResult = [int]$e.HResult; Categories = @($e.Categories | ForEach-Object { [string]$_.Name }) })
            }
        }
        $res.History = $hist.ToArray()
    }
    catch { }
    try { $res.Reboot = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } catch { }
    if (-not $res.Reboot) { $res.Reboot = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') }
    # Who decides what installs and when: an update server (WSUS), Windows Update for Business policies from Intune
    # (MDM) or Group Policy. Settings may then hold back what Windows Update offers here.
    try {
        $au = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' -ErrorAction SilentlyContinue
        $gp = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' -ErrorAction SilentlyContinue
        $pm = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update' -ErrorAction SilentlyContinue
        $wufb = 'DeferQualityUpdates|DeferFeatureUpdates|PauseQualityUpdates|PauseFeatureUpdates|TargetReleaseVersion|ProductVersion|BranchReadinessLevel'
        if ($au.UseWUServer -eq 1 -and $gp.WUServer) { $res.Managed = 'wsus' }
        elseif ($pm -and @($pm.PSObject.Properties.Name | Where-Object { $_ -match $wufb }).Count) { $res.Managed = 'intune' }
        elseif ($gp -and @($gp.PSObject.Properties.Name | Where-Object { $_ -match $wufb }).Count) { $res.Managed = 'gpo' }
    }
    catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $res.Os = @{ Name = ([string]$os.Caption -replace '^Microsoft\s+', ''); Display = [string]$cv.DisplayVersion; Build = "$($cv.CurrentBuildNumber).$($cv.UBR)" }
    }
    catch { $res.Os = @{ Name = 'Windows'; Display = ''; Build = '' } }
    Send $res
}

if ($Op -eq 'startup') {
    # Apps that start at sign-in, as Task Manager lists them: the Run keys (yours, and every user's 64-bit and 32-bit
    # ones), the two Startup folders, and Store apps' startup tasks. StartupApproved says whether each may start: the
    # first byte of its value is even (02, 06) when allowed and odd (03, 07) when turned off; no value means allowed.
    $items = New-Object Collections.Generic.List[object]
    $err = $null
    try {
        $hku = [Microsoft.Win32.RegistryKey]::OpenBaseKey('CurrentUser', 'Registry64')
        $hkm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
        $approvedRoot = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
        function Test-Approved($Base, [string]$Sub, [string]$Name) {
            $k = $Base.OpenSubKey("$approvedRoot\$Sub")
            if (-not $k) { return $true }
            try { $v = $k.GetValue($Name); if ($v -is [byte[]] -and $v.Length) { return ($v[0] % 2) -eq 0 } return $true }
            finally { $k.Close() }
        }
        # The program a command line starts: a quoted path, or everything up to .exe; rundll32 runs the DLL it names
        function Get-Target([string]$Cmd) {
            $c = [Environment]::ExpandEnvironmentVariables($Cmd).Trim()
            $p = if ($c.StartsWith('"')) { $c.Substring(1).Split('"')[0] } elseif ($c -match '^(.+?\.(exe|com|bat|cmd))(\s|$)') { $Matches[1] } else { $c.Split(' ')[0] }
            if ($p -match '(?i)\\rundll32\.exe$' -and $c -match '(?i)rundll32(\.exe)?"?\s+"?([^",]+\.dll)') { $p = $Matches[2] }
            if ($p -and -not [IO.Path]::IsPathRooted($p)) { $w = Get-Command $p -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1; if ($w) { $p = $w.Source } }
            return $p
        }
        # The program's publisher and description (Task Manager names startup apps by the description)
        function Get-FileInfo([string]$Path) {
            $r = @{ Company = ''; Description = '' }
            try { if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) { $vi = (Get-Item -LiteralPath $Path).VersionInfo; $r.Company = ([string]$vi.CompanyName).Trim(); $r.Description = ([string]$vi.FileDescription).Trim() } } catch { }
            return $r
        }
        $runs = @(
            @{ Base = $hku; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Loc = 'hkcu'; Text = 'Registry (you)'; Admin = $false },
            @{ Base = $hkm; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run'; Loc = 'hklm'; Text = 'Registry (all users)'; Admin = $true },
            @{ Base = $hkm; Key = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = 'Run32'; Loc = 'hklm32'; Text = 'Registry (all users, 32-bit)'; Admin = $true })
        foreach ($r in $runs) {
            $k = $r.Base.OpenSubKey($r.Key)
            if (-not $k) { continue }
            try {
                foreach ($n in $k.GetValueNames()) {
                    if (-not $n) { continue }
                    $cmd = [string]$k.GetValue($n)
                    if (-not $cmd.Trim()) { continue }
                    $t = Get-Target $cmd
                    $fi = Get-FileInfo $t
                    $items.Add(@{ Name = $(if ($fi.Description) { $fi.Description } else { $n }); Command = $cmd; Target = $t; Publisher = $fi.Company; Location = $r.Loc; LocationText = $r.Text; Entry = $n
                            NeedsAdmin = $r.Admin; Enabled = (Test-Approved $r.Base $r.Approved $n) })
                }
            }
            finally { $k.Close() }
        }
        $shell = New-Object -ComObject WScript.Shell
        foreach ($f in @(@{ Dir = [Environment]::GetFolderPath('Startup'); Base = $hku; Loc = 'userfolder'; Text = 'Startup folder (you)'; Admin = $false },
                @{ Dir = [Environment]::GetFolderPath('CommonStartup'); Base = $hkm; Loc = 'commonfolder'; Text = 'Startup folder (all users)'; Admin = $true })) {
            if (-not $f.Dir -or -not (Test-Path -LiteralPath $f.Dir)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $f.Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
                $cmd = $file.FullName; $t = $file.FullName
                if ($file.Extension -eq '.lnk') { try { $lnk = $shell.CreateShortcut($file.FullName); $t = [string]$lnk.TargetPath; $cmd = ("`"$t`" $($lnk.Arguments)").Trim() } catch { } }
                $fi = Get-FileInfo $t
                $items.Add(@{ Name = $(if ($fi.Description) { $fi.Description } else { [IO.Path]::GetFileNameWithoutExtension($file.Name) }); Command = $cmd; Target = $t; Publisher = $fi.Company; Location = $f.Loc; LocationText = $f.Text
                        Entry = $file.Name; File = $file.FullName; NeedsAdmin = $f.Admin; Enabled = (Test-Approved $f.Base 'StartupFolder' $file.Name) })
            }
        }
        # Store apps: one key per startup task under the package's SystemAppData key, with State 2 or 4 when enabled
        # (0 off, 1 turned off by you, 3 turned off by policy)
        $sad = 'Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
        $root = $hku.OpenSubKey($sad)
        if ($root) {
            $pkgs = @{}
            try { foreach ($p in @(Get-AppxPackage -ErrorAction SilentlyContinue)) { $pkgs[$p.PackageFamilyName] = $p } } catch { }
            try {
                foreach ($fam in $root.GetSubKeyNames()) {
                    $fk = $root.OpenSubKey($fam)
                    if (-not $fk) { continue }
                    try {
                        foreach ($task in $fk.GetSubKeyNames()) {
                            $tk = $fk.OpenSubKey($task)
                            if (-not $tk) { continue }
                            try {
                                $state = $tk.GetValue('State')
                                if ($null -eq $state) { continue }
                                $pkg = $pkgs[$fam]
                                if (-not $pkg) { continue }
                                $display = ''; $pub = ''
                                try { $man = Get-AppxPackageManifest -Package $pkg.PackageFullName; $display = [string]$man.Package.Properties.DisplayName; $pub = [string]$man.Package.Properties.PublisherDisplayName } catch { }
                                if (-not $display -or $display -like 'ms-resource:*') { $display = ($pkg.Name -replace '^[^.]+\.', '' -creplace '([a-z])([A-Z])', '$1 $2') }
                                if ($pub -like 'ms-resource:*') { $pub = '' }
                                $items.Add(@{ Name = $display; Command = "$($pkg.Name) ($task)"; Target = [string]$pkg.InstallLocation; Publisher = $pub; Location = 'appx'
                                        LocationText = 'Store app'; Entry = "$sad\$fam\$task"; File = [string]$pkg.InstallLocation; NeedsAdmin = $false; Enabled = ([int]$state -in 2, 4); Policy = ([int]$state -in 3, 4) })
                            }
                            finally { $tk.Close() }
                        }
                    }
                    finally { $fk.Close() }
                }
            }
            finally { $root.Close() }
        }
        # Scheduled tasks that run at sign-in (trigger 9) or at startup (8), outside Windows' own \Microsoft folder.
        # Tasks that run as you can be changed without approval; others need it.
        try {
            $svc = New-Object -ComObject Schedule.Service
            $svc.Connect()
            $me = [Security.Principal.WindowsIdentity]::GetCurrent()
            $folders = New-Object System.Collections.Generic.Stack[object]
            $folders.Push($svc.GetFolder('\'))
            while ($folders.Count) {
                $fo = $folders.Pop()
                foreach ($sub in @($fo.GetFolders(0))) { if ($sub.Path -notlike '\Microsoft*') { $folders.Push($sub) } }
                foreach ($t in @($fo.GetTasks(1))) {
                    $def = $t.Definition
                    $kinds = @($def.Triggers | ForEach-Object { [int]$_.Type })
                    if ($kinds -notcontains 9 -and $kinds -notcontains 8) { continue }
                    $act = @($def.Actions | Where-Object { $_.Type -eq 0 }) | Select-Object -First 1
                    $path = if ($act) { [Environment]::ExpandEnvironmentVariables([string]$act.Path).Trim('"') } else { '' }
                    $fi = Get-FileInfo $path
                    $uid = [string]$def.Principal.UserId
                    $mine = [bool]$uid -and ($uid -eq $me.Name -or $uid -eq $me.User.Value -or $uid -eq $env:USERNAME)
                    $items.Add(@{ Name = [string]$t.Name; Command = $(if ($act) { ("`"$path`" " + [string]$act.Arguments).Trim() } else { '(no program)' }); Target = $path
                            Publisher = $(if ($fi.Company) { $fi.Company } else { [string]$def.RegistrationInfo.Author }); Location = 'task'
                            LocationText = $(if ($kinds -contains 9) { 'Scheduled task (sign-in)' } else { 'Scheduled task (startup)' }); Entry = [string]$t.Path; File = $path
                            NeedsAdmin = -not $mine; Enabled = [bool]$t.Enabled })
                }
            }
        }
        catch { }
        $hku.Close(); $hkm.Close()
    }
    catch { $err = $_.Exception.Message }
    Send @{ T = 'startup'; Items = $items.ToArray(); Error = $err }
}

if ($Op -eq 'health') {
    # The Health tab: the PC and Windows, a waiting restart, the battery (Windows' battery report, which a standard
    # user can read), and the drives. Disk wear and temperature need administrator rights, so they appear when the
    # app runs elevated.
    $h = @{ T = 'health'; Error = $null }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $cs = Get-CimInstance Win32_ComputerSystem
        $bios = Get-CimInstance Win32_BIOS
        $cpu = @(Get-CimInstance Win32_Processor) | Select-Object -First 1
        $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
        $biosDate = ''; try { $biosDate = ([datetime]$bios.ReleaseDate).ToString('yyyy-MM-dd') } catch { }
        $h.Sys = @{ Maker = ([string]$cs.Manufacturer).Trim(); Model = ([string]$cs.Model).Trim(); Serial = ([string]$bios.SerialNumber).Trim()
            Os = ([string]$os.Caption -replace '^Microsoft\s+', ''); Display = [string]$cv.DisplayVersion; Build = "$($cv.CurrentBuildNumber).$($cv.UBR)"
            Boot = [datetime]$os.LastBootUpTime; Installed = [datetime]$os.InstallDate; MemoryGB = [Math]::Round([double]$cs.TotalPhysicalMemory / 1GB)
            Cpu = ([string]$cpu.Name -replace '\s+', ' ').Trim(); Bios = [string]$bios.SMBIOSBIOSVersion; BiosDate = $biosDate; BiosMaker = [string]$bios.Manufacturer }
        $h.Reboot = (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
        try { if (-not $h.Reboot) { $h.Reboot = [bool](New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired } } catch { }
    }
    catch { $h.Error = $_.Exception.Message }
    # Battery: capacity when new, capacity now, cycles, and the charge right now
    try {
        $b = @(Get-CimInstance Win32_Battery)
        if ($b.Count) {
            $xml = Join-Path ([IO.Path]::GetTempPath()) "wsm-battery-$PID.xml"
            $null = & "$env:SystemRoot\System32\powercfg.exe" /batteryreport /xml /output $xml 2>&1
            $bats = @()
            if (Test-Path -LiteralPath $xml) {
                try { [xml]$x = Get-Content -LiteralPath $xml -Raw; $bats = @($x.BatteryReport.Batteries.Battery) } finally { Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue }
            }
            $h.Battery = @{ Charge = [int]$b[0].EstimatedChargeRemaining; Status = [int]$b[0].BatteryStatus; Count = $b.Count
                Design = [long](($bats | Measure-Object -Property DesignCapacity -Sum).Sum); Full = [long](($bats | Measure-Object -Property FullChargeCapacity -Sum).Sum)
                Cycles = [int](($bats | Measure-Object -Property CycleCount -Maximum).Maximum); Name = [string](@($bats | ForEach-Object { $_.Id }) -join ', ') }
        }
    }
    catch { }
    # Drives: each fixed volume's space, and each physical disk's health
    try {
        $h.Volumes = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object { $_.Size -gt 0 } | ForEach-Object { @{ Letter = [string]$_.DeviceID; Label = [string]$_.VolumeName; Size = [long]$_.Size; Free = [long]$_.FreeSpace } })
    }
    catch { $h.Volumes = @() }
    try {
        $disks = New-Object Collections.Generic.List[object]
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $rel = $null; try { $rel = $d | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            $disks.Add(@{ Name = ([string]$d.FriendlyName).Trim(); Media = [string]$d.MediaType; Bus = [string]$d.BusType; Size = [long]$d.Size; Health = [string]$d.HealthStatus
                    Status = [string](@($d.OperationalStatus) -join ', '); Wear = $(if ($rel) { $rel.Wear } else { $null }); Temp = $(if ($rel) { $rel.Temperature } else { $null })
                    Hours = $(if ($rel) { $rel.PowerOnHours } else { $null }) })
        }
        $h.Disks = $disks.ToArray()
    }
    catch { $h.Disks = @() }
    $ProgressPreference = 'SilentlyContinue'
    # Security: antivirus (Windows Security Center lists whichever is registered), Defender's own status, the
    # firewall, BitLocker on the system drive (the shell's property, which a standard user can read), Secure Boot,
    # the TPM (its device), and activation
    $sec = @{}
    try {
        $sec.Av = @(Get-CimInstance -Namespace root\SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object {
                # productState: the second byte says on (0x10/0x11) or off, the third out of date (0x10) or current
                $st = [int]$_.productState
                @{ Name = [string]$_.displayName; On = ((($st -shr 8) -band 0xFF) -band 0x10) -ne 0; Current = ((($st) -band 0xFF) -band 0x10) -eq 0 } })
    }
    catch { $sec.Av = @() }
    try { $m = Get-MpComputerStatus -ErrorAction Stop; $sec.Defender = @{ On = [bool]$m.AntivirusEnabled; Realtime = [bool]$m.RealTimeProtectionEnabled; SigAge = [int]$m.AntivirusSignatureAge; ScanAge = [int]$m.QuickScanAge } } catch { }
    try { $sec.Firewall = @(Get-NetFirewallProfile -ErrorAction Stop | ForEach-Object { @{ Name = [string]$_.Name; On = [bool]$_.Enabled } }) } catch { }
    try { $sec.BitLocker = (New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection') } catch { }
    try { $sec.SecureBoot = (Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction Stop).UEFISecureBootEnabled } catch { }
    try { $sec.Tpm = [string](@(Get-CimInstance Win32_PnPEntity -Filter "PNPClass='SecurityDevices'" | Where-Object { $_.Name -match 'Trusted Platform' }) | Select-Object -First 1).Name } catch { }
    try { $lic = @(Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL") | Select-Object -First 1; if ($lic) { $sec.License = [int]$lic.LicenseStatus } } catch { }
    $h.Security = $sec
    # Performance: memory in use, the processor's load right now, and the apps using the most memory
    try {
        $o = Get-CimInstance Win32_OperatingSystem
        $perf = @{ MemTotal = [long]$o.TotalVisibleMemorySize * 1KB; MemFree = [long]$o.FreePhysicalMemory * 1KB }
        try { $perf.Cpu = [int](@(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average) } catch { }
        $skip = 'Memory Compression', 'System', 'Idle', 'Registry', 'vmmem', 'Secure System'
        $perf.Top = @(Get-Process | Where-Object { $skip -notcontains $_.ProcessName } | Group-Object ProcessName | ForEach-Object {
                $p = $_.Group[0]
                $desc = ''; try { $desc = [string]$p.MainModule.FileVersionInfo.FileDescription } catch { }
                @{ Name = $(if ($desc) { $desc } else { $_.Name }); Bytes = [long]($_.Group | Measure-Object -Property WorkingSet64 -Sum).Sum } } |
            Sort-Object { $_.Bytes } -Descending | Select-Object -First 3)
        $perf.Processes = @(Get-Process).Count
        $h.Perf = $perf
    }
    catch { }
    # Temperatures. The processor's own sensor needs a kernel driver, so it comes from LibreHardwareMonitor or
    # OpenHardwareMonitor when one is running (they publish their sensors to WMI); otherwise the hottest ACPI thermal
    # zone, which a standard user can read but which on many desktops is the motherboard rather than the processor.
    # Graphics cards report their temperature to Windows (WDDM 2.9 and later, as Task Manager shows it), for any make.
    $temps = @{ Gpus = @() }
    foreach ($ns in 'root\LibreHardwareMonitor', 'root\OpenHardwareMonitor') {
        try {
            $cpuT = @(Get-CimInstance -Namespace $ns -ClassName Sensor -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' -and $_.Parent -match '/(amd|intel)cpu' -and $_.Value -gt 0 })
            if (-not $cpuT.Count) { continue }
            $pick = @($cpuT | Where-Object { $_.Name -match '^(CPU Package|Core \(Tctl/Tdie\)|Core \(Tctl\))$' }) | Select-Object -First 1
            if (-not $pick) { $pick = $cpuT | Sort-Object Value -Descending | Select-Object -First 1 }
            $temps.Cpu = @{ C = [Math]::Round([double]$pick.Value); Source = $(if ($ns -like '*Libre*') { 'LibreHardwareMonitor' } else { 'OpenHardwareMonitor' }); Sensor = [string]$pick.Name }
            break
        }
        catch { }
    }
    try {
        $zone = @(Get-CimInstance Win32_PerfFormattedData_Counters_ThermalZoneInformation -ErrorAction Stop | Where-Object { $_.HighPrecisionTemperature -gt 2732 } | Sort-Object HighPrecisionTemperature -Descending) | Select-Object -First 1
        if ($zone) { $temps.Zone = @{ C = [Math]::Round([double]$zone.HighPrecisionTemperature / 10 - 273.15); Name = [string]$zone.Name } }
    }
    catch { }
    try {
        if (-not ('WsmKmt.Kmt' -as [type])) {
            # (a plain string: this code is itself inside the worker's here-string)
            Add-Type -Namespace WsmKmt -Name Kmt -MemberDefinition (@(
                    '[StructLayout(LayoutKind.Sequential)] public struct LUID { public uint Low; public int High; }'
                    '[StructLayout(LayoutKind.Sequential)] public struct ADAPTERINFO { public uint hAdapter; public LUID AdapterLuid; public uint NumOfSources; public int bPrecisePresentRegionsPreferred; }'
                    '[StructLayout(LayoutKind.Sequential)] public struct ENUMADAPTERS2 { public uint NumAdapters; public IntPtr pAdapters; }'
                    '[StructLayout(LayoutKind.Sequential)] public struct QUERYADAPTERINFO { public uint hAdapter; public int Type; public IntPtr pPrivateDriverData; public uint PrivateDriverDataSize; }'
                    '[StructLayout(LayoutKind.Sequential)] public struct CLOSEADAPTER { public uint hAdapter; }'
                    '[DllImport("gdi32.dll")] public static extern int D3DKMTEnumAdapters2(ref ENUMADAPTERS2 p);'
                    '[DllImport("gdi32.dll")] public static extern int D3DKMTQueryAdapterInfo(ref QUERYADAPTERINFO p);'
                    '[DllImport("gdi32.dll")] public static extern int D3DKMTCloseAdapter(ref CLOSEADAPTER p);'
                ) -join "`n")
        }
        $M = [Runtime.InteropServices.Marshal]
        $en = New-Object WsmKmt.Kmt+ENUMADAPTERS2
        if ([WsmKmt.Kmt]::D3DKMTEnumAdapters2([ref]$en) -eq 0 -and $en.NumAdapters) {
            $sz = $M::SizeOf([type][WsmKmt.Kmt+ADAPTERINFO])
            $en.pAdapters = $M::AllocHGlobal($sz * $en.NumAdapters)
            # 62 is KMTQAITYPE_ADAPTERPERFDATA (temperature in tenths of a degree at offset 56), 8 the adapter's name
            $perfBuf = $M::AllocHGlobal(64); $nameBuf = $M::AllocHGlobal(2080)
            try {
                if ([WsmKmt.Kmt]::D3DKMTEnumAdapters2([ref]$en) -eq 0) {
                    $gpus = New-Object Collections.Generic.List[object]
                    for ($i = 0; $i -lt $en.NumAdapters; $i++) {
                        $ad = $M::PtrToStructure([IntPtr]($en.pAdapters.ToInt64() + $i * $sz), [type][WsmKmt.Kmt+ADAPTERINFO])
                        for ($b = 0; $b -lt 64; $b++) { $M::WriteByte($perfBuf, $b, 0) }
                        $q = New-Object WsmKmt.Kmt+QUERYADAPTERINFO
                        $q.hAdapter = $ad.hAdapter; $q.Type = 62; $q.pPrivateDriverData = $perfBuf; $q.PrivateDriverDataSize = 64
                        $deci = if ([WsmKmt.Kmt]::D3DKMTQueryAdapterInfo([ref]$q) -eq 0) { $M::ReadInt32($perfBuf, 56) } else { 0 }
                        if ($deci -gt 0 -and $deci -lt 1500) {
                            $q.Type = 8; $q.pPrivateDriverData = $nameBuf; $q.PrivateDriverDataSize = 2080
                            $name = if ([WsmKmt.Kmt]::D3DKMTQueryAdapterInfo([ref]$q) -eq 0) { ([string]$M::PtrToStringUni($nameBuf)).Trim() } else { 'Graphics' }
                            $gpus.Add(@{ Name = $name; C = [Math]::Round($deci / 10.0) })
                        }
                        $cl = New-Object WsmKmt.Kmt+CLOSEADAPTER; $cl.hAdapter = $ad.hAdapter; $null = [WsmKmt.Kmt]::D3DKMTCloseAdapter([ref]$cl)
                    }
                    $temps.Gpus = $gpus.ToArray()
                }
            }
            finally { $M::FreeHGlobal($en.pAdapters); $M::FreeHGlobal($perfBuf); $M::FreeHGlobal($nameBuf) }
        }
    }
    catch { }
    # older drivers don't report it to Windows: NVIDIA's own tool, which comes with its driver
    if (-not @($temps.Gpus).Count) {
        try {
            $smi = @("$env:SystemRoot\System32\nvidia-smi.exe", "$env:ProgramFiles\NVIDIA Corporation\NVSMI\nvidia-smi.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if ($smi) { $temps.Gpus = @(& $smi --query-gpu=name,temperature.gpu --format=csv,noheader 2>$null | ForEach-Object { $f = ([string]$_).Split(','); if ($f.Count -ge 2 -and $f[1].Trim() -match '^\d+$') { @{ Name = $f[0].Trim(); C = [int]$f[1].Trim() } } }) }
        }
        catch { }
    }
    $h.Temps = $temps
    # Reliability: Windows' stability index, unexpected shutdowns and blue screens (30 days), app crashes (7 days),
    # devices with a problem
    $rel = @{}
    try { $si = @(Get-CimInstance Win32_ReliabilityStabilityMetrics -ErrorAction Stop | Sort-Object TimeGenerated -Descending) | Select-Object -First 1; if ($si) { $rel.Index = [double]$si.SystemStabilityIndex } } catch { }
    $since = (Get-Date).AddDays(-30)
    try { $rel.Shutdowns = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41; StartTime = $since } -ErrorAction SilentlyContinue).Count } catch { }
    try { $rel.BlueScreens = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; ProviderName = 'Microsoft-Windows-WER-SystemErrorReporting'; StartTime = $since } -ErrorAction SilentlyContinue).Count } catch { }
    try {
        $crash = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; ProviderName = 'Application Error'; StartTime = (Get-Date).AddDays(-7) } -ErrorAction SilentlyContinue)
        $rel.Crashes = $crash.Count
        $rel.CrashApps = @($crash | Group-Object { [string]$_.Properties[0].Value } | Sort-Object Count -Descending | Select-Object -First 3 | ForEach-Object { "$($_.Name -replace '\.exe$', '') ($($_.Count))" })
    }
    catch { }
    try { $rel.Devices = @(Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode <> 0 AND ConfigManagerErrorCode <> 45').Count } catch { }
    $h.Reliability = $rel
    # Network: the connected adapters, their speed and address, the Wi-Fi network and signal, and the internet
    try {
        $nets = New-Object Collections.Generic.List[object]
        $wlan = @{}
        try {
            $cur = ''
            foreach ($l in @(& "$env:SystemRoot\System32\netsh.exe" wlan show interfaces 2>$null)) {
                if ($l -match '^\s+Name\s+:\s+(.+)$') { $cur = $Matches[1].Trim(); $wlan[$cur] = @{} }
                elseif ($cur -and $l -match '^\s+SSID\s+:\s+(.+)$') { $wlan[$cur].Ssid = $Matches[1].Trim() }
                elseif ($cur -and $l -match '^\s+Signal\s+:\s+(\d+)%') { $wlan[$cur].Signal = [int]$Matches[1] }
            }
        }
        catch { }
        $profiles = @{}
        try { foreach ($c in @(Get-NetConnectionProfile -ErrorAction Stop)) { $profiles[[string]$c.InterfaceAlias] = $c } } catch { }
        foreach ($a in @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })) {
            $ip = ''; try { $ip = [string](@(Get-NetIPAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '169.254.*' }) | Select-Object -First 1).IPAddress } catch { }
            $pf = $profiles[[string]$a.Name]
            $w = $wlan[[string]$a.Name]
            $nets.Add(@{ Name = [string]$a.Name; Description = [string]$a.InterfaceDescription; Speed = [string]$a.LinkSpeed; Ip = $ip
                    Wireless = [bool]($w -or $a.PhysicalMediaType -match '802\.11'); Ssid = $(if ($w) { [string]$w.Ssid } else { '' }); Signal = $(if ($w) { $w.Signal } else { $null })
                    Network = $(if ($pf) { [string]$pf.Name } else { '' }); Internet = $(if ($pf) { [string]$pf.IPv4Connectivity -eq 'Internet' -or [string]$pf.IPv6Connectivity -eq 'Internet' } else { $false }) })
        }
        $h.Network = $nets.ToArray()
    }
    catch { $h.Network = @() }
    # Connection quality: round trips to the router and to the internet (how long, how many are lost, how much they
    # vary) and how long a DNS lookup takes. A network that blocks ping is timed with a connection to port 443 instead.
    if (@($h.Network).Count) {
        $q = @{}
        $pinger = New-Object System.Net.NetworkInformation.Ping
        $probe = {
            param([string]$Target, [int]$Count)
            $times = New-Object Collections.Generic.List[double]; $lost = 0
            for ($i = 0; $i -lt $Count; $i++) {
                try { $r = $pinger.Send($Target, 1000); if ($r.Status -eq 'Success') { $times.Add([double]$r.RoundtripTime) } else { $lost++ } } catch { $lost++ }
            }
            $jit = $null
            if ($times.Count -ge 2) { $d = 0.0; for ($i = 1; $i -lt $times.Count; $i++) { $d += [Math]::Abs($times[$i] - $times[$i - 1]) }; $jit = [Math]::Round($d / ($times.Count - 1), 1) }
            @{ Target = $Target; Ms = $(if ($times.Count) { [Math]::Round(($times | Measure-Object -Average).Average, 1) } else { $null }); Jitter = $jit; Loss = [int][Math]::Round(100.0 * $lost / $Count); Method = 'ping' }
        }
        $route = $null
        try { $route = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Where-Object { $_.NextHop -and $_.NextHop -ne '0.0.0.0' } | Sort-Object { [int]$_.RouteMetric + [int]$_.InterfaceMetric }) | Select-Object -First 1 } catch { }
        if ($route) { try { $q.Gateway = & $probe ([string]$route.NextHop) 4 } catch { } }
        try {
            $q.Internet = & $probe '1.1.1.1' 6
            if ($null -eq $q.Internet.Ms) {
                $times = @(foreach ($i in 1..3) {
                        $tcp = New-Object System.Net.Sockets.TcpClient
                        try { $sw = [Diagnostics.Stopwatch]::StartNew(); if ($tcp.ConnectAsync('1.1.1.1', 443).Wait(2000)) { $sw.Elapsed.TotalMilliseconds } } catch { } finally { $tcp.Close() }
                    })
                if ($times.Count) { $q.Internet = @{ Target = '1.1.1.1'; Ms = [Math]::Round(($times | Measure-Object -Average).Average, 1); Jitter = $null; Loss = $null; Method = 'tcp' } }
            }
        }
        catch { }
        try {
            $dns = $null
            if ($route) { try { $dns = @((Get-DnsClientServerAddress -InterfaceIndex $route.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses) | Select-Object -First 1 } catch { } }
            $times = @(foreach ($n in 'www.microsoft.com', 'www.cloudflare.com') {
                    $sw = [Diagnostics.Stopwatch]::StartNew()
                    try {
                        # asking the server itself skips Windows' DNS cache
                        if ($dns) { $null = Resolve-DnsName $n -Type A -DnsOnly -QuickTimeout -Server $dns -ErrorAction Stop } else { $null = Resolve-DnsName $n -Type A -DnsOnly -QuickTimeout -ErrorAction Stop }
                        $sw.Elapsed.TotalMilliseconds
                    }
                    catch { }
                })
            $q.Dns = @{ Server = [string]$dns; Ms = $(if ($times.Count) { [Math]::Round(($times | Measure-Object -Average).Average, 1) } else { $null }); Failed = 2 - $times.Count }
        }
        catch { }
        $h.Quality = $q
    }
    Send $h
}

if ($Op -eq 'bigfiles') {
    # Cleanup: the largest files in your folders (Arg.Folders), at least Arg.MinBytes, the biggest Arg.Top. Files
    # that live only in OneDrive (not downloaded) are skipped, so nothing is fetched from the cloud.
    $found = New-Object Collections.Generic.List[object]
    # Offline, RecallOnOpen and RecallOnDataAccess, as numbers (Windows PowerShell won't cast the last two to FileAttributes)
    $cloud = 0x1000 -bor 0x40000 -bor 0x400000
    foreach ($root in @($Arg.Folders)) {
        if (-not $root -or -not (Test-Path -LiteralPath $root)) { continue }
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($root)
        while ($stack.Count) {
            $d = $stack.Pop()
            try {
                $di = New-Object IO.DirectoryInfo $d
                foreach ($f in $di.GetFiles()) {
                    if ($f.Length -lt $Arg.MinBytes -or ([int]$f.Attributes -band $cloud)) { continue }
                    $found.Add(@{ Path = $f.FullName; Name = $f.Name; Folder = $f.DirectoryName; Bytes = [long]$f.Length; Modified = $f.LastWriteTime.ToString('yyyy-MM-dd') })
                }
                foreach ($s in $di.GetDirectories()) { if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint) -and $s.Name -notmatch '^(AppData|\.git|node_modules)$') { $stack.Push($s.FullName) } }
            }
            catch { }
        }
    }
    Send @{ T = 'bigfiles'; Files = @($found | Sort-Object { $_.Bytes } -Descending | Select-Object -First $Arg.Top) }
}

if ($Op -eq 'cleanscan') {
    # Clean up: how much each item takes (Arg.Items: Key, Paths, OlderDays, Skip, Recycle), one event per item
    foreach ($it in @($Arg.Items)) {
        $total = [long]0; $unreadable = $false
        if ($it.Recycle) {
            try {
                $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                foreach ($dr in [IO.DriveInfo]::GetDrives()) { if ($dr.DriveType -eq 'Fixed' -and $dr.IsReady) { $v = Measure-CleanPath (Join-Path $dr.RootDirectory.FullName "`$Recycle.Bin\$sid") 0 @(); if ($v -gt 0) { $total += $v } } }
            }
            catch { }
        }
        foreach ($p in @($it.Paths)) { $v = Measure-CleanPath $p ([int]$it.OlderDays) @($it.Skip); if ($v -lt 0) { $unreadable = $true } else { $total += $v } }
        Send @{ T = 'cleansize'; Key = $it.Key; Bytes = $(if ($unreadable -and -not $total) { [long]-1 } else { $total }) }
    }
    Send @{ T = 'cleanscandone' }
}

if ($Op -eq 'clean') {
    # Clean up, for the items that don't need administrator rights (Arg.Items as for cleanscan)
    foreach ($it in @($Arg.Items)) {
        $freed = [long]0; $failed = 0
        if ($it.Recycle) {
            try {
                $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
                foreach ($dr in [IO.DriveInfo]::GetDrives()) { if ($dr.DriveType -eq 'Fixed' -and $dr.IsReady) { $v = Measure-CleanPath (Join-Path $dr.RootDirectory.FullName "`$Recycle.Bin\$sid") 0 @(); if ($v -gt 0) { $freed += $v } } }
                Clear-RecycleBin -Force -ErrorAction Stop
            }
            catch { $failed++ }
        }
        foreach ($p in @($it.Paths)) { $r = Remove-CleanPath $p ([int]$it.OlderDays) @($it.Skip); $freed += $r.Freed; $failed += $r.Failed }
        Write-Log "Clean up: $($it.Key) freed $([Math]::Round($freed / 1MB)) MB$(if ($failed) { " ($failed in use or protected, left alone)" })"
        Send @{ T = 'cleaned'; Key = $it.Key; Freed = $freed; Failed = $failed }
    }
    Send @{ T = 'cleandone' }
}

if ($Op -eq 'diag') {
    # Diagnostics: copies the files in Arg.Files (skipping missing ones; files in use are read shared) into a folder,
    # adds Arg.Text as system.txt with details read here, and zips it to Arg.Zip
    try {
        $stage = Join-Path ([IO.Path]::GetTempPath()) ("wsm-diag-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        $lines = New-Object Collections.Generic.List[string]
        foreach ($l in @($Arg.Text)) { $lines.Add([string]$l) }
        $lines.Add('')
        try {
            $os = Get-CimInstance Win32_OperatingSystem; $cs = Get-CimInstance Win32_ComputerSystem; $bios = Get-CimInstance Win32_BIOS
            $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $lines.Add("Windows:     $($os.Caption) $($cv.DisplayVersion), build $($cv.CurrentBuildNumber).$($cv.UBR), $($os.OSArchitecture), language $((Get-Culture).Name)")
            $lines.Add("PC:          $($cs.Manufacturer) $($cs.Model), serial $($bios.SerialNumber), BIOS $($bios.SMBIOSBIOSVersion)")
            $lines.Add("Started:     $($os.LastBootUpTime)   Memory: $([Math]::Round($cs.TotalPhysicalMemory / 1GB)) GB   Domain/workgroup: $($cs.Domain)")
            foreach ($g in @(Get-CimInstance Win32_VideoController)) { $lines.Add("Graphics:    $($g.Name), driver $($g.DriverVersion) ($($g.DriverDate))") }
            foreach ($p in @(Get-CimInstance Win32_Processor)) { $lines.Add("Processor:   $(($p.Name -replace '\s+', ' ').Trim())") }
        }
        catch { $lines.Add("Couldn't read system details: $($_.Exception.Message)") }
        try {
            $lines.Add(''); $lines.Add('Windows Update policy keys:')
            foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU', 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update') {
                $v = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
                if ($v) { foreach ($pp in $v.PSObject.Properties) { if ($pp.Name -notlike 'PS*') { $lines.Add("  $k\$($pp.Name) = $($pp.Value)") } } }
            }
        }
        catch { }
        [IO.File]::WriteAllLines((Join-Path $stage 'system.txt'), [string[]]$lines, (New-Object Text.UTF8Encoding($false)))
        foreach ($f in @($Arg.Files)) {
            if (-not $f.From -or -not (Test-Path -LiteralPath $f.From -PathType Leaf)) { continue }
            $to = Join-Path $stage $f.To
            New-Item -ItemType Directory -Path (Split-Path -Parent $to) -Force | Out-Null
            try {
                $in = [IO.File]::Open($f.From, 'Open', 'Read', 'ReadWrite, Delete')
                try { $out = [IO.File]::Create($to); try { $in.CopyTo($out) } finally { $out.Close() } } finally { $in.Close() }
            }
            catch { Add-Content -LiteralPath (Join-Path $stage 'skipped.txt') -Value "$($f.From): $($_.Exception.Message)" }
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $Arg.Zip) { Remove-Item -LiteralPath $Arg.Zip -Force }
        [IO.Compression.ZipFile]::CreateFromDirectory($stage, $Arg.Zip)
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        Send @{ T = 'diag'; Zip = $Arg.Zip; Error = $null }
    }
    catch { Send @{ T = 'diag'; Error = $_.Exception.Message } }
}

if ($Op -eq 'leftovers') {
    # What an uninstalled app (Arg.Name, Arg.Id) left behind: folders named after it in AppData, ProgramData and the
    # Program Files folders (also inside a folder named after its publisher), its scheduled tasks, and startup entries
    # whose program is gone. Only exact name matches count, and folders a running program uses are left out.
    $norm = { param($s) (([string]$s).ToLowerInvariant() -replace '\(.*?\)', '' -replace '\b\d+(\.\d+)+\b', '' -replace '[^a-z0-9]', '') }
    $names = New-Object System.Collections.Generic.HashSet[string]
    $nm = & $norm $Arg.Name
    if ($nm.Length -ge 4) { [void]$names.Add($nm) }
    $idParts = @(([string]$Arg.Id) -split '\.' | Where-Object { $_ })
    $vendor = ''
    if ($Arg.Id -notmatch '^(ARP|MSIX)\\' -and $idParts.Count -ge 2) {
        $vendor = & $norm $idParts[0]
        $last = & $norm $idParts[-1]
        if ($last.Length -ge 4) { [void]$names.Add($last) }
        $joined = & $norm ($idParts[1..($idParts.Count - 1)] -join '')
        if ($joined.Length -ge 4) { [void]$names.Add($joined) }
    }
    $skip = 'microsoft|windows|common files|packages|temp|programs|google|mozilla|nvidia|intel|dell|hp|lenovo|asus|adobe|java|nuget|npm|pip'
    $running = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Path } catch { } } | Where-Object { $_ })
    $found = New-Object System.Collections.Generic.List[object]
    $roots = @(
        @{ Path = $env:LOCALAPPDATA; Admin = $false }, @{ Path = (Join-Path $env:LOCALAPPDATA 'Programs'); Admin = $false }, @{ Path = $env:APPDATA; Admin = $false },
        @{ Path = $env:ProgramData; Admin = $true }, @{ Path = $env:ProgramFiles; Admin = $true }, @{ Path = ${env:ProgramFiles(x86)}; Admin = $true })
    $consider = {
        param($dir, $admin)
        if ($running | Where-Object { $_.StartsWith($dir.FullName + '\', [StringComparison]::OrdinalIgnoreCase) }) { return }
        $size = [long]0; try { foreach ($f in $dir.EnumerateFiles('*', 'AllDirectories')) { $size += $f.Length } } catch { }
        $found.Add(@{ Kind = 'folder'; Path = $dir.FullName; Size = $size; Admin = $admin })
    }
    foreach ($r in $roots) {
        if (-not $r.Path -or -not (Test-Path -LiteralPath $r.Path)) { continue }
        foreach ($d in @(try { (New-Object IO.DirectoryInfo $r.Path).GetDirectories() } catch { })) {
            $dn = & $norm $d.Name
            if ($names.Contains($dn) -and $d.Name -notmatch "^($skip)$") { & $consider $d $r.Admin }
            elseif ($vendor -and $dn -eq $vendor) {
                foreach ($s in @(try { $d.GetDirectories() } catch { })) { if ($names.Contains((& $norm $s.Name))) { & $consider $s $r.Admin } }
            }
        }
    }
    # scheduled tasks named after it (outside Windows' own)
    try {
        $svc = New-Object -ComObject Schedule.Service; $svc.Connect()
        $folders = New-Object System.Collections.Generic.Stack[object]; $folders.Push($svc.GetFolder('\'))
        while ($folders.Count) {
            $fo = $folders.Pop()
            foreach ($sub in @($fo.GetFolders(0))) { if ($sub.Path -notlike '\Microsoft*') { $folders.Push($sub) } }
            foreach ($t in @($fo.GetTasks(1))) {
                $tn = & $norm $t.Name
                if (@($names | Where-Object { $tn.Contains($_) }).Count) { $found.Add(@{ Kind = 'task'; Path = [string]$t.Path; Size = 0; Admin = $true }) }
            }
        }
    }
    catch { }
    # startup entries named after it whose program no longer exists
    foreach ($k in @(@{ Hive = 'CurrentUser'; Admin = $false }, @{ Hive = 'LocalMachine'; Admin = $true })) {
        try {
            $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($k.Hive, 'Registry64')
            $run = $base.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run')
            if ($run) {
                foreach ($v in $run.GetValueNames()) {
                    $cmd = [Environment]::ExpandEnvironmentVariables([string]$run.GetValue($v))
                    $exe = if ($cmd.StartsWith('"')) { $cmd.Substring(1).Split('"')[0] } elseif ($cmd -match '^(.+?\.exe)') { $Matches[1] } else { '' }
                    $vn = & $norm $v
                    if ($exe -and -not (Test-Path -LiteralPath $exe) -and @($names | Where-Object { $vn.Contains($_) -or (& $norm $exe).Contains($_) }).Count) {
                        $found.Add(@{ Kind = 'run'; Path = "$($k.Hive)\$v"; Hive = $k.Hive; Value = $v; Size = 0; Admin = $k.Admin })
                    }
                }
                $run.Close()
            }
            $base.Close()
        }
        catch { }
    }
    Send @{ T = 'leftovers'; Name = $Arg.Name; Id = $Arg.Id; Items = $found.ToArray() }
}

if ($Op -eq 'removeleftovers') {
    # Your own leftovers (Arg.Items): folders to the Recycle Bin, startup entries deleted
    Add-Type -AssemblyName Microsoft.VisualBasic
    foreach ($it in @($Arg.Items)) {
        $ok = $true; $why = ''
        try {
            if ($it.Kind -eq 'folder') { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, 'OnlyErrorDialogs', 'SendToRecycleBin') }
            elseif ($it.Kind -eq 'run') { $b = [Microsoft.Win32.RegistryKey]::OpenBaseKey($it.Hive, 'Registry64'); $r = $b.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Run', $true); $r.DeleteValue($it.Value); $r.Close(); $b.Close() }
        }
        catch { $ok = $false; $why = $_.Exception.Message }
        Send @{ T = 'leftoverdone'; Path = $it.Path; Ok = $ok; Error = $why }
    }
    Send @{ T = 'leftoversdone' }
}

if ($Op -eq 'appxlist') {
    # Built-in apps: your Store packages that Windows lets you remove (not frameworks, not parts of Windows itself),
    # with the names their manifests give them
    $items = New-Object Collections.Generic.List[object]
    $err = $null
    # manifests often name a resource ("ms-resource:AppName") instead of the text; Windows resolves it from the package
    if (-not ('WingetUM.Res' -as [type])) { Add-Type -Namespace WingetUM -Name Res -MemberDefinition '[DllImport("shlwapi.dll", CharSet=CharSet.Unicode)] public static extern int SHLoadIndirectString(string src, System.Text.StringBuilder buf, int cch, IntPtr r);' }
    $resolve = {
        param($p, [string]$s)
        if ($s -notlike 'ms-resource:*') { return $s.Trim() }
        $k = $s.Substring(12)
        $uri = if ($k -like '//*') { "ms-resource:$k" } elseif ($k -like '/*') { "ms-resource://$($p.Name)$k" } else { "ms-resource://$($p.Name)/resources/$k" }
        $sb = New-Object Text.StringBuilder 1024
        if ([WingetUM.Res]::SHLoadIndirectString("@{$($p.PackageFullName)?$uri}", $sb, 1024, [IntPtr]::Zero) -eq 0) { return $sb.ToString().Trim() }
        return ''
    }
    try {
        Import-Module Appx -ErrorAction SilentlyContinue
        foreach ($p in @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction Stop | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -in 'Store', 'System' })) {
            $display = ''; $pub = ''; $desc = ''
            try {
                $man = Get-AppxPackageManifest -Package $p.PackageFullName
                $display = & $resolve $p ([string]$man.Package.Properties.DisplayName)
                $pub = & $resolve $p ([string]$man.Package.Properties.PublisherDisplayName)
                # the description Start and the Store show, else the package's own
                foreach ($d in @(@($man.Package.Applications.Application | ForEach-Object { [string]$_.VisualElements.Description }) + [string]$man.Package.Properties.Description)) {
                    if (-not $d) { continue }
                    $desc = & $resolve $p $d
                    if ($desc) { break }
                }
            }
            catch { }
            if (-not $display) { $display = ($p.Name -replace '^[^.]+\.', '' -creplace '([a-z])([A-Z])', '$1 $2') }
            $items.Add(@{ Name = $display; Package = [string]$p.Name; Full = [string]$p.PackageFullName; Family = [string]$p.PackageFamilyName; Location = [string]$p.InstallLocation; Publisher = $pub; Version = [string]$p.Version; Description = $desc })
        }
    }
    catch { $err = $_.Exception.Message }
    Send @{ T = 'appxlist'; Items = $items.ToArray(); Error = $err }
}

if ($Op -eq 'appxchange') {
    # Removes a built-in app for you (Arg.Full), or registers it again from its install folder (Arg.Location)
    try {
        Import-Module Appx -ErrorAction SilentlyContinue
        if ($Arg.Remove) { Remove-AppxPackage -Package $Arg.Full -ErrorAction Stop }
        else {
            $man = Join-Path ([string]$Arg.Location) 'AppxManifest.xml'
            if (-not $Arg.Location -or -not (Test-Path -LiteralPath $man)) { throw 'its files are gone from this PC' }
            Add-AppxPackage -DisableDevelopmentMode -Register $man -ErrorAction Stop
        }
        Send @{ T = 'appxchanged'; Key = $Arg.Key; Remove = [bool]$Arg.Remove; Error = $null }
    }
    catch { Send @{ T = 'appxchanged'; Key = $Arg.Key; Remove = [bool]$Arg.Remove; Error = ($_.Exception.Message -split "`n")[0] } }
}

if ($Op -eq 'features') {
    # Windows' optional features (Win32_OptionalFeature, which needs no administrator rights to read):
    # InstallState 1 on, 2 off, 3 not available
    try {
        $items = @(Get-CimInstance Win32_OptionalFeature -ErrorAction Stop | ForEach-Object { @{ Name = [string]$_.Name; Caption = [string]$_.Caption; State = [int]$_.InstallState } })
        Send @{ T = 'features'; Items = $items; Error = $null }
    }
    catch { Send @{ T = 'features'; Items = @(); Error = $_.Exception.Message } }
}

if ($Op -eq 'featuredesc') {
    # The descriptions of optional features (Arg.Names) from Windows (Get-WindowsOptionalFeature: administrator only)
    $found = @{}
    try {
        Import-Module Dism -ErrorAction Stop
        foreach ($n in @($Arg.Names)) {
            # '' when Windows has none, so it isn't asked again
            try { $d = [string](Get-WindowsOptionalFeature -Online -FeatureName $n -ErrorAction Stop).Description; $found[$n] = ($d.Trim() -replace '\s+', ' ') } catch { }
        }
    }
    catch { }
    Send @{ T = 'featuredesc'; Items = $found }
}
'@

# Changelog

All notable changes to Windows Manager (called Windows Software Manager in 2.0, and Windows Package Manager before
1.0). The version is `$AppVersion` in `src\00-Startup.ps1`, which Build-Exe.ps1 also stamps on the exe.

## 2.4.3.1 - 2026-10-02

- **"What's new" in the update prompt no longer starts with odd characters.** Release notes are published without
  the hidden marker that caused them, the app reads them as UTF-8, and notes of earlier releases show cleanly too.
- `CLAUDE.md`: setting up a new PC, the two questions asked before publishing (publish? release?), how `main` is
  protected and how pull requests are merged.

## 2.4.3.0 - 2026-10-02

- **Nicer trend charts on Device Health.** Each line has a soft fill under it and a faint baseline. Hover anywhere on
  a chart: a guide line snaps to the nearest day and shows that day's value and date, so there's no need to aim at
  the line. Beside each chart, the latest value is in bold and the change since the first reading has an arrow, in
  green when it's good news (more free space, fewer crashes) and red when it isn't.

## 2.4.2.1 - 2026-10-02

- **Administrator steps run only what the app wrote.** Before each step that needs administrator approval (driver
  updates, Windows updates, Windows features, startup changes, cleanup, uninstall leftovers), the app writes the
  step's script to `%LOCALAPPDATA%\WindowsManager\Drivers`, a folder any program you run can change. Another program
  could have changed the script before you approved it, and your approval would then have run its code. Now the
  approved step checks that the script is exactly what the app wrote, and runs only that; a changed script doesn't
  run, and the log says so. The scripts and logs are still kept there to read afterwards.
- **About** (the **i** button) links to the source code on GitHub, under the contact email.

## 2.4.2.0 - 2026-10-02

- **Automatic updates run a protected copy.** When automatic updates run elevated (the default), the scheduled task
  now runs a copy of the app in `C:\Program Files\Windows Manager`, which only administrators can change. Before, it
  ran the app from wherever it was (such as Downloads), so another program could have swapped the app there and been
  started as administrator without anyone approving. Saving the schedule makes the copy (with the approval saving
  already needed). After the app updates itself, it offers to update the copy too; until then automatic runs keep
  using the older one. A task set up by an earlier version is offered the move once, and the Automatic updates panel
  says when the copy needs it. Turning automatic updates off removes the copy.
- Notification buttons keep opening the copy you use, not the protected copy.

## 2.4.1.0 - 2026-10-01

- **Windows Features describes what everything is.** Each optional feature has Windows' own description under its
  name (for example "Transfer files using the Trivial File Transfer Protocol" for TFTP Client), and each built-in app
  the description its package gives Start and the Store. Hover for the whole text; the filter searches descriptions
  too. Features this version doesn't know (from newer Windows builds) are read from Windows when the app runs as
  administrator, and remembered.
- Built-in apps show the names and publishers their packages give, where they were a guess before (for example
  *Microsoft News* rather than *Bing News*).
- `CLAUDE.md`: how to contribute, step by step, for people and for Claude Code.

## 2.4.0.0 - 2026-10-01

- **Network health.** Device Health's Network card measures the connection: the round trip to the router, latency,
  packet loss and jitter to the internet, and how long a DNS lookup takes, each green, amber or red, and its title
  says Good, Fair or Poor connection. Internet latency is kept in the daily reading and gets a line on **Trends**.
- Brandon Bolding is credited as a contributor (README and About).

## 2.3.0.0 - 2026-10-01

- **Windows Features tab** (Ctrl+8; Cleanup moves to Ctrl+9). **Built-in apps**: the Store apps Windows lets you
  remove, with their publisher; **Remove** removes one for your account, and removed apps stay listed with
  **Reinstall** (registered again from their files, or their Microsoft Store page when those are gone). **Optional
  features**: every optional feature, on or off, with **Turn on** / **Turn off** (one administrator approval, a restore
  point first, and a note when a restart is needed). Filter, and **On only**.
- **Uninstall leftovers.** After an uninstall from Installed Software, the app looks for folders named after the app
  (or inside its publisher's folder) in AppData, ProgramData and Program Files, its scheduled tasks, and startup
  entries whose program is gone, and lists them ticked. **Remove ticked** sends folders to the Recycle Bin; anything
  outside your profile needs one approval. Folders a running program uses are never listed.
- **Health trends.** Device Health keeps one reading a day (battery health, free space, stability index, app crashes,
  memory in use, drive wear) for 400 days, and a **Trends** card draws each over the last 90 days with its latest value
  and the change since the first reading.
- **Health alerts in automatic runs.** Automatic runs check the PC's health too and send a notification when
  something needs attention (antivirus or real-time protection off, old definitions, firewall off, a nearly full drive,
  a failing disk, a worn battery, blue screens, a restart waiting for days). Each is mentioned once, then weekly while
  it lasts. Options > Automatic runs > **Check the PC's health and tell me about problems** (on by default).
- **Health report.** Device Health > **Save report** writes the whole page as an HTML file on the desktop: every card,
  drives, waiting updates, startup apps and installed software.
- **Startup lists scheduled tasks** that start at sign-in or at startup (outside Windows' own), which Task Manager
  doesn't show, with Turn off / Turn on (disabling the task).
- **A safety net for updates.** After switching to a new version, the old copy waits, out of sight, until the new one
  has opened; if it closes or doesn't open within 90 seconds, the old exe is put back and carries on, and that version
  isn't offered again on start. The previous version is kept in `Previous\`, and Options > App updates > **Go back to
  <version>** switches back to it the same way.
- **Beta versions.** Options > App updates > **Get beta versions** offers GitHub pre-releases too.
- **One copy at a time.** Opening the app while it's open brings the open window to the front. Automatic runs,
  notification buttons and the log link aren't affected. Closing the window frees it straight away, even while
  background work is finishing.
- **GitHub Actions.** Every pull request is checked (ASCII only, parses, self-test) and built, with the exe attached
  to the run; pushing a `v<version>` tag builds and publishes the release with its CHANGELOG notes (a hyphenated tag
  becomes a pre-release). `tools\Test-Source.ps1` runs the same checks locally.
- **winget manifest.** `tools\New-WingetManifest.ps1` writes the manifest for a release (package
  `jdvieira.WindowsManager`, portable, command `windows-manager`) for a pull request to winget-pkgs; it passes
  `winget validate`.
- The tabs are a little tighter to fit nine, and the window opens a little wider (1280 x 820).
- **Fixed:** today's health reading wasn't saved when earlier readings existed.
- Tested as administrator on real hardware: restore point with System Protection off, saving a driver and forcing it
  back, an all-users startup app off and on, Windows temporary files cleanup, Dell Command | Update's check, disk wear
  and temperature, an optional feature on and off, re-registering a built-in app, leftovers, and both outcomes of a
  version switch.

## 2.2.0.2 - 2026-10-01

- **Fixed:** after an update, `Windows Manager.exe.old` was left next to the app. The new version tried to delete it
  while the old one was still closing; it now tries again every 2 seconds for a minute.
- The README has screenshots of Device Health, Installed Software, Drivers, Startup and Cleanup (in `docs/screenshots`;
  the PC's name, serial number and network details are replaced).
- The first update from 2.2.0.0 to 2.2.0.1 through GitHub worked end to end (download, checksum, version check,
  swap, restart, History).

## 2.2.0.1 - 2026-10-01

- **The release download is labeled "Windows Manager.exe".** GitHub doesn't allow spaces in release file names (it
  turns them into dots, so the file still downloads as `Windows.Manager.exe`), but each file can have a label, which
  is what the release page shows. Releases are now uploaded with that label. The in-app updater is unaffected: it
  always installs under the app's own name.
- First release published to test the updater end to end: copies on 2.2.0.0 find it and update themselves.

## 2.2.0.0 - 2026-10-01

- **Updates itself from GitHub.** On start the app reads the latest release on GitHub; when it's newer, it shows what's
  new and offers to update. Updating downloads the release's exe, checks GitHub's SHA-256 checksum and the file's
  version, swaps it in for the running exe (which becomes `.old` and is deleted on the next start) and restarts on the
  new version, with settings, history and the schedule unchanged. **Not now** skips that version. It waits while
  something is installing.
- **Options > App updates:** the version you have and the latest one, Check now, Update now, Release notes, and the
  switches *Check for a new version when the app opens* (on) and *Update without asking* (off).
- The update's steps go into the daily log as well as the log panel.

## 2.1.0.0 - 2026-10-01

- **Renamed to Windows Manager**, since it does much more than manage software: the exe is `Windows Manager.exe`, the
  data folder `%LOCALAPPDATA%\WindowsManager` (the old one moves across on first start) and the scheduled task
  *Windows Manager* (the app offers to move the old one). Notifications come from Windows Manager.
- **Device Health is the first tab, and where the app opens.** Besides the PC, BIOS, battery and drives, it now has
  Security (antivirus, real-time protection, definitions and last scan, firewall, BitLocker, Secure Boot, TPM,
  activation), Performance (memory, processor, the apps using the most memory, startup apps), Reliability (stability
  index, unexpected shutdowns, blue screens, app crashes, device problems), Updates (software, Windows and drivers
  waiting, and a waiting restart), Network (adapter, network and signal, speed, address, internet) and Cleanup cards.
  Each line has a green, amber, red or grey dot, and the top line says how many need a look. Cards are only as tall
  as what's in them, and the Drives list is compact.
- **Cleanup tab.** Clean up moved here from Health, with the system drive's space at the top, a new *Old downloads*
  item (off by default), **Large files** (the largest files over 100 MB in your folders, with Show and Delete to the
  Recycle Bin) and **Biggest apps** (with Uninstall).
- **Tabs renamed and reordered:** Device Health, Software Updates, Discover Software, Installed Software, Startup,
  Drivers, Windows Update, Cleanup (Ctrl+1 to Ctrl+8).
- **Fixed:** Diagnostics failed with "Cannot bind argument to parameter 'Path' because it is null" on a PC with no
  saved drivers.

## 2.0.0.0 - 2026-10-01

Three new tabs, safer driver changes, and the tools for setting up and supporting other PCs.

- **Startup tab.** Lists the apps that start when you sign in (Run keys, Startup folders, Store apps' startup tasks),
  named as Task Manager names them, with their publisher and where they start from. **Turn off** / **Turn on** use the
  same switch as Task Manager and Settings, so nothing is deleted; apps that start for every user ask for administrator
  approval.
- **Windows Update tab.** Windows' own updates (security and cumulative updates, .NET, Defender and more), installed
  through Windows Update one at a time in one administrator run, plus Windows Update's recent history, a **Restart now**
  button when a restart is waiting, and a note on PCs whose updates an organization manages. The tab shows how many
  updates are waiting.
- **Health tab.** The PC and Windows (with a note when a restart is waiting), the BIOS and whether the last driver check
  found a newer one, battery health and charge cycles (from Windows' battery report), each drive's free space and each
  disk's health. **Clean up** measures and deletes temporary files, winget downloads, the Recycle Bin, crash dumps,
  error reports, old driver files, Windows Update and Delivery Optimization files, and Dell, NVIDIA and AMD installer
  leftovers; Windows' items need one administrator approval.
- **Driver backups and Roll back.** Before the app removes, reinstalls or replaces a third-party driver (including the
  ones Windows Update and NVIDIA installs replace), it saves the current one. **Roll back** on the Devices list forces
  the saved driver back onto the device, after saving the current one. The newest two per device are kept.
- **Restore points that happen.** "Restore point first" is now remembered, skips Dell's scans (which change nothing),
  works more than once a day, and says in the log when System Protection is off. The Windows Update tab uses it too.
- **AMD graphics in Driver Updates.** The newest recommended Adrenalin driver, read from AMD's driver page, is listed
  when it's newer than the installed one. **Get installer** downloads AMD's installer, checks AMD's signature, and opens
  it (AMD doesn't document a silent install).
- **Apps Windows updates itself.** Edge, WebView2, Teams and Microsoft 365 are tagged *updated by Windows*, kept off the
  Updates list like hidden apps, and skipped by Update all and automatic updates. Any app whose winget update fails
  with "the install technology is different" joins them. Right-click > Let winget update it undoes that for one app;
  Options > Packages lists them.
- **Windows notifications.** Automatic runs now notify through Windows (the notification stays in the notification
  center, with Open and View log buttons). The app's own pop-up remains as an option, and is used when Windows
  notifications are off for the app.
- **Set up a new PC.** Options > Maintenance > **Back up this PC's setup** saves the apps, hidden apps, options and
  schedule in one file (to OneDrive when it's set up); winget import reads it too. **Set up from a backup** (or Import
  list) lists the apps with the missing ones ticked, then fills in the options to review and save.
- **Diagnostics.** A button at the bottom right (and in Options > Logs) saves a zip to the desktop with the app's logs,
  the administrator runs' scripts and logs, winget's logs, settings, history and a summary of the PC.
- **Source in parts.** The code moved from one 6,000-line script into `src\*.ps1`. `Windows_Software_Manager.ps1` now
  joins them and runs the result (exactly as the exe runs); Build-Exe.ps1 joins the same parts.
- `TESTING.md` lists what to try on real PCs. Ctrl+1 to Ctrl+7 switch tabs. History's driver lines read "Driver update"
  rather than "Dell updates".

## 1.1.0.1 - 2026-10-01

- **Header fits.** The line under the title ran under the Options button. It now reads "Apps and drivers on <PC>",
  the version sits beside the title, and the line shortens with "..." if the window is too narrow.

## 1.1.0.0 - 2026-10-01

- **NVIDIA drivers in Driver Updates.** On PCs with NVIDIA graphics, the tab asks NVIDIA for the newest Game Ready
  driver for the card (desktop and laptop cards each get their own package) and lists it, at the top, when it's newer
  than the installed driver. It installs in the same administrator run as the others: NVIDIA's package is downloaded
  with progress in the log, installed only when its NVIDIA signature is valid, run silently without a restart, and
  checked afterwards by reading the driver version back. Results go into History.
  The NVIDIA App and Intel Driver & Support Assistant have no command line or interface another app can drive, so
  the lookup goes to NVIDIA's own driver service. NVIDIA doesn't document that service; if it stops answering, the tab
  says so and the NVIDIA App can still check. Studio drivers aren't offered.
## 1.0.1.0 - 2026-10-01

- **Managed driver updates.** On a PC whose organization manages driver updates (Windows Update for Business through
  Intune, an update server, or a policy excluding drivers), Settings only shows the drivers IT has approved, while
  Driver Updates lists every driver Windows Update has for the hardware, so the two didn't match. The tab now notes
  this, leaves those drivers unticked, and says so again before installing any.
- **Dell's saved results.** When Dell Command | Update answers a check from its cache instead of asking Dell again,
  the "up to date" message says so.
- **Busy or stalled Dell checks.** A Dell check, install or driver restore isn't started while an earlier dcu-cli.exe
  is still running or Dell Command | Update's window is open (the tab says which). A run that makes no progress for 5
  minutes says so above the list, with **Stop waiting**; the run carries on in the background.
## 1.0.0.0 - 2026-09-30

Initial release.

- **Updates**: every app winget can upgrade, with installed and available versions and the source. Update one app,
  the selected apps or all of them from a queue (more can be added while one runs; Stop after current app cancels the
  rest), with per-app status, download progress and taskbar progress. **What's new** shows each update's release
  notes. **Hide (keep at this version)** takes an app off the list and pins it with winget, so nothing updates it
  (Update all, automatic updates or winget itself) until you unhide it; **Show hidden** brings hidden apps back into
  view.
- **Discover**: a starter list of about 50 popular apps by category, and winget search over everything else. Versions
  and descriptions fill in in the background (8 lookups at a time, remembered for next time). Install one app, the
  selected apps, for all users, interactively, or a specific version (optionally kept there). **Import list** opens an
  app list (from Export list, `winget export` or a text file of IDs) with the missing apps selected.
- **Installed**: everything installed on the PC, with a sortable size on disk (from Windows' uninstall entries, and
  measured for Store apps) and a total; uninstall with a confirmation (one copy at a time when a package is installed
  more than once); **Export list** in winget's export format.
- **Drivers**: the PC's vendor, model, serial number and BIOS. **Driver Updates** lists Windows Update's driver and
  firmware updates (checked when the tab opens) and, on Dell and Alienware PCs, Dell Command | Update's BIOS, firmware,
  driver and app updates; everything picked installs in one run with one administrator approval. The vendor's own
  driver tool is offered for install from a catalogue of vendors (Dell, HP, Lenovo, ASUS, MSI, Acer, Samsung, Surface,
  Razer, Gigabyte, ASRock, Dynabook, Framework; home-built PCs by their motherboard), plus Intel, NVIDIA and AMD tools
  for the PC's chips. **Driver downloads** opens the vendor's driver page. Every device is listed with its driver;
  reinstall one (pnputil) or remove a third-party driver, with an optional restore point first.
- **Automatic updates**: a scheduled task that installs updates silently (a notification only when something fails,
  optionally for restarts or after every run) or just lists what's available. Daily or weekly, optionally elevated,
  with a retry, a restore point, and network, power, delay and time-limit conditions. Test notification runs a real
  check without installing.
- **History** of every install, update, uninstall, hide and driver change, from the app and from automatic runs,
  filterable and kept for a year.
- **Options**: sources to search and check (and adding, removing or switching winget sources), install scope, silent
  installs, unknown versions, uninstall previous versions, check on open, the hidden apps list, automatic-run
  conditions, log retention and folder, verbose winget logs, winget maintenance, and exporting or importing all
  settings with the schedule.
- Runs as the signed-in user, with **Restart as administrator** for a session without prompts. Daily logs, a live log
  panel, keyboard shortcuts (Ctrl+1 to Ctrl+4, Ctrl+F, F5, Esc) and an About panel.
- Moves settings, data and the scheduled task over from the app's development builds (Windows Package Manager, Winget
  Manager, Winget Package Manager, Winget Update Manager).
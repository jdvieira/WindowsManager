# Testing on real PCs

Some parts of the app can only be confirmed on a real PC, by someone approving the administrator prompt, or on
particular hardware. They are listed here with what should happen. Everything else is covered by the self-tests in the
README.

When something goes wrong, click **Diagnostics** (bottom right) and keep the zip. Every administrator step also leaves
a script and its log in `%LOCALAPPDATA%\WindowsManager\Drivers`.

Tick each line once it has worked, with the PC and the date.

## Any PC

| Done | Test | Expect |
| --- | --- | --- |
| [ ] | Windows Update tab: install one small update (a Defender definition update is ideal) | One approval; the log shows "Downloading 1 of 1" and "Installing 1 of 1"; the row goes away after the check that follows; History has a *Windows update* line |
| [ ] | Windows Update tab: **Restart now** when a restart is waiting | Asks first, then Windows restarts after 15 seconds |
| [ ] | Drivers > Driver Updates: install one Windows Update driver | One approval; a restore point line in the log ("Restore point created."), then "Saved the current driver ..." when the device used a third-party driver; History has the result |
| [x] Dell laptop, 2026-10-01 (a saved driver forced back onto its device) | Drivers > Devices: **Roll back** on that device | Asks first; the device goes back to the saved version (the list shows it after a few seconds); History has *Rolled back driver* |
| [ ] | Drivers > Devices: **Reinstall** on a harmless device (a webcam or card reader) | The device drops out for a moment and comes back with the same driver |
| [ ] | Drivers > Devices: **Remove** on a third-party driver you can do without | "Saved the current driver" first; the device falls back to another driver; **Roll back** then brings it back |
| [x] Dell laptop, 2026-10-01 | Restore point with System Protection turned off | The run continues; its log says System Protection is off |
| [ ] | Startup: turn off an app that starts for you, sign out and in | It doesn't start; Task Manager's Startup apps page shows it as Disabled |
| [x] Dell laptop, 2026-10-01 (registry checked, not Task Manager) | Startup: turn off an app with a shield (starts for everyone) | One approval; Task Manager shows it as Disabled |
| [x] Dell laptop, 2026-10-01 | Cleanup > Clean up with a shield item ticked (Windows temporary files) | One approval; each item shows what it freed; History has a *Cleaned up* line |
| [ ] | Cleanup > Clean up > Windows Update downloads | Windows Update still works afterwards (check the Windows Update tab) |
| [ ] | Cleanup > Large files > **Delete** on a file you don't need | Asks first; the file goes to the Recycle Bin (and can be restored from there) |
| [ ] | First start after the rename to Windows Manager | Settings, history and saved drivers are still there; the app offers to move the old scheduled task; **Test run** shows *Windows Manager* as the sender |
| [x] 2026-10-01 (2.2.0.0 to 2.2.0.1) | After the next release is published, open the older exe | The update prompt shows the new version and its notes; **Update now** restarts on the new version and History has the update; the `.old` file is gone |
| [ ] | With an elevated schedule made by 2.4.1.0 or earlier, open 2.4.2.0 | It offers **Protect automatic maintenance**; one approval; `C:\Program Files\Windows Manager\Windows Manager.exe` appears and Task Scheduler's *Windows Manager* task runs it; the panel says it runs a protected copy |
| [ ] | Automatic maintenance > **Run now** with the protected copy | The run works as before (History, lastrun.json); the notification's **Open Windows Manager** opens your own copy, not the one in Program Files |
| [ ] | After the app updates itself, with an elevated schedule | It offers **Update the copy automatic maintenance uses**; one approval; the copy's version (file properties) matches |
| [ ] | Automatic maintenance: turn off and **Save** | One approval; the task and `C:\Program Files\Windows Manager` are gone |
| [ ] | Options > App updates > **Update without asking**, then open an older exe | It updates and restarts by itself, without a prompt |
| [ ] | Automatic maintenance > **Test run** | A Windows notification (not the pop-up) with **Open Windows Manager** and **View log** buttons; both work |
| [ ] | The first version with the Pulse icon | The taskbar, Start, the title bar, Alt+Tab and the header show the Pulse icon (a window with a heartbeat line), crisp at small sizes; the About window (**i**) still shows the V; **Automatic maintenance > Test run** shows the Pulse icon in its notification |
| [ ] | Device Health on a laptop or tablet | The Battery card shows (health, cycles, charge) beside This PC and BIOS, and Trends has a Battery health line; on a desktop neither shows, even if Windows reports a placeholder battery |
| [ ] | Turn off notifications for Windows Manager in Settings > System > Notifications, then **Test run** again | The app's own pop-up appears instead, listing each job and what it would do |
| [ ] | First start of 2.5 with a schedule set up by an earlier version, then open Automatic maintenance | App updates keeps your earlier choice (Do it for "Install updates", Tell me for "Just tell me"), every run; Health check is on (Tell me) unless you had turned it off in Options; Windows updates and Cleanup are Off |
| [ ] | Windows updates on **Do it** (elevated task), **Run now** when one is waiting (a Defender definition update is ideal) | It installs; History has a *Windows update* line marked automatic; a restart is never started, and when one is needed the notification says so |
| [ ] | Windows updates on **Do it** with **Run elevated** off | The panel warns before saving; the run lists the updates and its notification says installing needs Run elevated |
| [ ] | Cleanup on **Do it** with a shield item ticked (Windows temporary files), elevated task, **Run now** | Each ticked item is cleaned; History has a *Cleaned up* line marked automatic; the notification (with the summary switch on) shows what each freed |
| [ ] | Set a job to **Weekly**, **Run now** twice | The second run skips it; its log says it's not due yet and when it last ran |
| [ ] | Options > Maintenance > **Back up this PC's setup**, then **Set up from a backup** on a second PC | Discover lists the apps with the missing ones ticked; Options opens with the options and schedule filled in |
| [ ] | An app on Updates whose update fails with "install technology is different" | Its row turns *updated by Windows* and Update all skips it from then on |
| [ ] | **Diagnostics** | A zip on the desktop; Explorer opens with it selected |
| [x] Dell laptop, 2026-10-01 | Windows Features > Optional features: **Turn on** a harmless one (TFTP Client), then **Turn off** | One approval each; the row says Turned on / Turned off; History has both |
| [ ] | Windows Features: an optional feature that needs a restart (Windows Sandbox, Hyper-V) | The row says "Restart to finish" |
| [x] Dell laptop, 2026-10-01 (a made-up app folder) | Installed Software: uninstall an app that leaves folders behind | The leftovers list opens with its folders ticked; **Remove ticked** moves them to the Recycle Bin |
| [x] Dell laptop, 2026-10-01 | Startup lists scheduled tasks | Tasks that start at sign-in or startup appear as *Scheduled task* |
| [ ] | Startup: **Turn off** a scheduled task, then **Turn on** | Task Scheduler shows it Disabled, then Ready |
| [x] Dell laptop, 2026-10-01 | Device Health > **Save report** | An HTML file on the desktop with every card |
| [ ] | Device Health on the second day | The Trends card appears |
| [ ] | An automatic run with a health problem (turn the firewall off for a minute) | A notification about it; the next run doesn't repeat it |
| [x] Dell laptop, 2026-10-01 | Open the app twice | The second brings the first window to the front and closes |
| [x] Dell laptop, 2026-10-01 (temp copies) | An update whose new version closes straight away | The old version comes back with a message; History has the failure |
| [ ] | After an update from 2.3 on, Options > App updates > **Go back to <version>** | The previous version starts; History has *Went back to the previous version* |
| [ ] | **Get beta versions** with a pre-release published | It's offered, marked as a pre-release |
| [ ] | Device Health > **Fix my PC** with an app update and a Windows update waiting, the Recommended items ticked, **Fix** | One administrator approval; a restore point line in the log; the Windows update installs, then the apps update, then leftover files are cleaned; each item says how it went; History has *Fix my PC* |
| [ ] | **Fix my PC**: decline the administrator approval | The items with a shield say approval was declined; app updates and your own leftover files still go ahead |
| [ ] | **Fix my PC** with Repair Windows files and Optimize drives ticked | DISM then SFC run (10 to 20 minutes) and each drive is optimized; the log has the codes; the row points to CBS.log |
| [ ] | **Fix my PC** > Don't start an app when you sign in | The Startup tab shows it Off; signing out and in, it doesn't start |
| [ ] | Cleanup > **Windows' own cleanup** (Disk Cleanup) | One approval; it runs for a few minutes without a window; the row says what it freed; `StateFlags0077` values are gone from `HKLM\...\Explorer\VolumeCaches` afterwards |
| [ ] | Cleanup > **Windows component store** | DISM's component cleanup finishes (several minutes); installed updates are still listed under Settings > Windows Update > Update history > Uninstall updates |
| [ ] | Cleanup > **Old driver versions** on a PC with an older NVIDIA driver in the driver store | The log lists Removed and Kept lines; Device Manager still shows every device working; Drivers > Devices shows the same driver versions |
| [ ] | Cleanup > **Browser caches** with the browsers closed | Freed shown; the browsers open normally and stay signed in |
| [ ] | Extras > Speed > **High performance power plan**: Turn on, then **Restore** | One approval each; Control Panel > Power Options shows High performance, then the plan you had before |
| [ ] | Extras > System > **Turn off hibernation** on a PC where it's on, then **Restore** | hiberfil.sys goes, then comes back; Fast Startup follows |
| [ ] | Extras > Taskbar and Start > **Hide Widgets**, **Restart Explorer** | The Widgets button is gone; **Restore** brings it back |
| [ ] | Extras > Tweaks: **Turn on** Classic right-click menu, **Restart Explorer**, right-click a file | The full menu shows straight away; **Restore** (and Restart Explorer) brings back Windows 11's menu; History has both |
| [ ] | Extras > Tweaks: **Turn on** a Windows-wide one (Allow long file paths), then **Restore** | One approval each; Registry Editor shows LongPathsEnabled as it was before |
| [ ] | Extras: change three tweaks and add two desktop shortcuts (God Mode and Device Manager), then **Restore all** | One approval if a Windows-wide tweak is among them; every tweak is as it was and the shortcuts are gone from the desktop; `tweaks.json` is empty |
| [ ] | Extras > Shortcuts: **Open** each group's first shortcut, and God Mode | Each opens; on Windows Home, Group Policy says it's not on this PC |
| [ ] | Extras > Tweaks: **Turn on** Turn off mouse acceleration, sign out and in | Mouse settings shows Enhance pointer precision off; **Restore** and signing out again puts it back |

## Dell or Alienware

| Done | Test | Expect |
| --- | --- | --- |
| [x] Dell laptop, 2026-10-01 | Drivers: **Check for updates** | One approval; Dell's updates join the list (or "Dell has nothing newer") |
| [ ] | Install one Dell driver update | One approval; Dell's log in the Drivers folder; History has the result |
| [ ] | **Reinstall all drivers** (only when you mean it) | Dell's driver restore runs; a restart is usually needed |
| [ ] | A PC without Dell Command \| Update | Offered once when the Drivers tab opens; installs through winget; the check starts by itself afterwards |

## NVIDIA graphics

| Done | Test | Expect |
| --- | --- | --- |
| [ ] | Drivers > Driver Updates on a PC with an older NVIDIA driver | An NVIDIA row at the top with the newest Game Ready driver |
| [ ] | Install it | Download progress in the log, "Signed by NVIDIA Corporation", "Saved the current driver", a silent install (the screen may flicker), then "the driver is now <new version>" |
| [ ] | **Roll back** on the NVIDIA display adapter afterwards | The previous NVIDIA driver comes back |

## AMD Radeon graphics

| Done | Test | Expect |
| --- | --- | --- |
| [ ] | Drivers > Driver Updates on a PC with an older Adrenalin | An AMD row with the newest recommended version and the installed one (or "installed version unknown") |
| [ ] | **Get installer** | Download progress on the button, then AMD's installer opens; finishing it updates the driver; **Check again** then shows nothing newer |

## HP and Lenovo

| Done | Test | Expect |
| --- | --- | --- |
| [ ] | HP business PC without HP Image Assistant | Offered when the Drivers tab opens; installs; **Open HP Image Assistant** starts it |
| [ ] | HP home PC | **Get HP Support Assistant** opens HP's page |
| [ ] | Lenovo Think PC / Lenovo home PC | Lenovo System Update (winget) / Lenovo Vantage (Microsoft Store) offered, installed and opened |

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
| [ ] | Drivers > Devices: **Roll back** on that device | Asks first; the device goes back to the saved version (the list shows it after a few seconds); History has *Rolled back driver* |
| [ ] | Drivers > Devices: **Reinstall** on a harmless device (a webcam or card reader) | The device drops out for a moment and comes back with the same driver |
| [ ] | Drivers > Devices: **Remove** on a third-party driver you can do without | "Saved the current driver" first; the device falls back to another driver; **Roll back** then brings it back |
| [ ] | Restore point with System Protection turned off | The run continues; its log says System Protection is off |
| [ ] | Startup: turn off an app that starts for you, sign out and in | It doesn't start; Task Manager's Startup apps page shows it as Disabled |
| [ ] | Startup: turn off an app with a shield (starts for everyone) | One approval; Task Manager shows it as Disabled |
| [ ] | Cleanup > Clean up with a shield item ticked (Windows temporary files) | One approval; each item shows what it freed; History has a *Cleaned up* line |
| [ ] | Cleanup > Clean up > Windows Update downloads | Windows Update still works afterwards (check the Windows Update tab) |
| [ ] | Cleanup > Large files > **Delete** on a file you don't need | Asks first; the file goes to the Recycle Bin (and can be restored from there) |
| [ ] | First start after the rename to Windows Manager | Settings, history and saved drivers are still there; the app offers to move the old scheduled task; **Test notification** shows *Windows Manager* as the sender |
| [ ] | Automatic updates > **Test notification** | A Windows notification (not the pop-up) with **Open Windows Manager** and **View log** buttons; both work |
| [ ] | Turn off notifications for Windows Manager in Settings > System > Notifications, then **Test notification** again | The app's own pop-up appears instead |
| [ ] | Options > Maintenance > **Back up this PC's setup**, then **Set up from a backup** on a second PC | Discover lists the apps with the missing ones ticked; Options opens with the options and schedule filled in |
| [ ] | An app on Updates whose update fails with "install technology is different" | Its row turns *updated by Windows* and Update all skips it from then on |
| [ ] | **Diagnostics** | A zip on the desktop; Explorer opens with it selected |

## Dell or Alienware

| Done | Test | Expect |
| --- | --- | --- |
| [ ] | Drivers: **Check for updates** | One approval; Dell's updates join the list (or "Dell has nothing newer") |
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

# Windows Manager - Model (part of src\; see Windows_Manager.ps1)

# A small bindable class, so rows update in place as their state and progress change.
if (-not ('WingetUM.Package' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
namespace WingetUM {
    public class Package : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private string section = "updates", name = "", id = "", version = "", available = "", source = "", state = "", detail = "";
        private bool selected, explicitTarget, truncated, hidden, installed, selfUpdating;
        private string description = "", descState = "", category = "";
        private string pin = "", notes = "", notesUrl = "";
        private double progress = -1;
        private long sizeKb;

        // updates (winget upgrade), discover (search / starter list, to install) or installed (winget list, to uninstall)
        public string Section { get { return section; } set { section = value; Changed("Section", "Key", "Action", "ActionText", "CanUpdate", "InteractiveMenuText", "IsUpdates", "IsDiscover", "IsInstalledList"); } }
        // Installed can list one package ID several times (per architecture or version), so its rows include the version
        public string Key { get { return section + "|" + id + "|" + source + (section == "installed" ? "|" + version : ""); } }
        public string Action { get { return section == "discover" ? "install" : section == "installed" ? "uninstall" : "update"; } }
        public bool IsUpdates { get { return section == "updates"; } }
        public bool IsDiscover { get { return section == "discover"; } }
        public bool IsInstalledList { get { return section == "installed"; } }
        public string Name { get { return name; } set { name = value; Changed("Name"); } }
        public string Id { get { return id; } set { id = value; Changed("Id", "Key"); } }
        public string Version { get { return version; } set { version = value; Changed("Version", "Key"); } }
        // Updates and Installed: the available version. Discover: the search match or starter-list category.
        public string Available { get { return available; } set { available = value; Changed("Available", "HasAvailable", "DescriptionTip"); } }
        public bool HasAvailable { get { return !string.IsNullOrEmpty(available); } }
        public string Source { get { return source; } set { source = value; Changed("Source", "Key", "HasSource", "IsStore", "CanHold", "OffersHold"); } }
        public bool HasSource { get { return !string.IsNullOrEmpty(source); } }
        public bool Selected { get { return selected; } set { selected = value; Changed("Selected"); } }
        public bool ExplicitTarget { get { return explicitTarget; } set { explicitTarget = value; Changed("ExplicitTarget"); } }
        public bool Truncated { get { return truncated; } set { truncated = value; Changed("Truncated", "CanUpdate", "CanHold"); } }
        // In the Hidden list (Options). Hidden apps are kept at their version: see IsConcealed.
        public bool Hidden { get { return hidden; } set { hidden = value; Changed("Hidden", "IsConcealed", "HideMenuText", "CanUpdate", "ActionText", "IsWindowsUpdated", "ShowHiddenTag"); } }
        // Updated by Windows or by the app itself, not by winget (Edge, WebView2, ...): off the Updates list like a hidden
        // app, but not pinned, since winget isn't what updates it
        public bool SelfUpdating { get { return selfUpdating; } set { selfUpdating = value; Changed("SelfUpdating", "IsConcealed", "HideMenuText", "CanUpdate", "ActionText", "IsWindowsUpdated", "ShowHiddenTag"); } }
        public bool IsWindowsUpdated { get { return selfUpdating && !hidden && !IsHeld; } }
        public bool ShowHiddenTag { get { return IsConcealed && !IsWindowsUpdated; } }
        // Discover: a short description from winget show, fetched in the background ("", loading, ok, none) and cached
        public string Description { get { return description; } set { description = value; Changed("Description", "DescriptionTip"); } }
        public string DescState { get { return descState; } set { descState = value; Changed("DescState"); } }
        public string DescriptionTip { get { return string.IsNullOrEmpty(available) ? description : description + "\n\nMatched on " + available; } }
        public string Category { get { return category; } set { category = value; Changed("Category", "HasCategory"); } }
        public bool HasCategory { get { return !string.IsNullOrEmpty(category); } }
        public bool IsStore { get { return source == "msstore"; } }
        // Installed: size on disk as the app reports it to Windows (EstimatedSize in its uninstall entry), in KB
        public long SizeKB { get { return sizeKb; } set { sizeKb = value; Changed("SizeKB", "SizeText"); } }
        public string SizeText {
            get {
                if (sizeKb <= 0) return "";
                double mb = sizeKb / 1024.0;
                if (mb >= 1024) return (mb / 1024).ToString("0.0") + " GB";
                if (mb >= 10) return mb.ToString("0") + " MB";
                if (mb >= 1) return mb.ToString("0.0") + " MB";
                return sizeKb + " KB";
            }
        }
        // A winget pin ("" none, Blocking, Pinning, Gating). Held apps stay listed but this app never updates them.
        public string Pin { get { return pin; } set { pin = value ?? ""; Changed("Pin", "IsHeld", "IsConcealed", "CanUpdate", "ActionText", "HideMenuText", "IsWindowsUpdated", "ShowHiddenTag"); } }
        public bool IsHeld { get { return !string.IsNullOrEmpty(pin); } }
        // Hidden: kept at this version. Off the Updates list (unless Show hidden), and nothing updates it: not this app,
        // not automatic updates, and (through a blocking pin) not winget itself. A pin set elsewhere counts too.
        public bool IsConcealed { get { return hidden || IsHeld || selfUpdating; } }
        public bool OffersHold { get { return section != "discover"; } }
        public bool CanHold { get { return OffersHold && !IsBusy; } }
        public string HideMenuText { get { return IsWindowsUpdated ? "Let winget update it" : IsConcealed ? "Unhide (allow updates again)" : "Hide (keep at this version)"; } }
        // Updates: release notes of the available version (winget show), fetched in the background
        public string Notes { get { return notes; } set { notes = value ?? ""; Changed("Notes", "HasNotes", "NotesTip"); } }
        public string NotesUrl { get { return notesUrl; } set { notesUrl = value ?? ""; Changed("NotesUrl", "HasNotes", "NotesTip"); } }
        public bool HasNotes { get { return !string.IsNullOrEmpty(notes) || !string.IsNullOrEmpty(notesUrl); } }
        public string NotesTip {
            get {
                if (string.IsNullOrEmpty(notes)) return "Release notes: " + notesUrl;
                string s = notes.Length > 700 ? notes.Substring(0, 700) + (char)0x2026 : notes;
                return s + "\n\nClick for everything that changed.";
            }
        }
        // Discover: already on this PC
        public bool IsInstalled { get { return installed; } set { installed = value; Changed("IsInstalled", "CanUpdate", "ActionText"); } }
        // "" (idle), queued, running, ok, reboot, skipped, error, cancelled
        public string State { get { return state; } set { state = value; Changed("State", "IsBusy", "IsDone", "CanUpdate", "ActionText", "HasState", "CanHold"); } }
        public bool HasState { get { return !string.IsNullOrEmpty(state); } }
        public string Detail { get { return detail; } set { detail = value; Changed("Detail"); } }
        public double Progress { get { return progress; } set { progress = value; Changed("Progress", "IsIndeterminate"); } }
        public bool IsIndeterminate { get { return progress < 0; } }
        public bool IsBusy { get { return state == "queued" || state == "running"; } }
        public bool IsDone { get { return state == "ok" || state == "reboot"; } }
        public bool CanUpdate { get { return !IsBusy && !IsDone && !truncated && !(section == "discover" && installed) && !(section == "updates" && IsConcealed); } }
        public string ActionText {
            get {
                if (section == "updates" && IsConcealed && string.IsNullOrEmpty(state)) return IsWindowsUpdated ? "Automatic" : "Hidden";
                if (state == "error") return "Retry";
                if (section == "discover") return installed ? "Installed" : "Install";
                return section == "installed" ? "Uninstall" : "Update";
            }
        }
        public string InteractiveMenuText {
            get { return section == "discover" ? "Install interactively (show installer)" : section == "installed" ? "Uninstall interactively (show uninstaller)" : "Update interactively (show installer)"; }
        }
    }

    // Drivers tab: one device and the driver it uses (Win32_PnPSignedDriver), plus any problem Windows reports
    public class DeviceDriver : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private string state = "", detail = "";
        public string Name { get; set; }
        public string Class { get; set; }
        public string Manufacturer { get; set; }
        public string Provider { get; set; }
        public string Version { get; set; }
        public string Date { get; set; }
        public string Inf { get; set; }
        public string InstanceId { get; set; }
        // The device's first hardware ID, which a saved driver is matched against and forced back onto
        public string HardwareId { get; set; }
        public string Problem { get; set; }
        // The newest saved copy of an earlier driver for this device (DriverBackups), if any
        private string backupPath = "", backupVersion = "", backupDate = "";
        public string BackupPath { get { return backupPath; } set { backupPath = value ?? ""; Changed("BackupPath", "CanRollback", "RollbackTip", "HasBackup"); } }
        public string BackupVersion { get { return backupVersion; } set { backupVersion = value ?? ""; Changed("BackupVersion", "RollbackTip"); } }
        public string BackupDate { get { return backupDate; } set { backupDate = value ?? ""; Changed("BackupDate", "RollbackTip"); } }
        public bool HasBackup { get { return !string.IsNullOrEmpty(backupPath); } }
        public bool CanRollback { get { return CanAct && HasBackup; } }
        public string RollbackTip { get { return HasBackup ? "Go back to the saved driver " + backupVersion + " (saved " + backupDate + "), forcing it onto this device" : "No earlier driver is saved for this device. This app saves one before it removes or replaces a driver."; } }
        public bool HasProblem { get { return !string.IsNullOrEmpty(Problem); } }
        // Devices without a class sort after the rest
        public string SortClass { get { return string.IsNullOrEmpty(Class) ? "zzzz" : Class; } }
        public string SubText {
            get {
                string c = string.IsNullOrEmpty(Class) ? "Device" : Class;
                return string.IsNullOrEmpty(Manufacturer) ? c : c + "  " + (char)0x00B7 + "  " + Manufacturer;
            }
        }
        // Third-party drivers (oem*.inf) can be removed; Windows' own in-box drivers can't
        public bool IsOem { get { return Inf != null && Inf.StartsWith("oem", StringComparison.OrdinalIgnoreCase); } }
        // "" (idle), running, ok, reboot, error
        public string State { get { return state; } set { state = value ?? ""; Changed("State", "IsBusy", "CanAct", "CanRemove", "CanRollback", "StatusText"); } }
        public string Detail { get { return detail; } set { detail = value ?? ""; Changed("Detail", "StatusText"); } }
        public bool IsBusy { get { return state == "running"; } }
        public bool CanAct { get { return !IsBusy && !string.IsNullOrEmpty(InstanceId); } }
        public bool CanRemove { get { return CanAct && IsOem; } }
        public string StatusText { get { return !string.IsNullOrEmpty(state) ? detail : (HasProblem ? Problem : ""); } }
    }

    // Drivers tab: one driver update, from Windows Update or the vendor's tool (Dell Command | Update's scan report)
    public class DriverUpdate : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool included = true;
        // "Windows Update" (picked one by one) or "Dell Command | Update" (picked by type)
        public string Source { get; set; }
        public string UpdateId { get; set; }
        public bool IsWu { get { return Source == "Windows Update"; } }
        public bool IsDell { get { return Source == "Dell Command | Update"; } }
        // Windows Update's and NVIDIA's updates are ticked one by one; Dell Command | Update's by type; an update with an
        // action of its own (AMD's installer) is not part of the install run at all
        public bool Pickable { get { return !IsDell && !HasAction; } }
        private string actionText = "";
        public string ActionText { get { return actionText; } set { actionText = value ?? ""; PropertyChangedEventHandler h = PropertyChanged; if (h != null) { h(this, new PropertyChangedEventArgs("ActionText")); h(this, new PropertyChangedEventArgs("HasAction")); } } }
        public bool HasAction { get { return !string.IsNullOrEmpty(actionText); } }
        public string ActionTip { get; set; }
        public string Url { get; set; }
        public string Name { get; set; }
        public string Type { get; set; }
        public string Kind { get; set; }
        public string Category { get; set; }
        public string Version { get; set; }
        public string Severity { get; set; }
        public string SizeText { get; set; }
        public string Released { get; set; }
        public bool Included {
            get { return included; }
            set { included = value; PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs("Included")); }
        }
    }

    // Startup tab: one app that starts when you sign in (a Run registry value, a Startup folder shortcut, or a Store
    // app's startup task), and whether Windows lets it start (the StartupApproved data Task Manager uses)
    public class StartupItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private bool enabled;
        private string state = "", detail = "";
        public string Name { get; set; }
        public string Command { get; set; }
        public string Publisher { get; set; }
        // hkcu | hklm | hklm32 | userfolder | commonfolder | appx
        public string Location { get; set; }
        public string LocationText { get; set; }
        // The registry value or shortcut file name (the StartupApproved value name), or the Store app's task key
        public string Entry { get; set; }
        public string FilePath { get; set; }
        public bool NeedsAdmin { get; set; }
        public string AdminTip { get { return NeedsAdmin ? "Starts for everyone who signs in to this PC: turning it on or off asks for administrator approval" : "Starts when you sign in"; } }
        public bool Enabled { get { return enabled; } set { enabled = value; Changed("Enabled", "StatusText", "ActionText"); } }
        public string State { get { return state; } set { state = value ?? ""; Changed("State", "IsBusy", "CanToggle", "StatusText"); } }
        public string Detail { get { return detail; } set { detail = value ?? ""; Changed("Detail", "StatusText"); } }
        public bool IsBusy { get { return state == "running"; } }
        public bool CanToggle { get { return !IsBusy; } }
        public string StatusText { get { return !string.IsNullOrEmpty(state) && !string.IsNullOrEmpty(detail) ? detail : (enabled ? "On" : "Off"); } }
        public string ActionText { get { return enabled ? "Turn off" : "Turn on"; } }
    }

    // Windows Update tab: one update (software, not drivers), or one line of Windows Update's own history
    public class WinUpdate : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private bool included = true;
        public string UpdateId { get; set; }
        public string Title { get; set; }
        public string SubText { get; set; }
        public string Type { get; set; }
        public string Severity { get; set; }
        public string SizeText { get; set; }
        public string Released { get; set; }
        public string Description { get; set; }
        public string Url { get; set; }
        // Optional updates (previews, and updates Windows offers to choose) start unticked
        public bool Optional { get; set; }
        // History rows: the result (ok, error, other) and its text
        public string Result { get; set; }
        public string ResultText { get; set; }
        public bool Included {
            get { return included; }
            set { included = value; PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs("Included")); }
        }
    }

    // Health tab: a drive (volume) and how full it is, and a physical disk and its health
    public class HealthVolume {
        public string Name { get; set; }
        public string Detail { get; set; }
        public double UsedPct { get; set; }
        // ok | warn | bad
        public string Level { get; set; }
    }
    public class HealthDisk {
        public string Name { get; set; }
        public string Detail { get; set; }
        public string Health { get; set; }
        public string Level { get; set; }
    }

    // Health tab: something that can be cleaned up, and how much space it takes
    public class CleanupItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private bool included;
        private long bytes = -1;
        private string state = "", detail = "";
        public string Key { get; set; }
        public string Name { get; set; }
        public string About { get; set; }
        public bool NeedsAdmin { get; set; }
        // -1: not measured (or can't be without administrator rights)
        public long Bytes { get { return bytes; } set { bytes = value; Changed("Bytes", "SizeText"); } }
        public string SizeText {
            get {
                if (bytes < 0) return NeedsAdmin ? "?" : "";
                if (bytes == 0) return "0 MB";
                double mb = bytes / 1048576.0;
                if (mb >= 1024) return (mb / 1024).ToString("0.0") + " GB";
                return mb < 1 ? "< 1 MB" : mb.ToString("0") + " MB";
            }
        }
        public bool Included { get { return included; } set { included = value; Changed("Included"); } }
        public string State { get { return state; } set { state = value ?? ""; Changed("State", "StatusText"); } }
        public string Detail { get { return detail; } set { detail = value ?? ""; Changed("Detail", "StatusText"); } }
        public string StatusText { get { return string.IsNullOrEmpty(detail) ? About : detail; } }
    }

    // Device Health: one line on a card (what it is, its value, ok / warn / bad / info)
    public class HealthCheck {
        public string Label { get; set; }
        public string Value { get; set; }
        public string Level { get; set; }
        public string Tip { get; set; }
    }
    // Device Health's Temperatures card: one processor or graphics card and each of its sensors
    public class HealthTempGroup {
        public string Name { get; set; }
        public HealthCheck[] Items { get; set; }
    }

    // Cleanup: a large file in your folders
    public class BigFile : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private string state = "", detail = "";
        public string Name { get; set; }
        public string Folder { get; set; }
        public string Path { get; set; }
        public long Bytes { get; set; }
        public string SizeText { get { double g = Bytes / 1073741824.0; return g >= 1 ? g.ToString("0.0") + " GB" : (Bytes / 1048576.0).ToString("0") + " MB"; } }
        public string Modified { get; set; }
        public string State { get { return state; } set { state = value ?? ""; Changed("State", "StatusText", "CanDelete"); } }
        public string Detail { get { return detail; } set { detail = value ?? ""; Changed("Detail", "StatusText"); } }
        public string StatusText { get { return string.IsNullOrEmpty(detail) ? Folder : detail; } }
        public bool CanDelete { get { return state != "ok"; } }
    }

    // Windows Features tab: a built-in app (Store package) or an optional Windows feature, and whether it's there
    public class FeatureItem : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Changed(params string[] names) {
            PropertyChangedEventHandler h = PropertyChanged;
            if (h == null) return;
            foreach (string n in names) h(this, new PropertyChangedEventArgs(n));
        }
        private bool on;
        private string state = "", detail = "";
        // app | feature
        public string Kind { get; set; }
        public string Name { get; set; }
        public string SubText { get; set; }
        public string Publisher { get; set; }
        private string description = "";
        public string Description { get { return description; } set { description = value ?? ""; Changed("Description", "HasDescription"); } }
        public bool HasDescription { get { return description.Length > 0; } }
        // the package's full name or the feature's name; the package family and install folder, for reinstalling
        public string Key { get; set; }
        public string Family { get; set; }
        public string Location { get; set; }
        public bool Available { get; set; }
        public bool On { get { return on; } set { on = value; Changed("On", "StatusText", "ActionText"); } }
        public string State { get { return state; } set { state = value ?? ""; Changed("State", "IsBusy", "CanChange", "StatusText"); } }
        public string Detail { get { return detail; } set { detail = value ?? ""; Changed("Detail", "StatusText"); } }
        public bool IsBusy { get { return state == "running"; } }
        public bool CanChange { get { return !IsBusy && (Kind == "app" || Available); } }
        public string StatusText {
            get {
                if (!string.IsNullOrEmpty(state) && !string.IsNullOrEmpty(detail)) return detail;
                if (Kind == "app") return on ? "Installed" : "Removed";
                return !Available ? "Not available" : (on ? "On" : "Off");
            }
        }
        public string ActionText { get { return Kind == "app" ? (on ? "Remove" : "Reinstall") : (on ? "Turn off" : "Turn on"); } }
        // Optional features' tree, as Windows shows it: the feature it sits under, how deep, whether features sit
        // under it and are showing, and how many of those are on. SortKey keeps the list in tree order (apps: name).
        public string ParentKey { get; set; }
        public int Depth { get; set; }
        public double IndentWidth { get { return Depth * 24; } }
        private bool hasChildren, expanded;
        public bool HasChildren { get { return hasChildren; } set { hasChildren = value; Changed("HasChildren"); } }
        public bool IsExpanded { get { return expanded; } set { expanded = value; Changed("IsExpanded"); } }
        public string SortKey { get; set; }
        private string treeNote = "";
        public string TreeNote { get { return treeNote; } set { treeNote = value ?? ""; Changed("TreeNote", "HasTreeNote"); } }
        public bool HasTreeNote { get { return treeNote.Length > 0; } }
    }

    // One line of the History panel (history.jsonl)
    public class HistoryEntry {
        public System.DateTime Time { get; set; }
        public string Action { get; set; }
        public string Name { get; set; }
        public string Id { get; set; }
        public string From { get; set; }
        public string To { get; set; }
        public string State { get; set; }
        public string Detail { get; set; }
        public string Origin { get; set; }
        public string When { get { return Time.ToString("ddd MMM d, h:mm tt"); } }
        public bool IsAuto { get { return Origin == "auto"; } }
        public string ActionText {
            get {
                switch (Action) {
                    case "install": return "Installed";
                    case "uninstall": return "Uninstalled";
                    case "hold": return "Hid";
                    case "release": return "Unhid";
                    case "drvupdate": return "Driver update:";
                    case "drvrollback": return "Rolled back driver:";
                    case "winupdate": return "Windows update:";
                    case "startupoff": return "Turned off at startup:";
                    case "startupon": return "Turned on at startup:";
                    case "cleanup": return "Cleaned up:";
                    case "drvinstall": return "Reinstalled all drivers:";
                    case "drvreinstall": return "Reinstalled driver:";
                    case "drvremove": return "Removed driver:";
                    default: return "Updated";
                }
            }
        }
        public string Glyph {
            get {
                switch (Action) {
                    case "install": return ((char)0xE896).ToString();
                    case "uninstall": return ((char)0xE74D).ToString();
                    case "hold": return ((char)0xE72E).ToString();
                    case "release": return ((char)0xE785).ToString();
                    case "drvupdate": case "drvinstall": case "drvreinstall": case "drvremove": case "drvrollback": return ((char)0xE950).ToString();
                    case "winupdate": return ((char)0xE895).ToString();
                    case "startupoff": case "startupon": return ((char)0xE7E8).ToString();
                    case "cleanup": return ((char)0xE74D).ToString();
                    default: return ((char)0xE777).ToString();
                }
            }
        }
        public string Change {
            get {
                bool f = !string.IsNullOrEmpty(From), t = !string.IsNullOrEmpty(To);
                if (f && t && From != To) return From + " " + (char)0x2192 + " " + To;
                return t ? To : (f ? From : "");
            }
        }
    }
}
'@
}

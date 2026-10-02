# Windows Manager - Window (part of src\; see Windows_Manager.ps1)

$Window = [System.Windows.Markup.XamlReader]::Parse($Xaml)
$Window.Add_SourceInitialized({
        try {
            if (-not ('WingetUM.Dwm' -as [type])) {
                Add-Type -Namespace WingetUM -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);'
            }
            $hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle
            $dark = 1; [void][WingetUM.Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$dark, 4)          # immersive dark mode
            $caption = 0x001E1E1E; [void][WingetUM.Dwm]::DwmSetWindowAttribute($hwnd, 35, [ref]$caption, 4)  # caption color (Win 11)
        }
        catch { }
    })
$UI = @{}
foreach ($name in 'HeaderLogo', 'HeaderVersion', 'SubTitle', 'AdminBadge', 'AdminGlyph', 'AdminText', 'BtnElevate', 'Search', 'BtnRefresh',
    'BtnUpdateSelected', 'BtnUpdateAll', 'UpdateAllText', 'ColumnHeader', 'CheckAll', 'SortName', 'SortNameGlyph', 'SortSource', 'SortSourceGlyph', 'SortSize', 'SortSizeGlyph',
    'List', 'LoadingPanel', 'EmptyPanel', 'EmptyText', 'NoMatchPanel', 'NoMatchText', 'ErrorPanel', 'ErrorTitle', 'ErrorText', 'BtnRetry',
    'BtnGetWinget', 'LogPanel', 'LogBox', 'BtnStop', 'BtnLog', 'BtnLogFolder', 'BusyBar', 'StatusText',
    'BtnSchedule', 'ScheduleText', 'ScheduleOverlay', 'SchEnabled', 'SchOptions', 'SchDaily', 'SchWeekly', 'SchTime', 'SchDays', 'SchElevated',
    'SchCatchUp', 'SchNotifyReboot', 'SchNotifyAlways', 'SchStatus', 'SchError', 'SchRunNow', 'SchDryRun', 'SchCancel', 'SchSave',
    'IdlePanel', 'BtnOptions', 'OptionsOverlay', 'OptVersion', 'OptNav', 'PageUpdates', 'PageAuto', 'PageLogs', 'PageMaint',
    'OptSrcAll', 'OptSrcWinget', 'OptSrcStore', 'OptSilent', 'OptUnknown', 'OptUninstallPrev', 'OptScanOnOpen',
    'OptTaskNote', 'OptRetry', 'OptRestorePoint', 'OptNetwork', 'OptAC', 'OptDelay', 'OptMaxHours', 'OptDismiss',
    'OptRetention', 'OptLogDir', 'OptLogBrowse', 'OptLogDefault', 'OptLogHint', 'OptVerbose', 'OptOpenLogs', 'OptOpenWingetLogs',
    'OptWingetInfo', 'OptSrcUpdate', 'OptSrcReset', 'OptMaintStatus', 'OptExport', 'OptImport', 'OptOpenData', 'OptResetAll',
    'TabUpdates', 'TabDiscover', 'TabInstalled', 'UpdatesBadge', 'UpdatesBadgeText', 'InstalledCount', 'SearchHint', 'BtnSearchGo', 'ChkWingetOnly',
    'BtnInstallSelected', 'InstallSelectedText', 'HdrVersion', 'HdrAvailable', 'LoadingTitle', 'LoadingText', 'EmptyTitle',
    'OptScopeDefault', 'OptScopeUser', 'OptScopeMachine', 'DetailsOverlay', 'DetClose', 'DetName', 'DetSub', 'DetLoading', 'DetDesc', 'DetFields',
    'DetHomepage', 'DetAction', 'ConfirmOverlay', 'ConfirmTitle', 'ConfirmText', 'ConfirmNo', 'ConfirmYes',
    'HColVer', 'HColThird', 'HColSource', 'HColStatus', 'HdrStatus', 'BtnAbout', 'AboutOverlay', 'AboutLogo', 'AboutVersion', 'AboutMail', 'AboutRepo', 'AboutCopy', 'AboutClose',
    'OptCancel', 'OptSave', 'OptMessage', 'BtnShowHidden', 'ShowHiddenGlyph', 'ShowHiddenText', 'OptHiddenList', 'OptHiddenEmpty', 'OptHideAdd', 'OptHideAddBtn',
    'BtnImportList', 'BtnExportList', 'BtnHistory', 'SchModeInstall', 'SchModeNotify', 'SchModeHint', 'PageSources', 'OptSourceList', 'OptSourceEmpty',
    'OptSrcName', 'OptSrcUrl', 'OptSrcTypeRest', 'OptSrcTypeIndexed', 'OptSrcExplicit', 'OptSrcAdd',
    'HistoryOverlay', 'HistClose', 'HistSub', 'HistSearch', 'HistAll', 'HistAutoOnly', 'HistFailed', 'HistList', 'HistEmpty', 'HistEmptyText', 'HistClear', 'HistDone',
    'NotesOverlay', 'NotesClose', 'NotesTitle', 'NotesSub', 'NotesText', 'NotesOpen', 'NotesUpdate',
    'VersionOverlay', 'VerSub', 'VerList', 'VerLoading', 'VerError', 'VerHold', 'VerCancel', 'VerInstall',
    'PickOverlay', 'PickTitle', 'PickText', 'PickCount', 'PickAll', 'PickNone', 'PickList', 'PickCancel', 'PickOk',
    'TabDrivers', 'SectionToolbar', 'MainCard', 'DriversPanel', 'DrvOpenTool', 'DrvReinstallAll', 'DrvToolAction', 'DrvMaker', 'DrvModel', 'DrvToolText',
    'DrvViewDevices', 'DrvViewDevicesText', 'DrvViewUpdates', 'DrvViewUpdatesText', 'DrvSearch', 'DrvUpdateTools', 'DrvTypeDriver', 'DrvTypeFirmware',
    'DrvTypeBios', 'DrvTypeApp', 'DrvProblemsOnly', 'DrvRestore', 'DrvRefresh', 'DrvRefreshText', 'DrvApply', 'DrvApplyText', 'DrvDevHeader', 'DrvUpdHeader',
    'DrvDevices', 'DrvUpdates', 'DrvMsgPanel', 'DrvMsgBar', 'DrvMsgTitle', 'DrvMsgText', 'DrvMsgAction', 'DrvSupport', 'DrvExtras', 'DrvNote', 'DrvNoteText', 'DrvNoteAction') {
    $UI[$name] = $Window.FindName($name)
    if (-not $UI[$name]) { throw "XAML element '$name' not found." }
}
# 2.0: the Startup, Windows Update and Health tabs, diagnostics, notifications, setup backups
foreach ($name in 'TabStartup', 'TabWindows', 'TabHealth', 'WinBadge', 'WinBadgeText', 'BtnDiag',
    'StartupPanel', 'StTitle', 'StText', 'StOpenTaskMgr', 'StSearch', 'StOffOnly', 'StRefresh', 'StHeader', 'StList', 'StMsgPanel', 'StMsgBar', 'StMsgTitle', 'StMsgText', 'StMsgAction',
    'WinPanel', 'WinTitle', 'WinVersion', 'WinStatus', 'WinSettings', 'WinRestart', 'WinViewAvail', 'WinViewAvailText', 'WinViewHistory', 'WinSearch', 'WinRestore',
    'WinRefresh', 'WinRefreshText', 'WinApply', 'WinApplyText', 'WinNote', 'WinNoteText', 'WinAvailHeader', 'WinHistHeader', 'WinList', 'WinHistList',
    'WinMsgPanel', 'WinMsgBar', 'WinMsgTitle', 'WinMsgText', 'WinMsgAction',
    'HealthPanel', 'HlRefresh', 'HlBusy', 'HlSummary', 'HlSysTitle', 'HlSysText', 'HlSysNote', 'HlBiosTitle', 'HlBiosText', 'HlBiosCheck', 'HlBatTitle', 'HlBatBar',
    'HlBatText', 'HlBatReport', 'HlVolumes', 'HlDisks', 'HlDiskCleanup', 'HlStorage', 'HlClean', 'HlCleanText', 'HlCleanInfo', 'HlCleanList',
    'OptNotifyToast', 'OptNotifyWindow', 'OptWinUpdated', 'OptWinUpdReset', 'OptDiag', 'OptSetupSave', 'OptSetupLoad', 'OptSetupHint') {
    $UI[$name] = $Window.FindName($name)
    if (-not $UI[$name]) { throw "XAML element '$name' not found." }
}
# 2.1: Device Health's new cards and the Cleanup tab
foreach ($name in 'TabCleanup', 'CleanupPanel', 'ClTitle', 'ClDriveBar', 'ClDriveText', 'ClRefresh', 'ClBigInfo', 'ClBigScan', 'ClBigList', 'ClAppsInfo', 'ClAllApps', 'ClAppList',
    'HlSecTitle', 'HlSecItems', 'HlSecOpen', 'HlPerfTitle', 'HlMemBar', 'HlPerfItems', 'HlPerfOpen', 'HlRelTitle', 'HlRelItems', 'HlRelOpen',
    'HlUpdTitle', 'HlUpdItems', 'HlUpdOpen', 'HlNetTitle', 'HlNetItems', 'HlNetOpen', 'HlCleanSumTitle', 'HlCleanSumText', 'HlCleanOpen',
    'PageApp', 'OptAppStatus', 'OptAppCheckNow', 'OptAppInstall', 'OptAppReleases', 'OptAppCheck', 'OptAppAuto', 'OptAppBack', 'OptAppBeta', 'OptHealthAlerts', 'HlReport', 'HlTrends', 'HlTrendsNote', 'HlTrendsLabel',
    'TabFeatures', 'FeaturesPanel', 'FtTitle', 'FtText', 'FtViewApps', 'FtViewAppsText', 'FtViewFeatures', 'FtViewFeaturesText', 'FtSearch', 'FtOnOnly', 'FtRefresh',
    'FtHeader', 'FtHeadName', 'FtHeadPub', 'FtList', 'FtMsgPanel', 'FtMsgBar', 'FtMsgTitle', 'FtMsgText') {
    $UI[$name] = $Window.FindName($name)
    if (-not $UI[$name]) { throw "XAML element '$name' not found." }
}

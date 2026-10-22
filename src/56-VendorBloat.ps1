# Windows Manager - VendorBloat (part of src\; see Windows_Manager.ps1)

# Remove vendor bloat (Uninstall Software): the extras a new PC comes with, found in the installed list by name and
# offered in a pick list. Trials, promos and the PC maker's add-ons that do nothing on their own are ticked; the
# maker's tools that can matter (support, hotkeys, audio, fan and lighting control, updates) and promo apps people
# often use are listed unticked, with what each one does. Drivers, firmware tools and Microsoft's own apps are never
# listed. The ticked apps go through the uninstall queue, after a restore point when "Restore point first" is on.
#   Match: a regex against the app's name and ID. Kind: junk (ticked) or keep (unticked). Note: what it is.
$VendorBloat = @(
    # Trial antivirus and other trials
    @{ Match = '^McAfee'; Kind = 'junk'; Note = 'Trial antivirus. Windows Security protects the PC without it' }
    @{ Match = '^Norton (Security|360|AntiVirus|Internet Security)'; Kind = 'junk'; Note = 'Trial antivirus. Windows Security protects the PC without it' }
    @{ Match = '^WildTangent'; Kind = 'junk'; Note = 'Game trials and ads' }
    @{ Match = '^ExpressVPN'; Kind = 'keep'; Note = 'VPN trial; keep it if you subscribed' }
    @{ Match = '^Keeper Password Manager|KeeperSecurityInc'; Kind = 'keep'; Note = 'Password manager trial; keep it if your passwords are in it' }
    @{ Match = '^Dropbox (Promotion|25 GB|offer)'; Kind = 'junk'; Note = 'A Dropbox offer, not Dropbox itself' }
    @{ Match = '^Amazon Assistant'; Kind = 'junk'; Note = 'Shopping add-on from the PC maker' }
    @{ Match = '^CyberLink (Power2Go|PowerDVD|PhotoDirector|PowerDirector|YouCam|Media Suite)'; Kind = 'keep'; Note = 'Media software bundled with the PC; often a limited edition' }
    # Promo apps and games preinstalled from the Store
    @{ Match = 'king\.com\.|Candy Crush|Bubble Witch'; Kind = 'junk'; Note = 'Preinstalled game' }
    @{ Match = 'Gameloft|^Asphalt|March of Empires'; Kind = 'junk'; Note = 'Preinstalled game' }
    @{ Match = 'Disney Magic Kingdoms|Hidden City|Royal Revolt|FarmVille|Seekers Notes|Legacy Games'; Kind = 'junk'; Note = 'Preinstalled game' }
    @{ Match = '^Booking\.com|PricelinePartnerNetwork'; Kind = 'junk'; Note = 'Preinstalled travel promo' }
    @{ Match = 'Phototastic|PicsArt|Fotor'; Kind = 'junk'; Note = 'Preinstalled photo app promo' }
    @{ Match = '^Spotify|SpotifyAB\.'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    @{ Match = '^Netflix|4DF9E0F8\.Netflix'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    @{ Match = '^Disney\+|Disney\.37853'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    @{ Match = '^Prime Video|AmazonVideo\.PrimeVideo'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    @{ Match = '^TikTok|BytedancePte'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    @{ Match = '^Instagram|^Facebook$|^Messenger$|Facebook\.(Instagram|Facebook|Messenger)'; Kind = 'keep'; Note = 'Often preinstalled; keep it if you use it' }
    # Dell and Alienware
    @{ Match = '^Dell Digital Delivery|^Alienware Digital Delivery'; Kind = 'junk'; Note = 'Downloads software bought with the PC; not needed once it is installed' }
    @{ Match = '^Dell Customer Connect|^Dell Partner Promo|^Dell Pair$|^Dell Mobile Connect'; Kind = 'junk'; Note = "Dell's surveys, offers or phone link (discontinued)" }
    @{ Match = '^Dell SupportAssist( for|$| Remediation| OS Recovery)|^Alienware SupportAssist'; Kind = 'keep'; Note = "Dell's diagnostics and recovery tool; keep it if Dell support may need it" }
    @{ Match = '^Dell Optimizer|^Dell Power Manager|^Dell Peripheral Manager|^Dell Display Manager|^Dell Trusted Device|^Dell Core Services|^Dell TechHub|^My Dell'; Kind = 'keep'; Note = "Dell's settings tool; keep it if you use what it controls" }
    @{ Match = '^Alienware Command Center|^AWCC|^Alienware Update'; Kind = 'keep'; Note = "Alienware's lighting, fan and performance control; keep it if you use it" }
    # HP and OMEN
    @{ Match = '^HP Documentation|^HP JumpStart|^HP Connection Optimizer|^HP Privacy Settings|^HP Notifications|^HP Registration Service|^HP Customer Experience|^HP Easy Clean|^HP QuickDrop|^HP Insights'; Kind = 'junk'; Note = "HP's welcome, registration, survey or promo add-on" }
    @{ Match = '^HP Wolf Security|^HP Sure (Click|Sense|Run|Recover)|^HP Security Update Service'; Kind = 'keep'; Note = "HP's security add-on; Windows Security protects the PC without it" }
    @{ Match = '^HP Support Assistant|^myHP|^HP PC Hardware Diagnostics|^HP System Event Utility|^HP Audio Switch|^HP Presence|^HP Desktop Support|^OMEN Gaming Hub'; Kind = 'keep'; Note = "HP's support or hardware tool (hotkeys, audio, diagnostics); keep it if you use it" }
    # Lenovo
    @{ Match = '^Lenovo Now|^Lenovo Welcome|^Lenovo Migration Assistant|^Lenovo Voice'; Kind = 'junk'; Note = "Lenovo's welcome, promo or migration add-on" }
    @{ Match = '^Lenovo Vantage|^Lenovo Smart Appearance|^Lenovo Hotkeys|^Lenovo Pen Settings|^Lenovo Utility'; Kind = 'keep'; Note = "Lenovo's settings tool (battery, hotkeys, camera); keep it if you use it" }
    # Acer
    @{ Match = '^Acer Jumpstart|^Acer ?Collection|^Acer Product Registration|^Acer Registration|^Acer Portal|^Acer Survey|^Acer User Experience'; Kind = 'junk'; Note = "Acer's welcome, registration, survey or promo add-on" }
    @{ Match = '^Acer Care Center|^Acer Quick Access|^Acer Configuration Manager|^AcerSense|^Acer Purified Voice'; Kind = 'keep'; Note = "Acer's settings or support tool; keep it if you use it" }
    # ASUS
    @{ Match = '^ASUS GiftBox|^ASUS Product Register|^ASUS WebStorage|^ASUS Virtual Pet|^GlideX'; Kind = 'junk'; Note = "ASUS's promo, registration or companion add-on" }
    @{ Match = '^MyASUS|^Armoury Crate|^ASUS Splendid|^ASUS Keyboard Hotkeys|^ASUS Live Update|^ScreenXpert'; Kind = 'keep'; Note = "ASUS's settings tool (fans, lighting, display, hotkeys); keep it if you use it" }
    # MSI
    @{ Match = '^MSI App Player'; Kind = 'junk'; Note = 'An Android app player bundled with the PC' }
    @{ Match = '^MSI Center|^MSI Dragon Center|^MSI True Color'; Kind = 'keep'; Note = "MSI's settings tool (fans, lighting, display); keep it if you use it" }
)
# never listed, whatever the patterns above say
$VendorBloatNever = 'Driver|Firmware|BIOS|Dell Command|Realtek|Intel|NVIDIA|AMD |Synaptics|Thunderbolt|Microsoft'

function Find-VendorBloat {
    $found = foreach ($p in @($InstalledItems)) {
        if (-not $p.CanUpdate) { continue }
        if ($p.Name -match $VendorBloatNever) { continue }
        $hit = @($VendorBloat | Where-Object { $p.Name -match $_.Match -or $p.Id -match $_.Match }) | Select-Object -First 1
        if ($hit) { [pscustomobject]@{ Name = $p.Name; Id = $p.Id; Source = $p.Source; Note = $hit.Note; Item = $p; Checked = $hit.Kind -eq 'junk' } }
    }
    return @(@($found) | Sort-Object { -not $_.Checked }, Name)
}

function Open-VendorBloat {
    $rows = Find-VendorBloat
    if (-not $rows.Count) {
        [void][System.Windows.MessageBox]::Show("No vendor bloat was found among the $($InstalledItems.Count) installed apps.`n`nThis looks for trials, promos and PC maker add-ons by name; anything else is on the list to uninstall yourself.", $AppName, 'OK', 'Information')
        return
    }
    $rp = if ($Settings.DriverRestorePoint) { ' A restore point is made first (one administrator approval).' } else { '' }
    Show-Pick 'bloat' 'Remove vendor bloat' "Trials, promos and PC maker add-ons found on this PC. The ticked ones are safe to remove; the others are tools some people use, so they are left unticked. They uninstall one at a time.$rp" 'Uninstall ticked' $rows
}

function Remove-VendorBloat($Rows) {
    $UI.PickOverlay.Visibility = 'Collapsed'
    $items = @($Rows | ForEach-Object { $_.Item } | Where-Object { $_ -and $_.CanUpdate })
    if (-not $items.Count) { return }
    Add-LogLine "Removing vendor bloat: $(($items | ForEach-Object { $_.Name }) -join ', ')"
    if ($Settings.DriverRestorePoint -and -not $script:Elev) {
        Start-Elevated 'bloat' 'Creating a restore point' "Say 'Restore point step finished.'" @() @{ Items = $items } -RestorePoint -RestoreText 'Before removing vendor bloat'
        return
    }
    Add-Job $items
}
$ElevHandlers.bloat = {
    param($Ev, $why, $code, $last, $tag)
    if ($Ev.Declined) { Add-LogLine 'Removing vendor bloat cancelled: administrator approval was declined.'; $script:LastSummary = 'Vendor bloat: cancelled'; return }
    if ($why) { Add-LogLine "Restore point not made ($why); uninstalling anyway." }
    Add-Job @($tag.Items)
}

# Windows Manager - Splash (part of src\; see Windows_Manager.ps1)

# Build-Exe.ps1 fills these with assets\icon.ico and assets\logo.jpg (base64), so the exe needs no other files.
$EmbeddedIcon = ''
$EmbeddedLogo = ''
$AssetsDir = if ($AppRoot) { Join-Path $AppRoot 'assets' } else { $null }
function Get-AssetBytes([string]$Embedded, [string]$FileName) {
    if ($Embedded) { return , [Convert]::FromBase64String($Embedded) }
    if ($AssetsDir) {
        $file = Join-Path $AssetsDir $FileName
        if (Test-Path -LiteralPath $file) { return , [IO.File]::ReadAllBytes($file) }
    }
    return $null
}
# The app's icon (assets\icon.ico, drawn by tools\New-AppIcon.ps1). A window's Icon picks its own sizes from it;
# -Size returns the smallest frame at least that big (the largest when none is), for the header and notifications.
function Get-AppIcon([int]$Size) {
    try {
        $bytes = Get-AssetBytes $EmbeddedIcon 'icon.ico'
        if (-not $bytes) { return $null }
        $f = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object IO.MemoryStream(, $bytes)), 'None', 'OnLoad')
        if ($Size -le 0 -or -not $f.Decoder) { return $f }
        $all = @($f.Decoder.Frames | Sort-Object PixelWidth)
        $fit = @($all | Where-Object { $_.PixelWidth -ge $Size }) | Select-Object -First 1
        if ($fit) { return $fit }
        return $all[-1]
    }
    catch { }
    return $null
}

# The splash: the app's icon, name and version, and a bar that fills as the rest of the app loads. A start after the
# PC has been idle can take several seconds (PowerShell and .NET load from disk first), so something shows at once.
# Only for the window: 00-Startup.ps1 takes the single-instance lock only then. Step-Splash (00-Startup.ps1) moves
# the bar and redraws it; the window closes it once it's ready to use (90-Wiring.ps1).
if ($script:AppMutex) {
    try {
        $splashWin = [System.Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Manager" Width="460" Height="220" WindowStyle="None" ResizeMode="NoResize"
        AllowsTransparency="True" Background="Transparent" WindowStartupLocation="CenterScreen" Topmost="True"
        FontFamily="Segoe UI" Foreground="#F2F2F2" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Border Margin="16" Background="#1E1E1E" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="10">
    <Border.Effect><DropShadowEffect BlurRadius="16" ShadowDepth="3" Opacity="0.5"/></Border.Effect>
    <Grid Margin="28,22,28,24">
      <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Image x:Name="Logo" Width="56" Height="56" Margin="0,0,16,0" RenderOptions.BitmapScalingMode="HighQuality"/>
        <StackPanel VerticalAlignment="Center">
          <TextBlock Text="Windows Manager" FontSize="22" FontWeight="SemiBold"/>
          <TextBlock x:Name="Version" Foreground="#9A9A9A" FontSize="12.5" Margin="1,2,0,0"/>
        </StackPanel>
      </StackPanel>
      <TextBlock Grid.Row="1" x:Name="Status" Text="Starting&#x2026;" Foreground="#9A9A9A" FontSize="12.5" Margin="0,0,0,8"/>
      <ProgressBar Grid.Row="2" x:Name="Bar" Height="4" Minimum="0" Maximum="100" Value="2">
        <ProgressBar.Template>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" Background="#333333" CornerRadius="2"/>
              <Border x:Name="PART_Indicator" HorizontalAlignment="Left" CornerRadius="2">
                <Border.Background>
                  <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                    <GradientStop Color="#22C8D8" Offset="0"/>
                    <GradientStop Color="#6A74F0" Offset="1"/>
                  </LinearGradientBrush>
                </Border.Background>
              </Border>
            </Grid>
          </ControlTemplate>
        </ProgressBar.Template>
      </ProgressBar>
    </Grid>
  </Border>
</Window>
'@)
        $splashIcon = Get-AppIcon 64
        if ($splashIcon) { $splashWin.FindName('Logo').Source = $splashIcon }
        $splashIcon = Get-AppIcon
        if ($splashIcon) { $splashWin.Icon = $splashIcon }
        $splashWin.FindName('Version').Text = "Version $AppVersion"
        $script:Splash = @{ Window = $splashWin; Bar = $splashWin.FindName('Bar'); Status = $splashWin.FindName('Status') }
        $splashWin.Show()
        Step-Splash 2
    }
    catch { $script:Splash = $null }
    Remove-Variable splashWin, splashIcon -ErrorAction SilentlyContinue
}

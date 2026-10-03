# Windows Manager - WindowXaml (part of src\; see Windows_Manager.ps1)

$Xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Windows Manager" Width="1280" Height="820" MinWidth="1180" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#1E1E1E"
        FontFamily="Segoe UI" FontSize="13.5" Foreground="#F2F2F2" UseLayoutRounding="True"
        TextOptions.TextFormattingMode="Display">
  <Window.TaskbarItemInfo>
    <TaskbarItemInfo/>
  </Window.TaskbarItemInfo>
  <Window.Resources>
    <!-- Accent palette, taken from the logo's teal-to-violet gradient -->
    <SolidColorBrush x:Key="Accent" Color="#27B9D4"/>
    <SolidColorBrush x:Key="Highlight" Color="#4FD8E0"/>
    <SolidColorBrush x:Key="Violet" Color="#8E96F4"/>
    <SolidColorBrush x:Key="Warn" Color="#F6B115"/>
    <LinearGradientBrush x:Key="AccentGradient" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#13879C" Offset="0"/>
      <GradientStop Color="#4A52C4" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="BarGradient" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#22C8D8" Offset="0"/>
      <GradientStop Color="#6A74F0" Offset="1"/>
    </LinearGradientBrush>
    <SolidColorBrush x:Key="InputBg" Color="#333333"/>
    <SolidColorBrush x:Key="InputHover" Color="#3B3B3B"/>
    <SolidColorBrush x:Key="Muted" Color="#9A9A9A"/>
    <SolidColorBrush x:Key="Good" Color="#5BC27A"/>
    <SolidColorBrush x:Key="Bad" Color="#FF7B6B"/>

    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{StaticResource InputBg}"/>
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="CaretBrush" Value="#F2F2F2"/>
      <Setter Property="SelectionBrush" Value="{StaticResource Accent}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Padding" Value="10,7"/>
      <Setter Property="MinHeight" Value="36"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6">
              <!-- TextBox applies its Padding to the text itself; a margin here as well would double it -->
              <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="{StaticResource InputHover}"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Toggle switch (options) -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#D6D6D6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="Track" Width="40" Height="22" CornerRadius="11" Background="#4A4A4A">
                <Ellipse x:Name="Knob" Width="16" Height="16" Fill="White" HorizontalAlignment="Left" Margin="3,0,0,0"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Track" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="Knob" Property="Margin" Value="0,0,3,0"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Square check box (row selection) -->
    <Style x:Key="Check" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border Background="Transparent" Padding="6">
              <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" Background="Transparent" BorderBrush="#6A6A6A" BorderThickness="1.5">
                <TextBlock x:Name="Tick" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="White"
                           HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
              </Border>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Box" Property="BorderBrush" Value="#A0A0A0"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="{x:Null}">
                <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Tick" Property="Text" Value="&#xE738;"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.3"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Square check box with its label (pick lists) -->
    <Style x:Key="CheckItem" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="Bg" Background="Transparent" CornerRadius="6" Padding="8,7">
              <DockPanel>
                <Border x:Name="Box" Width="18" Height="18" CornerRadius="4" Background="Transparent" BorderBrush="#6A6A6A" BorderThickness="1.5" VerticalAlignment="Center" Margin="0,0,12,0">
                  <TextBlock x:Name="Tick" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="White"
                             HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed"/>
                </Border>
                <ContentPresenter VerticalAlignment="Center"/>
              </DockPanel>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bg" Property="Background" Value="#2A2A2A"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
                <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Buttons -->
    <Style TargetType="Button">
      <Setter Property="Background" Value="#333333"/>
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6"/>
              <Border x:Name="Hover" Background="White" Opacity="0" CornerRadius="6"/>
              <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Hover" Property="Opacity" Value="0.08"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="Hover" Property="Opacity" Value="0.16"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource AccentGradient}"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderBrush" Value="#8A3A30"/>
      <Setter Property="Foreground" Value="#FF7B6B"/>
    </Style>
    <Style x:Key="Ghost" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#CFCFCF"/>
      <Setter Property="Padding" Value="12,6"/>
    </Style>
    <Style x:Key="RowButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Padding" Value="14,6"/>
      <Setter Property="Margin" Value="0"/>
      <Setter Property="MinWidth" Value="78"/>
      <Setter Property="Focusable" Value="False"/>
    </Style>
    <Style x:Key="LinkButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Highlight}"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="11" Margin="0,1,6,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="Label" Text="{TemplateBinding Content}" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Label" Property="TextDecorations" Value="Underline"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="HeaderButton" TargetType="Button">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="White"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Selectable chip (frequency and weekdays); works for toggle and radio buttons -->
    <Style x:Key="Chip" TargetType="ToggleButton">
      <Setter Property="Foreground" Value="#D6D6D6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ToggleButton">
            <Border x:Name="Bd" Background="#333333" BorderBrush="#474747" BorderThickness="1" CornerRadius="15" Padding="14,6,14,7" MinWidth="52">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="BorderBrush" Value="#6A6A6A"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#17414C"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource Accent}"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <BooleanToVisibilityConverter x:Key="B2V"/>
    <!-- Section tabs (Updates / Discover / Installed) -->
    <Style x:Key="Tab" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#9A9A9A"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Margin" Value="0,0,20,0"/>
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="Transparent" BorderThickness="0,0,0,2" Padding="2,6,2,10">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="#E0E0E0"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter Property="Foreground" Value="White"/>
                <Setter TargetName="Bd" Property="BorderBrush" Value="{StaticResource BarGradient}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="NavItem" TargetType="ListBoxItem">
      <Setter Property="Foreground" Value="#CFCFCF"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" Padding="14,10" Margin="12,2" CornerRadius="6">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#2A2A2A"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="Bd" Property="Background" Value="#17414C"/><Setter Property="Foreground" Value="White"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Hint" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#8A8A8A"/>
      <Setter Property="FontSize" Value="12.5"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="Margin" Value="48,3,0,0"/>
    </Style>
    <Style x:Key="PageTitle" TargetType="TextBlock">
      <Setter Property="FontSize" Value="19"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Foreground" Value="White"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/>
      <Setter Property="FontSize" Value="11.5"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>

    <!-- Progress bar with its own indeterminate slide -->
    <Style x:Key="Bar" TargetType="ProgressBar">
      <Setter Property="Foreground" Value="{StaticResource BarGradient}"/>
      <Setter Property="Background" Value="#3A3A3A"/>
      <Setter Property="Height" Value="4"/>
      <Setter Property="Minimum" Value="0"/>
      <Setter Property="Maximum" Value="100"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid x:Name="PART_Track" ClipToBounds="True">
              <Border Background="{TemplateBinding Background}" CornerRadius="2"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="2" HorizontalAlignment="Left"/>
              <Border x:Name="Slider" Background="{TemplateBinding Foreground}" CornerRadius="2" Width="70" HorizontalAlignment="Left" Visibility="Collapsed">
                <Border.RenderTransform><TranslateTransform X="-70"/></Border.RenderTransform>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsIndeterminate" Value="True">
                <Setter TargetName="PART_Indicator" Property="Visibility" Value="Collapsed"/>
                <Setter TargetName="Slider" Property="Visibility" Value="Visible"/>
                <Trigger.EnterActions>
                  <BeginStoryboard x:Name="Slide">
                    <Storyboard RepeatBehavior="Forever">
                      <DoubleAnimation Storyboard.TargetName="Slider" Storyboard.TargetProperty="(UIElement.RenderTransform).(TranslateTransform.X)"
                                       From="-70" To="300" Duration="0:0:1.3"/>
                    </Storyboard>
                  </BeginStoryboard>
                </Trigger.EnterActions>
                <Trigger.ExitActions><StopStoryboard BeginStoryboardName="Slide"/></Trigger.ExitActions>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Rows: no selection highlight, hover tint, divider -->
    <Style x:Key="Row" TargetType="ListBoxItem">
      <Setter Property="Focusable" Value="False"/>
      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="Bd" Background="Transparent" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Background" Value="#2A2A2A"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Dark context menu -->
    <Style TargetType="ContextMenu">
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ContextMenu">
            <Border Background="#2E2E2E" BorderBrush="#444444" BorderThickness="1" CornerRadius="6" Padding="0,4">
              <StackPanel IsItemsHost="True"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="Bd" Background="Transparent" CornerRadius="4" Margin="4,1" Padding="12,7" MinWidth="190">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="Bd" Property="Background" Value="#3D3D3D"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Thin dark scroll bars -->
    <ControlTemplate x:Key="ScrollThumb" TargetType="Thumb">
      <Border Background="#4A4A4A" CornerRadius="4" Margin="2"/>
    </ControlTemplate>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/>
      <Setter Property="MinWidth" Value="10"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb><Thumb Template="{StaticResource ScrollThumb}"/></Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/>
          <Setter Property="Height" Value="10"/>
          <Setter Property="MinHeight" Value="10"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb><Thumb Template="{StaticResource ScrollThumb}"/></Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="#2E2E2E"/>
      <Setter Property="Foreground" Value="#F2F2F2"/>
      <Setter Property="BorderBrush" Value="#444444"/>
      <Setter Property="Padding" Value="10,6"/>
    </Style>

    <!-- A check line on a Device Health card: a coloured dot, what it is, and its value -->
    <DataTemplate x:Key="CheckRow">
      <DockPanel Margin="0,3,0,3" Background="Transparent" ToolTip="{Binding Tip}">
        <Ellipse x:Name="Dot" DockPanel.Dock="Left" Width="7" Height="7" Fill="{StaticResource Good}" Margin="0,0,9,0" VerticalAlignment="Center"/>
        <TextBlock DockPanel.Dock="Left" Text="{Binding Label}" Foreground="#9A9A9A" FontSize="12.5" Margin="0,0,12,0" VerticalAlignment="Center"/>
        <TextBlock Text="{Binding Value}" Foreground="#E0E0E0" FontSize="12.5" TextAlignment="Right" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
      </DockPanel>
      <DataTemplate.Triggers>
        <DataTrigger Binding="{Binding Level}" Value="warn"><Setter TargetName="Dot" Property="Fill" Value="{StaticResource Warn}"/></DataTrigger>
        <DataTrigger Binding="{Binding Level}" Value="bad"><Setter TargetName="Dot" Property="Fill" Value="{StaticResource Bad}"/></DataTrigger>
        <DataTrigger Binding="{Binding Level}" Value="info"><Setter TargetName="Dot" Property="Fill" Value="#5E5E5E"/></DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>

    <!-- One app row. Column widths match the header grid. -->
    <DataTemplate x:Key="RowTemplate">
      <Grid x:Name="RowRoot" Height="60" Background="Transparent">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="52"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition x:Name="ColVer" Width="150"/>
          <ColumnDefinition x:Name="ColThird" Width="160"/>
          <ColumnDefinition x:Name="ColSource" Width="84"/>
          <ColumnDefinition x:Name="ColStatus" Width="230"/>
          <ColumnDefinition Width="112"/>
        </Grid.ColumnDefinitions>
        <Grid.ContextMenu>
          <ContextMenu>
            <MenuItem Header="{Binding ActionText}" Tag="update" IsEnabled="{Binding CanUpdate}"/>
            <MenuItem Header="{Binding InteractiveMenuText}" Tag="interactive" IsEnabled="{Binding CanUpdate}"/>
            <MenuItem Header="Install for all users" Tag="machine" IsEnabled="{Binding CanUpdate}" Visibility="{Binding IsDiscover, Converter={StaticResource B2V}}"/>
            <MenuItem Header="Install a specific version&#x2026;" Tag="version" IsEnabled="{Binding CanUpdate}" Visibility="{Binding IsDiscover, Converter={StaticResource B2V}}"/>
            <MenuItem Header="What's new in this update" Tag="notes" Visibility="{Binding HasNotes, Converter={StaticResource B2V}}"/>

            <MenuItem Header="Show details" Tag="details" Visibility="{Binding HasSource, Converter={StaticResource B2V}}"/>
            <MenuItem Header="Copy package ID" Tag="copyid"/>
            <MenuItem Header="Copy winget command" Tag="copycmd"/>
            <MenuItem Header="{Binding HideMenuText}" Tag="hide" IsEnabled="{Binding CanHold}" Visibility="{Binding OffersHold, Converter={StaticResource B2V}}"/>
          </ContextMenu>
        </Grid.ContextMenu>
        <CheckBox x:Name="RowCheck" Style="{StaticResource Check}" IsChecked="{Binding Selected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                  IsEnabled="{Binding CanUpdate}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,16,0">
          <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" FontSize="14" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
          <StackPanel Orientation="Horizontal" Margin="0,3,0,0">
            <TextBlock Text="{Binding Id}" Foreground="#8A8A8A" FontSize="12" FontFamily="Consolas" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
            <Border x:Name="PinTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#272B48"
                    ToolTip="winget only upgrades this app when asked for it by name (it is pinned or marked for explicit upgrade). Update all skips it.">
              <TextBlock Text="explicit" FontSize="10.5" Foreground="{StaticResource Violet}"/>
            </Border>
            <Border x:Name="HiddenTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#333333"
                    ToolTip="Hidden and kept at this version: Update all, automatic updates and winget itself (through a winget pin) leave it alone. Right-click > Unhide to allow updates again.">
              <TextBlock Text="hidden" FontSize="10.5" Foreground="#BDBDBD"/>
            </Border>
            <Border x:Name="WindowsTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#17414C"
                    ToolTip="Windows (or the app itself) keeps this app up to date, so winget doesn't need to and its update often fails. Update all and automatic updates leave it alone. Right-click > Let winget update it to change that.">
              <TextBlock Text="updated by Windows" FontSize="10.5" Foreground="{StaticResource Highlight}"/>
            </Border>
            <Border x:Name="StoreTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#272B48" ToolTip="From the Microsoft Store">
              <TextBlock Text="Store" FontSize="10.5" Foreground="{StaticResource Violet}"/>
            </Border>
            <Border x:Name="CategoryTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#333333">
              <TextBlock Text="{Binding Category}" FontSize="10.5" Foreground="#BDBDBD"/>
            </Border>
            <Border x:Name="UpdateTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#272B48">
              <Border.ToolTip><TextBlock><Run Text="Update available: "/><Run Text="{Binding Available, Mode=OneWay}"/><Run Text=" (see the Updates tab)"/></TextBlock></Border.ToolTip>
              <TextBlock Text="update" FontSize="10.5" Foreground="{StaticResource Violet}"/>
            </Border>
            <Border x:Name="ShortTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#3A2E1E" ToolTip="{Binding Detail}">
              <TextBlock Text="ID shortened" FontSize="10.5" Foreground="{StaticResource Warn}"/>
            </Border>
          </StackPanel>
        </StackPanel>
        <TextBlock x:Name="VerText" Grid.Column="2" Text="{Binding Version}" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,12,0" ToolTip="{Binding Version}"/>
        <StackPanel Grid.Column="3" VerticalAlignment="Center" Margin="0,0,12,0">
          <StackPanel x:Name="AvailPanel" Orientation="Horizontal">
            <TextBlock x:Name="AvailArrow" Text="&#xE72A;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="#6E6E6E" Margin="0,1,9,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="AvailText" Text="{Binding Available}" Foreground="{StaticResource Highlight}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" ToolTip="{Binding Available}"/>
          </StackPanel>
          <!-- Updates: release notes of the new version, when winget has them -->
          <Button x:Name="NotesLink" Style="{StaticResource LinkButton}" Content="What's new" Tag="notes" FontSize="11.5" Margin="19,3,0,0" HorizontalAlignment="Left" Visibility="Collapsed">
            <Button.ToolTip><ToolTip MaxWidth="480"><TextBlock Text="{Binding NotesTip}" TextWrapping="Wrap"/></ToolTip></Button.ToolTip>
          </Button>
        </StackPanel>
        <!-- Installed: size on disk -->
        <TextBlock x:Name="SizeText" Grid.Column="3" Text="{Binding SizeText}" Foreground="#BDBDBD" VerticalAlignment="Center" Margin="0,0,12,0" Visibility="Collapsed"/>
        <!-- Discover: the description, fetched in the background when the row is shown (then cached) -->
        <Grid x:Name="DescPanel" Grid.Column="3" VerticalAlignment="Center" Margin="0,0,20,0" Visibility="Collapsed">
          <TextBlock x:Name="DescText" Text="{Binding Description}" Foreground="#BDBDBD" FontSize="12.5" TextWrapping="Wrap" TextTrimming="CharacterEllipsis"
                     MaxHeight="36" LineHeight="17" Visibility="Collapsed">
            <TextBlock.ToolTip>
              <ToolTip MaxWidth="460"><TextBlock Text="{Binding DescriptionTip}" TextWrapping="Wrap"/></ToolTip>
            </TextBlock.ToolTip>
          </TextBlock>
        </Grid>
        <TextBlock x:Name="SrcText" Grid.Column="4" Text="{Binding Source}" Foreground="#8A8A8A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        <!-- Status: its own column on Updates; on Discover and Installed it only appears (over other columns) while a job runs -->
        <StackPanel x:Name="StatusPanel" Grid.Column="5" VerticalAlignment="Center" Margin="0,0,14,0">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="StatusGlyph" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,1,7,0" VerticalAlignment="Center" Visibility="Collapsed"/>
            <TextBlock x:Name="StatusText" Text="{Binding Detail}" Foreground="#8A8A8A" FontSize="12.5" TextTrimming="CharacterEllipsis" ToolTip="{Binding Detail}"/>
          </StackPanel>
          <ProgressBar x:Name="Bar" Style="{StaticResource Bar}" Margin="0,7,0,0" Visibility="Collapsed"
                       Value="{Binding Progress, Mode=OneWay}" IsIndeterminate="{Binding IsIndeterminate, Mode=OneWay}"/>
        </StackPanel>
        <Button x:Name="RowBtn" Grid.Column="6" Style="{StaticResource RowButton}" Content="{Binding ActionText}" Tag="update"
                IsEnabled="{Binding CanUpdate}" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,18,0"/>
      </Grid>
      <DataTemplate.Triggers>
        <DataTrigger Binding="{Binding ExplicitTarget}" Value="True"><Setter TargetName="PinTag" Property="Visibility" Value="Visible"/></DataTrigger>
        <DataTrigger Binding="{Binding IsConcealed}" Value="True">
          <Setter TargetName="PinTag" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="AvailText" Property="Foreground" Value="#8A8A8A"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding ShowHiddenTag}" Value="True"><Setter TargetName="HiddenTag" Property="Visibility" Value="Visible"/></DataTrigger>
        <DataTrigger Binding="{Binding IsWindowsUpdated}" Value="True"><Setter TargetName="WindowsTag" Property="Visibility" Value="Visible"/></DataTrigger>
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsUpdates}" Value="True"/>
            <Condition Binding="{Binding IsConcealed}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="RowRoot" Property="Opacity" Value="0.55"/>
        </MultiDataTrigger>
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsUpdates}" Value="True"/>
            <Condition Binding="{Binding HasNotes}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="NotesLink" Property="Visibility" Value="Visible"/>
        </MultiDataTrigger>

        <DataTrigger Binding="{Binding State}" Value="queued">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE823;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="#9A9A9A"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
          <Setter TargetName="StatusText" Property="Foreground" Value="#BDBDBD"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="running">
          <Setter TargetName="Bar" Property="Visibility" Value="Visible"/>
          <Setter TargetName="StatusText" Property="Foreground" Value="White"/>
        </DataTrigger>
        <!-- Installed: no selection; an available version only when there is one. Discover: the third column is the match/category -->
        <DataTrigger Binding="{Binding IsInstalledList}" Value="True"><Setter TargetName="RowCheck" Property="Visibility" Value="Hidden"/></DataTrigger>
        <DataTrigger Binding="{Binding HasAvailable}" Value="False"><Setter TargetName="AvailArrow" Property="Visibility" Value="Collapsed"/></DataTrigger>
        <DataTrigger Binding="{Binding IsDiscover}" Value="True">
          <Setter TargetName="AvailPanel" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="DescPanel" Property="Visibility" Value="Visible"/>
          <Setter TargetName="ColVer" Property="Width" Value="120"/>
          <Setter TargetName="ColThird" Property="Width" Value="1.6*"/>
          <Setter TargetName="ColSource" Property="Width" Value="0"/>
          <Setter TargetName="ColStatus" Property="Width" Value="0"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding IsInstalledList}" Value="True">
          <Setter TargetName="AvailPanel" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="SizeText" Property="Visibility" Value="Visible"/>
          <Setter TargetName="ColThird" Property="Width" Value="110"/>
          <Setter TargetName="ColStatus" Property="Width" Value="0"/>
        </DataTrigger>
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsInstalledList}" Value="True"/>
            <Condition Binding="{Binding HasAvailable}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="UpdateTag" Property="Visibility" Value="Visible"/>
        </MultiDataTrigger>
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsUpdates}" Value="False"/>
            <Condition Binding="{Binding Truncated}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="ShortTag" Property="Visibility" Value="Visible"/>
        </MultiDataTrigger>
        <!-- while a job runs: Discover shows its status over the description, Installed over the version and source -->
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsDiscover}" Value="True"/>
            <Condition Binding="{Binding HasState}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="DescPanel" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="StatusPanel" Property="Grid.Column" Value="3"/>
          <Setter TargetName="StatusPanel" Property="MaxWidth" Value="320"/>
          <Setter TargetName="StatusPanel" Property="HorizontalAlignment" Value="Left"/>
          <Setter TargetName="StatusPanel" Property="MinWidth" Value="220"/>
        </MultiDataTrigger>
        <MultiDataTrigger>
          <MultiDataTrigger.Conditions>
            <Condition Binding="{Binding IsInstalledList}" Value="True"/>
            <Condition Binding="{Binding HasState}" Value="True"/>
          </MultiDataTrigger.Conditions>
          <Setter TargetName="VerText" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="SizeText" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="SrcText" Property="Visibility" Value="Collapsed"/>
          <Setter TargetName="StatusPanel" Property="Grid.Column" Value="2"/>
          <Setter TargetName="StatusPanel" Property="Grid.ColumnSpan" Value="3"/>
        </MultiDataTrigger>
        <DataTrigger Binding="{Binding IsStore}" Value="True"><Setter TargetName="StoreTag" Property="Visibility" Value="Visible"/></DataTrigger>
        <DataTrigger Binding="{Binding HasCategory}" Value="True"><Setter TargetName="CategoryTag" Property="Visibility" Value="Visible"/></DataTrigger>
        <DataTrigger Binding="{Binding DescState}" Value="loading">
          <Setter TargetName="DescText" Property="Visibility" Value="Visible"/>
          <Setter TargetName="DescText" Property="Text" Value="Loading description&#x2026;"/>
          <Setter TargetName="DescText" Property="FontStyle" Value="Italic"/>
          <Setter TargetName="DescText" Property="Foreground" Value="#7A7A7A"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding DescState}" Value="ok">
          <Setter TargetName="DescText" Property="Visibility" Value="Visible"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding DescState}" Value="none">
          <Setter TargetName="DescText" Property="Visibility" Value="Visible"/>
          <Setter TargetName="DescText" Property="Text" Value="No description available"/>
          <Setter TargetName="DescText" Property="Foreground" Value="#7A7A7A"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="ok">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE73E;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="{StaticResource Good}"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
          <Setter TargetName="StatusText" Property="Foreground" Value="{StaticResource Good}"/>
          <Setter TargetName="RowBtn" Property="Visibility" Value="Hidden"/>
          <Setter TargetName="AvailText" Property="Foreground" Value="#BDBDBD"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="reboot">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE777;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="{StaticResource Warn}"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
          <Setter TargetName="StatusText" Property="Foreground" Value="{StaticResource Warn}"/>
          <Setter TargetName="RowBtn" Property="Visibility" Value="Hidden"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="error">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE783;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="{StaticResource Bad}"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
          <Setter TargetName="StatusText" Property="Foreground" Value="{StaticResource Bad}"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="skipped">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE946;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="#9A9A9A"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
        </DataTrigger>
        <DataTrigger Binding="{Binding State}" Value="cancelled">
          <Setter TargetName="StatusGlyph" Property="Text" Value="&#xE711;"/>
          <Setter TargetName="StatusGlyph" Property="Foreground" Value="#9A9A9A"/>
          <Setter TargetName="StatusGlyph" Property="Visibility" Value="Visible"/>
        </DataTrigger>
      </DataTemplate.Triggers>
    </DataTemplate>
  </Window.Resources>

  <Grid Background="#1E1E1E">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <Grid Margin="32,26,32,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Border x:Name="HeaderLogo" Width="52" Height="52" CornerRadius="12" Background="Transparent" Margin="0,0,16,0"/>
      <StackPanel Grid.Column="1" VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="Windows Manager" FontSize="26" FontWeight="Bold" Foreground="White"/>
          <TextBlock x:Name="HeaderVersion" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="10,0,0,4" VerticalAlignment="Bottom"/>
        </StackPanel>
        <TextBlock x:Name="SubTitle" Foreground="{StaticResource Muted}" Margin="0,3,0,0" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
      <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="BtnOptions" Style="{StaticResource Ghost}" Margin="0,0,8,0" BorderBrush="#383838" Padding="10,7" ToolTip="Options">
          <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="15"/>
        </Button>
        <Button x:Name="BtnSchedule" Style="{StaticResource Ghost}" Margin="0,0,12,0" BorderBrush="#383838" Padding="12,6"
                ToolTip="Automatic maintenance: app and Windows updates, cleanup and a health check, on a schedule">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE823;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="ScheduleText" Text="Automatic maintenance: off" FontSize="12.5" VerticalAlignment="Center"/>
          </StackPanel>
        </Button>
        <Border x:Name="AdminBadge" CornerRadius="13" Padding="11,5" Background="#262626" BorderBrush="#383838" BorderThickness="1" VerticalAlignment="Center">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="AdminGlyph" Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,1,7,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="AdminText" FontSize="12.5" VerticalAlignment="Center"/>
          </StackPanel>
        </Border>
        <Button x:Name="BtnElevate" Content="Restart as administrator" Margin="10,0,0,0"
                ToolTip="Run elevated so updates for apps installed for all users do not each ask for approval"/>
      </StackPanel>
    </Grid>

    <!-- Section tabs and the toolbar for the current section -->
    <StackPanel Grid.Row="1">
    <Border Margin="32,18,32,0" BorderBrush="#2A2A2A" BorderThickness="0,0,0,1">
      <StackPanel Orientation="Horizontal">
        <RadioButton x:Name="TabHealth" GroupName="Section" Style="{StaticResource Tab}" IsChecked="True" Content="Device Health" ToolTip="How this PC is doing: security, performance, reliability, battery, drives and more (Ctrl+1)"/>
        <RadioButton x:Name="TabUpdates" GroupName="Section" Style="{StaticResource Tab}" ToolTip="Apps with an update available (Ctrl+2)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Software Updates"/>
            <Border x:Name="UpdatesBadge" Margin="8,2,0,0" Padding="7,0,7,1" CornerRadius="9" Background="#17414C" VerticalAlignment="Center" Visibility="Collapsed">
              <TextBlock x:Name="UpdatesBadgeText" FontSize="11.5" Foreground="White"/>
            </Border>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="TabDiscover" GroupName="Section" Style="{StaticResource Tab}" Content="Discover Software" ToolTip="Find and install new apps (Ctrl+3)"/>
        <RadioButton x:Name="TabInstalled" GroupName="Section" Style="{StaticResource Tab}" ToolTip="Everything installed on this PC (Ctrl+4)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Installed Software"/>
            <TextBlock x:Name="InstalledCount" Foreground="#6E6E6E" Margin="8,0,0,0"/>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="TabStartup" GroupName="Section" Style="{StaticResource Tab}" Content="Startup" ToolTip="Apps that start when you sign in, and turning them on or off (Ctrl+5)"/>
        <RadioButton x:Name="TabDrivers" GroupName="Section" Style="{StaticResource Tab}" Content="Drivers" ToolTip="Your PC's hardware, its drivers, and driver updates from Windows Update and the vendor (Ctrl+6)"/>
        <RadioButton x:Name="TabWindows" GroupName="Section" Style="{StaticResource Tab}" ToolTip="Windows' own updates: security and cumulative updates, .NET, Defender and more (Ctrl+7)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="Windows Update"/>
            <Border x:Name="WinBadge" Margin="8,2,0,0" Padding="7,0,7,1" CornerRadius="9" Background="#17414C" VerticalAlignment="Center" Visibility="Collapsed">
              <TextBlock x:Name="WinBadgeText" FontSize="11.5" Foreground="White"/>
            </Border>
          </StackPanel>
        </RadioButton>
        <RadioButton x:Name="TabFeatures" GroupName="Section" Style="{StaticResource Tab}" Content="Windows Features" ToolTip="Windows' optional features, to turn on or off (Ctrl+8)"/>
        <RadioButton x:Name="TabCleanup" GroupName="Section" Style="{StaticResource Tab}" Content="Cleanup" ToolTip="Free up space: leftover files, large files and the biggest apps (Ctrl+9)"/>
        <RadioButton x:Name="TabExtras" GroupName="Section" Style="{StaticResource Tab}" Content="Extras" ToolTip="Windows tweaks you can undo, and shortcuts to Windows' hidden tools (Ctrl+0)"/>
      </StackPanel>
    </Border>
    <Grid x:Name="SectionToolbar" Margin="32,16,32,14">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="360"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Grid>
        <TextBox x:Name="Search" Padding="34,7,10,7"/>
        <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
        <TextBlock x:Name="SearchHint" Text="Search apps" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
          <TextBlock.Style>
            <Style TargetType="TextBlock">
              <Setter Property="Visibility" Value="Collapsed"/>
              <Style.Triggers>
                <DataTrigger Binding="{Binding Text, ElementName=Search}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
              </Style.Triggers>
            </Style>
          </TextBlock.Style>
        </TextBlock>
      </Grid>

      <StackPanel Grid.Column="2" Orientation="Horizontal">
        <Button x:Name="BtnSearchGo" Style="{StaticResource Primary}" Visibility="Collapsed" ToolTip="Search winget (Enter)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="Search winget"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnImportList" Style="{StaticResource Ghost}" BorderBrush="#383838" Padding="14,8" Visibility="Collapsed"
                ToolTip="Open an app list (from Export list, winget export, or a setup backup) and install the apps in it">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE8E5;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="Import list"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnExportList" Style="{StaticResource Ghost}" BorderBrush="#383838" Padding="14,8" Visibility="Collapsed"
                ToolTip="Save the apps on this PC to a file, to install them on another PC (or after a reset)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="Export list"/>
          </StackPanel>
        </Button>
        <ToggleButton x:Name="ChkWingetOnly" Content="winget packages only" Style="{StaticResource Chip}" Margin="0,0,8,0" VerticalAlignment="Center" Visibility="Collapsed"
                      ToolTip="Hide apps that winget did not install and has no package for"/>
        <Button x:Name="BtnShowHidden" Style="{StaticResource Ghost}" Padding="14,8" Visibility="Collapsed"
                ToolTip="Show or hide the updates you have hidden">
          <StackPanel Orientation="Horizontal">
            <TextBlock x:Name="ShowHiddenGlyph" Text="&#xE7B3;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="ShowHiddenText" Text="Show hidden"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnRefresh" ToolTip="Check for updates again (F5)">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock Text="Refresh"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnUpdateSelected" Content="Update selected"/>
        <Button x:Name="BtnInstallSelected" Style="{StaticResource Primary}" Margin="0" Visibility="Collapsed">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="InstallSelectedText" Text="Install selected"/>
          </StackPanel>
        </Button>
        <Button x:Name="BtnUpdateAll" Style="{StaticResource Primary}" Margin="0">
          <StackPanel Orientation="Horizontal">
            <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="UpdateAllText" Text="Update all"/>
          </StackPanel>
        </Button>
      </StackPanel>
    </Grid>
    </StackPanel>

    <!-- App list card -->
    <Border x:Name="MainCard" Grid.Row="2" Margin="32,0,32,18" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
        </Grid.RowDefinitions>
        <Border x:Name="ColumnHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
          <Grid Height="44">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="52"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition x:Name="HColVer" Width="150"/>
              <ColumnDefinition x:Name="HColThird" Width="160"/>
              <ColumnDefinition x:Name="HColSource" Width="84"/>
              <ColumnDefinition x:Name="HColStatus" Width="230"/>
              <ColumnDefinition Width="112"/>
            </Grid.ColumnDefinitions>
            <CheckBox x:Name="CheckAll" Style="{StaticResource Check}" HorizontalAlignment="Center" VerticalAlignment="Center" ToolTip="Select all shown"/>
            <Button x:Name="SortName" Grid.Column="1" Style="{StaticResource HeaderButton}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="APP" FontSize="11.5" FontWeight="SemiBold"/>
                <TextBlock x:Name="SortNameGlyph" Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" FontSize="9" Margin="6,2,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <TextBlock x:Name="HdrVersion" Grid.Column="2" Text="INSTALLED" FontSize="11.5" FontWeight="SemiBold" Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
            <TextBlock x:Name="HdrAvailable" Grid.Column="3" Text="AVAILABLE" FontSize="11.5" FontWeight="SemiBold" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="19,0,0,0"/>
            <Button x:Name="SortSize" Grid.Column="3" Style="{StaticResource HeaderButton}" Visibility="Collapsed" ToolTip="Size on disk, as each app reports it to Windows. Store apps and some others don't report one.">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="SIZE" FontSize="11.5" FontWeight="SemiBold"/>
                <TextBlock x:Name="SortSizeGlyph" FontFamily="Segoe MDL2 Assets" FontSize="9" Margin="6,2,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <Button x:Name="SortSource" Grid.Column="4" Style="{StaticResource HeaderButton}">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="SOURCE" FontSize="11.5" FontWeight="SemiBold"/>
                <TextBlock x:Name="SortSourceGlyph" FontFamily="Segoe MDL2 Assets" FontSize="9" Margin="6,2,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </Button>
            <TextBlock x:Name="HdrStatus" Grid.Column="5" Text="STATUS" FontSize="11.5" FontWeight="SemiBold" Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
          </Grid>
        </Border>
        <ListBox x:Name="List" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}"
                 ItemTemplate="{StaticResource RowTemplate}" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                 VirtualizingPanel.ScrollUnit="Pixel" Focusable="False"/>

        <!-- States shown instead of the list -->
        <StackPanel x:Name="LoadingPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
          <ProgressBar Style="{StaticResource Bar}" Width="240" IsIndeterminate="True"/>
          <TextBlock x:Name="LoadingTitle" Text="Checking for updates" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,20,0,0"/>
          <TextBlock x:Name="LoadingText" Text="winget is querying its sources. This can take a minute the first time." Foreground="{StaticResource Muted}" HorizontalAlignment="Center" Margin="0,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="EmptyPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
          <Border Width="64" Height="64" CornerRadius="32" Background="#1F3326" HorizontalAlignment="Center">
            <TextBlock Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="26" Foreground="{StaticResource Good}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="EmptyTitle" Text="Everything is up to date" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,18,0,0"/>
          <TextBlock x:Name="EmptyText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" Margin="0,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="IdlePanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
          <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="28" Foreground="#6E6E6E" HorizontalAlignment="Center"/>
          <TextBlock Text="Ready to check for updates" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,16,0,0"/>
          <TextBlock Text="Checking when the app opens is turned off in Options. Click Refresh or press F5." Foreground="{StaticResource Muted}" HorizontalAlignment="Center" Margin="0,6,0,0"/>
        </StackPanel>
        <StackPanel x:Name="NoMatchPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="28" Foreground="#6E6E6E" HorizontalAlignment="Center"/>
          <TextBlock x:Name="NoMatchText" FontSize="15" HorizontalAlignment="Center" Margin="0,14,0,0"/>
        </StackPanel>
        <StackPanel x:Name="ErrorPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="620" Visibility="Collapsed">
          <Border Width="64" Height="64" CornerRadius="32" Background="#3A2220" HorizontalAlignment="Center">
            <TextBlock Text="&#xE783;" FontFamily="Segoe MDL2 Assets" FontSize="26" Foreground="{StaticResource Bad}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock x:Name="ErrorTitle" Text="Couldn't check for updates" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" Margin="0,18,0,0"/>
          <TextBlock x:Name="ErrorText" Foreground="{StaticResource Muted}" TextWrapping="Wrap" TextAlignment="Center" Margin="0,6,0,0"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,18,0,0">
            <Button x:Name="BtnRetry" Content="Try again"/>
            <Button x:Name="BtnGetWinget" Content="Get App Installer" Style="{StaticResource Primary}" Margin="0" Visibility="Collapsed"/>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Border>

    <!-- Drivers: the PC's vendor and its driver tool, driver updates, and every device's driver -->
    <Grid x:Name="DriversPanel" Grid.Row="2" Margin="32,16,32,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border x:Name="DrvNote" Grid.Row="2" Background="#3A3120" BorderBrush="#6B5420" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12" Visibility="Collapsed">
        <DockPanel>
          <TextBlock DockPanel.Dock="Left" Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{StaticResource Warn}" Margin="0,1,10,0" VerticalAlignment="Top"/>
          <Button x:Name="DrvNoteAction" DockPanel.Dock="Right" Content="Stop waiting" Margin="12,0,0,0" Padding="12,5" VerticalAlignment="Center" Visibility="Collapsed"/>
          <TextBlock x:Name="DrvNoteText" Foreground="#E8D9B5" FontSize="12.5" TextWrapping="Wrap" LineHeight="18" VerticalAlignment="Center"/>
        </DockPanel>
      </Border>
      <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="DrvSupport" Style="{StaticResource Ghost}" Content="Driver downloads" Visibility="Collapsed" ToolTip="Open the vendor's driver download page for this PC"/>
            <Button x:Name="DrvOpenTool" Style="{StaticResource Ghost}" Visibility="Collapsed"/>
            <Button x:Name="DrvReinstallAll" Content="Reinstall all drivers" Visibility="Collapsed"
                    ToolTip="Dell Command | Update's driver restore: reinstalls every base driver for this model (dcu-cli /driverInstall). Useful after a reset, or when several devices misbehave."/>
            <Button x:Name="DrvToolAction" Style="{StaticResource Primary}" Margin="0" Visibility="Collapsed"/>
          </StackPanel>
          <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
            <TextBlock Text="&#xE7F8;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
            <TextBlock x:Name="DrvMaker" FontSize="16" FontWeight="SemiBold" Foreground="White" TextTrimming="CharacterEllipsis" Text="Reading your PC's hardware&#x2026;"/>
            <TextBlock x:Name="DrvModel" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="DrvToolText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
            <!-- Tools for this PC's components (Intel, NVIDIA, AMD), whoever made the PC -->
            <WrapPanel x:Name="DrvExtras" Margin="0,8,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Row="1" Margin="0,14,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="260"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <RadioButton x:Name="DrvViewDevices" GroupName="DrvView" Style="{StaticResource Chip}" Margin="0,0,8,0">
            <TextBlock x:Name="DrvViewDevicesText" Text="Devices"/>
          </RadioButton>
          <RadioButton x:Name="DrvViewUpdates" GroupName="DrvView" Style="{StaticResource Chip}" Margin="0,0,16,0" IsChecked="True">
            <TextBlock x:Name="DrvViewUpdatesText" Text="Driver Updates"/>
          </RadioButton>
        </StackPanel>
        <Grid Grid.Column="1">
          <TextBox x:Name="DrvSearch" Padding="34,7,10,7"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <TextBlock Text="Filter" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Visibility" Value="Collapsed"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Text, ElementName=DrvSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </Grid>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <StackPanel x:Name="DrvUpdateTools" Orientation="Horizontal" Visibility="Collapsed">
            <ToggleButton x:Name="DrvTypeDriver" Content="Drivers" Style="{StaticResource Chip}" IsChecked="True" Margin="0,0,6,0"/>
            <ToggleButton x:Name="DrvTypeFirmware" Content="Firmware" Style="{StaticResource Chip}" IsChecked="True" Margin="0,0,6,0"/>
            <ToggleButton x:Name="DrvTypeBios" Content="BIOS" Style="{StaticResource Chip}" Margin="0,0,6,0"
                          ToolTip="BIOS updates restart into the update. BitLocker is suspended for one restart automatically."/>
            <ToggleButton x:Name="DrvTypeApp" Content="Dell apps" Style="{StaticResource Chip}" IsChecked="True" Margin="0,0,12,0"/>
          </StackPanel>
          <ToggleButton x:Name="DrvProblemsOnly" Content="Problems only" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
          <ToggleButton x:Name="DrvRestore" Content="Restore point first" Style="{StaticResource Chip}" IsChecked="True" Margin="0,0,8,0"
                        ToolTip="Create a Windows restore point before changing drivers (needs System Protection; Windows makes at most one a day)"/>
          <Button x:Name="DrvRefresh" ToolTip="Read the devices again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="DrvRefreshText" Text="Refresh"/>
            </StackPanel>
          </Button>
          <Button x:Name="DrvApply" Style="{StaticResource Primary}" Margin="0" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="DrvApplyText" Text="Install updates"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
      <Border Grid.Row="3" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="DrvDevHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="130"/>
                <ColumnDefinition Width="95"/>
                <ColumnDefinition Width="150"/>
                <ColumnDefinition Width="160"/>
                <ColumnDefinition Width="272"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="DEVICE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="DRIVER" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="DATE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="PROVIDER" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="4" Text="STATUS" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border x:Name="DrvUpdHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1" Visibility="Collapsed">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="120"/>
                <ColumnDefinition Width="150"/>
                <ColumnDefinition Width="170"/>
                <ColumnDefinition Width="80"/>
                <ColumnDefinition Width="100"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="UPDATE" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="36,0,0,0"/>
              <TextBlock Grid.Column="1" Text="TYPE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="VERSION" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="FROM" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="4" Text="SIZE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="5" Text="RELEASED" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="DrvDevices" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid Height="56" Margin="20,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="130"/>
                    <ColumnDefinition Width="95"/>
                    <ColumnDefinition Width="150"/>
                    <ColumnDefinition Width="160"/>
                    <ColumnDefinition Width="272"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,14,0">
                    <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding InstanceId}"/>
                    <TextBlock Text="{Binding SubText}" Foreground="#8A8A8A" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="1" Text="{Binding Version}" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Inf}" Margin="0,0,10,0"/>
                  <TextBlock Grid.Column="2" Text="{Binding Date}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="3" Text="{Binding Provider}" Foreground="#9A9A9A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0"/>
                  <StackPanel Grid.Column="4" VerticalAlignment="Center" Margin="0,0,10,0">
                    <TextBlock x:Name="St" Text="{Binding StatusText}" Foreground="#9A9A9A" FontSize="12.5" TextTrimming="CharacterEllipsis" ToolTip="{Binding StatusText}"/>
                    <ProgressBar x:Name="StBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,6,0,0" Visibility="Collapsed"/>
                  </StackPanel>
                  <StackPanel Grid.Column="5" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button Content="Roll back" Tag="rollback" Style="{StaticResource RowButton}" IsEnabled="{Binding CanRollback}" Margin="0,0,6,0" MinWidth="0"
                            ToolTip="{Binding RollbackTip}" ToolTipService.ShowOnDisabled="True"/>
                    <Button Content="Reinstall" Tag="reinstall" Style="{StaticResource RowButton}" IsEnabled="{Binding CanAct}" Margin="0,0,6,0" MinWidth="0"
                            ToolTip="Remove the device and let Windows find it again, reinstalling its driver (pnputil /remove-device, then /scan-devices)"/>
                    <Button Content="Remove" Tag="remove" Style="{StaticResource RowButton}" IsEnabled="{Binding CanRemove}" MinWidth="0"
                            ToolTip="Uninstall this third-party driver (pnputil /delete-driver /uninstall); the device falls back to another driver. Windows' own drivers can't be removed."/>
                  </StackPanel>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding HasProblem}" Value="True"><Setter TargetName="St" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="StBar" Property="Visibility" Value="Visible"/><Setter TargetName="St" Property="Foreground" Value="White"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="ok"><Setter TargetName="St" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="reboot"><Setter TargetName="St" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="St" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <ListBox x:Name="DrvUpdates" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" Visibility="Collapsed"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid x:Name="UpdRow" Height="56" Margin="20,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="120"/>
                    <ColumnDefinition Width="150"/>
                    <ColumnDefinition Width="170"/>
                    <ColumnDefinition Width="80"/>
                    <ColumnDefinition Width="100"/>
                  </Grid.ColumnDefinitions>
                  <DockPanel VerticalAlignment="Center" Margin="0,0,14,0">
                    <Button DockPanel.Dock="Right" Content="{Binding ActionText}" Tag="drvaction" Style="{StaticResource RowButton}" Margin="10,0,0,0" VerticalAlignment="Center"
                            Visibility="{Binding HasAction, Converter={StaticResource B2V}}" ToolTip="{Binding ActionTip}"/>
                    <CheckBox x:Name="UpdCheck" DockPanel.Dock="Left" Style="{StaticResource Check}" IsChecked="{Binding Included, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                              IsEnabled="{Binding Pickable}" VerticalAlignment="Center" Margin="-6,0,8,0"
                              ToolTip="Windows Update and NVIDIA drivers are picked one by one; Dell Command | Update's by type, with the buttons above"/>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <TextBlock Text="{Binding Category}" Foreground="#8A8A8A" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                    </StackPanel>
                  </DockPanel>
                  <TextBlock Grid.Column="1" Text="{Binding Type}" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,8,0"/>
                  <TextBlock Grid.Column="2" Text="{Binding Version}" Foreground="{StaticResource Highlight}" FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0"/>
                  <StackPanel Grid.Column="3" VerticalAlignment="Center">
                    <TextBlock Text="{Binding Source}" Foreground="#BDBDBD" FontSize="12.5" TextTrimming="CharacterEllipsis"/>
                    <TextBlock Text="{Binding Severity}" Foreground="#8A8A8A" FontSize="12" TextTrimming="CharacterEllipsis"/>
                  </StackPanel>
                  <TextBlock Grid.Column="4" Text="{Binding SizeText}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="5" Text="{Binding Released}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Included}" Value="False"><Setter TargetName="UpdRow" Property="Opacity" Value="0.4"/></DataTrigger>
                  <DataTrigger Binding="{Binding HasAction}" Value="True"><Setter TargetName="UpdCheck" Property="Visibility" Value="Hidden"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="DrvMsgPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="560" Visibility="Collapsed">
            <ProgressBar x:Name="DrvMsgBar" Style="{StaticResource Bar}" Width="240" IsIndeterminate="True" Margin="0,0,0,20"/>
            <TextBlock x:Name="DrvMsgTitle" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
            <TextBlock x:Name="DrvMsgText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,6,0,0"/>
            <Button x:Name="DrvMsgAction" Style="{StaticResource Primary}" HorizontalAlignment="Center" Margin="0,18,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Startup: apps that start when you sign in, and whether Windows lets them -->
    <Grid x:Name="StartupPanel" Grid.Row="2" Margin="32,16,32,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="StOpenTaskMgr" Style="{StaticResource Ghost}" Content="Open Task Manager" Margin="0" ToolTip="Task Manager's Startup apps page also shows how much each app slows down sign-in"/>
          </StackPanel>
          <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
            <TextBlock Text="&#xE7E8;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
            <TextBlock x:Name="StTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" TextTrimming="CharacterEllipsis" Text="Apps that start with Windows"/>
            <TextBlock x:Name="StText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Row="1" Margin="0,14,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="260"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid>
          <TextBox x:Name="StSearch" Padding="34,7,10,7"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <TextBlock Text="Filter" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Visibility" Value="Collapsed"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Text, ElementName=StSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </Grid>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <ToggleButton x:Name="StOffOnly" Content="Turned off only" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
          <Button x:Name="StRefresh" ToolTip="Read the startup apps again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Refresh"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
      <Border Grid.Row="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="StHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="190"/>
                <ColumnDefinition Width="190"/>
                <ColumnDefinition Width="90"/>
                <ColumnDefinition Width="110"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="APP" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="PUBLISHER" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="STARTS FROM" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="STATUS" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="StList" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid x:Name="StRow" Height="56" Margin="20,0,16,0" Background="Transparent">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="190"/>
                    <ColumnDefinition Width="190"/>
                    <ColumnDefinition Width="90"/>
                    <ColumnDefinition Width="110"/>
                  </Grid.ColumnDefinitions>
                  <Grid.ContextMenu>
                    <ContextMenu>
                      <MenuItem Header="{Binding ActionText}" Tag="sttoggle" IsEnabled="{Binding CanToggle}"/>
                      <MenuItem Header="Open file location" Tag="stopen"/>
                      <MenuItem Header="Copy command" Tag="stcopy"/>
                    </ContextMenu>
                  </Grid.ContextMenu>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,14,0">
                    <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                    <TextBlock Text="{Binding Command}" Foreground="#8A8A8A" FontSize="12" FontFamily="Consolas" TextTrimming="CharacterEllipsis" Margin="0,2,0,0" ToolTip="{Binding Command}"/>
                  </StackPanel>
                  <TextBlock Grid.Column="1" Text="{Binding Publisher}" Foreground="#9A9A9A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0" ToolTip="{Binding Publisher}"/>
                  <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center" ToolTip="{Binding AdminTip}" Background="Transparent">
                    <TextBlock x:Name="StShield" Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#9A9A9A" Margin="0,1,6,0" VerticalAlignment="Center" Visibility="{Binding NeedsAdmin, Converter={StaticResource B2V}}"/>
                    <TextBlock Text="{Binding LocationText}" Foreground="#9A9A9A" FontSize="12.5" TextTrimming="CharacterEllipsis"/>
                  </StackPanel>
                  <StackPanel Grid.Column="3" VerticalAlignment="Center">
                    <TextBlock x:Name="StStatus" Text="{Binding StatusText}" Foreground="{StaticResource Good}" FontSize="12.5" TextTrimming="CharacterEllipsis" ToolTip="{Binding StatusText}"/>
                    <ProgressBar x:Name="StBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,6,10,0" Visibility="Collapsed"/>
                  </StackPanel>
                  <Button Grid.Column="4" Content="{Binding ActionText}" Tag="sttoggle" Style="{StaticResource RowButton}" IsEnabled="{Binding CanToggle}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Enabled}" Value="False">
                    <Setter TargetName="StStatus" Property="Foreground" Value="#8A8A8A"/>
                    <Setter TargetName="StRow" Property="Opacity" Value="0.6"/>
                  </DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="StBar" Property="Visibility" Value="Visible"/><Setter TargetName="StStatus" Property="Foreground" Value="White"/><Setter TargetName="StRow" Property="Opacity" Value="1"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="StStatus" Property="Foreground" Value="{StaticResource Bad}"/><Setter TargetName="StRow" Property="Opacity" Value="1"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="StMsgPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="560" Visibility="Collapsed">
            <ProgressBar x:Name="StMsgBar" Style="{StaticResource Bar}" Width="240" IsIndeterminate="True" Margin="0,0,0,20"/>
            <TextBlock x:Name="StMsgTitle" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
            <TextBlock x:Name="StMsgText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,6,0,0"/>
            <Button x:Name="StMsgAction" Style="{StaticResource Primary}" HorizontalAlignment="Center" Margin="0,18,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Windows Update: Windows' own updates (not drivers, which are on the Drivers tab), and its recent history -->
    <Grid x:Name="WinPanel" Grid.Row="2" Margin="32,16,32,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
            <Button x:Name="WinSettings" Style="{StaticResource Ghost}" Content="Windows Update settings" ToolTip="Open Settings > Windows Update"/>
            <Button x:Name="WinRestart" Style="{StaticResource Primary}" Content="Restart now" Margin="0" Visibility="Collapsed" ToolTip="Restart Windows to finish installing updates"/>
          </StackPanel>
          <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
            <TextBlock Text="&#xE895;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
            <TextBlock x:Name="WinTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" TextTrimming="CharacterEllipsis" Text="Windows"/>
            <TextBlock x:Name="WinVersion" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="WinStatus" Foreground="#BDBDBD" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Row="1" Margin="0,14,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="260"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <RadioButton x:Name="WinViewAvail" GroupName="WinView" Style="{StaticResource Chip}" Margin="0,0,8,0" IsChecked="True">
            <TextBlock x:Name="WinViewAvailText" Text="Available"/>
          </RadioButton>
          <RadioButton x:Name="WinViewHistory" GroupName="WinView" Style="{StaticResource Chip}" Margin="0,0,16,0">
            <TextBlock Text="Installed recently"/>
          </RadioButton>
        </StackPanel>
        <Grid Grid.Column="1">
          <TextBox x:Name="WinSearch" Padding="34,7,10,7"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <TextBlock Text="Filter" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Visibility" Value="Collapsed"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Text, ElementName=WinSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </Grid>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <ToggleButton x:Name="WinRestore" Content="Restore point first" Style="{StaticResource Chip}" IsChecked="True" Margin="0,0,8,0"
                        ToolTip="Create a Windows restore point before installing (needs System Protection). Shared with the Drivers tab."/>
          <Button x:Name="WinRefresh" ToolTip="Ask Windows Update again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="WinRefreshText" Text="Refresh"/>
            </StackPanel>
          </Button>
          <Button x:Name="WinApply" Style="{StaticResource Primary}" Margin="0" Visibility="Collapsed">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock x:Name="WinApplyText" Text="Install updates"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
      <Border x:Name="WinNote" Grid.Row="2" Background="#3A3120" BorderBrush="#6B5420" BorderThickness="1" CornerRadius="8" Padding="14,10" Margin="0,0,0,12" Visibility="Collapsed">
        <DockPanel>
          <TextBlock DockPanel.Dock="Left" Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="{StaticResource Warn}" Margin="0,1,10,0" VerticalAlignment="Top"/>
          <TextBlock x:Name="WinNoteText" Foreground="#E8D9B5" FontSize="12.5" TextWrapping="Wrap" LineHeight="18" VerticalAlignment="Center"/>
        </DockPanel>
      </Border>
      <Border Grid.Row="3" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="WinAvailHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="150"/>
                <ColumnDefinition Width="110"/>
                <ColumnDefinition Width="80"/>
                <ColumnDefinition Width="100"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="UPDATE" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="36,0,0,0"/>
              <TextBlock Grid.Column="1" Text="TYPE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="SEVERITY" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="SIZE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="4" Text="RELEASED" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <Border x:Name="WinHistHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1" Visibility="Collapsed">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="230"/>
                <ColumnDefinition Width="150"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="UPDATE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="RESULT" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="WHEN" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="WinList" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid x:Name="WinRow" Height="56" Margin="20,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="150"/>
                    <ColumnDefinition Width="110"/>
                    <ColumnDefinition Width="80"/>
                    <ColumnDefinition Width="100"/>
                  </Grid.ColumnDefinitions>
                  <DockPanel VerticalAlignment="Center" Margin="0,0,14,0">
                    <CheckBox DockPanel.Dock="Left" Style="{StaticResource Check}" IsChecked="{Binding Included, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" VerticalAlignment="Center" Margin="-6,0,8,0"/>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock Text="{Binding Title}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis">
                        <TextBlock.ToolTip><ToolTip MaxWidth="480"><TextBlock Text="{Binding Description}" TextWrapping="Wrap"/></ToolTip></TextBlock.ToolTip>
                      </TextBlock>
                      <TextBlock Text="{Binding SubText}" Foreground="#8A8A8A" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                    </StackPanel>
                  </DockPanel>
                  <TextBlock Grid.Column="1" Text="{Binding Type}" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,8,0"/>
                  <TextBlock x:Name="WinSev" Grid.Column="2" Text="{Binding Severity}" Foreground="#9A9A9A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
                  <TextBlock Grid.Column="3" Text="{Binding SizeText}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="4" Text="{Binding Released}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Included}" Value="False"><Setter TargetName="WinRow" Property="Opacity" Value="0.4"/></DataTrigger>
                  <DataTrigger Binding="{Binding Severity}" Value="Critical"><Setter TargetName="WinSev" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Severity}" Value="Important"><Setter TargetName="WinSev" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <ListBox x:Name="WinHistList" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False" Visibility="Collapsed">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid Height="56" Margin="20,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="230"/>
                    <ColumnDefinition Width="150"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,0,14,0">
                    <TextBlock Text="{Binding Title}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Title}"/>
                    <TextBlock Text="{Binding SubText}" Foreground="#8A8A8A" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                  </StackPanel>
                  <TextBlock x:Name="HRes" Grid.Column="1" Text="{Binding ResultText}" Foreground="#9A9A9A" FontSize="12.5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding ResultText}" Margin="0,0,10,0"/>
                  <TextBlock Grid.Column="2" Text="{Binding Released}" Foreground="#9A9A9A" VerticalAlignment="Center"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding Result}" Value="ok"><Setter TargetName="HRes" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                  <DataTrigger Binding="{Binding Result}" Value="error"><Setter TargetName="HRes" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="WinMsgPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="560" Visibility="Collapsed">
            <ProgressBar x:Name="WinMsgBar" Style="{StaticResource Bar}" Width="240" IsIndeterminate="True" Margin="0,0,0,20"/>
            <TextBlock x:Name="WinMsgTitle" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
            <TextBlock x:Name="WinMsgText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,6,0,0"/>
            <Button x:Name="WinMsgAction" Style="{StaticResource Primary}" HorizontalAlignment="Center" Margin="0,18,0,0" Visibility="Collapsed"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Device Health: the landing page. The PC and how it's doing, at a glance -->
    <ScrollViewer x:Name="HealthPanel" Grid.Row="2" Margin="32,16,20,18" Padding="0,0,12,0" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
      <StackPanel>
        <DockPanel Margin="0,0,0,12">
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="HlFix" Style="{StaticResource Primary}" ToolTip="Check this PC for what can make it run better (updates, leftover files, security), and fix what you choose with one click">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Fix my PC"/>
            </StackPanel>
          </Button>
          <Button x:Name="HlReport" ToolTip="Save Device Health, installed software, startup apps and waiting updates as a web page, to keep or send to someone helping">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE74E;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Save report"/>
            </StackPanel>
          </Button>
          <Button x:Name="HlRefresh" ToolTip="Read the PC's health again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Refresh"/>
            </StackPanel>
          </Button>
          </StackPanel>
          <ProgressBar x:Name="HlBusy" DockPanel.Dock="Left" Style="{StaticResource Bar}" Width="90" IsIndeterminate="True" Margin="0,0,12,0" VerticalAlignment="Center" Visibility="Collapsed"/>
          <TextBlock x:Name="HlSummary" Foreground="{StaticResource Muted}" VerticalAlignment="Center" TextWrapping="Wrap"/>
        </DockPanel>
        <!-- Six columns: three cards a row, each two columns wide. Without a battery the top row is two cards, three
             columns each (Update-HealthView). Every card keeps a 12 px gap right and below; the grid's -12 px right
             margin takes back the last one. -->
        <Grid Margin="0,0,-12,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
          <Border x:Name="HlSysCard" Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="THIS PC" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlSysTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="HlSysText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap" LineHeight="19"/>
              <TextBlock x:Name="HlSysNote" Foreground="{StaticResource Warn}" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
          <Border x:Name="HlBiosCard" Grid.Row="0" Grid.Column="2" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="BIOS AND FIRMWARE" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlBiosTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="HlBiosText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap" LineHeight="19"/>
              <Button x:Name="HlBiosCheck" Style="{StaticResource Ghost}" Content="Check for updates" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Opens the Drivers tab and checks Windows Update and the vendor's tool, which also offer BIOS and firmware updates"/>
            </StackPanel>
          </Border>
          <Border x:Name="HlBatCard" Grid.Row="0" Grid.Column="4" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="BATTERY" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlBatTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="HlBatBar" Style="{StaticResource Bar}" Height="6" Margin="0,10,0,0" Visibility="Collapsed"/>
              <TextBlock x:Name="HlBatText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap" LineHeight="19"/>
              <Button x:Name="HlBatReport" Style="{StaticResource Ghost}" Content="Battery report" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Windows' detailed battery report (powercfg /batteryreport): capacity history, recent use and life estimates" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="SECURITY" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlSecTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ItemsControl x:Name="HlSecItems" Margin="0,8,0,0" ItemTemplate="{StaticResource CheckRow}"/>
              <Button x:Name="HlSecOpen" Style="{StaticResource Ghost}" Content="Windows Security" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Open Windows Security"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="1" Grid.Column="2" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="PERFORMANCE" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlPerfTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ProgressBar x:Name="HlMemBar" Style="{StaticResource Bar}" Height="6" Margin="0,10,0,0"/>
              <ItemsControl x:Name="HlPerfItems" Margin="0,8,0,0" ItemTemplate="{StaticResource CheckRow}"/>
              <Button x:Name="HlPerfOpen" Style="{StaticResource Ghost}" Content="Task Manager" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Open Task Manager to see what is using the processor and memory"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="1" Grid.Column="4" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="RELIABILITY" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlRelTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ItemsControl x:Name="HlRelItems" Margin="0,8,0,0" ItemTemplate="{StaticResource CheckRow}"/>
              <Button x:Name="HlRelOpen" Style="{StaticResource Ghost}" Content="Reliability history" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Windows' Reliability Monitor: every crash, failed update and problem, day by day"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="UPDATES" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlUpdTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ItemsControl x:Name="HlUpdItems" Margin="0,8,0,0" ItemTemplate="{StaticResource CheckRow}"/>
              <Button x:Name="HlUpdOpen" Style="{StaticResource Ghost}" Content="See updates" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Open the tab with the updates"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="NETWORK" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlNetTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <ItemsControl x:Name="HlNetItems" Margin="0,8,0,0" ItemTemplate="{StaticResource CheckRow}"/>
              <Button x:Name="HlNetOpen" Style="{StaticResource Ghost}" Content="Network settings" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Open Settings > Network and internet"/>
            </StackPanel>
          </Border>
          <Border Grid.Row="2" Grid.Column="4" Grid.ColumnSpan="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="CLEANUP" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlCleanSumTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Margin="0,10,0,0" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="HlCleanSumText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap" LineHeight="19"/>
              <Button x:Name="HlCleanOpen" Style="{StaticResource Ghost}" Content="Open Cleanup" HorizontalAlignment="Left" Margin="0,10,0,0" ToolTip="Free up space: leftover files, large files and the biggest apps"/>
            </StackPanel>
          </Border>
          <!-- Drives and Temperatures side by side, half the width each -->
          <Border Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="3" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="DRIVES" Style="{StaticResource Label}"/>
              <ItemsControl x:Name="HlVolumes" Margin="0,10,0,0">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,5,0,5">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="130"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <ProgressBar x:Name="VolBar" Grid.Column="1" Style="{StaticResource Bar}" Height="8" Value="{Binding UsedPct, Mode=OneWay}" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="{Binding Detail}" Foreground="#9A9A9A" FontSize="12.5" Margin="16,0,0,0" VerticalAlignment="Center"/>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding Level}" Value="warn"><Setter TargetName="VolBar" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                      <DataTrigger Binding="{Binding Level}" Value="bad"><Setter TargetName="VolBar" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
              <ItemsControl x:Name="HlDisks" Margin="0,6,0,0">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,5,0,5">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <TextBlock Grid.Column="1" Text="{Binding Detail}" Foreground="#9A9A9A" FontSize="12.5" Margin="16,0,0,0" MaxWidth="260" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Detail}"/>
                      <TextBlock x:Name="DiskHealth" Grid.Column="2" Text="{Binding Health}" Foreground="{StaticResource Good}" FontSize="12.5" Margin="16,0,0,0" VerticalAlignment="Center"/>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding Level}" Value="warn"><Setter TargetName="DiskHealth" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                      <DataTrigger Binding="{Binding Level}" Value="bad"><Setter TargetName="DiskHealth" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                      <DataTrigger Binding="{Binding Level}" Value="info"><Setter TargetName="DiskHealth" Property="Foreground" Value="#9A9A9A"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </StackPanel>
          </Border>
          <Border Grid.Row="3" Grid.Column="3" Grid.ColumnSpan="3" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,12,12">
            <StackPanel>
              <TextBlock Text="TEMPERATURES" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlTempNote" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap"/>
              <ItemsControl x:Name="HlTempGroups" Margin="0,2,0,0">
                <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Columns="2" VerticalAlignment="Top"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <StackPanel Margin="0,10,24,0">
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <ItemsControl ItemsSource="{Binding Items}" Margin="0,4,0,0" ItemTemplate="{StaticResource CheckRow}"/>
                    </StackPanel>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
              <Button x:Name="HlTempGet" Style="{StaticResource Ghost}" HorizontalAlignment="Left" Margin="0,12,0,0" Visibility="Collapsed"/>
            </StackPanel>
          </Border>
        </Grid>
          <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0">
            <StackPanel>
              <TextBlock x:Name="HlTrendsLabel" Text="TRENDS" Style="{StaticResource Label}"/>
              <TextBlock x:Name="HlTrendsNote" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,6,0,0" TextWrapping="Wrap"/>
              <UniformGrid x:Name="HlTrends" Columns="2" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
      </StackPanel>
    </ScrollViewer>

    <!-- Windows Features: built-in apps to remove or reinstall, and Windows' optional features -->
    <Grid x:Name="FeaturesPanel" Grid.Row="2" Margin="32,16,32,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16">
        <DockPanel>
          <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
            <TextBlock Text="&#xE71D;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center">
            <TextBlock x:Name="FtTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Text="Windows Features"/>
            <TextBlock x:Name="FtText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Row="1" Margin="0,14,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="260"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="FtViewFeaturesText" Text="Optional features" Foreground="#BDBDBD" VerticalAlignment="Center" Margin="0,0,16,0"/>
        <Grid Grid.Column="1">
          <TextBox x:Name="FtSearch" Padding="34,7,10,7"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <TextBlock Text="Filter" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Visibility" Value="Collapsed"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Text, ElementName=FtSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </Grid>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <ToggleButton x:Name="FtOnOnly" Content="On only" Style="{StaticResource Chip}" Margin="0,0,8,0" ToolTip="Only the features that are turned on"/>
          <Button x:Name="FtRefresh" ToolTip="Read them again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Refresh"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
      <Border Grid.Row="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="FtHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="220"/>
                <ColumnDefinition Width="120"/>
                <ColumnDefinition Width="110"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="FtHeadName" Text="FEATURE" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock x:Name="FtHeadPub" Grid.Column="1" Text="" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="2" Text="STATUS" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="FtList" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid x:Name="FtRow" MinHeight="56" Margin="20,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="120"/>
                    <ColumnDefinition Width="110"/>
                  </Grid.ColumnDefinitions>
                  <!-- optional features are a tree: indented by depth, with a chevron on the ones that have features under them -->
                  <DockPanel VerticalAlignment="Center" Margin="0,9,14,9">
                    <Border x:Name="FtIndent" DockPanel.Dock="Left" Width="{Binding IndentWidth}"/>
                    <Button x:Name="FtToggle" DockPanel.Dock="Left" Tag="fttoggle" Style="{StaticResource HeaderButton}" Width="26" Height="20" VerticalAlignment="Top" Margin="0,0,4,0" ToolTip="Show or hide the features under it">
                      <!-- the whole square takes the click, not just the arrow's strokes -->
                      <Border Width="26" Height="20" Background="Transparent">
                        <TextBlock x:Name="FtChevron" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                    </Button>
                    <StackPanel>
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <TextBlock x:Name="FtDesc" Text="{Binding Description}" Foreground="#A8A8A8" FontSize="12.5" TextTrimming="CharacterEllipsis" Margin="0,2,0,0" ToolTip="{Binding Description}"/>
                      <TextBlock Text="{Binding SubText}" Foreground="#8A8A8A" FontSize="12" FontFamily="Consolas" TextTrimming="CharacterEllipsis" Margin="0,2,0,0" ToolTip="{Binding SubText}"/>
                    </StackPanel>
                  </DockPanel>
                  <TextBlock Grid.Column="1" Text="{Binding Publisher}" Foreground="#9A9A9A" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,10,0"/>
                  <StackPanel Grid.Column="2" VerticalAlignment="Center">
                    <TextBlock x:Name="FtStatus" Text="{Binding StatusText}" Foreground="{StaticResource Good}" FontSize="12.5" TextTrimming="CharacterEllipsis" ToolTip="{Binding StatusText}"/>
                    <TextBlock x:Name="FtTreeNote" Text="{Binding TreeNote}" Foreground="#8A8A8A" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis" ToolTip="{Binding TreeNote}"/>
                    <ProgressBar x:Name="FtBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,6,10,0" Visibility="Collapsed"/>
                  </StackPanel>
                  <Button Grid.Column="3" Content="{Binding ActionText}" Tag="ftaction" Style="{StaticResource RowButton}" IsEnabled="{Binding CanChange}" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding On}" Value="False"><Setter TargetName="FtStatus" Property="Foreground" Value="#8A8A8A"/></DataTrigger>
                  <DataTrigger Binding="{Binding HasDescription}" Value="False"><Setter TargetName="FtDesc" Property="Visibility" Value="Collapsed"/></DataTrigger>
                  <DataTrigger Binding="{Binding HasTreeNote}" Value="False"><Setter TargetName="FtTreeNote" Property="Visibility" Value="Collapsed"/></DataTrigger>
                  <DataTrigger Binding="{Binding HasChildren}" Value="False"><Setter TargetName="FtToggle" Property="Visibility" Value="Hidden"/></DataTrigger>
                  <DataTrigger Binding="{Binding IsExpanded}" Value="True"><Setter TargetName="FtChevron" Property="Text" Value="&#xE70D;"/></DataTrigger>
                  <DataTrigger Binding="{Binding Kind}" Value="app"><Setter TargetName="FtToggle" Property="Visibility" Value="Collapsed"/><Setter TargetName="FtIndent" Property="Visibility" Value="Collapsed"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="FtBar" Property="Visibility" Value="Visible"/><Setter TargetName="FtStatus" Property="Foreground" Value="White"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="FtStatus" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="reboot"><Setter TargetName="FtStatus" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="FtMsgPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="560" Visibility="Collapsed">
            <ProgressBar x:Name="FtMsgBar" Style="{StaticResource Bar}" Width="240" IsIndeterminate="True" Margin="0,0,0,20"/>
            <TextBlock x:Name="FtMsgTitle" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
            <TextBlock x:Name="FtMsgText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,6,0,0"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Extras: tweaks (each restorable) and shortcuts to Windows' hidden tools -->
    <Grid x:Name="ExtrasPanel" Grid.Row="2" Margin="32,16,32,18" Visibility="Collapsed">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16">
        <DockPanel>
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="16,0,0,0">
            <Button x:Name="ExRestartExplorer" Style="{StaticResource Ghost}" Content="Restart Explorer" ToolTip="Restart File Explorer and the taskbar, so changes to them show (open File Explorer windows close)"/>
            <Button x:Name="ExRestoreAll" Margin="8,0,0,0" ToolTip="Put back everything this app changed here: each tweak as it was before, and the desktop shortcuts it added">
              <StackPanel Orientation="Horizontal">
                <TextBlock Text="&#xE777;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
                <TextBlock x:Name="ExRestoreAllText" Text="Restore all"/>
              </StackPanel>
            </Button>
          </StackPanel>
          <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
            <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center">
            <TextBlock FontSize="16" FontWeight="SemiBold" Foreground="White" Text="Extras"/>
            <TextBlock x:Name="ExText" Foreground="#BDBDBD" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
          </StackPanel>
        </DockPanel>
      </Border>
      <Grid Grid.Row="1" Margin="0,14,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="260"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" Margin="0,0,16,0">
          <RadioButton x:Name="ExViewTweaks" GroupName="ExView" Style="{StaticResource Chip}" Margin="0,0,8,0" IsChecked="True">
            <TextBlock x:Name="ExViewTweaksText" Text="Tweaks"/>
          </RadioButton>
          <RadioButton x:Name="ExViewTools" GroupName="ExView" Style="{StaticResource Chip}" Margin="0">
            <TextBlock x:Name="ExViewToolsText" Text="Shortcuts"/>
          </RadioButton>
        </StackPanel>
        <Grid Grid.Column="1">
          <TextBox x:Name="ExSearch" Padding="34,7,10,7"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
          <TextBlock Text="Filter" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
            <TextBlock.Style>
              <Style TargetType="TextBlock">
                <Setter Property="Visibility" Value="Collapsed"/>
                <Style.Triggers>
                  <DataTrigger Binding="{Binding Text, ElementName=ExSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                </Style.Triggers>
              </Style>
            </TextBlock.Style>
          </TextBlock>
        </Grid>
        <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="ExExpandAll" Style="{StaticResource Ghost}" Margin="0,0,8,0" ToolTip="Open or close every category"><TextBlock x:Name="ExExpandAllText" Text="Expand all"/></Button>
          <ToggleButton x:Name="ExChangedOnly" Content="Changed by this app" Style="{StaticResource Chip}" Margin="0,0,8,0" ToolTip="Only what this app changed (and can restore)"/>
          <Button x:Name="ExRefresh" ToolTip="Read them again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Refresh"/>
            </StackPanel>
          </Button>
        </StackPanel>
      </Grid>
      <Border Grid.Row="2" Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border x:Name="ExHeader" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="40" Margin="20,0,26,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="170"/>
                <ColumnDefinition Width="290"/>
              </Grid.ColumnDefinitions>
              <TextBlock x:Name="ExHeadName" Text="TWEAK" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock x:Name="ExHeadStatus" Grid.Column="1" Text="STATUS" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="ExList" Grid.Row="1" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
                   VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid>
                <!-- a category: the whole row opens or closes it, like a feature's chevron on Windows Features -->
                <Button x:Name="ExGroupRow" Tag="exgroup" Focusable="False" Visibility="Collapsed" Cursor="Hand" ToolTip="Show or hide what's in it">
                  <Button.Template>
                    <ControlTemplate TargetType="Button"><ContentPresenter/></ControlTemplate>
                  </Button.Template>
                  <Border Background="Transparent" Padding="20,12,16,12">
                    <DockPanel>
                      <TextBlock x:Name="ExChevron" Text="&#xE76C;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#BDBDBD" Width="26" VerticalAlignment="Center"/>
                      <TextBlock Text="{Binding HeaderNote}" DockPanel.Dock="Right" Foreground="#8A8A8A" FontSize="12.5" VerticalAlignment="Center" Margin="12,0,0,0"/>
                      <TextBlock Text="{Binding Name}" Foreground="{StaticResource Highlight}" FontSize="14" FontWeight="SemiBold" VerticalAlignment="Center"/>
                    </DockPanel>
                  </Border>
                </Button>
                <Grid x:Name="ExItemRow" MinHeight="56" Margin="46,0,16,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="170"/>
                    <ColumnDefinition Width="290"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel VerticalAlignment="Center" Margin="0,9,14,9">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Name}"/>
                      <TextBlock Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#9A9A9A" Margin="8,2,0,0" VerticalAlignment="Center" Background="Transparent"
                                 Visibility="{Binding NeedsAdmin, Converter={StaticResource B2V}}" ToolTip="Needs administrator approval"/>
                    </StackPanel>
                    <TextBlock Text="{Binding Description}" Foreground="#A8A8A8" FontSize="12.5" TextWrapping="Wrap" Margin="0,2,0,0"/>
                    <TextBlock Text="{Binding SubText}" Foreground="#8A8A8A" FontSize="12" FontFamily="Consolas" TextTrimming="CharacterEllipsis" Margin="0,2,0,0" ToolTip="{Binding SubText}"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" VerticalAlignment="Center" Margin="0,0,10,0">
                    <TextBlock x:Name="ExStatus" Text="{Binding StatusText}" Foreground="{StaticResource Good}" FontSize="12.5" TextWrapping="Wrap"/>
                    <TextBlock x:Name="ExSaved" Text="{Binding SavedNote}" Foreground="#8A8A8A" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                    <ProgressBar x:Name="ExBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,6,10,0" Visibility="Collapsed"/>
                  </StackPanel>
                  <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button Content="{Binding Action2Text}" Tag="exaction2" Style="{StaticResource RowButton}" IsEnabled="{Binding CanAction2}" Margin="0,0,8,0"/>
                    <Button Content="{Binding ActionText}" Tag="exaction" Style="{StaticResource RowButton}" IsEnabled="{Binding CanChange}"/>
                  </StackPanel>
                </Grid>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding IsHeader}" Value="True"><Setter TargetName="ExGroupRow" Property="Visibility" Value="Visible"/><Setter TargetName="ExItemRow" Property="Visibility" Value="Collapsed"/></DataTrigger>
                  <DataTrigger Binding="{Binding IsExpanded}" Value="True"><Setter TargetName="ExChevron" Property="Text" Value="&#xE70D;"/></DataTrigger>
                  <DataTrigger Binding="{Binding On}" Value="False"><Setter TargetName="ExStatus" Property="Foreground" Value="#8A8A8A"/></DataTrigger>
                  <DataTrigger Binding="{Binding HasSavedNote}" Value="False"><Setter TargetName="ExSaved" Property="Visibility" Value="Collapsed"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="ExBar" Property="Visibility" Value="Visible"/><Setter TargetName="ExStatus" Property="Foreground" Value="White"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="ok"><Setter TargetName="ExStatus" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="ExStatus" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="reboot"><Setter TargetName="ExStatus" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="ExMsgPanel" Grid.RowSpan="2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="560" Visibility="Collapsed">
            <TextBlock x:Name="ExMsgTitle" FontSize="17" FontWeight="SemiBold" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap"/>
            <TextBlock x:Name="ExMsgText" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" TextAlignment="Center" TextWrapping="Wrap" Margin="0,6,0,0"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Cleanup: free up space -->
    <ScrollViewer x:Name="CleanupPanel" Grid.Row="2" Margin="32,16,20,18" Padding="0,0,12,0" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
      <StackPanel>
        <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,0,12">
          <DockPanel>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
              <Button x:Name="HlDiskCleanup" Style="{StaticResource Ghost}" Content="Disk Cleanup" ToolTip="Windows' own Disk Cleanup, which also removes old Windows installations and update leftovers"/>
              <Button x:Name="HlStorage" Style="{StaticResource Ghost}" Content="Storage settings" ToolTip="Settings > System > Storage, including Storage Sense"/>
          <Button x:Name="ClRefresh" ToolTip="Measure everything again (F5)">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
              <TextBlock Text="Refresh"/>
            </StackPanel>
          </Button>
            </StackPanel>
            <Border Width="44" Height="44" CornerRadius="10" Background="#17414C" Margin="0,0,14,0" VerticalAlignment="Center">
              <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <StackPanel VerticalAlignment="Center" Margin="0,0,16,0">
              <TextBlock x:Name="ClTitle" FontSize="16" FontWeight="SemiBold" Foreground="White" Text="Free up space"/>
              <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <ProgressBar x:Name="ClDriveBar" Style="{StaticResource Bar}" Width="300" Height="8" VerticalAlignment="Center"/>
                <TextBlock x:Name="ClDriveText" Foreground="#BDBDBD" FontSize="12.5" Margin="14,0,0,0" VerticalAlignment="Center"/>
              </StackPanel>
            </StackPanel>
          </DockPanel>
        </Border>
          <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,0,12">
            <StackPanel>
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="HlClean" Style="{StaticResource Primary}" Margin="0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="13" Margin="0,1,8,0" VerticalAlignment="Center"/>
                      <TextBlock x:Name="HlCleanText" Text="Clean up"/>
                    </StackPanel>
                  </Button>
                </StackPanel>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="LEFTOVER FILES" Style="{StaticResource Label}"/>
                  <TextBlock x:Name="HlCleanInfo" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </DockPanel>
              <ItemsControl x:Name="HlCleanList" Margin="0,12,0,0">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,5,0,5">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="36"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="28"/>
                        <ColumnDefinition Width="90"/>
                      </Grid.ColumnDefinitions>
                      <CheckBox Style="{StaticResource Check}" IsChecked="{Binding Included, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" VerticalAlignment="Center" HorizontalAlignment="Left"/>
                      <StackPanel Grid.Column="1" VerticalAlignment="Center">
                        <TextBlock Text="{Binding Name}" Foreground="#F2F2F2"/>
                        <TextBlock x:Name="ClDetail" Text="{Binding StatusText}" Foreground="#8A8A8A" FontSize="12" Margin="0,2,0,0" TextWrapping="Wrap"/>
                      </StackPanel>
                      <TextBlock Grid.Column="2" Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#9A9A9A" VerticalAlignment="Center" Background="Transparent"
                                 Visibility="{Binding NeedsAdmin, Converter={StaticResource B2V}}" ToolTip="Needs administrator approval (asked once for everything ticked)"/>
                      <TextBlock Grid.Column="3" Text="{Binding SizeText}" Foreground="#BDBDBD" VerticalAlignment="Center" HorizontalAlignment="Right"/>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding State}" Value="ok"><Setter TargetName="ClDetail" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="ClDetail" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="ClDetail" Property="Foreground" Value="White"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </StackPanel>
          </Border>
          <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,0,12">
            <StackPanel>
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="ClBigScan" Content="Look again" Margin="0" ToolTip="Look through your folders for large files again"/>
                </StackPanel>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="LARGE FILES" Style="{StaticResource Label}"/>
                  <TextBlock x:Name="ClBigInfo" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </DockPanel>
              <ItemsControl x:Name="ClBigList" Margin="0,12,0,0">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,5,0,5">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="90"/>
                        <ColumnDefinition Width="110"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel VerticalAlignment="Center" Margin="0,0,12,0">
                        <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis" ToolTip="{Binding Path}"/>
                        <TextBlock x:Name="BfSub" Text="{Binding StatusText}" Foreground="#8A8A8A" FontSize="12" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                      </StackPanel>
                      <TextBlock Grid.Column="1" Text="{Binding SizeText}" Foreground="#BDBDBD" VerticalAlignment="Center"/>
                      <TextBlock Grid.Column="2" Text="{Binding Modified}" Foreground="#9A9A9A" VerticalAlignment="Center" ToolTip="Last changed"/>
                      <StackPanel Grid.Column="3" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button Content="Show" Tag="bigshow" Style="{StaticResource RowButton}" MinWidth="0" Margin="0,0,6,0" ToolTip="Show it in File Explorer"/>
                        <Button Content="Delete" Tag="bigdel" Style="{StaticResource RowButton}" MinWidth="0" IsEnabled="{Binding CanDelete}" ToolTip="Move it to the Recycle Bin"/>
                      </StackPanel>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding State}" Value="ok"><Setter TargetName="BfSub" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="BfSub" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </StackPanel>
          </Border>
          <Border Background="#232323" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Padding="20,16" Margin="0,0,0,12">
            <StackPanel>
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="ClAllApps" Style="{StaticResource Ghost}" Content="All installed software" Margin="0" ToolTip="Open Installed Software, sorted by size"/>
                </StackPanel>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="BIGGEST APPS" Style="{StaticResource Label}"/>
                  <TextBlock x:Name="ClAppsInfo" Foreground="{StaticResource Muted}" FontSize="12.5" Margin="0,4,0,0" TextWrapping="Wrap"/>
                </StackPanel>
              </DockPanel>
              <ItemsControl x:Name="ClAppList" Margin="0,12,0,0">
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,5,0,5">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="90"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <StackPanel VerticalAlignment="Center" Margin="0,0,12,0">
                        <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis"/>
                        <TextBlock x:Name="ApSub" Text="{Binding Id}" Foreground="#8A8A8A" FontSize="12" FontFamily="Consolas" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                      </StackPanel>
                      <TextBlock Grid.Column="1" Text="{Binding SizeText}" Foreground="#BDBDBD" VerticalAlignment="Center"/>
                      <Button Grid.Column="2" Content="{Binding ActionText}" Tag="appuninstall" Style="{StaticResource RowButton}" IsEnabled="{Binding CanUpdate}" VerticalAlignment="Center"/>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding HasState}" Value="True"><Setter TargetName="ApSub" Property="Text" Value="{Binding Detail}"/><Setter TargetName="ApSub" Property="FontFamily" Value="Segoe UI"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </StackPanel>
          </Border>
      </StackPanel>
    </ScrollViewer>

    <!-- Log -->
    <Border x:Name="LogPanel" Grid.Row="3" Height="200" Margin="32,0,32,18" Background="#171717" BorderBrush="#2C2C2C" BorderThickness="1" CornerRadius="10" Visibility="Collapsed">
      <TextBox x:Name="LogBox" Background="Transparent" IsReadOnly="True" FontFamily="Consolas" FontSize="12" Foreground="#C8C8C8"
               VerticalContentAlignment="Top" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" Padding="12,10"/>
    </Border>

    <!-- Status bar -->
    <Border Grid.Row="4" Background="#191919" BorderBrush="#262626" BorderThickness="0,1,0,0" Padding="32,10">
      <DockPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
          <Button x:Name="BtnStop" Content="Stop after current app" Style="{StaticResource Danger}" Padding="12,6" Visibility="Collapsed"
                  ToolTip="Cancel the queued updates. The app being updated now finishes first."/>
          <Button x:Name="BtnHistory" Content="History" Style="{StaticResource Ghost}" ToolTip="What was installed, updated, removed or held, and when"/>
          <Button x:Name="BtnLog" Content="Show log" Style="{StaticResource Ghost}"/>
          <Button x:Name="BtnLogFolder" Content="Log folder" Style="{StaticResource Ghost}" ToolTip="Open the folder with the daily log files"/>
          <Button x:Name="BtnDiag" Content="Diagnostics" Style="{StaticResource Ghost}" ToolTip="Save a zip file with this app's logs and details about this PC, to send to whoever helps when something goes wrong"/>
          <Button x:Name="BtnAbout" Style="{StaticResource Ghost}" Margin="0" Padding="9,6" ToolTip="About Windows Manager">
            <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="13"/>
          </Button>
        </StackPanel>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <ProgressBar x:Name="BusyBar" Style="{StaticResource Bar}" Width="90" IsIndeterminate="True" Margin="0,0,12,0" Visibility="Collapsed"/>
          <TextBlock x:Name="StatusText" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- Automatic maintenance (scheduled task) panel -->
    <Grid x:Name="ScheduleOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border x:Name="SchCard" Width="660" Margin="24" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12" Padding="30,26,20,24"
              HorizontalAlignment="Center" VerticalAlignment="Center">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,0,10,0">
          <StackPanel>
          <TextBlock Text="Automatic maintenance" FontSize="21" FontWeight="Bold" Foreground="White"/>
          <TextBlock Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,5,0,20"
                     Text="A scheduled task runs while you are signed in and does the jobs you choose below. For each job, Tell me only lets you know what's waiting, and Do it takes care of it."/>
          <CheckBox x:Name="SchEnabled" Content="Run automatic maintenance" FontSize="14"/>
          <StackPanel x:Name="SchOptions" Margin="0,22,0,0">
            <TextBlock Text="WHEN" Style="{StaticResource Label}"/>
            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
              <RadioButton x:Name="SchDaily" Content="Daily" GroupName="Freq" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
              <RadioButton x:Name="SchWeekly" Content="Weekly" GroupName="Freq" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
              <TextBlock Text="at" Foreground="#BDBDBD" VerticalAlignment="Center" Margin="10,0,10,0"/>
              <TextBox x:Name="SchTime" Width="124" MinHeight="32" Padding="12,4" ToolTip="24-hour (15:30) or 12-hour (3:30 PM)"/>
            </StackPanel>
            <WrapPanel x:Name="SchDays" Margin="0,12,0,0">
              <ToggleButton Content="Mon" Tag="Monday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Tue" Tag="Tuesday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Wed" Tag="Wednesday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Thu" Tag="Thursday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Fri" Tag="Friday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Sat" Tag="Saturday" Style="{StaticResource Chip}"/>
              <ToggleButton Content="Sun" Tag="Sunday" Style="{StaticResource Chip}"/>
            </WrapPanel>
            <CheckBox x:Name="SchElevated" Content="Run elevated, so installs and Windows' own cleanup never ask for approval" Margin="0,8,0,12"
                      ToolTip="Runs the task with your highest privileges, from a protected copy of the app. Needed to install Windows updates and to clean up Windows' folders. Saving this needs administrator approval once."/>
            <CheckBox x:Name="SchCatchUp" Content="Run as soon as possible after a missed start"
                      ToolTip="If the computer was off or asleep at the scheduled time, run when it is next available."/>
            <TextBlock Text="WHAT TO DO" Style="{StaticResource Label}" Margin="0,22,0,10"/>
            <StackPanel x:Name="SchJobs"/>
            <TextBlock Text="NOTIFICATIONS" Style="{StaticResource Label}" Margin="0,12,0,12"/>
            <CheckBox x:Name="SchNotifyReboot" Content="Tell me when something needs a restart" Margin="0,0,0,12"
                      ToolTip="Nothing ever restarts by itself; this tells you when updates are waiting for a restart to finish."/>
            <CheckBox x:Name="SchNotifyAlways" Content="Show a summary after every run that changes something"
                      ToolTip="Otherwise you only hear about problems, things waiting for you, and restarts."/>
          </StackPanel>
          <Border Background="#1C1C1C" CornerRadius="8" Padding="14,11" Margin="0,20,0,0">
            <TextBlock x:Name="SchStatus" TextWrapping="Wrap" Foreground="#BDBDBD" FontSize="12.5" LineHeight="19"/>
          </Border>
          <TextBlock x:Name="SchError" Foreground="{StaticResource Bad}" TextWrapping="Wrap" Margin="0,12,0,0" Visibility="Collapsed"/>
          </StackPanel>
          </ScrollViewer>
          <DockPanel Grid.Row="1" Margin="0,22,10,0">
            <StackPanel DockPanel.Dock="Left" Orientation="Horizontal">
              <Button x:Name="SchRunNow" Content="Run now" ToolTip="Start the scheduled task now"/>
              <Button x:Name="SchDryRun" Content="Test run" Style="{StaticResource Ghost}"
                      ToolTip="Go through the jobs that are on as saved, changing nothing, and show the notification a real run would send"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="SchCancel" Content="Cancel"/>
              <Button x:Name="SchSave" Content="Save" Style="{StaticResource Primary}" Margin="0" MinWidth="84"/>
            </StackPanel>
          </DockPanel>
        </Grid>
      </Border>
    </Grid>
    <!-- Package details (winget show) -->
    <Grid x:Name="DetailsOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="660" MaxHeight="640" Margin="36" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <DockPanel Margin="30,26,20,0">
            <Button x:Name="DetClose" DockPanel.Dock="Right" Style="{StaticResource Ghost}" Padding="9,5" Margin="0" VerticalAlignment="Top" ToolTip="Close (Esc)">
              <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11"/>
            </Button>
            <StackPanel>
              <TextBlock x:Name="DetName" FontSize="21" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
              <TextBlock x:Name="DetSub" Foreground="{StaticResource Muted}" FontFamily="Consolas" FontSize="12.5" Margin="0,5,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </DockPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="30,18,20,0" Padding="0,0,10,0">
            <StackPanel>
              <ProgressBar x:Name="DetLoading" Style="{StaticResource Bar}" IsIndeterminate="True" Width="220" HorizontalAlignment="Left" Margin="0,8,0,12"/>
              <TextBlock x:Name="DetDesc" TextWrapping="Wrap" Foreground="#D6D6D6" LineHeight="20" Margin="0,0,0,18"/>
              <Grid x:Name="DetFields">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="150"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
              </Grid>
            </StackPanel>
          </ScrollViewer>
          <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="30,18,30,24">
            <Button x:Name="DetHomepage" Content="Open homepage" Style="{StaticResource Ghost}" Visibility="Collapsed"/>
            <Button x:Name="DetAction" Style="{StaticResource Primary}" Margin="0" MinWidth="100"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- About -->
    <Grid x:Name="AboutOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="420" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12" Padding="30,28,30,24" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <Border x:Name="AboutLogo" Width="64" Height="64" CornerRadius="14" Background="#000000" BorderBrush="#2A2A2A" BorderThickness="1" HorizontalAlignment="Center"/>
          <TextBlock Text="Windows Manager" FontSize="20" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" Margin="0,16,0,0"/>
          <TextBlock x:Name="AboutVersion" Foreground="{StaticResource Muted}" HorizontalAlignment="Center" Margin="0,4,0,0"/>
          <TextBlock Text="Install, update and remove apps with winget, and keep your drivers current." Foreground="#BDBDBD" HorizontalAlignment="Center" TextWrapping="Wrap" TextAlignment="Center" Margin="0,14,0,0"/>
          <Border Background="#1C1C1C" CornerRadius="8" Padding="16,12" Margin="0,20,0,0">
            <StackPanel>
              <TextBlock Text="MADE BY" Style="{StaticResource Label}"/>
              <TextBlock Text="Justin Vieira" FontSize="15" Foreground="White" Margin="0,4,0,10"/>
              <TextBlock Text="CONTRIBUTORS" Style="{StaticResource Label}"/>
              <TextBlock Text="Brandon Bolding" FontSize="15" Foreground="White" Margin="0,4,0,10"/>
              <TextBlock Text="CONTACT" Style="{StaticResource Label}"/>
              <TextBlock Margin="0,4,0,10" FontSize="14">
                <Hyperlink x:Name="AboutMail" NavigateUri="mailto:jdvieira@icloud.com" Foreground="{StaticResource Highlight}">jdvieira@icloud.com</Hyperlink>
              </TextBlock>
              <TextBlock Text="GITHUB" Style="{StaticResource Label}"/>
              <TextBlock Margin="0,4,0,0" FontSize="14">
                <Hyperlink x:Name="AboutRepo" NavigateUri="https://github.com/jdvieira/WindowsManager" Foreground="{StaticResource Highlight}" ToolTip="Opens the repository on GitHub in your browser">https://github.com/jdvieira/WindowsManager</Hyperlink>
              </TextBlock>
            </StackPanel>
          </Border>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
            <Button x:Name="AboutCopy" Content="Copy email"/>
            <Button x:Name="AboutClose" Content="Close" Style="{StaticResource Primary}" Margin="0" MinWidth="84"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>


    <!-- Options: sidebar with four pages; Save applies everything at once -->
    <Grid x:Name="OptionsOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border MaxWidth="920" MaxHeight="660" Margin="36" Background="#232323" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="220"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Border Background="#1B1B1B" CornerRadius="12,0,0,12" BorderBrush="#2C2C2C" BorderThickness="0,0,1,0">
            <DockPanel>
              <TextBlock DockPanel.Dock="Top" Text="Options" FontSize="21" FontWeight="Bold" Foreground="White" Margin="26,26,0,18"/>
              <TextBlock DockPanel.Dock="Bottom" x:Name="OptVersion" Foreground="#6E6E6E" FontSize="11.5" Margin="26,0,16,20" TextWrapping="Wrap"/>
              <ListBox x:Name="OptNav" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource NavItem}" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                <ListBoxItem Tag="PageUpdates"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="Packages"/></StackPanel></ListBoxItem>
                <ListBoxItem Tag="PageSources"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE774;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="Sources"/></StackPanel></ListBoxItem>
                <ListBoxItem Tag="PageAuto"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE823;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="Automatic runs"/></StackPanel></ListBoxItem>
                <ListBoxItem Tag="PageLogs"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE7C3;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="Logs"/></StackPanel></ListBoxItem>
                <ListBoxItem Tag="PageApp"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE895;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="App updates"/></StackPanel></ListBoxItem>
                <ListBoxItem Tag="PageMaint"><StackPanel Orientation="Horizontal"><TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" Width="28" VerticalAlignment="Center"/><TextBlock Text="Maintenance"/></StackPanel></ListBoxItem>
              </ListBox>
            </DockPanel>
          </Border>
          <Grid Grid.Column="1">
            <Grid.RowDefinitions>
              <RowDefinition Height="*"/>
              <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- Updates -->
            <ScrollViewer x:Name="PageUpdates" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16">
              <StackPanel>
                <TextBlock Text="Packages" Style="{StaticResource PageTitle}"/>
                <TextBlock Text="How apps are found, installed and updated, in the app and in automatic runs." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <TextBlock Text="SOURCES" Style="{StaticResource Label}"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,4">
                  <RadioButton x:Name="OptSrcAll" Content="All sources" GroupName="Src" Style="{StaticResource Chip}"/>
                  <RadioButton x:Name="OptSrcWinget" Content="winget" GroupName="Src" Style="{StaticResource Chip}"/>
                  <RadioButton x:Name="OptSrcStore" Content="Microsoft Store" GroupName="Src" Style="{StaticResource Chip}"/>
                </StackPanel>
                <TextBlock Text="Limit the update check to one source (--source)." Style="{StaticResource Hint}" Margin="0,0,0,20"/>
                <TextBlock Text="INSTALL NEW APPS FOR" Style="{StaticResource Label}"/>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,4">
                  <RadioButton x:Name="OptScopeDefault" Content="Installer default" GroupName="Scope" Style="{StaticResource Chip}"/>
                  <RadioButton x:Name="OptScopeUser" Content="Just me" GroupName="Scope" Style="{StaticResource Chip}"/>
                  <RadioButton x:Name="OptScopeMachine" Content="All users" GroupName="Scope" Style="{StaticResource Chip}"/>
                </StackPanel>
                <TextBlock Text="Used by Discover (--scope). All users usually needs administrator approval. Right-click an app to install it for all users once." Style="{StaticResource Hint}" Margin="0,0,0,20"/>
                <TextBlock Text="INSTALLING" Style="{StaticResource Label}" Margin="0,0,0,12"/>
                <CheckBox x:Name="OptSilent" Content="Silent installs"/>
                <TextBlock Text="Installers run without their own windows (--silent). Automatic runs are always silent." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptUnknown" Content="Include apps with unknown versions"/>
                <TextBlock Text="Also list apps whose installed version winget can't read (--include-unknown)." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptUninstallPrev" Content="Uninstall the previous version during an upgrade"/>
                <TextBlock Text="For installers that leave the old version behind (--uninstall-previous). Leave off unless you need it." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptScanOnOpen" Content="Check for updates when the app opens"/>
                <TextBlock Text="HIDDEN APPS" Style="{StaticResource Label}" Margin="0,24,0,10"/>
                <StackPanel x:Name="OptHiddenList"/>
                <TextBlock x:Name="OptHiddenEmpty" Text="No apps are hidden. Right-click an app and choose Hide (keep at this version), or add its package ID here." Style="{StaticResource Hint}" Margin="0,0,0,10"/>
                <DockPanel Margin="0,4,0,0">
                  <Button x:Name="OptHideAddBtn" DockPanel.Dock="Right" Content="Add" Margin="8,0,0,0"/>
                  <TextBox x:Name="OptHideAdd" ToolTip="A winget package ID, for example Git.Git"/>
                </DockPanel>
                <TextBlock Text="Hidden apps stay at their current version: they leave the Updates list, and Update all, automatic updates and winget itself (through a winget pin, set when you click Save) leave them alone." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                <TextBlock Text="UPDATED BY WINDOWS" Style="{StaticResource Label}" Margin="0,24,0,10"/>
                <TextBlock x:Name="OptWinUpdated" Foreground="#BDBDBD" FontSize="12.5" TextWrapping="Wrap" LineHeight="19"/>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                  <Button x:Name="OptWinUpdReset" Content="Forget learned apps" ToolTip="Clear the apps this app learned are updated by Windows, and any you set back to winget"/>
                </StackPanel>
                <TextBlock Text="Windows or the app itself updates these, so they leave the Updates list (Show hidden lists them) and Update all and automatic updates skip them. Apps are added when winget says the installed copy came from a different installer. Right-click one on Updates to let winget update it after all." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <!-- Sources -->
            <ScrollViewer x:Name="PageSources" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Sources" Style="{StaticResource PageTitle}"/>
                <TextBlock Text="Where winget finds apps. Changes here happen right away (they don't wait for Save), and adding, removing or switching a source needs administrator approval." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <TextBlock Text="YOUR SOURCES" Style="{StaticResource Label}" Margin="0,0,0,10"/>
                <StackPanel x:Name="OptSourceList"/>
                <TextBlock x:Name="OptSourceEmpty" Style="{StaticResource Hint}" Margin="0,0,0,6"/>
                <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                  <Button x:Name="OptSrcUpdate" Content="Update sources" ToolTip="winget source update"/>
                  <Button x:Name="OptSrcReset" Content="Reset sources" Style="{StaticResource Danger}"
                          ToolTip="winget source reset --force, then update. Needs administrator approval."/>
                </StackPanel>
                <TextBlock Text="Reset puts winget's sources back to their defaults (and removes any you added), which fixes most &quot;failed to open source&quot; errors." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                <TextBlock x:Name="OptMaintStatus" Foreground="#BDBDBD" TextWrapping="Wrap" Margin="0,10,0,0" Visibility="Collapsed"/>
                <TextBlock Text="ADD A SOURCE" Style="{StaticResource Label}" Margin="0,26,0,10"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="70"/>
                    <ColumnDefinition Width="*"/>
                  </Grid.ColumnDefinitions>
                  <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                  </Grid.RowDefinitions>
                  <TextBlock Text="Name" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptSrcName" Grid.Column="1" Margin="0,0,0,8" ToolTip="A short name without spaces, for example contoso"/>
                  <TextBlock Grid.Row="1" Text="URL" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptSrcUrl" Grid.Row="1" Grid.Column="1" ToolTip="The source's address, for example https://winget.contoso.com/api"/>
                </Grid>
                <StackPanel Orientation="Horizontal" Margin="70,10,0,0">
                  <RadioButton x:Name="OptSrcTypeRest" Content="REST source" GroupName="SrcType" Style="{StaticResource Chip}" IsChecked="True"
                               ToolTip="A Windows Package Manager (winget) REST source, such as a company repository (--type Microsoft.Rest)"/>
                  <RadioButton x:Name="OptSrcTypeIndexed" Content="Pre-indexed (like winget)" GroupName="SrcType" Style="{StaticResource Chip}"
                               ToolTip="A pre-indexed package source, like the default winget source"/>
                </StackPanel>
                <CheckBox x:Name="OptSrcExplicit" Content="Only use it when a package asks for it by name" Margin="70,4,0,0"
                          ToolTip="Explicit: left out of searches and update checks unless --source names it"/>
                <StackPanel Orientation="Horizontal" Margin="70,14,0,0">
                  <Button x:Name="OptSrcAdd" Content="Add source"/>
                </StackPanel>
                <TextBlock Text="Only add sources you trust: winget installs whatever they offer." Style="{StaticResource Hint}" Margin="70,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <!-- Automatic runs -->
            <ScrollViewer x:Name="PageAuto" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Automatic runs" Style="{StaticResource PageTitle}"/>
                <TextBlock x:Name="OptTaskNote" Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <TextBlock Text="DURING A RUN" Style="{StaticResource Label}" Margin="0,0,0,12"/>
                <TextBlock Text="What each run does (app and Windows updates, cleanup, the health check) is set in Automatic maintenance, from the header." Style="{StaticResource Hint}" Margin="0,0,0,14"/>
                <CheckBox x:Name="OptRestorePoint" Content="Create a restore point before installing"/>
                <TextBlock Text="Needs the task to run elevated and System Protection turned on. Windows creates at most one restore point every 24 hours; the updates go ahead either way." Style="{StaticResource Hint}" Margin="48,3,0,20"/>
                <TextBlock Text="WHEN TO RUN" Style="{StaticResource Label}" Margin="0,0,0,12"/>
                <CheckBox x:Name="OptNetwork" Content="Only run when a network connection is available"/>
                <TextBlock Text="Otherwise the task waits and runs once you are back online." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptAC" Content="Only run on AC power"/>
                <TextBlock Text="For laptops. The run also stops if the computer switches to battery." Style="{StaticResource Hint}" Margin="48,3,0,16"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                  <TextBlock Text="Random start delay" Width="210" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptDelay" Width="70" MinHeight="32" Padding="10,4"/>
                  <TextBlock Text="minutes (0 to 60)" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
                  <TextBlock Text="Stop a run after" Width="210" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptMaxHours" Width="70" MinHeight="32" Padding="10,4"/>
                  <TextBlock Text="hours (1 to 24)" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
                <TextBlock Text="NOTIFICATIONS" Style="{StaticResource Label}" Margin="0,0,0,10"/>
                <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
                  <RadioButton x:Name="OptNotifyToast" Content="Windows notification" GroupName="NotifyStyle" Style="{StaticResource Chip}"/>
                  <RadioButton x:Name="OptNotifyWindow" Content="This app's pop-up" GroupName="NotifyStyle" Style="{StaticResource Chip}"/>
                </StackPanel>
                <TextBlock Text="A Windows notification stays in the notification center, with Open and View log buttons. When Windows notifications are turned off for this app, the pop-up is used instead." Style="{StaticResource Hint}" Margin="0,0,0,14"/>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="Close success notifications after" Width="210" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptDismiss" Width="70" MinHeight="32" Padding="10,4"/>
                  <TextBlock Text="minutes (0 keeps them open)" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
                <TextBlock Text="For the pop-up: applies to summaries and restart reminders. Failure notifications stay until you close them. Which notifications appear is set in Automatic maintenance." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <!-- Logs -->
            <ScrollViewer x:Name="PageLogs" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Logs" Style="{StaticResource PageTitle}"/>
                <TextBlock Text="One log file per day records everything winget did, in the app and in automatic runs." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="Keep logs for" Width="120" VerticalAlignment="Center"/>
                  <TextBox x:Name="OptRetention" Width="70" MinHeight="32" Padding="10,4"/>
                  <TextBlock Text="days (1 to 365)" Foreground="{StaticResource Muted}" VerticalAlignment="Center" Margin="10,0,0,0"/>
                </StackPanel>
                <TextBlock Text="Older daily logs, and the app's own error log, are deleted when the app starts." Style="{StaticResource Hint}" Margin="0,6,0,22"/>
                <TextBlock Text="LOG FOLDER" Style="{StaticResource Label}" Margin="0,0,0,10"/>
                <DockPanel>
                  <Button x:Name="OptLogDefault" DockPanel.Dock="Right" Content="Default" Margin="8,0,0,0"/>
                  <Button x:Name="OptLogBrowse" DockPanel.Dock="Right" Content="Browse" Margin="8,0,0,0"/>
                  <TextBox x:Name="OptLogDir"/>
                </DockPanel>
                <TextBlock x:Name="OptLogHint" Style="{StaticResource Hint}" Margin="0,6,0,22"/>
                <TextBlock Text="TROUBLESHOOTING" Style="{StaticResource Label}" Margin="0,0,0,12"/>
                <CheckBox x:Name="OptVerbose" Content="Verbose winget logging"/>
                <TextBlock Text="winget writes detailed diagnostic logs (--verbose-logs) to its own folder. Turn on while chasing a stubborn installer." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="OptOpenLogs" Content="Open log folder"/>
                  <Button x:Name="OptOpenWingetLogs" Content="Open winget's logs"/>
                  <Button x:Name="OptDiag" Content="Save diagnostics"/>
                </StackPanel>
                <TextBlock Text="Save diagnostics makes a zip file on your desktop with this app's logs, the driver tools' logs, settings and details about this PC, to send to whoever is helping." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <!-- Windows Manager's own updates, from its GitHub releases -->
            <ScrollViewer x:Name="PageApp" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="App updates" Style="{StaticResource PageTitle}"/>
                <TextBlock Text="New versions of Windows Manager are published as releases on GitHub (github.com/jdvieira/WindowsManager)." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <TextBlock Text="THIS VERSION" Style="{StaticResource Label}" Margin="0,0,0,10"/>
                <Border Background="#1C1C1C" CornerRadius="8" Padding="14,11">
                  <TextBlock x:Name="OptAppStatus" TextWrapping="Wrap" Foreground="#BDBDBD" FontSize="12.5" LineHeight="19"/>
                </Border>
                <StackPanel Orientation="Horizontal" Margin="0,10,0,22">
                  <Button x:Name="OptAppCheckNow" Content="Check now"/>
                  <Button x:Name="OptAppInstall" Content="Update now" Style="{StaticResource Primary}" Visibility="Collapsed"/>
                  <Button x:Name="OptAppBack" Content="Go back" Visibility="Collapsed" ToolTip="Go back to the version this one replaced (it is kept for that)"/>
                  <Button x:Name="OptAppReleases" Content="Release notes" Style="{StaticResource Ghost}" ToolTip="Open the releases page on GitHub"/>
                </StackPanel>
                <TextBlock Text="AUTOMATIC UPDATES" Style="{StaticResource Label}" Margin="0,0,0,12"/>
                <CheckBox x:Name="OptAppCheck" Content="Check for a new version when the app opens"/>
                <TextBlock Text="Looks at the latest release on GitHub in the background and offers to update when it's newer. Not now skips that version until you choose it here." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptAppAuto" Content="Update without asking"/>
                <TextBlock Text="When a newer version is found, it downloads, swaps itself in and restarts the app straight away (unless something is installing). Settings, history and the schedule stay as they are." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <CheckBox x:Name="OptAppBeta" Content="Get beta versions"/>
                <TextBlock Text="Also offer pre-releases: versions published for testing before everyone gets them. They may have rough edges; Go back returns to the version before." Style="{StaticResource Hint}" Margin="48,3,0,14"/>
                <TextBlock Text="Downloads are checked against the checksum GitHub publishes and the version they say they are, before they replace this app. If a new version doesn't open, the one you had comes back by itself." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <!-- Maintenance -->
            <ScrollViewer x:Name="PageMaint" VerticalScrollBarVisibility="Auto" Padding="34,26,30,16" Visibility="Collapsed">
              <StackPanel>
                <TextBlock Text="Maintenance" Style="{StaticResource PageTitle}"/>
                <TextBlock Text="These act right away; they don't wait for Save." Foreground="{StaticResource Muted}" TextWrapping="Wrap" Margin="0,4,0,22"/>
                <TextBlock Text="WINGET" Style="{StaticResource Label}" Margin="0,0,0,10"/>
                <Border Background="#1C1C1C" CornerRadius="8" Padding="14,11" Margin="0,0,0,0">
                  <TextBlock x:Name="OptWingetInfo" TextWrapping="Wrap" Foreground="#BDBDBD" FontSize="12.5" LineHeight="19"/>
                </Border>
                <TextBlock Text="Updating, resetting and editing winget's sources is on the Sources page." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                <TextBlock Text="SETTINGS" Style="{StaticResource Label}" Margin="0,26,0,10"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="OptExport" Content="Export"/>
                  <Button x:Name="OptImport" Content="Import"/>
                  <Button x:Name="OptOpenData" Content="Open data folder"/>
                  <Button x:Name="OptResetAll" Content="Reset to defaults" Style="{StaticResource Danger}"/>
                </StackPanel>
                <TextBlock Text="Export saves every option and the automatic update schedule to a file, to set up another PC the same way. Import and Reset fill in the options; nothing changes until you click Save." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
                <TextBlock Text="SET UP A NEW PC" Style="{StaticResource Label}" Margin="0,26,0,10"/>
                <StackPanel Orientation="Horizontal">
                  <Button x:Name="OptSetupSave" Content="Back up this PC's setup" Style="{StaticResource Primary}"/>
                  <Button x:Name="OptSetupLoad" Content="Set up from a backup"/>
                </StackPanel>
                <TextBlock x:Name="OptSetupHint" Text="A setup backup is one file with your apps (in winget's format), hidden apps, options and schedule. On a new or reset PC, open it with Set up from a backup: Discover lists the apps with the missing ones ticked, and the options are filled in for you to save." Style="{StaticResource Hint}" Margin="0,6,0,0"/>
              </StackPanel>
            </ScrollViewer>

            <Border Grid.Row="1" BorderBrush="#2E2E2E" BorderThickness="0,1,0,0" Padding="34,14,30,16">
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                  <Button x:Name="OptCancel" Content="Cancel"/>
                  <Button x:Name="OptSave" Content="Save" Style="{StaticResource Primary}" Margin="0" MinWidth="84"/>
                </StackPanel>
                <TextBlock x:Name="OptMessage" TextWrapping="Wrap" VerticalAlignment="Center" Margin="0,0,16,0" FontSize="12.5"/>
              </DockPanel>
            </Border>
          </Grid>
        </Grid>
      </Border>
    </Grid>

    <!-- History: every install, update, uninstall and hold, from the app and from automatic runs -->
    <Grid x:Name="HistoryOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border MaxWidth="1040" Margin="36" Background="#232323" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <DockPanel Margin="30,26,20,0">
            <Button x:Name="HistClose" DockPanel.Dock="Right" Style="{StaticResource Ghost}" Padding="9,5" Margin="0" VerticalAlignment="Top" ToolTip="Close (Esc)">
              <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11"/>
            </Button>
            <StackPanel>
              <TextBlock Text="History" FontSize="21" FontWeight="Bold" Foreground="White"/>
              <TextBlock x:Name="HistSub" Foreground="{StaticResource Muted}" Margin="0,4,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </DockPanel>
          <Grid Grid.Row="1" Margin="30,18,30,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="300"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Grid>
              <TextBox x:Name="HistSearch" Padding="34,7,10,7"/>
              <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#8A8A8A" Margin="12,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False"/>
              <TextBlock Text="Filter by app" Foreground="#7A7A7A" Margin="36,0,0,0" VerticalAlignment="Center" IsHitTestVisible="False">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Setter Property="Visibility" Value="Collapsed"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Text, ElementName=HistSearch}" Value=""><Setter Property="Visibility" Value="Visible"/></DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>
            </Grid>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <RadioButton x:Name="HistAll" Content="Everything" GroupName="HistKind" Style="{StaticResource Chip}" Margin="0,0,8,0" IsChecked="True"/>
              <RadioButton x:Name="HistAutoOnly" Content="Automatic runs" GroupName="HistKind" Style="{StaticResource Chip}" Margin="0,0,8,0"/>
              <RadioButton x:Name="HistFailed" Content="Failed" GroupName="HistKind" Style="{StaticResource Chip}" Margin="0"/>
            </StackPanel>
          </Grid>
          <Border Grid.Row="2" Margin="30,0,30,0" BorderBrush="#2E2E2E" BorderThickness="0,0,0,1">
            <Grid Height="34" Margin="14,0,16,0">
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="170"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="210"/>
                <ColumnDefinition Width="240"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="WHEN" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="1" Text="APP" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="36,0,0,0"/>
              <TextBlock Grid.Column="2" Text="VERSION" Style="{StaticResource Label}" VerticalAlignment="Center"/>
              <TextBlock Grid.Column="3" Text="RESULT" Style="{StaticResource Label}" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <ListBox x:Name="HistList" Grid.Row="3" Margin="30,0,30,0" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource Row}"
                   ScrollViewer.HorizontalScrollBarVisibility="Disabled" VirtualizingPanel.ScrollUnit="Pixel" Focusable="False">
            <ListBox.ItemTemplate>
              <DataTemplate>
                <Grid Height="52" Margin="14,0,6,0">
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="170"/>
                    <ColumnDefinition Width="36"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="210"/>
                    <ColumnDefinition Width="240"/>
                  </Grid.ColumnDefinitions>
                  <TextBlock Text="{Binding When}" Foreground="#9A9A9A" FontSize="12.5" VerticalAlignment="Center"/>
                  <TextBlock Grid.Column="1" Text="{Binding Glyph}" FontFamily="Segoe MDL2 Assets" FontSize="13" Foreground="#9A9A9A" VerticalAlignment="Center" ToolTip="{Binding ActionText}"/>
                  <StackPanel Grid.Column="2" VerticalAlignment="Center" Margin="0,0,14,0">
                    <StackPanel Orientation="Horizontal">
                      <TextBlock Text="{Binding ActionText}" Foreground="#9A9A9A" Margin="0,0,6,0"/>
                      <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextTrimming="CharacterEllipsis"/>
                      <Border x:Name="AutoTag" Visibility="Collapsed" Margin="8,0,0,0" Padding="7,1,7,2" CornerRadius="8" Background="#17414C" VerticalAlignment="Center">
                        <TextBlock Text="automatic" FontSize="10.5" Foreground="{StaticResource Highlight}"/>
                      </Border>
                    </StackPanel>
                    <TextBlock Text="{Binding Id}" Foreground="#8A8A8A" FontFamily="Consolas" FontSize="12" TextTrimming="CharacterEllipsis" Margin="0,2,0,0"/>
                  </StackPanel>
                  <TextBlock Grid.Column="3" Text="{Binding Change}" Foreground="#BDBDBD" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Change}" Margin="0,0,12,0"/>
                  <TextBlock x:Name="Res" Grid.Column="4" Text="{Binding Detail}" Foreground="#9A9A9A" FontSize="12.5" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" ToolTip="{Binding Detail}"/>
                </Grid>
                <DataTemplate.Triggers>
                  <DataTrigger Binding="{Binding IsAuto}" Value="True"><Setter TargetName="AutoTag" Property="Visibility" Value="Visible"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="ok"><Setter TargetName="Res" Property="Foreground" Value="{StaticResource Good}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="reboot"><Setter TargetName="Res" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                  <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="Res" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                </DataTemplate.Triggers>
              </DataTemplate>
            </ListBox.ItemTemplate>
          </ListBox>
          <StackPanel x:Name="HistEmpty" Grid.Row="3" HorizontalAlignment="Center" VerticalAlignment="Center" Visibility="Collapsed">
            <TextBlock Text="&#xE81C;" FontFamily="Segoe MDL2 Assets" FontSize="28" Foreground="#6E6E6E" HorizontalAlignment="Center"/>
            <TextBlock x:Name="HistEmptyText" FontSize="15" HorizontalAlignment="Center" Margin="0,14,0,0" TextWrapping="Wrap" TextAlignment="Center" MaxWidth="480"/>
          </StackPanel>
          <DockPanel Grid.Row="4" Margin="30,14,30,22">
            <Button x:Name="HistClear" DockPanel.Dock="Left" Content="Clear history" Style="{StaticResource Danger}" Padding="12,6"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="HistDone" Content="Close" Style="{StaticResource Primary}" Margin="0" MinWidth="84"/>
            </StackPanel>
          </DockPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Release notes of an update -->
    <Grid x:Name="NotesOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="660" MaxHeight="640" Margin="36" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <DockPanel Margin="30,26,20,0">
            <Button x:Name="NotesClose" DockPanel.Dock="Right" Style="{StaticResource Ghost}" Padding="9,5" Margin="0" VerticalAlignment="Top" ToolTip="Close (Esc)">
              <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="11"/>
            </Button>
            <StackPanel>
              <TextBlock x:Name="NotesTitle" FontSize="21" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
              <TextBlock x:Name="NotesSub" Foreground="{StaticResource Muted}" FontFamily="Consolas" FontSize="12.5" Margin="0,5,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </DockPanel>
          <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="30,18,20,0" Padding="0,0,10,0">
            <TextBlock x:Name="NotesText" TextWrapping="Wrap" Foreground="#D6D6D6" LineHeight="21"/>
          </ScrollViewer>
          <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="30,18,30,24">
            <Button x:Name="NotesOpen" Content="Open the release notes page" Style="{StaticResource Ghost}" Visibility="Collapsed"/>
            <Button x:Name="NotesUpdate" Style="{StaticResource Primary}" Margin="0" MinWidth="100"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Install a chosen version -->
    <Grid x:Name="VersionOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="470" MaxHeight="620" Margin="36" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Margin="30,26,30,0">
            <TextBlock Text="Install a specific version" FontSize="20" FontWeight="Bold" Foreground="White"/>
            <TextBlock x:Name="VerSub" Foreground="{StaticResource Muted}" Margin="0,5,0,14" TextWrapping="Wrap"/>
          </StackPanel>
          <Grid Grid.Row="1" Margin="30,0,30,0" MinHeight="120">
            <ListBox x:Name="VerList" Background="#1C1C1C" BorderThickness="0" ItemContainerStyle="{StaticResource NavItem}" ScrollViewer.HorizontalScrollBarVisibility="Disabled" Padding="0,6"/>
            <StackPanel x:Name="VerLoading" VerticalAlignment="Center" HorizontalAlignment="Center">
              <ProgressBar Style="{StaticResource Bar}" Width="200" IsIndeterminate="True"/>
              <TextBlock Text="Asking winget for the versions it has" Foreground="{StaticResource Muted}" Margin="0,12,0,0" HorizontalAlignment="Center"/>
            </StackPanel>
            <TextBlock x:Name="VerError" Foreground="{StaticResource Bad}" TextWrapping="Wrap" VerticalAlignment="Center" TextAlignment="Center" Visibility="Collapsed"/>
          </Grid>
          <StackPanel Grid.Row="2" Margin="30,16,30,24">
            <CheckBox x:Name="VerHold" Content="Keep this version (hide its updates)" IsChecked="True"/>
            <TextBlock Text="Hides the app once it installs, so Update all, automatic updates and winget leave it at this version. Right-click > Unhide later to allow updates again." Style="{StaticResource Hint}" Margin="48,3,0,18"/>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
              <Button x:Name="VerCancel" Content="Cancel"/>
              <Button x:Name="VerInstall" Content="Install" Style="{StaticResource Primary}" Margin="0" MinWidth="96"/>
            </StackPanel>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Choose apps from a list (export) -->
    <Grid x:Name="PickOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="600" MaxHeight="680" Margin="36" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Margin="30,26,30,0">
            <TextBlock x:Name="PickTitle" FontSize="20" FontWeight="Bold" Foreground="White"/>
            <TextBlock x:Name="PickText" Foreground="{StaticResource Muted}" Margin="0,5,0,0" TextWrapping="Wrap" LineHeight="19"/>
          </StackPanel>
          <DockPanel Grid.Row="1" Margin="30,14,30,8">
            <TextBlock x:Name="PickCount" DockPanel.Dock="Right" Foreground="{StaticResource Muted}" VerticalAlignment="Center"/>
            <StackPanel Orientation="Horizontal">
              <Button x:Name="PickAll" Content="Select all" Style="{StaticResource Ghost}" Margin="0,0,4,0"/>
              <Button x:Name="PickNone" Content="Select none" Style="{StaticResource Ghost}"/>
            </StackPanel>
          </DockPanel>
          <Border Grid.Row="2" Margin="30,0,30,0" Background="#1C1C1C" CornerRadius="8">
            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="6">
              <StackPanel x:Name="PickList"/>
            </ScrollViewer>
          </Border>
          <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="30,18,30,24">
            <Button x:Name="PickCancel" Content="Cancel"/>
            <Button x:Name="PickOk" Style="{StaticResource Primary}" Margin="0" MinWidth="110"/>
          </StackPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Fix my PC: what can make the PC run better, ticked where it's safe, done with one click -->
    <Grid x:Name="FixOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="720" MaxHeight="720" Margin="36" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Margin="30,26,30,14">
            <StackPanel Orientation="Horizontal">
              <TextBlock Text="&#xE90F;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource Highlight}" Margin="0,2,12,0" VerticalAlignment="Center"/>
              <TextBlock Text="Fix my PC" FontSize="20" FontWeight="Bold" Foreground="White"/>
            </StackPanel>
            <TextBlock x:Name="FixText" Foreground="{StaticResource Muted}" Margin="0,8,0,0" TextWrapping="Wrap" LineHeight="19"/>
            <ProgressBar x:Name="FixBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,14,0,0" Visibility="Collapsed"/>
          </StackPanel>
          <Border Grid.Row="1" Margin="30,0,30,0" Background="#1C1C1C" CornerRadius="8">
            <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="14,4,14,10">
              <ItemsControl x:Name="FixList">
                <ItemsControl.GroupStyle>
                  <GroupStyle>
                    <GroupStyle.HeaderTemplate>
                      <DataTemplate>
                        <TextBlock Text="{Binding Name}" Style="{StaticResource Label}" Foreground="{StaticResource Highlight}" Margin="0,14,0,4"/>
                      </DataTemplate>
                    </GroupStyle.HeaderTemplate>
                  </GroupStyle>
                </ItemsControl.GroupStyle>
                <ItemsControl.ItemTemplate>
                  <DataTemplate>
                    <Grid Margin="0,6,0,6">
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="34"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                      </Grid.ColumnDefinitions>
                      <CheckBox Style="{StaticResource Check}" IsChecked="{Binding Included, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}" IsEnabled="{Binding CanCheck}"
                                Visibility="{Binding CanChoose, Converter={StaticResource B2V}}" VerticalAlignment="Top" Margin="0,1,0,0"/>
                      <TextBlock x:Name="FixDot" Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="14" Foreground="#9A9A9A" VerticalAlignment="Top" Margin="2,2,0,0" Visibility="Collapsed"/>
                      <StackPanel Grid.Column="1" Margin="0,0,12,0">
                        <StackPanel Orientation="Horizontal">
                          <TextBlock Text="{Binding Name}" Foreground="#F2F2F2" TextWrapping="Wrap"/>
                          <TextBlock Text="&#xEA18;" FontFamily="Segoe MDL2 Assets" FontSize="11" Foreground="#9A9A9A" Margin="8,3,0,0" Background="Transparent"
                                     Visibility="{Binding NeedsAdmin, Converter={StaticResource B2V}}" ToolTip="Part of the one administrator approval"/>
                        </StackPanel>
                        <TextBlock Text="{Binding Detail}" Foreground="#A8A8A8" FontSize="12.5" TextWrapping="Wrap" Margin="0,2,0,0"/>
                        <TextBlock x:Name="FixStatus" Text="{Binding StatusText}" Foreground="{StaticResource Good}" FontSize="12.5" TextWrapping="Wrap" Margin="0,3,0,0"/>
                        <ProgressBar x:Name="FixRowBar" Style="{StaticResource Bar}" IsIndeterminate="True" Margin="0,6,40,0" Visibility="Collapsed"/>
                      </StackPanel>
                      <Button Grid.Column="2" Content="{Binding ActionText}" Tag="fixopen" Style="{StaticResource RowButton}" VerticalAlignment="Top"
                              Visibility="{Binding HasAction, Converter={StaticResource B2V}}"/>
                    </Grid>
                    <DataTemplate.Triggers>
                      <DataTrigger Binding="{Binding CanChoose}" Value="False"><Setter TargetName="FixDot" Property="Visibility" Value="Visible"/></DataTrigger>
                      <DataTrigger Binding="{Binding StatusText}" Value=""><Setter TargetName="FixStatus" Property="Visibility" Value="Collapsed"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="running"><Setter TargetName="FixRowBar" Property="Visibility" Value="Visible"/><Setter TargetName="FixStatus" Property="Foreground" Value="White"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="reboot"><Setter TargetName="FixStatus" Property="Foreground" Value="{StaticResource Warn}"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="error"><Setter TargetName="FixStatus" Property="Foreground" Value="{StaticResource Bad}"/></DataTrigger>
                      <DataTrigger Binding="{Binding State}" Value="skipped"><Setter TargetName="FixStatus" Property="Foreground" Value="#8A8A8A"/></DataTrigger>
                    </DataTemplate.Triggers>
                  </DataTemplate>
                </ItemsControl.ItemTemplate>
              </ItemsControl>
            </ScrollViewer>
          </Border>
          <DockPanel Grid.Row="2" Margin="30,18,30,24">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <Button x:Name="FixClose" Content="Cancel"/>
              <Button x:Name="FixGo" Style="{StaticResource Primary}" Margin="0" MinWidth="130">
                <TextBlock x:Name="FixGoText" Text="Fix"/>
              </Button>
            </StackPanel>
            <TextBlock x:Name="FixNote" Foreground="{StaticResource Muted}" FontSize="12.5" VerticalAlignment="Center" TextWrapping="Wrap" Margin="0,0,16,0"/>
          </DockPanel>
        </Grid>
      </Border>
    </Grid>

    <!-- Yes/no question (uninstall, moving the scheduled task, removing a source); last, so it shows above every panel -->
    <Grid x:Name="ConfirmOverlay" Grid.RowSpan="5" Background="#B8000000" Visibility="Collapsed">
      <Border Width="480" Background="#252525" BorderBrush="#3A3A3A" BorderThickness="1" CornerRadius="12" Padding="28,24,28,22" HorizontalAlignment="Center" VerticalAlignment="Center">
        <StackPanel>
          <TextBlock x:Name="ConfirmTitle" FontSize="18" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
          <TextBlock x:Name="ConfirmText" Foreground="#BDBDBD" TextWrapping="Wrap" Margin="0,8,0,22" LineHeight="20"/>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="ConfirmNo" Content="Cancel"/>
            <Button x:Name="ConfirmYes" Style="{StaticResource Primary}" Margin="0" MinWidth="96"/>
          </StackPanel>
        </StackPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
'@

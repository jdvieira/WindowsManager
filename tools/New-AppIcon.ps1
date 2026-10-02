#Requires -Version 5.1
<#
.SYNOPSIS
Draws the app's icon (the Pulse mark) and writes assets\icon.ico.

.DESCRIPTION
The icon is a window with a heartbeat line through it, in the app's teal-to-violet gradient on a dark rounded tile,
drawn on a 64 x 64 grid. Every size Windows uses (16 to 256 px) is drawn from the same shapes, each as a PNG frame
in the .ico; the smallest sizes get slightly heavier lines so they stay crisp. Build-Exe.ps1 embeds the result, and
the app uses it for its window, header, taskbar and notifications. (The About window keeps assets\logo.jpg.)

.PARAMETER Preview
Also writes each size as a PNG to this folder, to look at.

.EXAMPLE
.\tools\New-AppIcon.ps1
.\tools\New-AppIcon.ps1 -Preview $env:TEMP\icon-preview

.NOTES
Created By:         Justin Vieira (jdvieira@icloud.com)
#>
[CmdletBinding()]
param([string]$Preview)

$ErrorActionPreference = 'Stop'
# WPF draws the icon: Windows PowerShell 5.1 on an STA thread
if ($PSVersionTable.PSEdition -ne 'Desktop' -or [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    $forward = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', $PSCommandPath)
    if ($Preview) { $forward += @('-Preview', $Preview) }
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @forward
    exit $LASTEXITCODE
}
Add-Type -AssemblyName PresentationCore, WindowsBase
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root 'assets\icon.ico'

# The mark, on a 64 x 64 grid (WPF path markup, the same as the SVG it was designed in)
$Tile = 'M15,1 H49 A14,14 0 0 1 63,15 V49 A14,14 0 0 1 49,63 H15 A14,14 0 0 1 1,49 V15 A14,14 0 0 1 15,1 Z'
$Window = 'M18,14 H46 A6,6 0 0 1 52,20 V44 A6,6 0 0 1 46,50 H18 A6,6 0 0 1 12,44 V20 A6,6 0 0 1 18,14 Z'
$TitleBar = 'M12,23 H52'
$Pulse = 'M16,38 H22.5 L26,31 L31,44 L35.5,34 L38.5,38 H48'
# 24 px and under: a larger window and a single spike, with lines on whole pixels (the 64 grid's 4n+2 at 16 px),
# so the mark stays sharp instead of blurring
$SmallWindow = 'M16,10 H48 A6,6 0 0 1 54,16 V48 A6,6 0 0 1 48,54 H16 A6,6 0 0 1 10,48 V16 A6,6 0 0 1 16,10 Z'
$SmallTitleBar = 'M10,22 H54'
$SmallPulse = 'M14,38 H22 L26,30 L34,46 L38,38 H50'

function New-Brush([string]$Hex) { return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex)) }

function New-IconFrame([int]$Size) {
    $g = New-Object System.Windows.Media.LinearGradientBrush
    $g.MappingMode = 'Absolute'; $g.StartPoint = '12,12'; $g.EndPoint = '52,52'
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#22C8D8')), 0))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString('#6A74F0')), 1))
    # lines no thinner than about 1.1 px at the smallest sizes
    $w = [Math]::Max(4.0, 1.15 * 64 / $Size)
    $pen = New-Object System.Windows.Media.Pen ($g, $w)
    $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'; $pen.LineJoin = 'Round'
    $thin = $pen.Clone(); $thin.Thickness = [Math]::Max(3.5, $w * 0.875)
    $dv = New-Object System.Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object System.Windows.Media.ScaleTransform ($Size / 64.0), ($Size / 64.0)))
    $edge = New-Object System.Windows.Media.Pen ((New-Brush '#2B2F38'), [Math]::Max(1.5, 64.0 / $Size))
    $dc.DrawGeometry((New-Brush '#0D1016'), $edge, [System.Windows.Media.Geometry]::Parse($Tile))
    $small = $Size -le 24
    $dc.DrawGeometry($null, $pen, [System.Windows.Media.Geometry]::Parse($(if ($small) { $SmallWindow } else { $Window })))
    $dc.DrawGeometry($null, $pen, [System.Windows.Media.Geometry]::Parse($(if ($small) { $SmallTitleBar } else { $TitleBar })))
    $dc.DrawGeometry($null, $(if ($small) { $pen } else { $thin }), [System.Windows.Media.Geometry]::Parse($(if ($small) { $SmallPulse } else { $Pulse })))
    $dc.Pop(); $dc.Close()
    $bmp = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $Size, $Size, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create([System.Windows.Media.Imaging.BitmapSource]$bmp))
    $ms = New-Object IO.MemoryStream
    $enc.Save($ms)
    return , $ms.ToArray()
}

# An .ico is a small header, one directory entry per size, then each frame (PNG frames, which Windows reads from Vista on)
$sizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)
$frames = @(foreach ($s in $sizes) { , (New-IconFrame $s) })
$ms = New-Object IO.MemoryStream
$bw = New-Object IO.BinaryWriter $ms
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $s = $sizes[$i]; $len = $frames[$i].Length
    $bw.Write([byte]($s % 256)); $bw.Write([byte]($s % 256))   # 256 is written as 0
    $bw.Write([byte]0); $bw.Write([byte]0); $bw.Write([uint16]1); $bw.Write([uint16]32)
    $bw.Write([uint32]$len); $bw.Write([uint32]$offset)
    $offset += $len
}
foreach ($f in $frames) { $bw.Write([byte[]]$f) }
$bw.Flush()
[IO.File]::WriteAllBytes($out, $ms.ToArray())
Write-Host "Wrote $out ($($sizes -join ', ') px, $([Math]::Round($ms.Length / 1KB)) KB)"

if ($Preview) {
    New-Item -ItemType Directory -Path $Preview -Force | Out-Null
    for ($i = 0; $i -lt $sizes.Count; $i++) { [IO.File]::WriteAllBytes((Join-Path $Preview "icon-$($sizes[$i]).png"), [byte[]]$frames[$i]) }
    Write-Host "Previews in $Preview"
}

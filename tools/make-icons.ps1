<#
    Renders branding\*.svg with headless Microsoft Edge and writes every icon and
    logo file the RustDesk Windows build needs into overlay\ (same relative paths
    as inside the rustdesk source tree).

    Run:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\make-icons.ps1 [-Target windows|mac|all]
    windows -> overlay\ (shared by both builds); mac -> mac\overlay\ and mac\MohiView.iconset\

    Pure ASCII on purpose: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
#>
param(
    [ValidateSet('windows', 'mac', 'all')]
    [string]$Target = 'all'
)
$ErrorActionPreference = 'Stop'
$root    = Split-Path -Parent $PSScriptRoot
$brand   = Join-Path $root 'branding'
$overlay = Join-Path $root 'overlay'
$work    = Join-Path $env:TEMP ('mohiview-icons-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
          "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") |
        Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge not found' }

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class IcoWriter {
    // Sizes below 256 are stored as classic 32-bit DIBs (widest compatibility),
    // 256 is stored as PNG, like Windows' own icons.
    public static void Write(string outPath, string[] pngPaths) {
        var blobs = new List<byte[]>();
        var sizes = new List<int>();
        foreach (var p in pngPaths) {
            using (var src = new Bitmap(p)) {
                int w = src.Width, h = src.Height;
                if (w != h) throw new Exception("icon frame is not square: " + p);
                sizes.Add(w);
                if (w >= 256) { blobs.Add(File.ReadAllBytes(p)); continue; }
                var rect = new Rectangle(0, 0, w, h);
                var px = new byte[w * h * 4];
                using (var b32 = src.Clone(rect, PixelFormat.Format32bppArgb)) {
                    var data = b32.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                    for (int y = 0; y < h; y++)
                        Marshal.Copy(IntPtr.Add(data.Scan0, y * data.Stride), px, y * w * 4, w * 4);
                    b32.UnlockBits(data);
                }
                int maskStride = ((w + 31) / 32) * 4;
                using (var ms = new MemoryStream())
                using (var bw = new BinaryWriter(ms)) {
                    bw.Write(40); bw.Write(w); bw.Write(h * 2);
                    bw.Write((short)1); bw.Write((short)32);
                    bw.Write(0); bw.Write(w * h * 4 + maskStride * h);
                    bw.Write(0); bw.Write(0); bw.Write(0); bw.Write(0);
                    for (int y = h - 1; y >= 0; y--) bw.Write(px, y * w * 4, w * 4);
                    for (int y = h - 1; y >= 0; y--) {
                        var row = new byte[maskStride];
                        for (int x = 0; x < w; x++)
                            if (px[(y * w + x) * 4 + 3] == 0) row[x >> 3] |= (byte)(0x80 >> (x & 7));
                        bw.Write(row);
                    }
                    bw.Flush();
                    blobs.Add(ms.ToArray());
                }
            }
        }
        using (var fs = File.Create(outPath))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write((short)0); bw.Write((short)1); bw.Write((short)blobs.Count);
            int offset = 6 + 16 * blobs.Count;
            for (int i = 0; i < blobs.Count; i++) {
                byte b = (byte)(sizes[i] >= 256 ? 0 : sizes[i]);
                bw.Write(b); bw.Write(b); bw.Write((byte)0); bw.Write((byte)0);
                bw.Write((short)1); bw.Write((short)32);
                bw.Write(blobs[i].Length); bw.Write(offset);
                offset += blobs[i].Length;
            }
            foreach (var blob in blobs) bw.Write(blob);
        }
    }
}
'@

function Render-Svg([string]$svg, [int]$w, [int]$h, [string]$outPng) {
    $html = Join-Path $work ('r{0}x{1}.html' -f $w, $h)
    $svgUri = ([Uri](Resolve-Path $svg).Path).AbsoluteUri
    $doc = '<!doctype html><html><head><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}' +
           'img{display:block;width:' + $w + 'px;height:' + $h + 'px}</style></head><body><img src="' + $svgUri + '"></body></html>'
    Set-Content -Path $html -Encoding ASCII -Value $doc
    if (Test-Path $outPng) { Remove-Item $outPng -Force }
    $profileDir = Join-Path $work 'edge-profile'
    $argList = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
                 '--no-default-browser-check', ('--user-data-dir="{0}"' -f $profileDir),
                 '--force-device-scale-factor=1', '--default-background-color=00000000',
                 ('--window-size={0},{1}' -f $w, $h), ('--screenshot="{0}"' -f $outPng),
                 ([Uri]$html).AbsoluteUri)
    $p = Start-Process -FilePath $edge -ArgumentList $argList -PassThru -WindowStyle Hidden
    if (-not $p.WaitForExit(90000)) { $p.Kill(); throw "Edge timed out rendering $svg at ${w}x$h" }
    if (-not (Test-Path $outPng)) { throw "Edge did not write $outPng" }
}

function Ensure-Dir([string]$path) { New-Item -ItemType Directory -Force -Path $path | Out-Null }

$icon = Join-Path $brand 'icon.svg'

if ($Target -ne 'mac') {
$res = Join-Path $overlay 'res'
$assets = Join-Path $overlay 'flutter\assets'
$runnerRes = Join-Path $overlay 'flutter\windows\runner\resources'
Ensure-Dir $res; Ensure-Dir $assets; Ensure-Dir $runnerRes

# Frames for the .ico files (every size Windows asks for at 100-200% scaling).
$frames = @()
foreach ($s in 16, 20, 24, 32, 40, 48, 64, 96, 128, 256) {
    $f = Join-Path $work ("icon-$s.png")
    Render-Svg $icon $s $s $f
    $frames += $f
}

# res\ (used by the Rust side, the tray fallback and flutter_launcher_icons)
Render-Svg $icon 1024 1024 (Join-Path $res 'icon.png')
Copy-Item (Join-Path $work 'icon-32.png')  (Join-Path $res '32x32.png') -Force
Copy-Item (Join-Path $work 'icon-64.png')  (Join-Path $res '64x64.png') -Force
Copy-Item (Join-Path $work 'icon-128.png') (Join-Path $res '128x128.png') -Force
Copy-Item (Join-Path $work 'icon-256.png') (Join-Path $res '128x128@2x.png') -Force
[IcoWriter]::Write((Join-Path $res 'icon.ico'), $frames)
[IcoWriter]::Write((Join-Path $res 'tray-icon.ico'), @((Join-Path $work 'icon-32.png')))

# Windows runner (exe, taskbar, shortcuts)
Copy-Item (Join-Path $res 'icon.ico') (Join-Path $runnerRes 'app_icon.ico') -Force

# Flutter assets: vector icon, 48 px raster (title bar, connection manager, tray),
# .ico for shortcuts, and the home-page logo for light and dark themes (2x of 300x60 box).
Copy-Item $icon (Join-Path $assets 'icon.svg') -Force
Copy-Item (Join-Path $work 'icon-48.png') (Join-Path $assets 'icon.png') -Force
Copy-Item (Join-Path $res 'icon.ico') (Join-Path $assets 'icon.ico') -Force
Render-Svg (Join-Path $brand 'logo-light.svg') 900 240 (Join-Path $assets 'logo_light.png')
Render-Svg (Join-Path $brand 'logo-dark.svg')  900 240 (Join-Path $assets 'logo_dark.png')
}

if ($Target -ne 'windows') {
    # macOS: app icon set (turned into AppIcon.icns by iconutil on the Mac runner),
    # the 1024 px mac-icon.png, and the menu-bar template icons (shape only).
    $mac = Join-Path $root 'mac'
    $iconset = Join-Path $mac 'MohiView.iconset'
    $macRes = Join-Path $mac 'overlay\res'
    Ensure-Dir $iconset; Ensure-Dir $macRes
    $sets = [ordered]@{
        'icon_16x16.png' = 16; 'icon_16x16@2x.png' = 32; 'icon_32x32.png' = 32; 'icon_32x32@2x.png' = 64
        'icon_128x128.png' = 128; 'icon_128x128@2x.png' = 256; 'icon_256x256.png' = 256
        'icon_256x256@2x.png' = 512; 'icon_512x512.png' = 512; 'icon_512x512@2x.png' = 1024
    }
    foreach ($name in $sets.Keys) { Render-Svg $icon $sets[$name] $sets[$name] (Join-Path $iconset $name) }
    Copy-Item (Join-Path $iconset 'icon_512x512@2x.png') (Join-Path $macRes 'mac-icon.png') -Force
    $tray = Join-Path $brand 'tray-template.svg'
    Render-Svg $tray 60 60 (Join-Path $macRes 'mac-tray-dark-x2.png')
    Render-Svg $tray 48 48 (Join-Path $macRes 'mac-tray-light-x2.png')
}

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
foreach ($dir in @($overlay, (Join-Path $root 'mac'))) {
    if (Test-Path $dir) {
        Get-ChildItem -Recurse -File $dir -Include *.png, *.ico, *.svg | ForEach-Object {
            '{0,-60} {1,8}' -f $_.FullName.Substring($root.Length + 1), $_.Length
        }
    }
}

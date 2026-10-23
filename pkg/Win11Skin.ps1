# Win11 skin pro VLC - motor
# Cte z Windows svetly/tmavy rezim a akcentni barvu, pripravi z nich skin a nastavi VLC.
# Spousti se pres Instalovat.bat / Odinstalovat.bat (nebo rucne: Win11Skin.ps1 -Action Status)
param(
    [ValidateSet('Install', 'Uninstall', 'Apply', 'Watch', 'Status', 'Probe', 'SetScale')]
    [string]$Action = 'Apply',
    [ValidateSet('', 'light', 'dark')]
    [string]$Theme = '',          # natvrdo svetly/tmavy (jinak podle Windows)
    [string]$Accent = '',         # natvrdo akcent jako RRGGBB (jinak podle Windows)
    [double]$Scale = 0,           # natvrdo meritko skinu 1, 1.25, 1.5, 1.75, 2 (jinak automaticky)
    [string]$OutDir = '',         # kam skin vygenerovat (jinak slozka instalace)
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$InstallDir = Join-Path $env:APPDATA 'Win11VLC'
$VlcCfgDir = Join-Path $env:APPDATA 'vlc'
$VlcRc = Join-Path $VlcCfgDir 'vlcrc'
$RunKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$RunName = 'Win11VLCSkin'
$SkinVersion = '1'
$Scales = @(1.0, 1.25, 1.5, 1.75, 2.0)

function Say([string]$msg) {
    if (-not $Quiet) { Write-Host $msg }
}

# ------------------------------------------------------------------ Windows
function Get-WindowsStyle {
    $light = $true
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme
        if ($v -eq 0) { $light = $false }
    } catch { }

    $acc = $null
    try {
        $pal = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent' -ErrorAction Stop).AccentPalette
        if ($pal -and $pal.Length -ge 32) {
            # paleta: 0 Light3, 1 Light2, 2 Light1, 3 Accent, 4 Dark1, 5 Dark2, 6 Dark3 (R,G,B,A)
            # Windows 11 pouziva ve svetlem rezimu Dark1 a v tmavem Light2
            if ($light) { $i = 4 } else { $i = 1 }
            $acc = @([int]$pal[$i * 4], [int]$pal[$i * 4 + 1], [int]$pal[$i * 4 + 2])
        }
    } catch { }

    if (-not $acc) {
        try {
            $c = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM' -ErrorAction Stop).AccentColor
            if ($null -ne $c) {
                $r = [int]($c -band 0xFF)
                $g = [int](($c -shr 8) -band 0xFF)
                $b = [int](($c -shr 16) -band 0xFF)
                if ($light) { $k = 0.85 } else { $k = 1.0 }
                $acc = @([int]($r * $k), [int]($g * $k), [int]($b * $k))
                if (-not $light) {
                    $acc = @([int]($r + (255 - $r) * 0.35), [int]($g + (255 - $g) * 0.35), [int]($b + (255 - $b) * 0.35))
                }
            }
        } catch { }
    }
    if (-not $acc) {
        if ($light) { $acc = @(0, 103, 192) } else { $acc = @(76, 194, 255) }
    }
    return @{ Light = $light; Accent = $acc }
}

function Get-DpiScale {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win11SkinNative {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr hdc, int index);
}
'@ -ErrorAction SilentlyContinue
        [void][Win11SkinNative]::SetProcessDPIAware()
        $dc = [Win11SkinNative]::GetDC([IntPtr]::Zero)
        $dpi = [Win11SkinNative]::GetDeviceCaps($dc, 88)
        [void][Win11SkinNative]::ReleaseDC([IntPtr]::Zero, $dc)
        if ($dpi -gt 0) { return $dpi / 96.0 }
    } catch { }
    return 1.0
}

function Get-VlcExe {
    foreach ($k in @('HKLM:\SOFTWARE\VideoLAN\VLC', 'HKLM:\SOFTWARE\WOW6432Node\VideoLAN\VLC', 'HKCU:\SOFTWARE\VideoLAN\VLC')) {
        try {
            $d = (Get-ItemProperty $k -ErrorAction Stop).InstallDir
            if ($d -and (Test-Path (Join-Path $d 'vlc.exe'))) { return (Join-Path $d 'vlc.exe') }
        } catch { }
    }
    foreach ($p in @("$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe")) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# Je VLC "DPI aware"? Zjistime to primo z okna skinu spustene instance VLC.
# (Kdyz neni, Windows cele okno pri vyssim meritku jen roztahne a skin se nema zvetsovat.)
function Measure-VlcAwareness {
    $exe = Get-VlcExe
    if (-not $exe) { return $null }
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class Win11SkinProbe {
    delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr h);
    [DllImport("user32.dll")] static extern int GetAwarenessFromDpiAwarenessContext(IntPtr c);
    // -2 = okno nenalezeno, -1 = funkce neni k dispozici, 0 unaware, 1 system, 2 per-monitor
    public static int Awareness(uint pid) {
        int result = -2;
        try {
            EnumWindows(delegate (IntPtr h, IntPtr l) {
                uint p; GetWindowThreadProcessId(h, out p);
                if (p != pid || !IsWindowVisible(h)) return true;
                StringBuilder sb = new StringBuilder(64);
                GetClassName(h, sb, 64);
                if (sb.ToString() != "SkinWindowClass") return true;
                result = GetAwarenessFromDpiAwarenessContext(GetWindowDpiAwarenessContext(h));
                return false;
            }, IntPtr.Zero);
        } catch { return -1; }
        return result;
    }
}
'@ -ErrorAction SilentlyContinue
    } catch { }
    $proc = $null
    try {
        $proc = Start-Process -FilePath $exe -PassThru
        $res = -2
        for ($i = 0; $i -lt 40; $i++) {
            Start-Sleep -Milliseconds 500
            $res = [Win11SkinProbe]::Awareness([uint32]$proc.Id)
            if ($res -ne -2) { break }
        }
    } catch { $res = -1 } finally {
        if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    }
    if ($res -eq 0) { return 'unaware' }
    if ($res -ge 1) { return 'aware' }
    return $null
}

function Get-StoredAwareness {
    $f = Join-Path $InstallDir 'dpi.txt'
    if (Test-Path $f) { return (Get-Content -LiteralPath $f -Raw).Trim() }
    return ''
}

function Pick-Scale([double]$wanted) {
    $best = $Scales[0]
    foreach ($s in $Scales) {
        if ([math]::Abs($s - $wanted) -lt [math]::Abs($best - $wanted)) { $best = $s }
    }
    return $best
}

# ------------------------------------------------------------------- skin
function New-LayerBitmap([int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bmp.SetResolution(96, 96)
    return $bmp
}

function Merge-Layers([string]$under, [string]$accentLayer, [string]$over, [int[]]$acc, [string]$dest) {
    $first = $null
    foreach ($p in @($under, $accentLayer, $over)) { if ($p) { $first = $p; break } }
    $probe = [System.Drawing.Image]::FromFile($first)
    $w = $probe.Width; $h = $probe.Height
    $probe.Dispose()
    $bmp = New-LayerBitmap $w $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)

    foreach ($layer in @(@($under, $false), @($accentLayer, $true), @($over, $false))) {
        $path = $layer[0]
        if (-not $path) { continue }
        $img = [System.Drawing.Image]::FromFile($path)
        $attr = New-Object System.Drawing.Imaging.ImageAttributes
        $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        if ($layer[1]) {
            # barva = akcent, pruhlednost zustava (R'=r, G'=g, B'=b, A'=A)
            $m = New-Object 'single[][]' 5
            $m[0] = [single[]]@(0, 0, 0, 0, 0)
            $m[1] = [single[]]@(0, 0, 0, 0, 0)
            $m[2] = [single[]]@(0, 0, 0, 0, 0)
            $m[3] = [single[]]@(0, 0, 0, 1, 0)
            $m[4] = [single[]]@(($acc[0] / 255.0), ($acc[1] / 255.0), ($acc[2] / 255.0), 0, 1)
            $cm = New-Object System.Drawing.Imaging.ColorMatrix(, $m)
            $attr.SetColorMatrix($cm)
        }
        $g.DrawImage($img, $rect, 0, 0, $w, $h, [System.Drawing.GraphicsUnit]::Pixel, $attr)
        $attr.Dispose()
        $img.Dispose()
    }
    $g.Dispose()
    $bmp.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Build-Skin([string]$dataDir, [string]$dest, [bool]$light, [int[]]$acc, [double]$scale) {
    if ($light) { $themeName = 'light' } else { $themeName = 'dark' }
    $sname = 's' + [int][math]::Round($scale * 100)
    $tpl = Join-Path (Join-Path $dataDir $themeName) $sname
    if (-not (Test-Path (Join-Path $tpl 'theme.xml.tpl'))) { throw "Chybi data skinu: $tpl" }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    # vrstvy -> hotove obrazky
    $groups = @{}
    foreach ($f in Get-ChildItem -LiteralPath $tpl -Filter '*.png') {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
        $idx = $stem.IndexOf('+')
        if ($idx -ge 0) {
            $base = $stem.Substring(0, $idx); $layer = $stem.Substring($idx + 1)
        } else {
            $base = $stem; $layer = 'full'
        }
        if (-not $groups.ContainsKey($base)) { $groups[$base] = @{} }
        $groups[$base][$layer] = $f.FullName
    }
    foreach ($base in $groups.Keys) {
        $g = $groups[$base]
        $target = Join-Path $dest ($base + '.png')
        if ($g.ContainsKey('full')) {
            Copy-Item -LiteralPath $g['full'] -Destination $target -Force
        } else {
            Merge-Layers $g['under'] $g['accent'] $g['over'] $acc $target
        }
    }

    # theme.xml
    $xml = [System.IO.File]::ReadAllText((Join-Path $tpl 'theme.xml.tpl'), [System.Text.Encoding]::UTF8)
    $m = [regex]::Match($xml, 'bgcolor1="#([0-9A-Fa-f]{6})"')
    $bar = @([Convert]::ToInt32($m.Groups[1].Value.Substring(0, 2), 16), [Convert]::ToInt32($m.Groups[1].Value.Substring(2, 2), 16), [Convert]::ToInt32($m.Groups[1].Value.Substring(4, 2), 16))
    $soft = @()
    for ($i = 0; $i -lt 3; $i++) { $soft += [int][math]::Round($bar[$i] * (1 - 0.28) + $acc[$i] * 0.28) }
    $hex = { param($c) ('#{0:X2}{1:X2}{2:X2}' -f $c[0], $c[1], $c[2]) }
    $xml = $xml.Replace('@ACCENT_SOFT@', (& $hex $soft)).Replace('@ACCENT@', (& $hex $acc))
    [System.IO.File]::WriteAllText((Join-Path $dest 'theme.xml'), $xml, (New-Object System.Text.UTF8Encoding($false)))

    # pismo: Segoe UI z Windows (neni nase, jen se zkopiruje na tomto pocitaci), jinak zalozni
    $font = Join-Path $dest 'font.ttf'
    $segoe = Join-Path $env:WINDIR 'Fonts\segoeui.ttf'
    $src = Join-Path $dataDir 'font-fallback.ttf'
    if (Test-Path $segoe) { $src = $segoe }
    try {
        $need = $true
        if ((Test-Path $font) -and ((Get-Item $font).Length -eq (Get-Item $src).Length)) { $need = $false }
        if ($need) { Copy-Item -LiteralPath $src -Destination $font -Force }
    } catch { }   # pismo muze byt zrovna otevrene ve VLC - nevadi
}

function Get-DataDir {
    foreach ($d in @((Join-Path $InstallDir 'data'), (Join-Path $ScriptDir 'data'))) {
        if (Test-Path (Join-Path $d 'dark')) { return $d }
    }
    throw 'Nenasel jsem slozku data se skinem.'
}

function Resolve-Style {
    $st = Get-WindowsStyle
    $light = $st.Light
    $acc = $st.Accent
    if ($Theme -eq 'light') { $light = $true }
    if ($Theme -eq 'dark') { $light = $false }
    if ($Accent -match '^#?([0-9A-Fa-f]{6})$') {
        $h = $Matches[1]
        $acc = @([Convert]::ToInt32($h.Substring(0, 2), 16), [Convert]::ToInt32($h.Substring(2, 2), 16), [Convert]::ToInt32($h.Substring(4, 2), 16))
    }
    $sc = 1.0
    $override = ''
    $sf = Join-Path $InstallDir 'scale.txt'
    if (Test-Path $sf) { $override = (Get-Content -LiteralPath $sf -Raw).Trim() }
    if ($Scale -gt 0) {
        $sc = Pick-Scale $Scale
    } elseif ($override -match '^[0-9.]+$') {
        $sc = Pick-Scale ([double]::Parse($override, [Globalization.CultureInfo]::InvariantCulture))
    } elseif ((Get-StoredAwareness) -eq 'aware') {
        $sc = Pick-Scale (Get-DpiScale)
    }
    return @{ Light = $light; Accent = $acc; Scale = $sc }
}

function Apply-Skin([bool]$force) {
    $style = Resolve-Style
    if ($OutDir) { $skinDir = $OutDir } else { $skinDir = Join-Path $InstallDir 'skin' }
    $key = '{0}|{1},{2},{3}|{4}|{5}' -f $style.Light, $style.Accent[0], $style.Accent[1], $style.Accent[2], $style.Scale, $SkinVersion
    $stateFile = Join-Path $skinDir 'state.txt'
    if ((-not $force) -and (Test-Path $stateFile) -and (Test-Path (Join-Path $skinDir 'theme.xml'))) {
        if ((Get-Content -LiteralPath $stateFile -Raw).Trim() -eq $key) { return $false }
    }
    Build-Skin (Get-DataDir) $skinDir $style.Light $style.Accent $style.Scale
    Set-Content -LiteralPath $stateFile -Value $key -Encoding ASCII
    Say ('Skin pripraven: {0}, akcent #{1:X2}{2:X2}{3:X2}, meritko {4}' -f ($(if ($style.Light) { 'svetly' } else { 'tmavy' })), $style.Accent[0], $style.Accent[1], $style.Accent[2], $style.Scale)
    return $true
}

# ------------------------------------------------------------------ vlcrc
function Get-IniLines {
    if (Test-Path $VlcRc) { return [System.IO.File]::ReadAllText($VlcRc, [System.Text.Encoding]::UTF8) }
    return ''
}

function Set-IniValue([string]$text, [string]$section, [string]$key, [string]$value, [bool]$comment) {
    $nl = "`n"
    if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $lines = New-Object System.Collections.ArrayList
    if ($text.Length -gt 0) { $lines.AddRange(($text -split "\r?\n")) }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $newLine = $key + '=' + $value
    if ($comment) { $newLine = '#' + $newLine }
    $secIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq "[$section]") { $secIdx = $i; break }
    }
    if ($secIdx -lt 0) {
        if ($lines.Count -gt 0) { [void]$lines.Add('') }
        [void]$lines.Add("[$section]")
        [void]$lines.Add($newLine)
    } else {
        $end = $lines.Count
        for ($i = $secIdx + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].TrimStart().StartsWith('[') -and $lines[$i].Trim().EndsWith(']')) { $end = $i; break }
        }
        $found = $false
        $pat = '^\s*#?\s*' + [regex]::Escape($key) + '\s*='
        for ($i = $secIdx + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match $pat) {
                if (-not $found) { $lines[$i] = $newLine; $found = $true }
            }
        }
        if (-not $found) { $lines.Insert($secIdx + 1, $newLine) }
    }
    return (($lines -join $nl) + $nl)
}

function Get-IniValue([string]$text, [string]$section, [string]$key) {
    $inSec = $false
    foreach ($ln in ($text -split "\r?\n")) {
        $t = $ln.Trim()
        if ($t.StartsWith('[') -and $t.EndsWith(']')) { $inSec = ($t -eq "[$section]"); continue }
        if ($inSec -and $t -match ('^' + [regex]::Escape($key) + '\s*=(.*)$')) { return $Matches[1] }
    }
    return $null
}

function Write-VlcRc([string]$text) {
    New-Item -ItemType Directory -Force -Path $VlcCfgDir | Out-Null
    [System.IO.File]::WriteAllText($VlcRc, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-VlcRunning {
    return [bool](Get-Process -Name 'vlc' -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- actions
function Do-Install {
    if (Test-VlcRunning) {
        Write-Host 'VLC prave bezi. Zavri ho (i v oznamovaci oblasti u hodin) a spust instalaci znovu.' -ForegroundColor Yellow
        return 2
    }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    # soubory skinu + skript
    if ($ScriptDir -ne $InstallDir) {
        Copy-Item -LiteralPath (Join-Path $ScriptDir 'Win11Skin.ps1') -Destination $InstallDir -Force
        $dst = Join-Path $InstallDir 'data'
        if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
        Copy-Item -LiteralPath (Join-Path $ScriptDir 'data') -Destination $dst -Recurse -Force
    }
    [void](Apply-Skin $true)

    # zaloha puvodniho nastaveni VLC
    $rc = Get-IniLines
    $backup = Join-Path $InstallDir 'backup.txt'
    if (-not (Test-Path $backup)) {
        $oi = Get-IniValue $rc 'core' 'intf'
        $os = Get-IniValue $rc 'skins2' 'skins2-last'
        $lines = @()
        if ($null -ne $oi) { $lines += ('intf=' + $oi) } else { $lines += 'intf-none' }
        if ($null -ne $os) { $lines += ('skins2-last=' + $os) } else { $lines += 'skins2-last-none' }
        Set-Content -LiteralPath $backup -Value $lines -Encoding UTF8
        if (Test-Path $VlcRc) { Copy-Item -LiteralPath $VlcRc -Destination (Join-Path $InstallDir 'vlcrc.puvodni') -Force }
    }
    $skinXml = Join-Path (Join-Path $InstallDir 'skin') 'theme.xml'
    $rc = Set-IniValue $rc 'core' 'intf' 'skins2,any' $false
    $rc = Set-IniValue $rc 'skins2' 'skins2-last' $skinXml $false
    Write-VlcRc $rc

    # na displeji s meritkem nad 100 % zjistime, jestli je VLC "DPI aware" (kratce se otevre a zavre VLC)
    $dpiFile = Join-Path $InstallDir 'dpi.txt'
    if (Test-Path $dpiFile) { Remove-Item -LiteralPath $dpiFile -Force }
    if ((Get-DpiScale) -ge 1.05) {
        Write-Host 'Kratce zkousim VLC (otevre se a za par vterin zavre) ...'
        $aw = Measure-VlcAwareness
        if ($aw) { Set-Content -LiteralPath $dpiFile -Value $aw -Encoding ASCII }
        [void](Apply-Skin $true)
    }

    # automaticke prebarvovani pri prihlaseni (skryte, bez okna)
    $ps1 = Join-Path $InstallDir 'Win11Skin.ps1'
    $vbs = Join-Path $InstallDir 'Win11Skin-Watch.vbs'
    $q = [char]34
    $cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + $q + $q + $ps1 + $q + $q + ' -Action Watch -Quiet'
    $vbsText = 'CreateObject("WScript.Shell").Run "' + $cmd + '", 0, False'
    Set-Content -LiteralPath $vbs -Value $vbsText -Encoding ASCII
    Set-ItemProperty -Path $RunKey -Name $RunName -Value ('wscript.exe //B //Nologo ' + $q + $vbs + $q)
    Start-Process -FilePath 'wscript.exe' -ArgumentList @('//B', '//Nologo', $vbs) | Out-Null

    Write-Host ''
    Write-Host 'Hotovo. Spust VLC - mel by se otevrit ve vzhledu Windows 11.' -ForegroundColor Green
    Write-Host 'Barvy se pri kazdem prihlaseni a pri zmene vzhledu Windows aktualizuji samy (projevi se pri dalsim spusteni VLC).'
    return 0
}

function Stop-Watchers {
    try {
        Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
            Where-Object { $_.CommandLine -match 'Win11Skin\.ps1' -and $_.CommandLine -match '-Action Watch' -and $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Do-Uninstall {
    if (Test-VlcRunning) {
        Write-Host 'VLC prave bezi. Zavri ho a spust odinstalaci znovu.' -ForegroundColor Yellow
        return 2
    }
    Stop-Watchers
    try { Remove-ItemProperty -Path $RunKey -Name $RunName -ErrorAction SilentlyContinue } catch { }
    $backup = Join-Path $InstallDir 'backup.txt'
    $rc = Get-IniLines
    if (Test-Path $VlcRc) {
        $b = @()
        if (Test-Path $backup) { $b = Get-Content -LiteralPath $backup }
        $oi = $null; $os = $null
        foreach ($l in $b) {
            if ($l.StartsWith('intf=')) { $oi = $l.Substring(5) }
            if ($l.StartsWith('skins2-last=')) { $os = $l.Substring(12) }
        }
        if ($null -ne $oi) { $rc = Set-IniValue $rc 'core' 'intf' $oi $false } else { $rc = Set-IniValue $rc 'core' 'intf' '' $true }
        if ($null -ne $os) { $rc = Set-IniValue $rc 'skins2' 'skins2-last' $os $false } else { $rc = Set-IniValue $rc 'skins2' 'skins2-last' '' $true }
        Write-VlcRc $rc
    }
    if (Test-Path $InstallDir) {
        # skript, ktery prave bezi, smazat nejde - smazeme zbytek
        foreach ($n in @('skin', 'data')) {
            $p = Join-Path $InstallDir $n
            if (Test-Path $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    Write-Host 'Odinstalovano. VLC se priste spusti v obycejnem vzhledu.' -ForegroundColor Green
    return 0
}

function Do-Watch {
    $created = $false
    $mutex = New-Object System.Threading.Mutex($true, 'Local\Win11VLCSkinWatch', [ref]$created)
    if (-not $created) { return 0 }
    $script:OutDirSaved = $OutDir
    try {
        while ($true) {
            try { [void](Apply-Skin $false) } catch { }
            Start-Sleep -Seconds 3
        }
    } finally {
        $mutex.ReleaseMutex()
    }
}

function Do-Status {
    $style = Resolve-Style
    $exe = Get-VlcExe
    Write-Host ('Rezim aplikaci : ' + $(if ($style.Light) { 'svetly' } else { 'tmavy' }))
    Write-Host ('Akcentni barva : #{0:X2}{1:X2}{2:X2}' -f $style.Accent[0], $style.Accent[1], $style.Accent[2])
    Write-Host ('Meritko skinu  : {0}' -f $style.Scale)
    Write-Host ('VLC            : {0}' -f $(if ($exe) { $exe } else { 'nenalezen' }))
    Write-Host ('VLC DPI (ulozeno): {0}' -f (Get-StoredAwareness))
    return 0
}

switch ($Action) {
    'Install'   { exit (Do-Install) }
    'Uninstall' { exit (Do-Uninstall) }
    'Apply'     { [void](Apply-Skin $true); exit 0 }
    'Watch'     { exit (Do-Watch) }
    'Status'    { exit (Do-Status) }
    'Probe'     { Write-Host ('Zjisteno: ' + (Measure-VlcAwareness)); exit 0 }
    'SetScale'  {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
        $sf = Join-Path $InstallDir 'scale.txt'
        if ($Scale -gt 0) { Set-Content -LiteralPath $sf -Value ($Scale.ToString([Globalization.CultureInfo]::InvariantCulture)) -Encoding ASCII }
        else { if (Test-Path $sf) { Remove-Item -LiteralPath $sf -Force } }
        [void](Apply-Skin $true)
        Write-Host 'Hotovo. Meritko se projevi pri dalsim spusteni VLC.'
        exit 0
    }
}

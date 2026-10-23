$ErrorActionPreference = 'Continue'
Set-Location "$env:GITHUB_WORKSPACE\pkg"
$o = & powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Install 2>&1 | Out-String
$o
"install exit code: $LASTEXITCODE"
"---- probe"
$o = & powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Probe 2>&1 | Out-String
$o
"---- vlcrc relevant lines"
Select-String -Path "$env:APPDATA\vlc\vlcrc" -Pattern '^\s*#?\s*(intf|skins2-last)\s*=' | ForEach-Object { $_.Line }
Get-ChildItem "$env:APPDATA\Win11VLC" | Format-Table Name, Length | Out-Host
Get-Content "$env:APPDATA\Win11VLC\skin\state.txt"
Get-Content "$env:APPDATA\Win11VLC\backup.txt"
Get-Process powershell, wscript -ErrorAction SilentlyContinue | Format-Table Id, ProcessName | Out-Host
Add-Content -Path "$env:APPDATA\vlc\vlcrc" -Value "`n[qt]`nqt-privacy-ask=0`n[core]`nmetadata-network-access=0"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
function Shot($name) {
  $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
  $bmp.Save("$env:GITHUB_WORKSPACE\shots\$name.png")
  "screen: $($b.Width)x$($b.Height)"
}
New-Item -ItemType Directory -Force "$env:GITHUB_WORKSPACE\shots" | Out-Null
$vlc = "C:\Program Files\VideoLAN\VLC\vlc.exe"
function Run($name) {
  $p = Start-Process $vlc -ArgumentList '-vv', '--file-logging', "--logfile=$env:GITHUB_WORKSPACE\shots\$name.log" -PassThru
  Start-Sleep 12
  Shot $name
  Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
  Start-Sleep 2
}
Run 'default_theme'
# change Windows look: other theme and a red accent palette
$pers = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
if (-not (Test-Path $pers)) { New-Item -Path $pers -Force | Out-Null }
$cur = (Get-ItemProperty $pers -ErrorAction SilentlyContinue).AppsUseLightTheme
"AppsUseLightTheme was: $cur"
if ($cur -eq 0) { $new = 1 } else { $new = 0 }
Set-ItemProperty $pers -Name AppsUseLightTheme -Value $new -Type DWord
$acc = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent'
if (-not (Test-Path $acc)) { New-Item -Path $acc -Force | Out-Null }
[byte[]]$pal = 0xFF,0x9A,0x9A,0, 0xFF,0x6B,0x6B,0, 0xF0,0x30,0x40,0, 0xE8,0x11,0x23,0, 0xC0,0x0E,0x1C,0, 0x90,0x0A,0x15,0, 0x60,0x07,0x0E,0, 0xF7,0x63,0x0C,0
Set-ItemProperty $acc -Name AccentPalette -Value $pal -Type Binary
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:APPDATA\Win11VLC\Win11Skin.ps1" -Action Status
Start-Sleep 5   # the watcher started by the installer should pick the change up
Get-Content "$env:APPDATA\Win11VLC\skin\state.txt"
Run 'switched_theme'
Get-Content "$env:GITHUB_WORKSPACE\shots\switched_theme.log" | Select-String -Pattern 'skins2' | Select-Object -First 15 | ForEach-Object { $_.Line }
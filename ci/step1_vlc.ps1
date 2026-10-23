$ErrorActionPreference = 'Continue'
choco install vlc -y --no-progress | Out-Host
$exe = "C:\Program Files\VideoLAN\VLC\vlc.exe"
(Get-Item $exe).VersionInfo.ProductVersion
Get-ChildItem "C:\Program Files\VideoLAN\VLC\skins" | Format-Table Name, Length | Out-Host
$bytes = [System.IO.File]::ReadAllBytes($exe)
$text = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
$m = [regex]::Matches($text, '<(?:\w+:)?(?:dpiAware|dpiAwareness|longPathAware|gdiScaling)[^>]*>[^<]*<')
"manifest dpi entries: $($m.Count)"
$m | ForEach-Object { $_.Value }
$i = $text.IndexOf('<assembly')
if ($i -ge 0) { $text.Substring($i, [Math]::Min(3000, $text.Length - $i)) }
"psversion: $($PSVersionTable.PSVersion)"
choco install ffmpeg -y --no-progress | Out-Null
$ff = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
"ffmpeg: $ff"
if ($ff) {
  & $ff -y -loglevel error -f lavfi -i testsrc2=duration=60:size=640x360:rate=10 -f lavfi -i sine=frequency=440:duration=60 -c:v libx264 -preset veryfast -crf 30 -pix_fmt yuv420p -c:a aac -shortest "$env:GITHUB_WORKSPACE\test.mp4"
  Get-Item "$env:GITHUB_WORKSPACE\test.mp4" | Format-Table Name, Length | Out-Host
}

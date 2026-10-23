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
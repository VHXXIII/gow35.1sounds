Set-Location "$env:GITHUB_WORKSPACE\pkg"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Uninstall
Select-String -Path "$env:APPDATA\vlc\vlcrc" -Pattern '^\s*#?\s*(intf|skins2-last)\s*=' | ForEach-Object { $_.Line }
(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue).Win11VLCSkin
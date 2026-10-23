$ErrorActionPreference = 'Continue'
Set-Location "$env:GITHUB_WORKSPACE\pkg"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Status
$sw = [Diagnostics.Stopwatch]::StartNew()
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Apply -Theme dark -Accent 4CC2FF -Scale 1 -OutDir "$env:GITHUB_WORKSPACE\out\dark_blue"
"dark apply seconds: $($sw.Elapsed.TotalSeconds)"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Apply -Theme light -Accent 0067C0 -Scale 1 -OutDir "$env:GITHUB_WORKSPACE\out\light_blue"
powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11Skin.ps1 -Action Apply -Theme dark -Accent E81123 -Scale 1.5 -OutDir "$env:GITHUB_WORKSPACE\out\dark_red150"
python -m pip install pillow | Out-Null
Set-Location $env:GITHUB_WORKSPACE
python ci\compare.py
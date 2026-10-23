@echo off
chcp 65001 >nul
title Win11 skin pro VLC - meritko
echo Velikost skinu: napis 1, 1.25, 1.5, 1.75 nebo 2 (100, 125, 150, 175, 200 procent).
echo Napis auto, aby se velikost vybrala sama.
set /p S=Tvoje volba: 
if "%S%"=="auto" set S=0
set S=%S:,=.%
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Skin.ps1" -Action SetScale -Scale %S%
echo.
pause

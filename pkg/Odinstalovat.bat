@echo off
chcp 65001 >nul
title Win11 skin pro VLC - odinstalace
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Win11Skin.ps1" -Action Uninstall
echo.
pause

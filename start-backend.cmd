@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo Starting GLM Coding Helper backend...
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\start_backend.ps1" -Mode cpu -Port 8888
pause

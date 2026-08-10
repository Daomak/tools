@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "count.ps1"

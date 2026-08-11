@echo off
chcp 65001 >nul
cd /d "%~dp0"

if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "update.ps1" %*
) else (
    powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "update.ps1" %*
)

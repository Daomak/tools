# DaoKits one-click update
# Usage: irm https://tools.daomak.com/boot.ps1 | iex

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://tools.daomak.com/boot.ps1 | iex`""
    exit
}

$dir = "C:\Daokits\update"
$base = "https://tools.daomak.com"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "        DaoKits Bootstrapper" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

New-Item -ItemType Directory -Force $dir | Out-Null
$wc = New-Object Net.WebClient

Write-Host "Downloading " -ForegroundColor Gray -NoNewline
Write-Host "updater" -ForegroundColor White -NoNewline
Write-Host "..." -ForegroundColor Gray

$wc.DownloadFile("$base/update.ps1", "$dir\update.ps1")
Write-Host "  update.ps1 " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White

$wc.DownloadFile("$base/update.ini", "$dir\update.ini")
Write-Host "  update.ini  " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White

$wc.DownloadFile("$base/count.ps1", "$dir\count.ps1")
Write-Host "  count.ps1   " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White

$wc.DownloadFile("$base/update.bat", "$dir\update.bat")
Write-Host "  update.bat  " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White

$wc.DownloadFile("$base/count.bat", "$dir\count.bat")
Write-Host "  count.bat   " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White

Write-Host ""
Write-Host "Starting " -ForegroundColor Gray -NoNewline
Write-Host "updater" -ForegroundColor White -NoNewline
Write-Host "..." -ForegroundColor Gray
Write-Host ""

powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\update.ps1"

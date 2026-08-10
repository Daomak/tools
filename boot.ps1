# DaoKits one-click update
# Usage: irm https://tools.daomak.com/boot.ps1 | iex

$dir = "C:\Daokits\update"
$base = "https://tools.daomak.com"

New-Item -ItemType Directory -Force $dir | Out-Null
$wc = New-Object Net.WebClient

$wc.DownloadFile("$base/update.ps1", "$dir\update.ps1")
$wc.DownloadFile("$base/count.ps1", "$dir\count.ps1")
$wc.DownloadFile("$base/update.bat", "$dir\update.bat")
$wc.DownloadFile("$base/count.bat", "$dir\count.bat")

powershell -NoProfile -ExecutionPolicy Bypass -File "$dir\update.ps1"

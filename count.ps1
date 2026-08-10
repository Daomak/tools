# DaoKits file counter
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$binDir = Join-Path (Split-Path -Parent $PSScriptRoot) "bin"
$count = 0
if (Test-Path $binDir) {
    $count = (Get-ChildItem $binDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
}

$statFile = Join-Path $PSScriptRoot "文件统计.ini"
$updateCount = 0
if (Test-Path $statFile) {
    Get-Content $statFile -Encoding Default | ForEach-Object {
        if ($_ -match '更新库数=(\d+)') { $updateCount = $Matches[1] }
    }
}

$out = "[文件统计]`r`n更新库数=$updateCount`r`n实际库数=$count`r`n"
[System.IO.File]::WriteAllText($statFile, $out, [System.Text.Encoding]::GetEncoding("GBK"))

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "        DaoKits File Counter" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Updated: " -ForegroundColor Gray -NoNewline
Write-Host "$updateCount" -ForegroundColor White -NoNewline
Write-Host " files" -ForegroundColor Gray
Write-Host "Actual:  " -ForegroundColor Gray -NoNewline
Write-Host "$count" -ForegroundColor White -NoNewline
Write-Host " files" -ForegroundColor Gray
Write-Host ""
if ($count -eq $updateCount) {
    Write-Host "Status: " -ForegroundColor Gray -NoNewline
    Write-Host "In sync" -ForegroundColor Green
} else {
    Write-Host "Status: " -ForegroundColor Gray -NoNewline
    Write-Host "Mismatch" -ForegroundColor Yellow
}
Write-Host ""

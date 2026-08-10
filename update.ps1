# DaoKits Auto Update Script (Single File)
$OutputEncoding = [System.Text.Encoding]::UTF8

# ==========================================
# Config
# ==========================================
$downloadUrl = "https://github.com/Daomak/tools/releases/latest/download/Daokits.zip"
$targetDir = "..\"
$mainExe = "DaoKits"
# ==========================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$zipName = [System.IO.Path]::GetFileName($downloadUrl)
if (-not $zipName.EndsWith('.zip')) { $zipName += '.zip' }

if (-not [System.IO.Path]::IsPathRooted($targetDir)) {
    $targetDir = Join-Path $scriptDir $targetDir
}
$targetDir = [System.IO.Path]::GetFullPath($targetDir)

$zipFile = Join-Path $scriptDir $zipName
$tempDir = Join-Path $scriptDir "temp_update"
$logFile = Join-Path $scriptDir "更新日志.ini"

Write-Host "========================================"
Write-Host "        DaoKits Updater"
Write-Host "========================================"
Write-Host ""

# ==========================================
# Step 0: Check .NET
# ==========================================
Write-Host "[0/3] Checking environment..."
Write-Host ""

function Test-DotNet45 {
    $ndpPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    if (Test-Path $ndpPath) {
        try {
            $release = (Get-ItemProperty -Path $ndpPath -Name Release -ErrorAction Stop).Release
            if ($release -ge 378389) { return $true }
        } catch {}
    }
    return $false
}

if (-not (Test-DotNet45)) {
    Write-Host ".NET Framework 4.5+ not found, installing 4.8..."
    $installerUrl = "https://go.microsoft.com/fwlink/?LinkId=2085155"
    $installerPath = Join-Path $scriptDir "dotnet48_setup.exe"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($installerUrl, $installerPath)
        $p = Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait -PassThru -Verb RunAs
        Remove-Item $installerPath -Force
    } catch {
        Write-Host "Failed to install .NET 4.8"
        Start-Sleep 5
        exit 1
    }
}
Write-Host "Environment OK"
Write-Host ""

# ==========================================
# Step 1: Download
# ==========================================
Write-Host "[1/3] Downloading update..."
Write-Host "URL: $downloadUrl"
Write-Host ""

$totalSize = 0
try {
    $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
    $req.Method = "HEAD"
    $resp = $req.GetResponse()
    $totalSize = $resp.ContentLength
    $resp.Close()
} catch {}

$downloadJob = Start-Job -ScriptBlock {
    param($url, $zipFile)
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile($url, $zipFile)
} -ArgumentList $downloadUrl, $zipFile

$lastPercent = -1
while ($downloadJob.State -eq 'Running') {
    Start-Sleep -Milliseconds 100
    if ($totalSize -gt 0 -and (Test-Path $zipFile)) {
        $cur = (Get-Item $zipFile).Length
        $pct = [math]::Min([math]::Round($cur / $totalSize * 100, 0), 99)
        if ($pct -ne $lastPercent) {
            $lastPercent = $pct
            $rMB = [math]::Round($cur / 1MB, 2)
            $tMB = [math]::Round($totalSize / 1MB, 2)
            $bar = "o" * ([math]::Round($pct / 100 * 30)) + " " * (30 - [math]::Round($pct / 100 * 30))
            Write-Host "`rDownloading $pct% ($rMB / $tMB MB) [$bar]" -NoNewline
            [Console]::Out.Flush()
        }
    }
}
Wait-Job $downloadJob | Out-Null
Receive-Job $downloadJob -ErrorAction SilentlyContinue | Out-Null
Remove-Job $downloadJob

if (-not (Test-Path $zipFile) -or (Get-Item $zipFile).Length -eq 0) {
    Write-Host ""
    Write-Host "Download failed!"
    exit 1
}

$finalMB = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)
Write-Host "`rDownloading 100% ($finalMB MB) [oooooooooooooooooooooooooooooo]"
Write-Host "Download complete!"
Write-Host ""

# ==========================================
# Step 2: Extract
# ==========================================
Write-Host "[2/3] Extracting..."
Write-Host ""

if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipFile)
$totalEntries = ($zip.Entries | Where-Object { $_.Length -gt 0 }).Count
$zip.Dispose()

$job = Start-Job -ScriptBlock {
    param($zipFile, $tempDir)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFile, $tempDir)
} -ArgumentList $zipFile, $tempDir

$lastPercent = -1
while ($job.State -eq 'Running') {
    Start-Sleep -Milliseconds 100
    if (Test-Path $tempDir) {
        $fc = (Get-ChildItem $tempDir -Recurse -File | Measure-Object).Count
        $pct = [math]::Min([math]::Round($fc / $totalEntries * 100, 0), 99)
        if ($pct -ne $lastPercent) {
            $lastPercent = $pct
            $bar = "o" * ([math]::Round($pct / 100 * 30)) + " " * (30 - [math]::Round($pct / 100 * 30))
            Write-Host "`rExtracting $pct% ($fc / $totalEntries files) [$bar]" -NoNewline
            [Console]::Out.Flush()
        }
    }
}
Wait-Job $job | Out-Null
Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
Remove-Job $job

Write-Host "`rExtracting 100% ($totalEntries / $totalEntries files) [oooooooooooooooooooooooooooooo]"
Write-Host "Extract complete!"
Write-Host ""

$updateFileList = Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
    $_.FullName.Substring($tempDir.Length + 1)
}
$updateFileCount = $updateFileList.Count
$updateZipSize = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)

# ==========================================
# Step 3: Update files (sync bin folder only)
# ==========================================
Write-Host "[3/3] Updating files..."
Write-Host "Target: $targetDir"
Write-Host ""

Copy-Item -Path "$tempDir\*" -Destination $targetDir -Recurse -Force

$targetBin = Join-Path $targetDir "bin"
$tempBin = Join-Path $tempDir "bin"
$deletedFiles = 0
$skippedFiles = 0
$deletedDirs = 0

if ((Test-Path $targetBin) -and (Test-Path $tempBin)) {
    Write-Host "Syncing bin folder..."
    Get-ChildItem -Path $targetBin -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($targetBin.Length + 1)
        $src = Join-Path $tempBin $rel
        if (-not (Test-Path $src)) {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                $deletedFiles++
                Write-Host "  Removed: bin\$rel"
            } catch {
                $skippedFiles++
                Write-Host "  Skipped (in use): bin\$rel"
            }
        }
    }
    Get-ChildItem -Path $targetBin -Recurse -Directory | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        $rel = $_.FullName.Substring($targetBin.Length + 1)
        $src = Join-Path $tempBin $rel
        if (-not (Test-Path $src)) {
            try {
                if ((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
                    Remove-Item $_.FullName -Recurse -Force -ErrorAction Stop
                    $deletedDirs++
                }
            } catch {}
        }
    }
}

Write-Host ""
Write-Host "Update complete!"
if ($deletedFiles -gt 0 -or $deletedDirs -gt 0) {
    Write-Host "Cleaned $deletedFiles old files, $deletedDirs old folders"
}
Write-Host ""

Remove-Item $zipFile -Force
Remove-Item $tempDir -Recurse -Force

Write-Host "========================================"
Write-Host "        Update Finished!"
Write-Host "========================================"

Start-Sleep -Milliseconds 500

# ==========================================
# Generate log file (use Chinese for output files)
# ==========================================
$today = Get-Date -Format "yyyy/MM/dd - HH:mm:ss"
$shortDate = Get-Date -Format "yyyy/MM/dd"

$newRecord = "[$today]`r`n"
$newRecord += "Size: $updateZipSize MB`r`n"
$newRecord += "Files: $updateFileCount`r`n"
$newRecord += "File list:`r`n"
foreach ($f in $updateFileList) {
    $newRecord += "  - $f`r`n"
}
$newRecord += "----------------------------------------`r`n"

$oldContent = ""
if (Test-Path $logFile) {
    $oldContent = Get-Content $logFile -Raw -Encoding Default
    $idx = $oldContent.IndexOf("========================================")
    if ($idx -gt 0) {
        $oldContent = $oldContent.Substring($idx)
        $idx2 = $oldContent.IndexOf("`r`n`r`n")
        if ($idx2 -gt 0) { $oldContent = $oldContent.Substring($idx2 + 2) }
    }
}

$header = "[最后更新时间]`r`n时间=$shortDate`r`n`r`n========================================`r`n        更新日志`r`n========================================`r`n`r`n"
[System.IO.File]::WriteAllText($logFile, $header + $newRecord + $oldContent, [System.Text.Encoding]::GetEncoding("GBK"))

# File count
$binDir = Join-Path $targetDir "bin"
$binCount = 0
if (Test-Path $binDir) {
    $binCount = (Get-ChildItem $binDir -Recurse -File | Measure-Object).Count
}
$statFile = Join-Path $scriptDir "文件统计.ini"
$stat = "[文件统计]`r`n更新库数=$binCount`r`n"
[System.IO.File]::WriteAllText($statFile, $stat, [System.Text.Encoding]::GetEncoding("GBK"))

Write-Host ""
Write-Host "Updated: $today"
Write-Host "Files: $updateFileCount"
Write-Host "bin files: $binCount"
Write-Host ""

# Create start menu shortcut if not exists
$startMenuPath = Join-Path $env:ProgramData "Microsoft\Windows\Start Menu\Programs\DaoKits.lnk"
if (-not (Test-Path $startMenuPath)) {
    if ($mainExe) {
        if (-not $mainExe.EndsWith('.exe')) { $mainExeExe = $mainExe + '.exe' } else { $mainExeExe = $mainExe }
        $exePath = Join-Path $targetDir $mainExeExe
        if (Test-Path $exePath) {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($startMenuPath)
            $sc.TargetPath = $exePath
            $sc.WorkingDirectory = $targetDir
            $sc.Description = "DaoKits"
            $sc.Save()
            Write-Host "Start Menu shortcut created"
        }
    }
}

# Create desktop shortcut on first run only
$desktopFlag = Join-Path $scriptDir ".desktop_shortcut"
$desktopPath = Join-Path $env:PUBLIC "Desktop\DaoKits.lnk"
if (-not (Test-Path $desktopFlag) -and -not (Test-Path $desktopPath)) {
    if ($mainExe) {
        if (-not $mainExe.EndsWith('.exe')) { $mainExeExe = $mainExe + '.exe' } else { $mainExeExe = $mainExe }
        $exePath = Join-Path $targetDir $mainExeExe
        if (Test-Path $exePath) {
            $ws = New-Object -ComObject WScript.Shell
            $sc = $ws.CreateShortcut($desktopPath)
            $sc.TargetPath = $exePath
            $sc.WorkingDirectory = $targetDir
            $sc.Description = "DaoKits"
            $sc.Save()
            # Write flag so we don't create again
            [System.IO.File]::WriteAllText($desktopFlag, (Get-Date).ToString("yyyy/MM/dd HH:mm:ss"), [System.Text.Encoding]::ASCII)
            Write-Host "Desktop shortcut created"
        }
    }
}

# Launch main exe
if ($mainExe) {
    if (-not $mainExe.EndsWith('.exe')) { $mainExe += '.exe' }
    $exePath = Join-Path $targetDir $mainExe
    if (Test-Path $exePath) {
        Write-Host "Starting $mainExe..."
        Start-Process -FilePath $exePath -WorkingDirectory $targetDir
        Start-Sleep -Milliseconds 500
    }
}

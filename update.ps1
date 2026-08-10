# DaoKits Auto Update Script (Single File)
$OutputEncoding = [System.Text.Encoding]::UTF8

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ==========================================
# Config (defaults, can be overridden by update.ini)
# ==========================================
$downloadUrls = @(
    "http://nas.daomak.com:9980/SF/DP/Daokits/Daokits.zip",
    "https://ghproxy.com/https://github.com/Daomak/tools/releases/download/GA/Daokits.zip",
    "https://github.com/Daomak/tools/releases/download/GA/Daokits.zip"
)
$targetDir = "..\"
$mainExe = "daokits"
# ==========================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$iniPath = Join-Path $scriptDir "update.ini"

# Load external config if exists
if (Test-Path $iniPath) {
    $iniUrls = @()
    $section = ""
    Get-Content $iniPath -Encoding Default | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].ToLower(); return }
        if ($line -match '^(.+?)=(.+)$') {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            if ($section -eq "download" -and $val -match '^https?://') {
                $iniUrls += $val
            }
            if ($section -eq "settings") {
                if ($key -eq "target") { $script:targetDir = $val }
                if ($key -eq "exe") { $script:mainExe = $val }
            }
        }
    }
    if ($iniUrls.Count -gt 0) { $script:downloadUrls = $iniUrls | Select-Object -Unique }
}

$zipName = "Daokits.zip"

if (-not [System.IO.Path]::IsPathRooted($targetDir)) {
    $targetDir = Join-Path $scriptDir $targetDir
}
$targetDir = [System.IO.Path]::GetFullPath($targetDir)

$zipFile = Join-Path $scriptDir $zipName
$tempDir = Join-Path $scriptDir "temp_update"
$logFile = Join-Path $scriptDir "更新日志.ini"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "        DaoKits Updater" -ForegroundColor White
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ==========================================
# Step 0: Check .NET
# ==========================================
Write-Host "[0/3] " -ForegroundColor Yellow -NoNewline
Write-Host "Checking environment..." -ForegroundColor Gray
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
    Write-Host ".NET Framework 4.5+ not found, installing 4.8..." -ForegroundColor Yellow
    $installerUrl = "https://go.microsoft.com/fwlink/?LinkId=2085155"
    $installerPath = Join-Path $scriptDir "dotnet48_setup.exe"
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($installerUrl, $installerPath)
        $p = Start-Process -FilePath $installerPath -ArgumentList "/quiet /norestart" -Wait -PassThru -Verb RunAs
        Remove-Item $installerPath -Force
    } catch {
        Write-Host "Failed to install .NET 4.8" -ForegroundColor Red
        Start-Sleep 5
        exit 1
    }
}
Write-Host "Environment " -ForegroundColor Green -NoNewline
Write-Host "OK" -ForegroundColor White
Write-Host ""

# ==========================================
# Step 1: Download (speed test + fallback)
# ==========================================
Write-Host "[1/3] " -ForegroundColor Yellow -NoNewline
Write-Host "Downloading update..." -ForegroundColor Gray

# Build name map from ini
$urlNames = @{}
if (Test-Path $iniPath) {
    $section = ""
    Get-Content $iniPath -Encoding Default | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\[(.+)\]$') { $section = $Matches[1].ToLower(); return }
        if ($section -eq "download" -and $line -match '^(.+?)=(https?://.+)$') {
            $urlNames[$Matches[2].Trim()] = $Matches[1].Trim()
        }
    }
}

Write-Host "Testing " -ForegroundColor Gray -NoNewline
Write-Host "$($downloadUrls.Count)" -ForegroundColor White -NoNewline
Write-Host " source(s)..." -ForegroundColor Gray

$results = @()
$speedJobs = @()
$idx = 0
foreach ($url in $downloadUrls) {
    $idx++
    $name = if ($urlNames.ContainsKey($url)) { $urlNames[$url] } else { "Source $idx" }
    $speedJobs += Start-Job -ScriptBlock {
        param($u, $n)
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $req = [System.Net.HttpWebRequest]::Create($u)
            $req.Method = "HEAD"
            $req.Timeout = 5000
            $resp = $req.GetResponse()
            $sw.Stop()
            $size = $resp.ContentLength
            $resp.Close()
            return @{ Name = $n; Url = $u; Ms = [int64]$sw.ElapsedMilliseconds; Size = $size; OK = $true }
        } catch {
            $sw.Stop()
            return @{ Name = $n; Url = $u; Ms = [int64]99999; Size = 0; OK = $false }
        }
    } -ArgumentList $url, $name
}
$null = Wait-Job $speedJobs
foreach ($j in $speedJobs) {
    $r = Receive-Job $j
    $results += $r
    Write-Host "  " -NoNewline
    if ($r.OK) {
        Write-Host "$($r.Name)" -ForegroundColor White -NoNewline
        Write-Host ": " -NoNewline
        Write-Host "$($r.Ms)ms" -ForegroundColor Green
    } else {
        Write-Host "$($r.Name)" -ForegroundColor DarkGray -NoNewline
        Write-Host ": " -NoNewline
        Write-Host "unreachable" -ForegroundColor Red
    }
}
Remove-Job $speedJobs

# Sort by speed, fastest first, skip unreachable
$sortedUrls = $results | Where-Object { $_.OK } | Sort-Object { [int64]$_.Ms } | ForEach-Object { $_.Url }
if ($sortedUrls.Count -eq 0) { $sortedUrls = $downloadUrls }
Write-Host ""

$downloadOk = $false
foreach ($downloadUrl in $sortedUrls) {
    $totalSize = 0
    $match = $results | Where-Object { $_.Url -eq $downloadUrl } | Select-Object -First 1
    if ($match) {
        $totalSize = $match.Size
    }
    $srcName = if ($urlNames.ContainsKey($downloadUrl)) { $urlNames[$downloadUrl] } else { "source" }
    Write-Host "Downloading from " -ForegroundColor Gray -NoNewline
    Write-Host $srcName -ForegroundColor White -NoNewline
    Write-Host "..." -ForegroundColor Gray

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
                Write-Host "`rDownloading " -ForegroundColor Gray -NoNewline
                Write-Host "$pct%" -ForegroundColor Yellow -NoNewline
                Write-Host " (" -NoNewline
                Write-Host "$rMB" -ForegroundColor White -NoNewline
                Write-Host " / " -NoNewline
                Write-Host "$tMB MB" -ForegroundColor White -NoNewline
                Write-Host ") [" -NoNewline
                Write-Host $bar -ForegroundColor Cyan -NoNewline
                Write-Host "]" -NoNewline
                [Console]::Out.Flush()
            }
        }
    }
    Wait-Job $downloadJob | Out-Null
    Receive-Job $downloadJob -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $downloadJob

    if (Test-Path $zipFile) {
        $fileSize = (Get-Item $zipFile).Length
        if ($fileSize -gt 0) {
            $downloadOk = $true
            $finalMB = [math]::Round($fileSize / 1MB, 2)
            Write-Host "`rDownloading " -ForegroundColor Gray -NoNewline
            Write-Host "100%" -ForegroundColor Green -NoNewline
            Write-Host " (" -NoNewline
            Write-Host "$finalMB MB" -ForegroundColor White -NoNewline
            Write-Host ") [" -NoNewline
            Write-Host "oooooooooooooooooooooooooooooo" -ForegroundColor Green -NoNewline
            Write-Host "]"
            Write-Host "Download " -ForegroundColor Green -NoNewline
            Write-Host "complete!" -ForegroundColor White
            Write-Host ""
            break
        }
    }

    Write-Host "`r$srcName " -ForegroundColor Red -NoNewline
    Write-Host "failed, trying next..." -ForegroundColor Yellow
    Write-Host ""
    Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
}

if (-not $downloadOk) {
    Write-Host "All download sources failed!" -ForegroundColor Red
    exit 1
}

# ==========================================
# Step 2: Extract
# ==========================================
Write-Host "[2/3] " -ForegroundColor Yellow -NoNewline
Write-Host "Extracting..." -ForegroundColor Gray
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
            Write-Host "`rExtracting " -ForegroundColor Gray -NoNewline
            Write-Host "$pct%" -ForegroundColor Yellow -NoNewline
            Write-Host " (" -NoNewline
            Write-Host "$fc" -ForegroundColor White -NoNewline
            Write-Host " / " -NoNewline
            Write-Host "$totalEntries files" -ForegroundColor White -NoNewline
            Write-Host ") [" -NoNewline
            Write-Host $bar -ForegroundColor Cyan -NoNewline
            Write-Host "]" -NoNewline
            [Console]::Out.Flush()
        }
    }
}
Wait-Job $job | Out-Null
Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
Remove-Job $job

Write-Host "`rExtracting " -ForegroundColor Gray -NoNewline
Write-Host "100%" -ForegroundColor Green -NoNewline
Write-Host " (" -NoNewline
Write-Host "$totalEntries" -ForegroundColor White -NoNewline
Write-Host " / " -NoNewline
Write-Host "$totalEntries files" -ForegroundColor White -NoNewline
Write-Host ") [" -NoNewline
Write-Host "oooooooooooooooooooooooooooooo" -ForegroundColor Green -NoNewline
Write-Host "]"
Write-Host "Extract " -ForegroundColor Green -NoNewline
Write-Host "complete!" -ForegroundColor White
Write-Host ""

$updateFileList = Get-ChildItem -Path $tempDir -Recurse -File | ForEach-Object {
    $_.FullName.Substring($tempDir.Length + 1)
}
$updateFileCount = $updateFileList.Count
$updateZipSize = [math]::Round((Get-Item $zipFile).Length / 1MB, 2)

# ==========================================
# Step 3: Update files (sync bin folder only)
# ==========================================
Write-Host "[3/3] " -ForegroundColor Yellow -NoNewline
Write-Host "Updating files..." -ForegroundColor Gray
Write-Host "Target: " -ForegroundColor Gray -NoNewline
Write-Host $targetDir -ForegroundColor White
Write-Host ""

Copy-Item -Path "$tempDir\*" -Destination $targetDir -Recurse -Force

$targetBin = Join-Path $targetDir "bin"
$tempBin = Join-Path $tempDir "bin"
$deletedFiles = 0
$skippedFiles = 0
$deletedDirs = 0

if ((Test-Path $targetBin) -and (Test-Path $tempBin)) {
    Write-Host "Syncing bin folder..." -ForegroundColor Gray
    Get-ChildItem -Path $targetBin -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($targetBin.Length + 1)
        $src = Join-Path $tempBin $rel
        if (-not (Test-Path $src)) {
            try {
                Remove-Item $_.FullName -Force -ErrorAction Stop
                $deletedFiles++
                Write-Host "  Removed: " -ForegroundColor DarkYellow -NoNewline
                Write-Host "bin\$rel" -ForegroundColor DarkGray
            } catch {
                $skippedFiles++
                Write-Host "  Skipped (in use): " -ForegroundColor DarkYellow -NoNewline
                Write-Host "bin\$rel" -ForegroundColor DarkGray
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
Write-Host "Update " -ForegroundColor Green -NoNewline
Write-Host "complete!" -ForegroundColor White
if ($deletedFiles -gt 0 -or $deletedDirs -gt 0) {
    Write-Host "Cleaned " -ForegroundColor Gray -NoNewline
    Write-Host "$deletedFiles" -ForegroundColor White -NoNewline
    Write-Host " old files, " -NoNewline
    Write-Host "$deletedDirs" -ForegroundColor White -NoNewline
    Write-Host " old folders" -ForegroundColor Gray
}
Write-Host ""

Remove-Item $zipFile -Force
Remove-Item $tempDir -Recurse -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "        Update Finished!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan

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
Write-Host "Updated: " -ForegroundColor Gray -NoNewline
Write-Host $today -ForegroundColor White
Write-Host "Files: " -ForegroundColor Gray -NoNewline
Write-Host $updateFileCount -ForegroundColor White
Write-Host "bin files: " -ForegroundColor Gray -NoNewline
Write-Host $binCount -ForegroundColor White
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
            Write-Host "Start Menu shortcut " -ForegroundColor Green -NoNewline
            Write-Host "created" -ForegroundColor White
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
            [System.IO.File]::WriteAllText($desktopFlag, (Get-Date).ToString("yyyy/MM/dd HH:mm:ss"), [System.Text.Encoding]::ASCII)
            Write-Host "Desktop shortcut " -ForegroundColor Green -NoNewline
            Write-Host "created" -ForegroundColor White
        }
    }
}

# Launch main exe
if ($mainExe) {
    if (-not $mainExe.EndsWith('.exe')) { $mainExe += '.exe' }
    $exePath = Join-Path $targetDir $mainExe
    if (Test-Path $exePath) {
        Write-Host "Starting " -ForegroundColor Gray -NoNewline
        Write-Host $mainExe -ForegroundColor White -NoNewline
        Write-Host "..." -ForegroundColor Gray
        Start-Process -FilePath $exePath -WorkingDirectory $targetDir
        Start-Sleep -Milliseconds 500
    }
}

# 极简单文件统计，GBK编码输出
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

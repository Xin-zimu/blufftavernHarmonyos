# UI 操作辅助脚本：dumpLayout -> 按文本定位 -> 点击中心
# 用法: .\click-text.ps1 -Text "加入房间" [-DumpName "click-dump.json"]
# 环境变量（可选）:
#   HDC_PATH    - hdc.exe 路径，默认取 DevEco Studio 工具链位置
#   HDC_TARGET  - hdc 目标序列号/地址，默认 127.0.0.1:5555（模拟器）
#   DUMP_DIR    - dump 文件本地保存目录，默认 .\.verify-dumps
param([string]$Text, [string]$DumpName = "click-dump.json")

$hdc = if ($env:HDC_PATH) { $env:HDC_PATH } else { "D:\HUAWEI-DEV\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" }
$target = if ($env:HDC_TARGET) { $env:HDC_TARGET } else { "127.0.0.1:5555" }
$dumpDir = if ($env:DUMP_DIR) { $env:DUMP_DIR } else { "$PWD\.verify-dumps" }
if (-not (Test-Path $dumpDir)) { New-Item -ItemType Directory -Path $dumpDir | Out-Null }
$local = Join-Path $dumpDir $DumpName

& $hdc -t $target shell "uitest dumpLayout -p /data/local/tmp/$DumpName" | Out-Null
& $hdc -t $target file recv "/data/local/tmp/$DumpName" $local | Out-Null
$json = (Get-Content $local -Raw) | ConvertFrom-Json
$found = $null
function Walk($n) {
  if ($null -ne $n.attributes) {
    $a = $n.attributes
    if ($null -ne $a.text -and $a.text -eq $Text -and $null -ne $a.bounds) { $script:found = $a }
  }
  if ($null -ne $n.children) { foreach ($c in $n.children) { Walk $c } }
}
Walk $json
if ($null -eq $found) { Write-Output "NOT_FOUND: $Text"; exit 1 }
if ($found.bounds -cmatch '^\[(\d+),(\d+)\]\[(\d+),(\d+)\]$') {
  $cx = ([int]$Matches[1] + [int]$Matches[3]) / 2
  $cy = ([int]$Matches[2] + [int]$Matches[4]) / 2
  Write-Output "CLICK $Text at $cx,$cy"
  & $hdc -t $target shell "uitest uiInput click $cx $cy"
} else { Write-Output "BAD_BOUNDS: $($found.bounds)"; exit 1 }

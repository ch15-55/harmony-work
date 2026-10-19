<#
.SYNOPSIS
  在 ASCII 路径下构建轻账本，规避 Hvigor 对中文工程路径的限制（00306003）。

.DESCRIPTION
  Hvigor 只接受由字母、数字、连字符、下划线、点、英文括号、空格和 @ 组成的工程路径。
  本仓库位于含中文的目录时，直接在原地构建会被拒绝；脚本先把工程同步到英文临时目录，
  再调用 DevEco 自带的 hvigorw 构建，最后把 HAP 复制到 local-data/fixes（已被 Git 忽略）。

  不改动原工程，不修改签名配置，不上传产物。

.PARAMETER ProjectDir
  工程目录，默认仓库根下的 harmony。

.PARAMETER WorkDir
  英文临时构建目录，默认 %TEMP%\lifeledger-build。为安全起见，删除前要求路径包含 lifeledger-build。

.PARAMETER DevEcoHome
  DevEco Studio 安装目录，默认 E:\DevEco Studio。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_ascii.ps1
#>
[CmdletBinding()]
param(
  [string]$ProjectDir = '',
  [string]$WorkDir = '',
  [string]$DevEcoHome = 'E:\DevEco Studio'
)

$ErrorActionPreference = 'Stop'

# 让中文日志在 UTF-8 控制台与管道中可读（Windows PowerShell 5.1 默认按本地代码页输出）
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($ProjectDir -eq '') { $ProjectDir = Join-Path $repoRoot 'harmony' }
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP 'lifeledger-build' }

if (-not (Test-Path (Join-Path $ProjectDir 'build-profile.json5'))) {
  throw "未找到 $ProjectDir\build-profile.json5；请先恢复本机签名配置（模板见 build-profile.example.json5）"
}
if ($WorkDir -notlike '*lifeledger-build*') {
  throw "为避免误删，WorkDir 路径必须包含 lifeledger-build：$WorkDir"
}

$sdk = Join-Path $DevEcoHome 'sdk'
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path $hvigor)) { throw "未找到 hvigorw：$hvigor" }

if (Test-Path $WorkDir) {
  Remove-Item $WorkDir -Recurse -Force -Confirm:$false
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# /XD 排除构建缓存与依赖，其余源码原样复制
robocopy $ProjectDir $WorkDir /E /XD build .hvigor .idea oh_modules .preview /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
  throw "源码同步失败，robocopy 退出码 $LASTEXITCODE"
}

$env:DEVECO_SDK_HOME = $sdk
Push-Location $WorkDir
try {
  & $hvigor --mode module -p product=default assembleHap --no-daemon
  if ($LASTEXITCODE -ne 0) {
    throw "构建失败，hvigor 退出码 $LASTEXITCODE"
  }
} finally {
  Pop-Location
}

$outDir = Join-Path $WorkDir 'entry\build\default\outputs\default'
$targetDir = Join-Path $repoRoot 'local-data\fixes'
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

$hapFiles = Get-ChildItem -Path $outDir -Filter *.hap -ErrorAction SilentlyContinue
if ($hapFiles.Count -eq 0) {
  throw "构建完成但未找到 HAP：$outDir"
}
foreach ($hap in $hapFiles) {
  $dest = Join-Path $targetDir $hap.Name
  Copy-Item $hap.FullName $dest -Force
  Write-Output ("产物：" + $dest)
}

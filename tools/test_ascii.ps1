<#
.SYNOPSIS
  Build and compile LifeLedger unit tests under an ASCII path to bypass Hvigor's
  Chinese-path restriction (00306003). Verifies test sources compile; a device is
  required to actually run the tests.
#>
[CmdletBinding()]
param(
  [string]$ProjectDir = '',
  [string]$WorkDir = '',
  [string]$DevEcoHome = 'E:\DevEco Studio'
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($ProjectDir -eq '') { $ProjectDir = Join-Path $repoRoot 'harmony' }
if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP 'lifeledger-test' }

if (-not (Test-Path (Join-Path $ProjectDir 'build-profile.json5'))) {
  throw "Missing build-profile.json5; restore local signing config first (see build-profile.example.json5)"
}
if ($WorkDir -notlike '*lifeledger-test*') {
  throw "For safety WorkDir must contain lifeledger-test"
}

$sdk = Join-Path $DevEcoHome 'sdk'
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path $hvigor)) { throw "hvigorw not found: $hvigor" }

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -Confirm:$false }
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

robocopy $ProjectDir $WorkDir /E /XD build .hvigor .idea oh_modules .preview /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Source sync failed, robocopy exit $LASTEXITCODE" }

$env:DEVECO_SDK_HOME = $sdk
Push-Location $WorkDir
try {
  $ohpm = Join-Path $DevEcoHome 'tools\ohpm\bin\ohpm.bat'
  if (Test-Path $ohpm) {
    Write-Output "Running ohpm install to resolve test deps..."
    & $ohpm install 2>&1 | Out-String -Width 200 | ForEach-Object { Write-Output $_ }
  }
  & $hvigor --mode module -p product=default test --no-daemon
  Write-Output ("hvigor test exit code: " + $LASTEXITCODE)
} finally {
  Pop-Location
}

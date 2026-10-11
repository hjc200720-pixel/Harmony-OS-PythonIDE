<#
  把 AppGallery Connect 下载的发布签名材料写进 build-profile.json5（先自动备份）。
  用法：
    .\scripts\prepare-release-signing.ps1 -StoreFile D:\keys\release.p12 -KeyAlias releaseKey -CertPath D:\keys\release.cer -Profile D:\keys\release.p7b -StorePassword *** -KeyPassword ***
  不给密码时只打印模板，不改文件。
#>
param(
  [Parameter(Mandatory=$true)][string]$StoreFile,
  [Parameter(Mandatory=$true)][string]$KeyAlias,
  [Parameter(Mandatory=$true)][string]$CertPath,
  [Parameter(Mandatory=$true)][string]$Profile,
  [string]$StorePassword = '',
  [string]$KeyPassword = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bp = Join-Path $root 'build-profile.json5'
if (-not (Test-Path $bp)) { throw ('找不到 ' + $bp) }
foreach ($f in @($StoreFile, $CertPath, $Profile)) {
  if (-not (Test-Path $f)) { throw ('签名材料不存在：' + $f + '（请先在 AGC 申请并下载）') }
}
Write-Host '请先在 AGC 确认两件事：' -ForegroundColor Cyan
Write-Host '  1) 已在「证书、App ID 和 Profile」下载发布证书 .cer/.p7b 与密钥 .p12'
Write-Host '  2) 已把发布证书的 SHA-256 指纹登记到 Account Kit（否则华为账号登录会报 1001502002/1001502003）'
$lines = @(
  '      {',
  '        "name": "release",',
  '        "type": "HarmonyOS",',
  '        "material": {',
  ('          "storeFile": "' + $StoreFile + '",'),
  ('          "keyAlias": "' + $KeyAlias + '",'),
  ('          "storePassword": "' + $(if ($StorePassword) { $StorePassword } else { '<storePassword>' }) + '",'),
  ('          "keyPassword": "' + $(if ($KeyPassword) { $KeyPassword } else { '<keyPassword>' }) + '",'),
  ('          "certpath": "' + $CertPath + '",'),
  ('          "profile": "' + $Profile + '",'),
  '          "signAlg": "SHA256withECDSA"',
  '        }',
  '      },'
)
Write-Host ''
Write-Host '要写入的内容：' -ForegroundColor Cyan
$lines | ForEach-Object { Write-Host $_ }
if ($StorePassword -and $KeyPassword) {
  Copy-Item $bp ($bp + '.bak') -Force
  Write-Host ('已备份原文件到 ' + $bp + '.bak')
  $txt = Get-Content $bp -Raw
  $anchor = '  "signingConfigs": ['
  if ($txt.IndexOf($anchor) -lt 0) { throw 'build-profile.json5 结构变化，请手动加入 signingConfigs' }
  $nl = [Environment]::NewLine
  $txt = $txt.Replace($anchor, $anchor + $nl + ($lines -join $nl))
  Set-Content -Path $bp -Value $txt -Encoding UTF8
  Write-Host '已把 release 签名写入 build-profile.json5（原文件已备份）' -ForegroundColor Green
  Write-Host '接着把 products 里的 signingConfig 改成 "release" 即可出发布包。'
} else {
  Write-Host '未提供密码 → 只打印模板。加上 -StorePassword/-KeyPassword 会自动写入。' -ForegroundColor Yellow
}
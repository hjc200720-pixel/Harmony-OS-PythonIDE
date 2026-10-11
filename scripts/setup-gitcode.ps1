# One-shot GitCode setup: create repo (API) + store credential + add 2nd push remote + push + verify.
# Usage:  powershell -ExecutionPolicy Bypass -File scripts\setup-gitcode.ps1
#         (it will ask for your GitCode access token once; token is stored in Windows Credential Manager,
#          NOT in .git/config)
param(
  [string]$User = 'hjc200720',
  [string]$Repo = 'Harmony-OS-PythonIDE',
  [string]$Token = ''      # 也可直接传令牌，避免交互输入
)
$ErrorActionPreference = 'Continue'
$repoDir = Split-Path -Parent $PSScriptRoot
Set-Location $repoDir

$token = $Token
if ([string]::IsNullOrWhiteSpace($token)) {
  $token = Read-Host -Prompt 'Paste GitCode access token (paste and press Enter)'
}
if ([string]::IsNullOrWhiteSpace($token)) { Write-Host 'no token, abort'; exit 1 }

Write-Host '--- 1) try to create the repo via API (ignored if it already exists) ---'
$body = @{ name = $Repo; private = $false; auto_init = $false } | ConvertTo-Json
$headers = @{ 'Authorization' = ('Bearer ' + $token); 'Content-Type' = 'application/json' }
try {
  $r = Invoke-WebRequest -Uri 'https://gitcode.com/api/v5/user/repos' -Method Post -Headers $headers -Body $body -TimeoutSec 30 -UseBasicParsing
  Write-Host ('created: HTTP ' + $r.StatusCode)
} catch {
  Write-Host ('create skipped/failed (may already exist): ' + $_.Exception.Message)
}

Write-Host '--- 2) store credential for gitcode.com ---'
$cred = "protocol=https`nhost=gitcode.com`nusername=$User`npassword=$token`n"
$cred | git credential approve
Write-Host 'credential stored'

Write-Host '--- 3) add second push remote (fetch stays GitHub) ---'
$url = 'https://gitcode.com/' + $User + '/' + $Repo + '.git'
$existing = (git remote get-url --all --push origin) -join ' '
if ($existing -notmatch 'gitcode') { git remote set-url --add --push origin $url; Write-Host ('added: ' + $url) }
else { Write-Host 'gitcode push url already present' }
git remote -v

Write-Host '--- 4) push to BOTH (GitHub + GitCode) ---'
git push origin main 2>&1 | Select-Object -Last 6

Write-Host '--- 5) verify both remotes ---'
git ls-remote --heads origin 2>&1 | Select-Object -First 4
Write-Host 'done'
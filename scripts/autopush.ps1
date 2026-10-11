# Auto commit + push to GitHub (Harmony-OS-PythonIDE).
# Manual:  powershell -ExecutionPolicy Bypass -File scripts\autopush.ps1
# Timed:   see the schtasks lines at the bottom.
param(
  [string]$Message = ''
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "not a git repo: $repo"; exit 1 }

$changes = (git status --porcelain | Measure-Object).Count
if ($changes -gt 0) {
  git add -A
  if ([string]::IsNullOrWhiteSpace($Message)) {
    $Message = "auto commit $(Get-Date -Format 'yyyy-MM-dd HH:mm') ($changes files)"
  }
  git commit -q -m $Message
  Write-Host "committed $changes file(s)"
} else {
  # 无改动：仍要推送（可能有别处产生的未推送提交）
  Write-Host 'no local changes; ensure remote is up to date'
}

# 非交互：绝不弹凭据框（后台任务里弹窗会打断用户）
$env:GIT_TERMINAL_PROMPT = '0'
$env:GCM_INTERACTIVE = 'never'
$env:GCM_PROVIDER = ''

# 1) 先推 GitHub（主仓库，必须成功）
git push -q origin main 2>&1 | Out-Null
$gh = $LASTEXITCODE

# 2) 再单独推 GitCode（容错：凭据失效/网络问题不影响 GitHub，也不弹窗）
$gitcode = (git remote get-url --all --push origin | Where-Object { $_ -match 'gitcode' } | Select-Object -First 1)
if ($gitcode) {
  git push -q $gitcode main 2>&1 | Out-Null
  $gc = $LASTEXITCODE
} else {
  $gc = -1
}

if ($gh -eq 0) {
  Write-Host "pushed GitHub: $Message"
  if ($gc -ne 0) { Write-Host 'GitCode push failed (token/credential) - GitHub is fine; re-run scripts\setup-gitcode.ps1 with a fresh token' }
  git log --oneline -1
} else {
  Write-Host 'GitHub push failed (network/credential); commit kept locally'
  exit 2
}

# Every 10 minutes automatically (run once in an ADMIN PowerShell):
# schtasks /create /tn "HarmonyPyIDE autopush" /tr "powershell -ExecutionPolicy Bypass -File '$repo\scripts\autopush.ps1'" /sc minute /mo 10
# Remove it:  schtasks /delete /tn "HarmonyPyIDE autopush" /f
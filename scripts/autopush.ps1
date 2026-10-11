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
if ($changes -eq 0) { Write-Host "no changes, skip ($(Get-Date -Format 'HH:mm:ss'))"; exit 0 }

git add -A
if ([string]::IsNullOrWhiteSpace($Message)) {
  $Message = "auto commit $(Get-Date -Format 'yyyy-MM-dd HH:mm') ($changes files)"
}
git commit -q -m $Message

git push -q origin main 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Host "pushed: $Message"
  git log --oneline -1
} else {
  Write-Host 'push failed (network/credential); commit kept locally'
  exit 2
}

# Every 10 minutes automatically (run once in an ADMIN PowerShell):
# schtasks /create /tn "HarmonyPyIDE autopush" /tr "powershell -ExecutionPolicy Bypass -File '$repo\scripts\autopush.ps1'" /sc minute /mo 10
# Remove it:  schtasks /delete /tn "HarmonyPyIDE autopush" /f
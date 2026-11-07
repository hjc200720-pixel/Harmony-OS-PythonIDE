# start-emulator.ps1
# Idempotent launcher / waiter for the DevEco Studio emulator (default HVD: "MateBook Pro", 2in1).
#
# IMPORTANT: keep this file PURE ASCII. Windows PowerShell reads a BOM-less .ps1
# as the system ANSI code page (GBK on zh-CN) and non-ASCII bytes break parsing.
# Chinese documentation lives in scripts/device/README.md.
#
# Why WMI (Win32_Process.Create) instead of Start-Process:
#   A process started with Start-Process is a child of the calling shell and gets
#   torn down when that shell / job exits (observed exit code -1073741510 =
#   STATUS_CONTROL_C_EXIT right after the emulator UI came up). WMI spawns the
#   emulator from WmiPrvSE so it survives the calling session.
#
# Exit codes: 0 = emulator online, 1 = timed out / died, 2 = bad configuration,
#             3 = spawn failed.

[CmdletBinding()]
param(
    [string]$Hvd = 'MateBook Pro',
    [string]$EmulatorExe = 'D:\DevEco Studio\tools\emulator\Emulator.exe',
    [string]$DeployedPath = 'D:/DevEcoStudioData/Emulator/deployed',
    [string]$ImageRoot = 'D:/DevEcoStudioData',
    [string]$Hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [int]$TimeoutSec = 420,
    [string]$TracePipe = '',
    [switch]$ForceRestart
)

$ErrorActionPreference = 'Continue'
$script:Hdc = $Hdc

function Write-Step([string]$m) { Write-Host ('[start-emulator] ' + $m) }

function Write-LogTail([string]$path, [int]$count) {
    if (Test-Path $path) {
        Write-Host ('[start-emulator] --- tail ' + $count + ' lines: ' + $path + ' ---')
        Get-Content $path -Tail $count -ErrorAction SilentlyContinue | ForEach-Object { Write-Host ('  ' + $_) }
    } else {
        Write-Host ('[start-emulator] log not found: ' + $path)
    }
}

function Invoke-HdcQuiet([string[]]$ArgList) {
    $out = & $script:Hdc @ArgList 2>&1
    return (($out | ForEach-Object { "$_" }) -join [Environment]::NewLine)
}

function Get-TargetRows {
    $raw = Invoke-HdcQuiet @('list', 'targets', '-v')
    $rows = @()
    foreach ($ln in ($raw -split '\r?\n')) {
        $t = $ln.Trim()
        if ($t -eq '') { continue }
        $parts = $t -split '\s+'
        if ($parts.Count -ge 3) {
            $rows += [pscustomobject]@{ Serial = $parts[0]; Transport = $parts[1]; State = $parts[2]; Raw = $t }
        }
    }
    return $rows
}

function Get-EmulatorSerial {
    # An emulator reaches the host hdc server over TCP (127.0.0.1:5555 by default).
    $rows = @(Get-TargetRows)
    $cand = @($rows | Where-Object { ($_.Transport -eq 'TCP') -and ($_.State -eq 'Connected') })
    foreach ($r in $cand) {
        $probe = Invoke-HdcQuiet @('-t', $r.Serial, 'shell', 'echo', 'PING_OK')
        if ($probe -match 'PING_OK') {
            $model = (Invoke-HdcQuiet @('-t', $r.Serial, 'shell', 'param', 'get', 'const.product.model')).Trim()
            return [pscustomobject]@{ Serial = $r.Serial; Model = $model }
        }
    }
    return $null
}

function Get-RunningEmulatorProcesses {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'Emulator.exe'" -ErrorAction SilentlyContinue)
    return @($procs | Where-Object {
        $_.CommandLine -and ($_.CommandLine -match '-hvd') -and ($_.CommandLine -match [regex]::Escape($Hvd))
    })
}

# ---------- preflight ----------
if (-not (Test-Path $Hdc)) { Write-Step ('FAIL: hdc not found: ' + $Hdc); exit 2 }
if (-not (Test-Path $EmulatorExe)) { Write-Step ('FAIL: Emulator.exe not found: ' + $EmulatorExe); exit 2 }
Write-Step ('hdc        = ' + $Hdc)
Write-Step ('emulator   = ' + $EmulatorExe)
Write-Step ('hvd        = ' + $Hvd)
Write-Step ('imageRoot  = ' + $ImageRoot)
Write-Step ('deployed   = ' + $DeployedPath)

$hvdDir = Join-Path $DeployedPath $Hvd
$logPath = Join-Path $hvdDir 'Log\Emulator.log'

# ---------- idempotency: already online? ----------
$online = Get-EmulatorSerial
if ($online -and (-not $ForceRestart)) {
    Write-Step ('OK: emulator already online: ' + $online.Serial + ' model=' + $online.Model)
    Write-Output ('SERIAL=' + $online.Serial)
    Write-Output ('MODEL=' + $online.Model)
    exit 0
}

# ---------- optional force restart ----------
$running = @(Get-RunningEmulatorProcesses)
if ($running.Count -gt 0) {
    if ($ForceRestart) {
        foreach ($p in $running) {
            Write-Step ('stopping emulator pid=' + $p.ProcessId)
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 3
    } else {
        $pids = (($running | ForEach-Object { $_.ProcessId }) -join ',')
        Write-Step ('emulator process already running (pid=' + $pids + '); waiting for hdc target')
    }
} else {
    # ---------- spawn detached via WMI ----------
    if ([string]::IsNullOrEmpty($TracePipe)) {
        $rand = Get-Random -Minimum 90000 -Maximum 99800
        $TracePipe = 'trace_' + $rand + '_commandPipe'
    }
    $argLine = '-hvd "' + $Hvd + '" -path "' + $DeployedPath + '" -t ' + $TracePipe + ' -imageRoot "' + $ImageRoot + '"'
    $cmdLine = '"' + $EmulatorExe + '" ' + $argLine
    Write-Step ('spawn: ' + $cmdLine)
    $create = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdLine }
    if ($create.ReturnValue -ne 0) {
        Write-Step ('FAIL: WMI Win32_Process.Create returned ' + $create.ReturnValue)
        exit 3
    }
    $spawnPid = [int]$create.ProcessId
    Write-Step ('spawned pid=' + $spawnPid + ' (detached from this shell)')
}

# ---------- wait for the hdc target ----------
$start = Get-Date
$deadline = $start.AddSeconds($TimeoutSec)
$serial = $null
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    $serial = Get-EmulatorSerial
    if ($serial) {
        $elapsed = [int]((Get-Date) - $start).TotalSeconds
        Write-Step ('OK: emulator online after ' + $elapsed + 's: ' + $serial.Serial + ' model=' + $serial.Model)
        Write-Output ('SERIAL=' + $serial.Serial)
        Write-Output ('MODEL=' + $serial.Model)
        Write-Output ('ELAPSED_SEC=' + $elapsed)
        exit 0
    }
    $procs = @(Get-RunningEmulatorProcesses)
    if ($procs.Count -eq 0) {
        Write-Step 'FAIL: no Emulator.exe process left while waiting for the hdc target'
        break
    }
    $elapsed = [int]((Get-Date) - $start).TotalSeconds
    $pids = (($procs | ForEach-Object { $_.ProcessId }) -join ',')
    Write-Step ('waiting for hdc target... ' + $elapsed + 's / ' + $TimeoutSec + 's (pid=' + $pids + ')')
}

# ---------- failure report ----------
Write-Step 'FAILED: emulator did not become reachable over hdc.'
Write-Step '--- hdc list targets -v ---'
$targetsDump = Invoke-HdcQuiet @('list', 'targets', '-v')
foreach ($ln in ($targetsDump -split '\r?\n')) { Write-Step ('  ' + $ln) }
Write-Step '--- Emulator.exe processes ---'
foreach ($p in @(Get-RunningEmulatorProcesses)) { Write-Step ('  pid=' + $p.ProcessId + ' cmd=' + $p.CommandLine) }
Write-LogTail $logPath 40
exit 1

# device.ps1
# Thin hdc wrapper used to verify HarmonyPyIDE on the DevEco emulator / a real device.
#
# IMPORTANT: keep this file PURE ASCII. Windows PowerShell reads a BOM-less .ps1
# as the system ANSI code page (GBK on zh-CN) and non-ASCII bytes break parsing.
# Chinese documentation lives in scripts/device/README.md.
#
# Quick examples:
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 targets
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 info
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 install
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 start
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 dump
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 shot
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 click -X 1800 -Y 300
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 summary -In <layout.json>
#   powershell -ExecutionPolicy Bypass -File .\device.ps1 shell uname -a
#
# Defaults:
#   - target selection prefers a TCP hdc target (emulator, 127.0.0.1:5555) and
#     falls back to a USB target (real device). Override with -Serial.
#   - dump/shot output goes to <project>\..\_cache\device2 when -Out is omitted.
#   - install defaults to entry\build\default\outputs\default\entry-default-signed.hap
#
# Exit codes: 0 ok, 1 command failed, 2 bad usage / no device, 3 timeout.

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$Action,
    [string]$Serial = '',
    [string]$Hap = '',
    [string]$Out = '',
    [string]$In = '',
    [int]$X = -1,
    [int]$Y = -1,
    [int]$KeyCode = -1,
    [string]$Text = '',
    [string]$Package = 'com.harmonyide.python',
    [string]$Ability = 'EntryAbility',
    [int]$TimeoutSec = 60,
    [int]$SettleMs = 0,
    [int]$MaxNodes = 250,
    [string]$Filter = '',
    [string]$Hdc = 'D:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = 'Continue'
$script:Hdc = $Hdc
$script:Serial = $Serial

if ($PSScriptRoot) {
    $script:ScriptDir = $PSScriptRoot
} else {
    $script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $script:ScriptDir)
$script:EvidenceDir = Join-Path (Join-Path $script:ProjectRoot '_cache') 'device2'

function Write-Ok([string]$m) { Write-Host ('[OK] ' + $m) }
function Write-Err([string]$m) { Write-Host ('[FAIL] ' + $m) }
function Write-Info([string]$m) { Write-Host ('[info] ' + $m) }

function Invoke-Hdc {
    param([string[]]$ArgList, [int]$TimeoutSec = 60)
    $fOut = [System.IO.Path]::GetTempFileName()
    $fErr = [System.IO.Path]::GetTempFileName()
    $quoted = ($ArgList | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }) -join ' '
    $proc = Start-Process -FilePath $script:Hdc -ArgumentList $quoted -NoNewWindow -PassThru -RedirectStandardOutput $fOut -RedirectStandardError $fErr
    $done = $proc.WaitForExit($TimeoutSec * 1000)
    $stdout = ''
    $stderr = ''
    try { $stdout = [System.IO.File]::ReadAllText($fOut) } catch { }
    try { $stderr = [System.IO.File]::ReadAllText($fErr) } catch { }
    $exitCode = $null
    if ($done) {
        try { $exitCode = $proc.ExitCode } catch { $exitCode = -1 }
    } else {
        try { $proc.Kill() } catch { }
    }
    Remove-Item $fOut, $fErr -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $stdout
        Stderr = $stderr
        TimedOut = (-not $done)
        CommandLine = ($script:Hdc + ' ' + $quoted)
    }
}

function Get-TargetRows {
    $r = Invoke-Hdc -ArgList @('list', 'targets', '-v') -TimeoutSec 30
    $rows = @()
    foreach ($ln in ($r.Stdout -split '\r?\n')) {
        $t = $ln.Trim()
        if ($t -eq '') { continue }
        $parts = $t -split '\s+'
        if ($parts.Count -ge 3) {
            $rows += [pscustomobject]@{ Serial = $parts[0]; Transport = $parts[1]; State = $parts[2]; Raw = $t }
        }
    }
    return $rows
}

function Resolve-Serial {
    if ($script:Serial -ne '') { return $script:Serial }
    $rows = @(Get-TargetRows)
    foreach ($tp in @('TCP', 'USB')) {
        $hit = @($rows | Where-Object { ($_.Transport -eq $tp) -and ($_.State -eq 'Connected') }) | Select-Object -First 1
        if ($hit) { return $hit.Serial }
    }
    $any = @($rows | Where-Object { $_.Transport -ne 'UART' }) | Select-Object -First 1
    if ($any) { return $any.Serial }
    return $null
}

function Resolve-OutPath([string]$prefix, [string]$ext) {
    if ($Out -ne '') { return $Out }
    if (-not (Test-Path $script:EvidenceDir)) {
        New-Item -ItemType Directory -Force -Path $script:EvidenceDir | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    return (Join-Path $script:EvidenceDir ($prefix + '_' + $stamp + '.' + $ext))
}

function Get-JpegSize([string]$path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -lt 4) { return $null }
    $i = 2
    while ($i -lt ($bytes.Length - 9)) {
        if ($bytes[$i] -ne 0xFF) { $i++; continue }
        $marker = $bytes[$i + 1]
        if ($marker -eq 0xD8 -or $marker -eq 0xD9) { $i += 2; continue }
        $len = ($bytes[$i + 2] * 256) + $bytes[$i + 3]
        if (($marker -ge 0xC0) -and ($marker -le 0xC3)) {
            $h = ($bytes[$i + 5] * 256) + $bytes[$i + 6]
            $w = ($bytes[$i + 7] * 256) + $bytes[$i + 8]
            return [pscustomobject]@{ Width = $w; Height = $h }
        }
        $i += 2 + $len
    }
    return $null
}

function Get-JsonField([string]$json, [string]$name) {
    $m = [regex]::Match($json, '"' + $name + '":"((?:[^"\\]|\\.)*)"')
    if (-not $m.Success) { return '' }
    return $m.Groups[1].Value
}

function Show-Usage {
    Write-Host 'device.ps1 <action> [options]'
    Write-Host 'actions: targets | wait | info | install | start | stop | dump | shot | click | text | key | shell | recv | summary | help'
    Write-Host 'common options: -Serial <key> -Hap <path> -Out <path> -In <json> -TimeoutSec <n> -Text <s> -X <n> -Y <n> -SettleMs <n> -Filter <regex>'
    Write-Host 'examples:'
    Write-Host '  device.ps1 install -Hap entry\build\default\outputs\default\entry-default-signed.hap'
    Write-Host '  device.ps1 start'
    Write-Host '  device.ps1 dump -Out _cache\device2\layout.json'
    Write-Host '  device.ps1 click -X 1800 -Y 300 -SettleMs 500'
    Write-Host '  device.ps1 shot -Out _cache\device2\shot.jpeg'
}

$deviceActions = @('info', 'install', 'start', 'stop', 'dump', 'shot', 'click', 'text', 'key', 'shell', 'recv', 'wait')
$serial = Resolve-Serial
if (($deviceActions -contains $Action.ToLower()) -and (-not $serial)) {
    Write-Err 'no usable device target; hdc list targets -v says:'
    $r = Invoke-Hdc -ArgList @('list', 'targets', '-v') -TimeoutSec 30
    Write-Host $r.Stdout
    Write-Host $r.Stderr
    exit 2
}

switch ($Action.ToLower()) {
    'help' {
        Show-Usage
        exit 0
    }
    'targets' {
        $r = Invoke-Hdc -ArgList @('list', 'targets', '-v') -TimeoutSec 30
        Write-Host $r.Stdout
        if ($r.Stderr.Trim() -ne '') { Write-Host $r.Stderr }
        if ($r.TimedOut) { Write-Err 'hdc list targets timed out'; exit 3 }
        exit 0
    }
    'wait' {
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $hit = Resolve-Serial
            if ($hit) { Write-Ok ('device online: ' + $hit); Write-Output ('SERIAL=' + $hit); exit 0 }
            Start-Sleep -Seconds 3
        }
        Write-Err ('no device online after ' + $TimeoutSec + 's')
        exit 1
    }
    'info' {
        Write-Info ('target serial = ' + $serial)
        $props = @(
            @('const.product.model', 'model'),
            @('const.product.name', 'name'),
            @('const.product.devicetype', 'deviceType'),
            @('const.ohos.apiversion', 'apiVersion'),
            @('const.product.software.version', 'softwareVersion'),
            @('const.build.characteristics', 'buildCharacteristics')
        )
        foreach ($p in $props) {
            $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'param', 'get', $p[0]) -TimeoutSec 20
            Write-Host ('  ' + $p[1] + ' = ' + $r.Stdout.Trim())
        }
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'wm', 'size') -TimeoutSec 20
        Write-Host ('  wm size = ' + $r.Stdout.Trim())
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'wm', 'density') -TimeoutSec 20
        Write-Host ('  wm density = ' + $r.Stdout.Trim())
        exit 0
    }
    'install' {
        $hapPath = $Hap
        if ($hapPath -eq '') {
            $hapPath = Join-Path $script:ProjectRoot 'entry\build\default\outputs\default\entry-default-signed.hap'
        }
        if (-not (Test-Path $hapPath)) { Write-Err ('hap not found: ' + $hapPath); exit 2 }
        Write-Info ('installing ' + $hapPath)
        $to = [Math]::Max($TimeoutSec, 240)
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'install', '-r', $hapPath) -TimeoutSec $to
        Write-Host $r.Stdout
        if ($r.Stderr.Trim() -ne '') { Write-Host $r.Stderr }
        if ($r.TimedOut) { Write-Err ('install timed out after ' + $to + 's'); exit 3 }
        if (($r.Stdout -match 'success') -and ($r.Stdout -notmatch 'fail')) {
            Write-Ok 'hap installed'
            exit 0
        }
        Write-Err ('install failed, exit=' + $r.ExitCode)
        exit 1
    }
    'start' {
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'aa', 'start', '-a', $Ability, '-b', $Package) -TimeoutSec $TimeoutSec
        Write-Host $r.Stdout
        if ($r.Stderr.Trim() -ne '') { Write-Host $r.Stderr }
        if ($r.TimedOut) { Write-Err 'aa start timed out'; exit 3 }
        if ($r.Stdout -match 'success') { Write-Ok ('started ' + $Package + '/' + $Ability); exit 0 }
        Write-Err ('aa start failed, exit=' + $r.ExitCode)
        exit 1
    }
    'stop' {
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'aa', 'force-stop', $Package) -TimeoutSec $TimeoutSec
        Write-Host $r.Stdout
        if ($r.Stderr.Trim() -ne '') { Write-Host $r.Stderr }
        if ($r.Stdout -match 'error|fail') { Write-Err 'force-stop failed'; exit 1 }
        Write-Ok ('stopped ' + $Package)
        exit 0
    }
    'dump' {
        $remote = '/data/local/tmp/layout.json'
        Write-Info ('target = ' + $serial + ' ; uitest dumpLayout -p ' + $remote)
        $r1 = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'uitest', 'dumpLayout', '-p', $remote) -TimeoutSec ([Math]::Max($TimeoutSec, 90))
        if ($r1.Stdout.Trim() -ne '') { Write-Host ('  ' + $r1.Stdout.Trim()) }
        if ($r1.TimedOut) { Write-Err 'dumpLayout timed out'; exit 3 }
        if ($r1.Stdout -match 'error|failed') { Write-Err ('dumpLayout failed: ' + $r1.Stdout.Trim()); exit 1 }
        $outPath = Resolve-OutPath 'layout' 'json'
        $r2 = Invoke-Hdc -ArgList @('-t', $serial, 'file', 'recv', $remote, $outPath) -TimeoutSec ([Math]::Max($TimeoutSec, 90))
        if ($r2.TimedOut) { Write-Err 'file recv timed out'; exit 3 }
        if (-not (Test-Path $outPath)) { Write-Err ('layout file not received: ' + $outPath + ' ; ' + $r2.Stdout.Trim()); exit 1 }
        $len = (Get-Item $outPath).Length
        if ($len -lt 200) { Write-Err ('layout file too small: ' + $len + ' bytes'); exit 1 }
        $head = Get-Content $outPath -TotalCount 1
        if ($head -notmatch '^\s*\{') { Write-Err 'layout file does not look like JSON'; exit 1 }
        Write-Ok ('layout saved: ' + $outPath + ' (' + $len + ' bytes)')
        Write-Output ('OUT=' + $outPath)
        exit 0
    }
    'shot' {
        $remote = '/data/local/tmp/shot.jpeg'
        Write-Info ('target = ' + $serial + ' ; snapshot_display -f ' + $remote)
        $r1 = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'snapshot_display', '-f', $remote) -TimeoutSec ([Math]::Max($TimeoutSec, 90))
        if ($r1.TimedOut) { Write-Err 'snapshot_display timed out'; exit 3 }
        if (($r1.Stdout -match 'error|failed') -or ($r1.Stderr -match 'error|failed')) {
            Write-Err ('snapshot_display failed: ' + $r1.Stdout.Trim() + ' ' + $r1.Stderr.Trim())
            exit 1
        }
        $outPath = Resolve-OutPath 'shot' 'jpeg'
        $r2 = Invoke-Hdc -ArgList @('-t', $serial, 'file', 'recv', $remote, $outPath) -TimeoutSec ([Math]::Max($TimeoutSec, 90))
        if ($r2.TimedOut) { Write-Err 'file recv timed out'; exit 3 }
        if (-not (Test-Path $outPath)) { Write-Err ('screenshot not received: ' + $outPath + ' ; ' + $r2.Stdout.Trim()); exit 1 }
        $len = (Get-Item $outPath).Length
        if ($len -lt 1000) { Write-Err ('screenshot too small: ' + $len + ' bytes'); exit 1 }
        $size = Get-JpegSize $outPath
        if ($size) {
            Write-Ok ('screenshot saved: ' + $outPath + ' (' + $len + ' bytes, ' + $size.Width + 'x' + $size.Height + ')')
        } else {
            Write-Ok ('screenshot saved: ' + $outPath + ' (' + $len + ' bytes)')
        }
        Write-Output ('OUT=' + $outPath)
        exit 0
    }
    'click' {
        if (($X -lt 0) -or ($Y -lt 0)) { Write-Err 'click needs -X and -Y'; exit 2 }
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'uitest', 'uiInput', 'click', [string]$X, [string]$Y) -TimeoutSec $TimeoutSec
        if ($r.TimedOut) { Write-Err 'click timed out'; exit 3 }
        $o = ($r.Stdout + ' ' + $r.Stderr).Trim()
        $o = $o -replace 'No Error', ''
        if ($o -match 'error|fail|invalid') { Write-Err ('click failed: ' + $o); exit 1 }
        if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
        Write-Ok ('click ' + $X + ',' + $Y)
        exit 0
    }
    'text' {
        if (($X -lt 0) -or ($Y -lt 0) -or ($Text -eq '')) { Write-Err 'text needs -X -Y and -Text'; exit 2 }
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'uitest', 'uiInput', 'inputText', [string]$X, [string]$Y, $Text) -TimeoutSec $TimeoutSec
        if ($r.TimedOut) { Write-Err 'inputText timed out'; exit 3 }
        $o = ($r.Stdout + ' ' + $r.Stderr).Trim()
        if ($o -match 'error|fail|invalid') { Write-Err ('inputText failed: ' + $o); exit 1 }
        if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
        Write-Ok ('inputText at ' + $X + ',' + $Y)
        exit 0
    }
    'key' {
        if ($KeyCode -lt 0) { Write-Err 'key needs -KeyCode <n>'; exit 2 }
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'shell', 'uitest', 'uiInput', 'keyEvent', [string]$KeyCode) -TimeoutSec $TimeoutSec
        if ($r.TimedOut) { Write-Err 'keyEvent timed out'; exit 3 }
        $o = ($r.Stdout + ' ' + $r.Stderr).Trim()
        if ($o -match 'error|fail|invalid') { Write-Err ('keyEvent failed: ' + $o); exit 1 }
        if ($SettleMs -gt 0) { Start-Sleep -Milliseconds $SettleMs }
        Write-Ok ('keyEvent ' + $KeyCode)
        exit 0
    }
    'shell' {
        if ($Rest.Count -eq 0) { Write-Err 'shell needs a command after the action'; exit 2 }
        $argv = @('-t', $serial, 'shell') + $Rest
        $r = Invoke-Hdc -ArgList $argv -TimeoutSec $TimeoutSec
        Write-Host $r.Stdout
        if ($r.Stderr.Trim() -ne '') { Write-Host $r.Stderr }
        if ($r.TimedOut) { Write-Err 'shell timed out'; exit 3 }
        if ($r.ExitCode -ne 0) { Write-Err ('shell exit=' + $r.ExitCode); exit 1 }
        exit 0
    }
    'recv' {
        if ($Rest.Count -lt 2) { Write-Err 'recv needs <remote> <local>'; exit 2 }
        $r = Invoke-Hdc -ArgList @('-t', $serial, 'file', 'recv', $Rest[0], $Rest[1]) -TimeoutSec ([Math]::Max($TimeoutSec, 120))
        Write-Host $r.Stdout
        if ($r.TimedOut) { Write-Err 'file recv timed out'; exit 3 }
        if (-not (Test-Path $Rest[1])) { Write-Err ('local file missing: ' + $Rest[1]); exit 1 }
        Write-Ok ('received ' + $Rest[0] + ' -> ' + $Rest[1])
        exit 0
    }
    'summary' {
        $jsonPath = $In
        if ($jsonPath -eq '') {
            $latest = Get-ChildItem $script:EvidenceDir -Filter '*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) { $jsonPath = $latest.FullName }
        }
        if (($jsonPath -eq '') -or (-not (Test-Path $jsonPath))) { Write-Err ('no dump json found: ' + $jsonPath); exit 2 }
        Write-Info ('summary of ' + $jsonPath + ' filter=[' + $Filter + ']')
        # dumpLayout emits one flat {"attributes":{...},"children":[...]} object per node;
        # ConvertFrom-Json is unreliable for these big files under Windows PowerShell 5.1,
        # so parse the attribute blocks with regex and take depth from the hierarchy chain.
        $raw = [System.IO.File]::ReadAllText($jsonPath, [System.Text.Encoding]::UTF8)
        $blocks = [regex]::Matches($raw, '\{"attributes":\{(.*?)\},"children"')
        $printed = 0
        foreach ($b in $blocks) {
            if ($printed -ge $MaxNodes) { break }
            $a = $b.Groups[1].Value
            $ty = Get-JsonField $a 'type'
            $tx = Get-JsonField $a 'text'
            $id = Get-JsonField $a 'id'
            $bd = Get-JsonField $a 'bounds'
            $ck = Get-JsonField $a 'clickable'
            $hi = Get-JsonField $a 'hierarchy'
            if (($tx -eq '') -and ($id -eq '')) { continue }
            if ($Filter -ne '') {
                if ((($ty + ' ' + $id + ' ' + $tx) -notmatch $Filter)) { continue }
            }
            $depth = 0
            if ($hi -ne '') { $depth = ($hi -split ',').Count - 1 }
            $pad = (' ' * ($depth * 2))
            Write-Output ($pad + '<' + $ty + '> id="' + $id + '" text="' + $tx + '" bounds="' + $bd + '" clickable=' + $ck)
            $printed++
        }
        Write-Ok ('printed ' + $printed + ' labeled nodes (max ' + $MaxNodes + ', total ' + $blocks.Count + ')')
        exit 0
    }
    default {
        Write-Err ('unknown action: ' + $Action)
        Show-Usage
        exit 2
    }
}

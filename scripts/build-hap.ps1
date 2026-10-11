<#
.SYNOPSIS
    Build the HarmonyPyIDE HAP from the command line (no DevEco Studio GUI needed).

.NOTES
    This file is intentionally ASCII-only.
    Windows PowerShell 5.1 reads a BOM-less UTF-8 file using the ANSI code page
    (GBK on a Chinese system), which mangles non-ASCII text and breaks the parser.
    Keeping build tooling ASCII-only removes that whole class of failure.

.DESCRIPTION
    Equivalent to DevEco Studio's Build > Build Hap(s). Sets JAVA_HOME / NODE_HOME /
    DEVECO_SDK_HOME and runs:
      1. ohpm install --all
      2. hvigorw assembleHap

    Two pitfalls this script handles for you:
      * hvigor's PackageHap step spawns "java". If java is not on PATH it fails with
        "spawn java ENOENT" -- even though ArkTS already compiled successfully, which
        makes it look like a code error. DevEco's bundled JBR is put first on PATH.
      * "compatibleSdkVersion" must use the <major>.<minor>.<patch> form (e.g. 26.0.0);
        the legacy "6.0.2(22)" form is rejected with "api version parameter is illegal".

.EXAMPLE
    powershell -File scripts\build-hap.ps1
    powershell -File scripts\build-hap.ps1 -Mode release
    powershell -File scripts\build-hap.ps1 -Clean
    powershell -File scripts\build-hap.ps1 -ResetHvigorCache   # after an hvigor cache ENOENT
#>
param(
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('debug', 'release')][string]$Mode = 'debug',
    [string]$Product = 'default',
    [string]$DevEcoHome = 'D:\DevEco Studio',
    [switch]$Clean,
    [switch]$ResetHvigorCache
)

$ErrorActionPreference = 'Stop'

function Assert-Exists([string]$Path, [string]$Name) {
    if (-not (Test-Path $Path)) {
        throw "missing $Name : $Path (use -DevEcoHome to point at the DevEco Studio install)"
    }
}

function Remove-Tree([string]$Path) {
    # Two Windows quirks make a naive Remove-Item unreliable here:
    #   1. PowerShell 5.1's Remove-Item fails on paths longer than MAX_PATH -- the
    #      ArkTS compiler cache nests ~200 character file names.
    #   2. With $ErrorActionPreference = 'Stop', a native command that writes to
    #      stderr becomes a TERMINATING NativeCommandError, so a plain
    #      "cmd /c rd /s /q" would abort the whole build.
    # robocopy /MIR from an empty directory is long-path aware and empties the tree;
    # a plain Remove-Item then succeeds. Every failure degrades to a warning.
    if (-not (Test-Path $Path)) { return }
    $empty = Join-Path $env:TEMP ('dsh-empty-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $empty | Out-Null
        & robocopy $empty $Path /MIR /NFL /NDL /NJH /NJS /NP /R:0 /W:0 2>&1 | Out-Null
    }
    catch {
        Write-Warning "robocopy cleanup failed for $Path : $($_.Exception.Message)"
    }
    try {
        if (Test-Path $Path) { Remove-Item -Recurse -Force $Path -ErrorAction Stop }
    }
    catch {
        Write-Warning "could not fully remove $Path : $($_.Exception.Message)"
    }
    if (Test-Path $empty) { Remove-Item -Recurse -Force $empty -ErrorAction SilentlyContinue }
}

$jbrHome = Join-Path $DevEcoHome 'jbr'
$nodeHome = Join-Path $DevEcoHome 'tools\node'
$ohpm = Join-Path $DevEcoHome 'tools\ohpm\bin\ohpm.bat'
$hvigorw = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.bat'
$sdkHome = Join-Path $DevEcoHome 'sdk'

Assert-Exists (Join-Path $jbrHome 'bin\java.exe') 'DevEco bundled JBR (java)'
Assert-Exists $nodeHome 'Node.js (bundled with DevEco)'
Assert-Exists $ohpm 'ohpm'
Assert-Exists $hvigorw 'hvigorw'
Assert-Exists $sdkHome 'HarmonyOS SDK'

$env:JAVA_HOME = $jbrHome
$env:NODE_HOME = $nodeHome
$env:DEVECO_SDK_HOME = $sdkHome
$env:Path = "$(Join-Path $jbrHome 'bin');$nodeHome;$(Join-Path $DevEcoHome 'tools\ohpm\bin');$(Join-Path $DevEcoHome 'tools\hvigor\bin');$env:Path"

if ($ResetHvigorCache) {
    # hvigor caches each project's dependency workspace in ~/.hvigor/project_caches/<hash>.
    # Concurrent or interrupted builds can corrupt it, showing up as
    #   ENOENT ... \workspace\node_modules\@ohos\hvigor\bin\hvigor.js
    $caches = Join-Path $env:USERPROFILE '.hvigor\project_caches'
    if (Test-Path $caches) {
        Write-Host "== clearing hvigor project caches: $caches ==" -ForegroundColor Yellow
        Remove-Tree $caches
    }
}

Push-Location $ProjectDir
try {
    if ($Clean) {
        Write-Host '== cleaning build outputs ==' -ForegroundColor Cyan
        foreach ($dir in @('entry\build', 'entry\.cxx', '.hvigor', 'build')) {
            $target = Join-Path $ProjectDir $dir
            if (Test-Path $target) {
                Remove-Tree $target
                Write-Host "   removed $dir"
            }
        }
    }

    Write-Host '== ohpm install ==' -ForegroundColor Cyan
    & $ohpm install --all
    if ($LASTEXITCODE -ne 0) { throw "ohpm install failed (exit $LASTEXITCODE)" }

    Write-Host "== hvigorw assembleHap ($Mode) ==" -ForegroundColor Cyan
    & $hvigorw --mode module -p product=$Product -p buildMode=$Mode assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "hvigorw build failed (exit $LASTEXITCODE)" }

    Write-Host '== artifacts ==' -ForegroundColor Green
    $haps = Get-ChildItem -Path (Join-Path $ProjectDir 'entry\build') -Recurse -Filter '*.hap' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    if ($haps.Count -eq 0) {
        Write-Warning 'no .hap found; check the build log above.'
    }
    else {
        foreach ($hap in $haps) {
            $sizeMb = [Math]::Round($hap.Length / 1MB, 2)
            Write-Host ("  {0}  ({1} MB)" -f $hap.FullName, $sizeMb)
        }
    }
}
finally {
    Pop-Location
}

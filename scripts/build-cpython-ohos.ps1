<#
.SYNOPSIS
    Cross-compile CPython 3.12.10 as a static library for HarmonyOS / OpenHarmony,
    and package the bundled standard library plus the pip wheel.

.NOTES
    This file is intentionally ASCII-only.
    Windows PowerShell 5.1 reads a BOM-less UTF-8 file using the ANSI code page
    (GBK on a Chinese system), which mangles non-ASCII text and breaks the parser.
    Keeping build tooling ASCII-only removes that entire class of failure, so no
    BOM is required and no editor can silently break it.

.DESCRIPTION
    Outputs (consumed by entry/src/main/cpp/CMakeLists.txt and PyRuntimeService.ets):
      entry\src\main\cpp\thirdparty\<abi>\libpython3.12.a
      entry\src\main\cpp\thirdparty\<abi>\include\*.h    (incl. the generated pyconfig.h)
      entry\src\main\resources\rawfile\python\python312.zip
      entry\src\main\resources\rawfile\python\wheels\pip-*.whl

    Why not "./configure && make": this host has no usable POSIX environment.
    Every MSYS/Cygwin binary dies at startup with
        *** fatal error - couldn't create signal pipe, Win32 error 5
    so scripts/ohos_cpython_build.py re-implements configure+make in pure Python:
    it probes the OHOS sysroot to synthesise pyconfig.h, decides which extension
    modules are buildable, freezes the bootstrap modules with the host Python,
    compiles with the NDK clang and archives with llvm-ar.
    See docs/CPYTHON-PORT-NOTES.md for every pitfall that was fixed.

    Objects are stored per ABI under <workspace>\_cache\build-cpython\ohos-build\<abi>\obj,
    so building several ABIs in a row can no longer contaminate each other.

.EXAMPLE
    powershell -File scripts\build-cpython-ohos.ps1                  # arm64-v8a (devices)
    powershell -File scripts\build-cpython-ohos.ps1 -Abi x86_64      # emulator
    powershell -File scripts\build-cpython-ohos.ps1 -Abi both        # sequential, supported
    powershell -File scripts\build-cpython-ohos.ps1 -SkipStdlib      # relink only
    powershell -File scripts\build-cpython-ohos.ps1 -AllowDownload   # fetch source if absent
#>
param(
    [ValidateSet('arm64-v8a', 'x86_64', 'both')][string]$Abi = 'arm64-v8a',
    [string]$DevEcoHome = 'D:\DevEco Studio',
    [string]$HostPython = 'C:\Users\HUAWEI\AppData\Local\Programs\Python\Python312\python.exe',
    [string]$SourceTree = '',
    [string]$ProjectDir = (Split-Path -Parent $PSScriptRoot),
    [switch]$SkipStdlib,
    [switch]$AllowDownload
)

$ErrorActionPreference = 'Stop'

$workspace = Split-Path -Parent $ProjectDir
$cacheRoot = Join-Path $workspace '_cache\build-cpython'
$ndk = Join-Path $DevEcoHome 'sdk\default\openharmony\native'
$driver = Join-Path $PSScriptRoot 'ohos_cpython_build.py'
$packer = Join-Path $PSScriptRoot 'package-stdlib.py'

function Assert-Exists([string]$Path, [string]$Name) {
    if (-not (Test-Path $Path)) { throw "missing $Name : $Path" }
}

Assert-Exists $driver 'ohos_cpython_build.py'
Assert-Exists $packer 'package-stdlib.py'
Assert-Exists $HostPython 'host Python 3.12 (needed to freeze the bootstrap modules; version must match the target)'
Assert-Exists $ndk 'OHOS NDK'
Assert-Exists (Join-Path $ndk 'llvm\bin\clang.exe') 'OHOS clang cross compiler'

# ---- 1. source tree (offline first; network only with -AllowDownload) --------
if ($SourceTree -eq '') {
    $SourceTree = Join-Path $cacheRoot 'cpython-3.12.10'
}
if (-not (Test-Path (Join-Path $SourceTree 'Lib\os.py'))) {
    New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    $tarball = Join-Path $cacheRoot 'Python-3.12.10.tgz'
    if (-not (Test-Path $tarball)) {
        $cached = Join-Path $workspace '_cache\Python-3.12.10.tgz'
        if (Test-Path $cached) {
            Write-Host "== using cached source archive: $cached ==" -ForegroundColor Cyan
            Copy-Item $cached $tarball -Force
        }
        elseif ($AllowDownload) {
            Write-Host '== downloading CPython 3.12.10 source (~26 MB) ==' -ForegroundColor Cyan
            Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.12.10/Python-3.12.10.tgz' `
                -OutFile $tarball -UseBasicParsing
        }
        else {
            throw ("CPython 3.12.10 source not found. Put Python-3.12.10.tgz into " +
                "$cached or $tarball, pass -SourceTree <extracted tree>, " +
                "or pass -AllowDownload to fetch it.")
        }
    }
    Write-Host '== extracting source ==' -ForegroundColor Cyan
    & tar.exe -xzf $tarball -C $cacheRoot
    # bsdtar extracts to Python-3.12.10\; the repository convention is cpython-3.12.10
    $extracted = Join-Path $cacheRoot 'Python-3.12.10'
    if ((Test-Path $extracted) -and -not (Test-Path $SourceTree)) {
        Move-Item $extracted $SourceTree
    }
    if (-not (Test-Path (Join-Path $SourceTree 'Lib\os.py'))) {
        throw "source tree still not found after extraction: $SourceTree"
    }
}

$abis = if ($Abi -eq 'both') { @('arm64-v8a', 'x86_64') } else { @($Abi) }

# ---- 2. build each ABI ------------------------------------------------------
foreach ($one in $abis) {
    $outDir = Join-Path $ProjectDir "entry\src\main\cpp\thirdparty\$one"
    Write-Host "== cross-compiling CPython for $one ==" -ForegroundColor Cyan
    # --skip-existing is safe: objects live per ABI under <work>\<abi>\obj\.
    & $HostPython $driver --src $SourceTree --abi $one --ndk $ndk `
        --host-python $HostPython --outdir $outDir --keep-going --skip-existing
    if ($LASTEXITCODE -ne 0) {
        throw "CPython build failed for $one (exit $LASTEXITCODE); see the failure list above"
    }

    # ---- 3. collect headers (pyconfig.h must come from this very build) -----
    $incOut = Join-Path $outDir 'include'
    New-Item -ItemType Directory -Force -Path $incOut | Out-Null
    # Do NOT use: Copy-Item "<src>\Include\*" -Destination <dir> -Recurse
    # When a same-named subdirectory already exists PowerShell aborts with
    # "cannot copy container to existing leaf item" and only half the headers refresh.
    Get-ChildItem (Join-Path $SourceTree 'Include') -Force | ForEach-Object {
        $dest = Join-Path $incOut $_.Name
        if ($_.PSIsContainer) {
            if (Test-Path $dest) {
                & cmd.exe /c rd /s /q "$dest" 2>$null
                if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
            }
            Copy-Item $_.FullName $dest -Recurse -Force
        }
        else {
            Copy-Item $_.FullName $dest -Force
        }
    }
    $pyconfigCandidates = @(
        (Join-Path $cacheRoot "ohos-build\$one\pyconfig.h"),   # per-ABI private copy (best)
        (Join-Path $SourceTree 'Include\pyconfig.h'),
        (Join-Path $SourceTree 'pyconfig.h'),
        (Join-Path $cacheRoot "ohos-build\pyconfig.h")
    )
    $found = $pyconfigCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($null -eq $found) {
        throw "no pyconfig.h produced by this build (looked at: $($pyconfigCandidates -join '; '))"
    }
    Copy-Item $found (Join-Path $incOut 'pyconfig.h') -Force
    $hdrCount = (Get-ChildItem $incOut -Recurse -File).Count
    Write-Host "   headers ready: $incOut ($hdrCount files; pyconfig.h from $found)" -ForegroundColor Green
}

# ---- 4. package the standard library zip (+ pip wheel) ----------------------
if (-not $SkipStdlib) {
    $zipOut = Join-Path $ProjectDir 'entry\src\main\resources\rawfile\python\python312.zip'
    $wheelOut = Join-Path $ProjectDir 'entry\src\main\resources\rawfile\python\wheels'
    Write-Host '== packaging python312.zip (and the pip wheel) ==' -ForegroundColor Cyan
    & $HostPython $packer --src $SourceTree --out $zipOut --pip-wheel-dir $wheelOut
    if ($LASTEXITCODE -ne 0) { throw 'stdlib packaging failed' }
}

Write-Host ''
Write-Host 'Done. Now rebuild the HAP: powershell -File scripts\build-hap.ps1' -ForegroundColor Green
Write-Host 'The CMake warning about a missing libpython3.12.a should be gone.' -ForegroundColor Green

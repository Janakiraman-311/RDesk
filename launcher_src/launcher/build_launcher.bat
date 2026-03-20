@echo off
setlocal enabledelayedexpansion

echo [DIAG] Current Directory: %CD%
echo [DIAG] Script Directory: %~dp0

REM ── Map Rtools to R: drive if possible (optional fallback)
set "RTOOLS_ORIG=C:\rtools45"
if not exist "%RTOOLS_ORIG%" set "RTOOLS_ORIG=C:\rtools44"
if exist "%RTOOLS_ORIG%" (
    subst R: /d >nul 2>&1
    subst R: "%RTOOLS_ORIG%" >diag_subst.txt 2>&1
    if !ERRORLEVEL! equ 0 (
        echo [DIAG] Successfully mapped R: to %RTOOLS_ORIG%
        set "PATH=R:\x86_64-w64-mingw32.static.posix\bin;R:\usr\bin;!PATH!"
    ) else (
        echo [DIAG] subst R: failed. Using original path.
        type diag_subst.txt
    )
)

echo [DIAG] PATH: !PATH!

where g++ >diag_where.txt 2>&1
if !ERRORLEVEL! equ 0 (
    echo [DIAG] Found g++ at:
    type diag_where.txt
) else (
    echo [DIAG] g++ NOT FOUND on PATH
)

g++ --version >diag_ver.txt 2>&1
if !ERRORLEVEL! equ 0 (
    echo [DIAG] g++ version:
    type diag_ver.txt
)

REM ── Ensure inst\bin exists
if not exist "%~dp0..\..\inst\bin" (
    echo [DIAG] Creating inst\bin...
    mkdir "%~dp0..\..\inst\bin"
)

REM ── Go to script directory
cd /d "%~dp0"

echo [DIAG] Starting compilation...

REM ── Direct compilation with all output redirected to log
g++ -O2 -static -mwindows -o rdesk-launcher.exe main.cpp ^
    -Iwebview ^
    -I../../inst/include ^
    -Iwebview2_sdk/build/native/include ^
    -lole32 -lshell32 -lshlwapi -luser32 -lversion -lcomdlg32 -loleaut32 -luuid ^
    >build_log.txt 2>&1

set "COMPILE_ERR=!ERRORLEVEL!"

if !COMPILE_ERR! neq 0 (
    echo [ERROR] Compilation FAILED with exit code !COMPILE_ERR!
    echo [ERROR] --- LOG START ---
    type build_log.txt
    echo [ERROR] --- LOG END ---
    exit /b !COMPILE_ERR!
)

echo [DIAG] Build SUCCESS!
if exist rdesk-launcher.exe (
    copy /y rdesk-launcher.exe "%~dp0..\..\inst\bin\rdesk-launcher.exe"
    echo [DIAG] Copied rdesk-launcher.exe to inst\bin\
) else (
    echo [ERROR] rdesk-launcher.exe not found after build
    exit /b 1
)

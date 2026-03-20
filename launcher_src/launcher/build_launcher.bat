@echo off
setlocal enabledelayedexpansion

REM --- 1. Tools Mapping (RTools 4.5/4.4) ---
set "RTOOLS_ORIG=C:\rtools45"
if not exist "%RTOOLS_ORIG%" set "RTOOLS_ORIG=C:\rtools44"

if exist "%RTOOLS_ORIG%" (
    subst R: /d >nul 2>&1
    subst R: "%RTOOLS_ORIG%"
    if !ERRORLEVEL! equ 0 (
        set "PATH=R:\x86_64-w64-mingw32.static.posix\bin;R:\usr\bin;!PATH!"
    )
)

REM --- 2. Resource Path Setup ---
set "SCRIPT_DIR=%~dp0"
set "INST_BIN=%SCRIPT_DIR%..\..\inst\bin"

if not exist "%INST_BIN%" mkdir "%INST_BIN%"
cd /d "%SCRIPT_DIR%"

REM --- 3. Direct G++ Compilation ---
echo Building RDesk Launcher...

g++ -O3 -std=c++17 -static -mwindows -o rdesk-launcher.exe main.cpp ^
    -Iwebview ^
    -I../../inst/include ^
    -Iwebview2_sdk/build/native/include ^
    -lole32 -lshell32 -lshlwapi -luser32 -lversion -lcomdlg32 -loleaut32 -luuid

if !ERRORLEVEL! neq 0 (
    echo [ERROR] Compilation failed.
    subst R: /d >nul 2>&1
    exit /b 1
)

REM --- 4. Asset Staging ---
if exist rdesk-launcher.exe (
    copy /y rdesk-launcher.exe "%INST_BIN%\rdesk-launcher.exe" >nul
)

if not exist "%INST_BIN%\WebView2Loader.dll" (
    if exist "webview2_sdk\runtimes\win-x64\native\WebView2Loader.dll" (
        copy /y "webview2_sdk\runtimes\win-x64\native\WebView2Loader.dll" "%INST_BIN%\WebView2Loader.dll" >nul
    )
)

echo Build SUCCESS.
subst R: /d >nul 2>&1
exit /b 0

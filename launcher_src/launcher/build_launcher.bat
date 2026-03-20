@echo off
REM ── Map Rtools to R: drive to avoid \r escape character issues (e.g. C:\rtools45)
set "RTOOLS_ORIG=C:\rtools45"
if not exist "%RTOOLS_ORIG%" set "RTOOLS_ORIG=C:\rtools44"
if exist "%RTOOLS_ORIG%" (
    subst R: /d >nul 2>&1
    subst R: "%RTOOLS_ORIG%"
    set "PATH=R:\x86_64-w64-mingw32.static.posix\bin;R:\usr\bin;%PATH%"
)

REM ── Ensure inst\bin exists so the copy at the end succeeds
if not exist "%~dp0..\..\inst\bin" mkdir "%~dp0..\..\inst\bin"

REM ── Go to script directory
cd /d "%~dp0"

echo Building RDesk Launcher via direct g++ compilation...
echo PATH: %PATH%

REM ── Direct compilation (bypasses CMake/Make fragility)
g++ -O2 -static -mwindows -o rdesk-launcher.exe main.cpp ^
    -Iwebview ^
    -I../../inst/include ^
    -Iwebview2_sdk/build/native/include ^
    -lole32 -lshell32 -lshlwapi -luser32 -lversion -lcomdlg32 -loleaut32 -luuid

if %ERRORLEVEL% neq 0 (
    echo ERROR: Compilation failed.
    exit /b %ERRORLEVEL%
)

echo Build SUCCESS!
if exist rdesk-launcher.exe (
    copy /y rdesk-launcher.exe "%~dp0..\..\inst\bin\rdesk-launcher.exe"
    echo Copied rdesk-launcher.exe to inst\bin\
) else (
    echo ERROR: rdesk-launcher.exe not found after build
    exit /b 1
)

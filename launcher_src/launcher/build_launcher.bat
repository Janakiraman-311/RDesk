@echo off
REM ── Map Rtools to R: drive to avoid \r escape character issues (e.g. C:\rtools45)
set "RTOOLS_ORIG=C:\rtools45"
if not exist "%RTOOLS_ORIG%" set "RTOOLS_ORIG=C:\rtools44"
if exist "%RTOOLS_ORIG%" (
    subst R: /d >nul 2>&1
    subst R: "%RTOOLS_ORIG%"
    set "RTOOLS_BIN=R:\x86_64-w64-mingw32.static.posix\bin"
    set "RTOOLS_USR=R:\usr\bin"
)

where cmake >nul 2>&1
if %errorlevel% equ 0 (
    set "CMAKE=cmake"
) else (
    if defined RTOOLS_BIN (
        if exist "%RTOOLS_BIN%\cmake.exe" (
            set "CMAKE=%RTOOLS_BIN%\cmake.exe"
            set "PATH=%RTOOLS_BIN%;%RTOOLS_USR%;%PATH%"
        ) else (
            echo ERROR: cmake not found on PATH or in Rtools.
            exit /b 1
        )
    ) else (
        echo ERROR: cmake not found and Rtools not detected.
        exit /b 1
    )
)

where g++ >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: g++ not found on PATH. Ensure Rtools bin directory is on PATH.
    exit /b 1
)

where make >nul 2>&1
if %errorlevel% neq 0 (
    where mingw32-make >nul 2>&1
    if %errorlevel% neq 0 (
        echo ERROR: make/mingw32-make not found on PATH.
        exit /b 1
    )
    REM Use mingw32-make alias
    set "MAKE_CMD=mingw32-make"
) else (
    set "MAKE_CMD=make"
)

echo Using cmake : %CMAKE%
echo Using g++   : found on PATH
echo Using make  : %MAKE_CMD%

REM ── Ensure inst\bin exists so the copy at the end succeeds
if not exist "%~dp0..\..\inst\bin" mkdir "%~dp0..\..\inst\bin"

REM ── Go to script directory and set up build folder
cd /d "%~dp0"
if exist build rmdir /s /q build
mkdir build
cd build

REM ── Detect g++ path for explicit CMake compiler flag
for /f "delims=" %%i in ('where g++') do set "GXX_PATH=%%i"
for /f "delims=" %%i in ('where gcc') do set "GCC_PATH=%%i"
for /f "delims=" %%i in ('where %MAKE_CMD%') do set "MAKE_PATH=%%i"

REM ── Convert backslashes to forward slashes for CMake robustness
set "GXX_PATH=%GXX_PATH:\=/%"
set "GCC_PATH=%GCC_PATH:\=/%"
set "MAKE_PATH=%MAKE_PATH:\=/%"

"%CMAKE%" .. -G "MinGW Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_CXX_COMPILER="%GXX_PATH%" ^
    -DCMAKE_C_COMPILER="%GCC_PATH%" ^
    -DCMAKE_MAKE_PROGRAM="%MAKE_PATH%" ^
    -DCMAKE_SH="CMAKE_SH-NOTFOUND"

if errorlevel 1 (
    echo CMake configure failed
    exit /b 1
)

"%CMAKE%" --build . --config Release
if errorlevel 1 (
    echo Build failed
    exit /b 1
)

echo Build SUCCESS!
if exist rdesk-launcher.exe (
    copy /y rdesk-launcher.exe "%~dp0..\..\inst\bin\rdesk-launcher.exe"
    echo Copied rdesk-launcher.exe to inst\bin\
) else (
    echo ERROR: rdesk-launcher.exe not found after build
    exit /b 1
)

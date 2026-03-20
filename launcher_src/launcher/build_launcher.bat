@echo on
set "RTOOLS_BIN=C:\rtools45\x86_64-w64-mingw32.static.posix\bin"
set "RTOOLS_USR=C:\rtools45\usr\bin"
if not exist "%RTOOLS_BIN%" (
    set "RTOOLS_BIN=C:\rtools44\x86_64-w64-mingw32.static.posix\bin"
    set "RTOOLS_USR=C:\rtools44\usr\bin"
)
set "PATH=%RTOOLS_BIN%;%RTOOLS_USR%;%PATH%"

echo --- DIAGNOSTICS ---
echo PATH: %PATH%
cmake --version
g++ --version
gcc --version

set "CMAKE=cmake"
if not exist "%RTOOLS_BIN%\g++.exe" (
    echo RTOOLS_BIN not found at %RTOOLS_BIN%, checking PATH...
    for /f "delims=" %%i in ('where g++.exe') do set "GXX=%%i"
    for /f "delims=" %%i in ('where gcc.exe') do set "GCC=%%i"
    for /f "delims=" %%i in ('where mingw32-make.exe') do set "MAKE=%%i"
) else (
    set "GXX=%RTOOLS_BIN%\g++.exe"
    set "GCC=%RTOOLS_BIN%\gcc.exe"
    set "MAKE=%RTOOLS_BIN%\mingw32-make.exe"
)

if not exist "%MAKE%" set "MAKE=%RTOOLS_USR%\make.exe"
if not exist "%MAKE%" for /f "delims=" %%i in ('where make.exe') do set "MAKE=%%i"

echo USING CMAKE: %CMAKE%
echo USING GXX: %GXX%
echo USING GCC: %GCC%
echo USING MAKE: %MAKE%

REM Go to script directory
cd /d "%~dp0"
echo CURRENT DIR: %CD%

if exist build rmdir /s /q build
mkdir build
cd build

echo --- CONFIGURING ---
"%CMAKE%" .. -G "MinGW Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_CXX_COMPILER="%GXX%" ^
    -DCMAKE_C_COMPILER="%GCC%" ^
    -DCMAKE_MAKE_PROGRAM="%MAKE%" ^
    -DCMAKE_SH="CMAKE_SH-NOTFOUND"

if %ERRORLEVEL% neq 0 (
    echo CMake selection/configuration failed.
    dir .. /s
    exit /b %ERRORLEVEL%
)

echo --- BUILDING ---
"%CMAKE%" --build . --config Release --verbose
if %ERRORLEVEL% neq 0 (
    echo Build step failed.
    exit /b %ERRORLEVEL%
)

echo Build SUCCESS!
if not exist "..\..\inst\bin" mkdir "..\..\inst\bin"
if not exist rdesk-launcher.exe (
    echo FAILURE: rdesk-launcher.exe was not produced.
    exit /b 1
)
copy /y rdesk-launcher.exe "..\..\inst\bin\rdesk-launcher.exe"
if %ERRORLEVEL% neq 0 (
    echo Copy to inst\bin failed.
    exit /b %ERRORLEVEL%
)

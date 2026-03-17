@echo off
set "RTOOLS_BIN=C:\rtools45\x86_64-w64-mingw32.static.posix\bin"
set "RTOOLS_USR=C:\rtools45\usr\bin"
set "PATH=%RTOOLS_BIN%;%RTOOLS_USR%;%PATH%"

set "CMAKE=%RTOOLS_BIN%\cmake.exe"
set "GXX=%RTOOLS_BIN%\g++.exe"
set "GCC=%RTOOLS_BIN%\gcc.exe"
set "MAKE=%RTOOLS_USR%\make.exe"

cd /d "c:\Users\Janak\OneDrive\Documents\RDesk\RDesk\launcher_src\launcher"
if exist build rmdir /s /q build
mkdir build
cd build

"%CMAKE%" .. -G "MinGW Makefiles" ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_CXX_COMPILER="%GXX%" ^
    -DCMAKE_C_COMPILER="%GCC%" ^
    -DCMAKE_MAKE_PROGRAM="%MAKE%" ^
    -DCMAKE_SH="CMAKE_SH-NOTFOUND"

if errorlevel 1 (
    echo CMake failed
    exit /b 1
)

"%CMAKE%" --build . --config Release
if errorlevel 1 (
    echo Build failed
    exit /b 1
)

echo Build SUCCESS!
copy /y rdesk-launcher.exe "..\..\..\inst\bin\rdesk-launcher.exe"

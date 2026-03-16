#!/bin/bash
# Run this from src/launcher/ to build the launcher binary
# Requires: cmake, ninja (or make), and platform webview dependencies

set -e
mkdir -p build
cd build
CMAKE="C:/rtools45/x86_64-w64-mingw32.static.posix/bin/cmake.exe"
$CMAKE .. -DCMAKE_BUILD_TYPE=Release -G "MinGW Makefiles"
$CMAKE --build . --config Release
echo "Build complete. Binary copied to inst/bin/"

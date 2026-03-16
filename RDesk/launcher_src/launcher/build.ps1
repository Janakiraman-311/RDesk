$currentDir = Get-Location
$buildDir = "$currentDir/build"

if (Test-Path $buildDir) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Path $buildDir
Set-Location $buildDir

# Use forward slashes for Rtools paths to avoid MSYS2 escaping issues
$RTOOLS_BIN = "C:/rtools45/x86_64-w64-mingw32.static.posix/bin"
$RTOOLS_USR = "C:/rtools45/usr/bin"

# Export to environment
$env:PATH = "$RTOOLS_BIN;$RTOOLS_USR;$env:PATH"

$CMAKE = "$RTOOLS_BIN/cmake.exe"
$GXX = "$RTOOLS_BIN/g++.exe"
$GCC = "$RTOOLS_BIN/gcc.exe"
$MAKE = "$RTOOLS_USR/make.exe"

Write-Output "Using CMAKE: $CMAKE"
Write-Output "Using GXX: $GXX"
Write-Output "Using MAKE: $MAKE"

# Run CMake
& $CMAKE .. -G "MinGW Makefiles" `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DCMAKE_CXX_COMPILER=$GXX" `
    "-DCMAKE_C_COMPILER=$GCC" `
    "-DCMAKE_MAKE_PROGRAM=$MAKE" `
    "-DCMAKE_SH=CMAKE_SH-NOTFOUND"

# Run Build
& $CMAKE --build . --config Release

if (Test-Path "rdesk-launcher.exe") {
    Write-Output "Build SUCCESS!"
    # The CMakeLists.txt should have copied it to inst/bin/
} else {
    Write-Output "Build FAILED - binary not found in build directory"
}

Set-Location $currentDir

$RTOOLS_BIN = "C:/rtools45/x86_64-w64-mingw32.static.posix/bin"
$env:PATH = "$RTOOLS_BIN;$env:PATH"

$currentDir = Get-Location
$buildDir = "$currentDir/build_vs"

if (Test-Path $buildDir) {
    Remove-Item -Recurse -Force $buildDir
}
New-Item -ItemType Directory -Path $buildDir
Set-Location $buildDir

Write-Output "Attempting build with RTools CMake + VS 2022..."

# Use RTools cmake but VS generator
& cmake .. -G "Visual Studio 17 2022" -A x64

# Build
& cmake --build . --config Release

if (Test-Path "Release/rdesk-launcher.exe") {
    Write-Output "Build SUCCESS!"
} elseif (Test-Path "rdesk-launcher.exe") {
    Write-Output "Build SUCCESS!"
} else {
    Write-Output "Build FAILED"
}

Set-Location $currentDir

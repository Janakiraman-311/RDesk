# Run the Windows package check with an explicit Rtools environment.
# This does not bypass R CMD check; it only avoids shell PATH inheritance issues.

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot

$rCommand = Get-Command R.exe -ErrorAction SilentlyContinue
if ($rCommand) {
  $rExe = $rCommand.Source
} else {
  $rExe = Get-ChildItem "C:\Program Files\R\R-*\bin\R.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1 -ExpandProperty FullName
}
if (-not $rExe) {
  throw "R.exe was not found on PATH or under C:\Program Files\R."
}
$rtools = $env:RTOOLS45_HOME
if (-not $rtools) { $rtools = "C:\rtools45" }

$mingw = Join-Path $rtools "x86_64-w64-mingw32.static.posix\bin"
$usr = Join-Path $rtools "usr\bin"
$compiler = Join-Path $mingw "g++.exe"
if (-not (Test-Path $compiler)) {
  throw "Rtools compiler not found: $compiler"
}

# R's Windows Makeconf uses BINPREF for the C/C++ toolchain.
$env:Path = "$mingw;$usr;$env:Path"
$env:BINPREF = (($mingw -replace "\\", "/") + "/")
$env:R_PROFILE_USER = "NUL"
$env:R_ENVIRON_USER = "NUL"

$tempRoot = Join-Path $env:TEMP ("RDesk-check-" + [guid]::NewGuid().ToString("N"))
$status = 1
$pushed = $false

try {
  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  robocopy $repo $tempRoot /E /NFL /NDL /NJH /NJS `
    /XD .git .r-lib dist renv scratch RDesk.Rcheck ..Rcheck `
    /XF *.tar.gz *.zip | Out-Null
  if ($LASTEXITCODE -gt 7) {
    throw "Could not create the clean check copy (robocopy exit $LASTEXITCODE)."
  }

  Write-Host "R: $rExe"
  Write-Host "Rtools: $rtools"
  Write-Host "Compiler: $compiler"
  & $compiler --version | Select-Object -First 1

  Push-Location $tempRoot
  $pushed = $true
  & $rExe CMD build --no-manual --no-build-vignettes .
  $buildStatus = $LASTEXITCODE
  if ($buildStatus -ne 0) {
    throw "R CMD build failed."
  }

  $package = Get-ChildItem -File -Filter "RDesk_*.tar.gz" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $package) {
    throw "R CMD build did not produce an RDesk source tarball."
  }

  Write-Host "Checking: $($package.FullName)"
  & $rExe CMD check --as-cran --no-manual --no-build-vignettes $package.FullName
  $status = $LASTEXITCODE
} finally {
  if ($pushed) { Pop-Location -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

exit $status

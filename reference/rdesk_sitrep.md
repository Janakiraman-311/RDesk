# Check RDesk environment and toolchain readiness

Reports the current R version, RDesk package version, native launcher
binary location, WebView2 Runtime availability (on Windows), C++
compiler (`g++`), Inno Setup (`ISCC.exe`), and 7-Zip (`7z.exe`).

## Usage

``` r
rdesk_sitrep()
```

## Value

A named list of detected paths and status values (invisibly).

## Examples

``` r
info <- rdesk_sitrep()
#> [RDesk sitrep] R: 4.5.1 (Windows) | RDesk: 1.0.7
#>   Launcher : D:/a/_temp/Library/RDesk/bin/rdesk-launcher.exe
#>   WebView2 : 156.0.4314.58
#>   g++      : C:\rtools45\X86_64~1.POS\bin\G__~1.EXE
#>   ISCC.exe : C:\PROGRA~3\CHOCOL~1\bin\ISCC.exe
#>   7-Zip    : C:\PROGRA~3\CHOCOL~1\bin\7z.exe
str(info)
#> List of 8
#>  $ r_version    : chr "4.5.1"
#>  $ platform     : chr "Windows"
#>  $ rdesk_version: chr "1.0.7"
#>  $ launcher_path: chr "D:/a/_temp/Library/RDesk/bin/rdesk-launcher.exe"
#>  $ webview2     : chr "156.0.4314.58"
#>  $ gpp_path     : Named chr "C:\\rtools45\\X86_64~1.POS\\bin\\G__~1.EXE"
#>   ..- attr(*, "names")= chr "g++"
#>  $ iscc_path    : chr "C:\\PROGRA~3\\CHOCOL~1\\bin\\ISCC.exe"
#>  $ sevenzip_path: chr "C:\\PROGRA~3\\CHOCOL~1\\bin\\7z.exe"
```

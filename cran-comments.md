## R CMD check results

0 errors | 1 warning | 3 notes

### Warning

* `inst/include/nlohmann/json.hpp` contains diagnostic suppression pragmas.
  This file is the nlohmann/json v3 single-header library, a widely-used
  MIT-licensed C++ JSON library vendored directly into the package to avoid
  external dependencies. The pragmas suppress known false-positive warnings
  from MSVC and GCC when compiling third-party code. This is standard
  practice for vendored C++ headers.

### Notes

* New submission — expected.

* Maintainer email — I will respond promptly to the CRAN confirmation email.

* Non-portable C++ flag `-mwindows` in src/Makevars.win. This flag is
  required for Windows GUI applications to suppress the console window
  when launching the native WebView2 window. It is only present in
  Makevars.win and only applies on Windows. The package declares
  OS_type: windows in DESCRIPTION as this package is inherently
  Windows-specific (it wraps Win32 APIs and Microsoft WebView2).

## Package notes

This package is Windows-only (OS_type: windows). It wraps Win32 APIs
and the Microsoft WebView2 runtime which are not available on other
platforms. Installation on Linux/macOS will fail with an informative
error message.

The compiled launcher in src/ intentionally writes JSON to stdout as
the designed IPC communication channel between the native window and
the R backend process. This is not debug output -- it is the core
messaging protocol of the framework.

build_app() downloads a portable R runtime at app packaging time only,
not at package install time. All examples and vignettes calling
build_app() are wrapped in \dontrun{}.

Checked with devtools::check_win_devel() and devtools::check_win_release()
on DATE. No ERRORs. No WARNINGs. Notes as described above.

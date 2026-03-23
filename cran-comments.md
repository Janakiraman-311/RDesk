## R CMD check results (v1.0.0)

0 errors | 1 warning | 2 notes

Full package documentation and vignettes are available at:
https://janakiraman-311.github.io/RDesk/

### Warning

* Two vendored third-party C++ headers contain diagnostic suppression pragmas:

  1. `inst/include/nlohmann/json.hpp` -- the nlohmann/json v3 single-header
     library, a widely-used MIT-licensed C++ JSON library. The pragmas
     suppress known false-positive warnings from MSVC and GCC when
     compiling third-party code.

  2. `src/webview/webview.h` -- the webview library header providing the
     cross-platform WebView2 wrapper. The pragmas suppress platform-specific
     compiler warnings in the third-party integration layer.

  Both files are vendored unchanged from their upstream sources and are
  standard practice for C++ projects embedding third-party headers.

### Notes

* Possibly misspelled words (RDesk, UI, WebView, callr, mirai): These are
  technical terms specific to this package and its dependencies. All have
  been added to inst/WORDLIST.

* New submission -- expected.

* Non-portable C++ flag `-mwindows` in src/Makevars.win. Required for
  Windows GUI applications to suppress the console window when launching
  the native WebView2 window. Only present in Makevars.win, only applies
  on Windows. Package declares OS_type: windows in DESCRIPTION.

## Release Hardening (v1.0.0)

The v1.0.0 release incorporates several stability features:
- Professional platform guard for macOS/Linux users.
- Automated system tray integration and auto-update plumbing.
- Optimized bundle size (~60MB with runtime pruning).

## Winbuilder results

Checked with devtools::check_win_devel() on 2026-03-23.
Status: 1 WARNING, 2 NOTEs -- all documented above.
Installation: OK
Check: OK
R version: 4.5.3 (2026-03-22 r89674 ucrt)
Launcher compiled successfully: rdesk-launcher.exe built via src/Makevars.win

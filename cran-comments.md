## Resubmission (v1.0.1)

This is a resubmission to address the automated points raised in the 2026-03-24 incoming pre-test. 

I would like to clarify that the identified WARNING and NOTEs are intentional and critical for the package's operation as a native Windows GUI framework:

1. **C++ Pragmas (WARNING)**: These exist in the vendored third-party headers `nlohmann/json` and `webview.h` to suppress platform-specific diagnostic noise (e.g., MSVC/GCC warnings). They are standard for these widely-used libraries.
2. **Technical Terms (NOTE)**: Terms such as 'RDesk', 'mirai', 'callr', and 'WebView' are technical names specific to this package and its dependencies. They have been added to the package WORDLIST.
3. **-mwindows Flag (NOTE)**: This is required in `Makevars.win` to ensure the application launches as a Windows GUI without an attached console window.

## R CMD check results (v1.0.1)

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

* Possibly misspelled words: 'RDesk', 'UI', 'WebView', 'callr', 'mirai'.
  These are technical terms and have been added to `inst/WORDLIST`.

* New submission -- expected.

* Non-portable C++ flag `-mwindows` in src/Makevars.win. Required for
  Windows GUI applications to suppress the console window when launching
  the native WebView2 window.

## Winbuilder results

Checked with devtools::check_win_devel() on 2026-03-23.
Status: 1 WARNING, 2 NOTEs -- all documented above.
Installation: OK
Check: OK
R version: 4.5.3 (2026-03-22 r89674 ucrt)
Launcher compiled successfully: rdesk-launcher.exe built via src/Makevars.win

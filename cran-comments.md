## Resubmission (1.0.2)

Changes in response to CRAN reviewer feedback from Uwe Ligges (2026-03-24):

* Removed all pragma suppression directives from vendored third-party
  headers inst/include/nlohmann/json.hpp and src/webview/webview.h
  as requested.
* Added single quotes around all software names in the Title and
  Description fields of DESCRIPTION as requested.

## R CMD check results

0 errors | 0 warnings | 2 notes

* New submission -- expected.
* Non-portable flag -mwindows: acceptable per reviewer confirmation.

## Notes on package design

OS_type: windows -- wraps Win32 APIs and Microsoft WebView2 runtime
which are unavailable on other platforms. Debian pre-check correctly
skips installation.

Checked with devtools::check_win_devel() and devtools::check_win_release().

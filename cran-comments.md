## Resubmission (1.0.5)

This is a patch update fixing a production bug discovered after the initial
CRAN acceptance of 1.0.4.

### Change summary

* `build_app()` now copies the developer's installed R as the app runtime
  by default (`runtime_dir = NULL`), instead of downloading a fixed R 4.4.2
  portable build. This eliminates crashes caused by a version mismatch between
  the downloaded R runtime and packages compiled for the developer's current
  R version (e.g. 4.5.x via renv).
* The legacy download behaviour is preserved via `runtime_dir = "download"`
  for backwards compatibility in CI/air-gapped environments.
* Added two internal helpers: `rdesk_detect_r_home()` and `rdesk_copy_r_runtime()`.

### R CMD check results

0 errors | 0 warnings | 2 notes

* Previously published package -- standard note.
* `-mwindows` flag: confirmed acceptable by Uwe Ligges (2026-03-24).

## Acronyms and Technical Terms

* IPC: Inter-Process Communication (standard R stdin/stdout pipes).
* Win32: Windows API (used for the native launcher and WebView2).
* 'R6': Reference class system for R.
* 'WebView2': Microsoft's Chromium-based web control for desktop apps.

## Console Output Justification

RDesk uses `cat()` specifically in `R/App.R` to send JSON messages to the 
native launcher's standard input. These calls are essential for the 
package's core functionality (the Zero-Port IPC bridge) and cannot be 
replaced with `message()` because the launcher specifically listens only 
to the stdout stream.

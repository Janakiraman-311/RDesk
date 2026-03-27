## Resubmission (1.0.4)

Responding to review by Konstanze Lauseker (2026-03-24) and 
Uwe Ligges (2026-03-24).

* Replaced \dontrun{} with \donttest{} or if(interactive()){} throughout.
  Functions opening native windows wrapped in if(interactive()){}.
  Long-running functions wrapped in \donttest{}.
  Fast safe examples unwrapped entirely.

* Executable R code chunks added to all six vignettes and verified 
  to run cleanly under R CMD check with eval=TRUE.

* All examples and default paths now write to tempdir() only.
  No writes to user home filespace or getwd().

* Added on.exit() immediately after every setwd() and options()
  call in R/build.R with add = TRUE.

* Replaced all installed.packages() calls with requireNamespace(),
  system.file(), or utils::packageVersion() as appropriate.

* Added executable R code chunks to all six vignettes. Each chunk
  runs in under 5 seconds without opening windows or writing files.

* Added copyright holders for all vendored third-party code to
  Authors@R with cph roles: Serge Zaitsev (webview.h), Niels Lohmann
  (nlohmann/json), Microsoft Corporation (WebView2 SDK).
  Created inst/COPYRIGHTS listing licenses for all vendored components.

* Removed all non-portable pragmas (`#pragma GCC diagnostic`) from 
  vendored C++ headers (`webview.h` and `json.hpp`).

## R CMD check results

0 errors | 0 warnings | 2 notes

* New submission -- expected.
* -mwindows flag: confirmed acceptable by Uwe Ligges (2026-03-24).

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

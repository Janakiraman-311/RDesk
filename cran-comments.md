## Resubmission (1.0.4)

Changes in response to CRAN reviewer Konstanze Lauseker (2026-03-24):

* Replaced \dontrun{} with \donttest{} or if(interactive()){} throughout.
  Functions opening native windows wrapped in if(interactive()){}.
  Long-running functions wrapped in \donttest{}.
  Fast safe examples unwrapped entirely.

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

## R CMD check results

0 errors | 0 warnings | 2 notes

* New submission -- expected.
* -mwindows flag: confirmed acceptable by Uwe Ligges (2026-03-24).

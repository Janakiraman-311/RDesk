## RDesk 1.0.7

This is a new submission following an earlier 1.0.6 submission. Since that
submission, RDesk has been extended to support development and application
bundling on Windows, macOS, and Linux.

### Change summary

* Added the cross-platform build and launcher foundation for macOS and Linux.
* Added HTML/JavaScript dialog fallbacks for non-Windows platforms.
* Hardened asynchronous jobs, storage, single-instance handling, and bundled
  application startup.
* Added reproducible-build support through optional `renv` integration.
* Updated package documentation and examples for the cross-platform API.

### System requirements

* Windows requires the Microsoft WebView2 Runtime.
* macOS requires Apple Clang/Xcode Command Line Tools.
* Linux source builds require GTK+ 3 and WebKitGTK development libraries.

The package does not download or install these system components during
`R CMD check`. Native launcher builds are exercised separately by the
project's platform-specific CI workflows.

### Checks

Final `R CMD check --as-cran` results will be recorded here after the release
candidate has been checked with current R release, R-patched/R-devel,
Winbuilder, and macbuilder. The package test suite is run separately on
Windows, macOS, and Linux in GitHub Actions.

No native application window is launched by package examples or CRAN tests.
Application bundle and launcher smoke tests are kept in the separate build
workflow because they require platform GUI/toolchain components.

### Response to previous review comments

* Examples and vignette execution avoid launching native windows. Long-running
  or interactive operations are guarded with `if (interactive())`; the
  executable vignettes use temporary, side-effect-free status checks.
* Build staging and temporary artifacts are created below `tempdir()`, and
  working-directory and option changes are restored with `on.exit()`.
* Package discovery uses `find.package()` and package metadata rather than
  `installed.packages()` in package code.
* `build_app()` does not install packages or contact a package repository. It
  copies the already-installed dependency closure; CI installs dependencies
  before invoking the build.
* Source-tree bundling uses optional `pkgbuild` rather than requiring the
  heavier `devtools` package at runtime.
* Vendored webview and JSON code has been listed in `Authors@R` and
  `inst/COPYRIGHTS`, including the copyright holders credited by the upstream
  headers.

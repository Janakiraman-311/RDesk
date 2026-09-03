## RDesk 1.0.7 Submission

This is a maintenance and feature update for RDesk following the 1.0.5 CRAN release, focusing on stability, reliability, and packaging improvements for Windows desktop applications.

### Test environments
* local Windows 11 x64 (build 26200), R 4.5.1 (ucrt)
* win-builder (R Under development 2026-08-31 r90457 ucrt)
* GitHub Actions `windows-latest`, R 4.5.1

### R CMD check results
There were 0 errors | 0 warnings | 1 note.

* checking compilation flags used ... NOTE
  Compilation used the following non-portable flag(s):
    '-mwindows'

  Explanation: The '-mwindows' flag is intentional and required for Windows GUI executables to ensure the native desktop window opens cleanly without creating an unwanted console window alongside the user interface. This was confirmed as acceptable by CRAN reviewer Uwe Ligges during the v1.0.2 review.

### Method References
There are no published references describing the methods in this package. The package implements original software architecture for packaging and running desktop applications using native R processes, IPC pipes, and the Microsoft WebView2 control.

### Change summary
* **App Bundling & Runtime Stability**: Hardened `build_app()` with unified input validation, R runtime version tolerance, and automatic exclusion of build-time header packages (`LinkingTo`) to avoid missing dependency errors.
* **Process Management & Window Bridging**: Added `rdesk_open_window()` with robust `processx` pipes, `READY` handshakes, and native process lifetime controls.
* **Auto-Updater Engine**: Enhanced `rdesk_auto_update()` with installer invocation, safe temporary staging, and version comparisons.
* **Storage Isolation**: Hardened persistent storage paths (`%LOCALAPPDATA%`, `%APPDATA%`) with fallback tempdir validation for restricted permission environments.
* **IDE & Working Directory Resolution**: Fixed app directory path resolution in Positron and RStudio when sourcing across active editor tabs.
* **Template Scaffolding**: Improved dynamic development loader and initial chart state for scaffolded applications.

### System requirements
Windows requires the Microsoft WebView2 Runtime (pre-installed on Windows 10/11). The package does not download or install system components during `R CMD check`. Native launcher builds are exercised separately by project CI workflows.

### Response to previous review comments
* Examples and vignette execution avoid launching native windows during checks. Long-running or interactive operations are guarded with `if (interactive())`.
* Build staging and temporary artifacts are created below `tempdir()`, and working-directory and option changes are restored with `on.exit()`.
* Package discovery uses `find.package()` and package metadata rather than `installed.packages()`.
* `build_app()` does not install packages or contact a package repository at check time.
* Vendored webview and JSON code is fully credited in `Authors@R` with `cph` roles and in `inst/COPYRIGHTS`.

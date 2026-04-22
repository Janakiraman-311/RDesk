# RDesk 1.0.5 (2026-04-22) — Runtime Fix

## Bug fixes

* `build_app()` now copies the developer's currently running R installation
  as the app runtime by default (`runtime_dir = NULL`). Previously it
  downloaded a fixed R 4.4.2 portable build which caused crashes in
  distributed apps when packages had been compiled for a newer R version
  (e.g. 4.5.x via `renv`). The version mismatch between the downloaded
  runtime and the bundled packages produced a cryptic shared-library ABI
  error on launch.

* Added `rdesk_detect_r_home()` (internal) which resolves the developer's
  R installation path via `R.home()` with a clear error if it is not found.

* Added `rdesk_copy_r_runtime()` (internal) which selectively copies
  `bin/`, `library/`, `etc/`, `modules/`, and `include/` from the source
  R installation into the bundle staging directory.

* The legacy download behaviour is preserved for CI environments or
  air-gapped scenarios via `runtime_dir = "download"`. A warning is
  printed advising users to prefer the default to avoid version mismatch.

# RDesk 1.0.4 (2026-04-01) — First CRAN Release 🎉

## CRAN compliance fixes

* Replaced all `\dontrun{}` with `if(interactive()){}` or `\donttest{}` as
  appropriate. Functions that open native windows are now wrapped in
  `if(interactive()){}`.
* Executable R code chunks added to all six vignettes and verified to run
  cleanly under `R CMD check`.
* All file-writing operations now default to `tempdir()`. No default paths
  write to the user's home filespace.
* `on.exit()` added immediately after every `setwd()` and `options()` call
  inside `build_app()`.
* Replaced all `installed.packages()` calls with `requireNamespace()` or
  `system.file()`.
* Added copyright holders for all vendored third-party code to `Authors@R`
  with `cph` roles: Serge Zaitsev (webview.h), Niels Lohmann (nlohmann/json),
  Microsoft Corporation (WebView2 SDK). Created `inst/COPYRIGHTS`.

# RDesk 1.0.0 (2026-03-22)

## New features

* **Native Window Management**: Added `app$set_size()`, `app$set_position()`, `app$minimize()`, `app$maximize()`, `app$restore()`, `app$fullscreen()`, and `app$always_on_top()`.
* **Enhanced Native Dialogs**: Implemented `app$dialog_folder()`, `app$message_box()` (OK/Yes/No/Cancel with icons), and `app$dialog_color()`.
* **System Integration**:
    * **Recursive Menus**: Native Win32 menu bars now support arbitrarily deep nesting and checkable items.
    * **System Tray Context Menus**: Added `app$set_tray_menu()` for native right-click interaction.
    * **Global Hotkeys**: Added `app$register_hotkey()` for system-wide keyboard shortcuts.
    * **Clipboard**: Added `app$clipboard_read()` and `app$clipboard_write()`.
* **Lifecycle & Stability Hardening**:
    * **Anti-Zombie Watchdog**: Native launcher now auto-terminates if the parent R process dies.
    * **Single-Instance Lock**: Prevents running multiple copies of the same application.
    * **Close Interception**: Added `app$on_close()` to intercept or cancel window exit attempts.
    * **Persistent Logging**: Success and error logs are now written to `%LOCALAPPDATA%/RDesk`.
* **Auto-Updater**: Added `app$check_update()` to detect and link to remote application updates.
* **renv integration**: The RDesk development environment and built bundles are now lockable via `renv.lock` for reproducible distribution.

## Bug fixes

* Fixed COM reference count leaks and Unicode path handling in the native launcher.
* Resolved R6 namespace collisions during complex application initialization.
* Hardened `build_app(dry_run = TRUE)` for rapid environment validation.
* Fixed plot rendering synchronization in background worker pools.

# RDesk 0.9.0 (2026-03-19)

## Breaking changes

* Removed httpuv dependency entirely. Apps built with earlier
  versions must be rebuilt with the new launcher.

## New features

* Zero-port native IPC architecture using WebView2
  PostWebMessageAsString and stdin/stdout pipe.
* Virtual hostname mapping via SetVirtualHostNameToFolderMapping --
  app assets load from disk with no HTTP server.
* Three-tier async engine: async() wrapper, rdesk_async(),
  and direct mirai access. 5.9x faster task startup vs callr alone.
* Loading overlay system with progress bar, cancellation,
  and toast notifications built into the framework.
* build_app() now supports build_installer = TRUE for InnoSetup
  Windows installer generation.
* rdesk_create_app() scaffold generates a complete working app
  structure ready to run.
* GitHub Actions CI/CD with three workflows: R-CMD-check,
  build-app, and release.
* Comprehensive error logging -- crash.log and rdesk_startup.log
  written on failure. Native Windows popup on crash.
* System tray, native menus, file dialogs, toast notifications.

## Bug fixes

* Fixed bundled dialog, tray, notify, and IPC command handling in
  `App.R` so packaged apps no longer try to write to a null window
  process handle.
* Hardened launcher shutdown, notification handling, request IDs,
  menu/tray updates, and save-dialog Unicode handling across the
  native C++ launcher and `window.R`.
* Fixed bundled stub logging and stdout handling so packaged apps
  preserve IPC while still writing crash diagnostics.
* Fixed scaffolded apps and demo apps so bundled mode no longer sinks
  stdout, app paths resolve more reliably, and generated tests/plots
  use safer defaults.
* Fixed `build_app()` package bundling, temp cleanup, empty-directory
  copies, and added explicit portable-R strategies via
  `portable_r_method` and `runtime_dir`.
* Fixed GitHub Actions bundled-app workflows to use explicit installer
  runtime provisioning and current setup actions.
* Fixed COM reference count leak in C++ launcher on shutdown.
* Replaced hardcoded personal paths with dynamic environment
  variable lookups in build.R.
* Fixed duplicate publisher parameter in build_app() signature.
* Corrected R-CMD-check YAML quoting for args and error-on fields.
* Removed dead httpuv private fields from App R6 class.
* Fixed @export tags incorrectly placed on private R6 methods.
* Unicode path handling hardened using MultiByteToWideChar
  throughout C++ launcher.

## Internal changes

* IPC message envelope standardised with id, type, version,
  payload, timestamp fields across R and JavaScript.
* Version centralised via getOption("rdesk.ipc_version").
* CI guard added -- headless environments skip native window init.
* mirai daemon pool pre-warmed at App$run() and shut down cleanly
  at App$cleanup().

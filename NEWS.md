# RDesk 1.0.0 (2026-03-22)

## New features

* renv integration -- the RDesk development environment is now lockable
  via `renv.lock` for reproducible builds across machines and contributors.
* `build_app()` now writes an `renv.lock` file and `restore_env.R` helper
  into every distributable bundle so package versions can be inspected and
  restored later.

## Bug fixes

* Added `broom` to `Suggests` for demo-app and check-time dependency
  completeness.
* Updated GitHub Actions workflows to restore a locked renv environment
  before checks and bundled-app builds when a project lockfile is present.

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

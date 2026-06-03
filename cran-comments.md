## Resubmission (1.0.6)

This is a feature and bug-fix update following the 1.0.5 patch release on CRAN.

### Change summary

**New features (Windows-only — package has OS_type: windows)**

* **Live Hot Reload** (`rdesk_watch()`): monitors `R/` and `www/` directories
  during development and reloads changed files without restarting the app.
* **Async Progress API** (`async_progress()`): lets background worker tasks
  report real-time progress percentages back to the WebView2 loading overlay.
* **Multi-User Storage Isolation** (`rdesk_storage()`, `RDeskStorage`):
  key-value storage managers automatically mapped to `%APPDATA%`,
  `%LOCALAPPDATA%`, and `%PROGRAMDATA%` via `app$prefs`, `app$recent`, and
  `app$shared`. Includes write-permission checks and temp-directory fallbacks.
* **Hardened Single-Instance Lock**: launcher now detects duplicate launches,
  restores minimized windows, and brings the existing window to the foreground.
* Added `mori` to `Suggests` for optional zero-copy shared memory across
  async workers (see new Cookbook vignette recipe).

**New helper exports**

* `rdesk_async()`, `async()` -- background task management wrappers.
* `rdesk_cancel_job()`, `rdesk_jobs_pending()`, `rdesk_jobs_list()`.
* `rdesk_df_to_list()`, `rdesk_plot_to_base64()`, `rdesk_error_plot()` --
  data and plot utilities for app server code.

**Bug fixes**

* `build_app()` now strips developer artifacts (`.Rprofile`, `renv/`,
  `renv.lock`, `.git/`, `.gitignore`, `tests/`) from the bundled app directory.
  Previously a stray `.Rprofile` could source `renv/activate.R` on startup,
  hijacking `.libPaths()` and crashing the distributed app with Error Code 1.
* Fixed mirai error class name (`miraiError` not `mirai_error`) in the async
  job polling loop; errors in background workers now correctly route to the
  `on_error` callback instead of silently crashing the JSON serializer.
* Fixed mirai daemon workers inheriting `.libPaths()` from the main process,
  allowing bundled packages in `packages/library/` to load inside workers.
* Fixed `mirai::mirai()` argument collision: internal variables renamed from
  `.task`/`.args` to avoid shadowing mirai's formal parameters.

### R CMD check results

0 errors | 0 warnings | 1 note (win-builder) / up to 2 notes (local)

**Note 1** - `-mwindows` compilation flag:
Confirmed acceptable by Uwe Ligges (2026-03-24). Required to suppress the
Windows console window for the native GUI launcher binary.

**Note 2** - `unable to verify current time` (local only):
Appears only when the local machine cannot reach an NTP server. This note
did NOT appear on win-builder. CRAN servers have unrestricted internet access.

## Acronyms and Technical Terms

* IPC: Inter-Process Communication (standard R stdin/stdout pipes).
* Win32: Windows API (used for the native launcher and WebView2).
* 'R6': Reference class system for R.
* 'WebView2': Microsoft's Chromium-based web control for desktop apps.
* '%APPDATA%', '%LOCALAPPDATA%', '%PROGRAMDATA%': Standard Windows
  user-data environment variables.

## Console Output Justification

RDesk uses `cat()` in `R/App.R` to send JSON messages to the native launcher's
standard input. These calls are essential for the package's core functionality
(the Zero-Port IPC bridge) and cannot be replaced with `message()` because the
launcher specifically listens only to the stdout stream.


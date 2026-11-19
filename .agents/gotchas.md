# RDesk Known Gotchas, Challenges & Proven Fixes

Hard-won lessons from debugging Windows, macOS, Linux, WebView2, `Rapp`, and GitHub Actions CI. Check this file first when anything behaves unexpectedly.

---

## 1. Windows GUI & Launcher Gotchas

### Antigravity Terminal Runs on a Hidden `exebox-...` Desktop
- **Symptom**: Running `app.R` or `rdesk demo cars` inside Antigravity's built-in terminal (or agent `run_command`) logs `[RDesk] Window opened: https://app.rdesk/index.html`, IPC succeeds, `rdesk-launcher.exe` runs with 10+ threads, yet **no window appears on the monitor** and `MainWindowHandle` reads `0`.
- **Cause**: Antigravity's `language_server.exe` executes terminals on a sandboxed Windows Desktop (`exebox-...`) separate from the user's visible `WinSta0\Default` desktop. Also, a stray `rdesk-launcher.exe` left running on `exebox-...` still holds the single-instance named mutex `Local\RDesk_Instance_<hash>`, blocking launches from an external terminal!
- **Fix**: Always launch GUI apps from an **external Windows Terminal / PowerShell (from Start Menu) or RStudio**, and kill any stray hidden-desktop `rdesk-launcher.exe` processes (`Stop-Process -Name rdesk-launcher -Force`) before testing.

### Win32 `ShowWindow()` First-Call `STARTUPINFO` (`SW_HIDE`) Trap
- **Symptom**: When `processx` or a headless parent spawns `rdesk-launcher.exe` with `STARTF_USESHOWWINDOW` + `SW_HIDE`, Windows ignores the `nCmdShow` argument on the very first `ShowWindow(m_window, SW_SHOW)` call inside `webview.h`, leaving the window hidden.
- **Fix**: Call `ShowWindow(m_window, SW_SHOW)` followed by `ShowWindow(m_window, SW_SHOWNORMAL)` in `src/webview/webview.h` and `ShowWindow(g_hwnd, SW_SHOWNORMAL); UpdateWindow(g_hwnd); SetForegroundWindow(g_hwnd);` in `src/launcher.cpp`.

### Shared WebView2 `userDataFolder` Multi-App Collision
- **Symptom**: Launching a second RDesk app while one is already running fails with `[RDesk] Launcher failed to start correctly` (`WEBVIEW_ERROR_INVALID_STATE`).
- **Fix**: Isolate `WEBVIEW2_USER_DATA_FOLDER` per app in `src/launcher.cpp` (`%APPDATA%\RDesk_WebView2\RDesk_Instance_<title_hash>`) and honor `WEBVIEW2_USER_DATA_FOLDER` in `src/webview/webview.h`.

### `processx` Unread `stderr = "|"` Pipe Deadlock
- **Symptom**: Long-running launcher sessions freeze when GTK/WebKit/WebView2 writes >64 KB of diagnostic chatter to stderr.
- **Fix**: Always pass `stderr = log_file` (file redirection, never `"|"`) in `R/window.R`.

### Second-Instance Focus After Dynamic `app$set_title()`
- **Symptom**: `FindWindowW(NULL, title)` misses an already-running window whose title changed at runtime.
- **Fix**: Tag `g_hwnd` with `SetPropW(g_hwnd, instance_prop, 1)` on startup and fall back to `EnumWindows` + `GetPropW` in `src/launcher.cpp`. Also open the native window *before* `rdesk_start_daemons()` in `R/App.R` so a second instance exiting on `ALREADY_RUNNING` never leaks `mirai` daemons.

---

## 2. R Packaging, `renv`, & `Rapp` CLI Gotchas

### `renv` Cache vs. Global `win-library\4.5` Mismatch
- **Symptom**: `rdesk --help` from `C:\Users\Janak` fails with `there is no package called 'Rapp'`, or `rdesk_create_app()` generates an older template.
- **Cause**: Running `R CMD INSTALL .` inside the repo installs into `renv`'s cache library, whereas commands run from outside the repo use `C:\Users\Janak\AppData\Local\R\win-library\4.5`.
- **Fix**: Install updated `RDesk` (and `Rapp`) into **both** `win-library\4.5` and `renv`.

### `Rapp` `--default-packages=base,RDesk` Leakage
- **Symptom**: Apps launched through `rdesk run` fail on `lm()`, `write.csv()`, or `mtcars` because `stats`, `utils`, `datasets`, and `methods` aren't attached.
- **Fix**: `rdesk_run()` strips `R_DEFAULT_PACKAGES` from the child environment (`child_env <- child_env[names(child_env) != "R_DEFAULT_PACKAGES"]`) before spawning `Rscript`.

### Detached `rdesk demo starter --detach` Tempdir Deletion
- **Symptom**: Launching `rdesk demo starter --detach` fails immediately after the CLI returns because R deletes the short-lived CLI process's `tempdir()`.
- **Fix**: When `detach = TRUE` (outside `rdesk.ci_mode`), `rdesk_demo("starter")` stages the scaffold under `tools::R_user_dir("RDesk", which = "cache")`.

### `roxygen2` Dropping `export(rdesk_message)` from `NAMESPACE`
- **Symptom**: Vignette build (`cookbook.Rmd`) fails with `'rdesk_message' is not an exported object from 'namespace:RDesk'`.
- **Cause**: An internal helper (`.rdesk_msg_id_counter`) placed directly between a roxygen `@export` block and `rdesk_message <- function(...)` causes `roxygen2` to attach `@export` to the internal helper instead.
- **Fix**: Always place internal helpers *above* the roxygen block of the exported function they support, and verify `NAMESPACE` after `devtools::document()`.

### `rdesk_resolve_www()` Auto-Copying `www/rdesk.js`
- **Symptom**: Untracked `inst/apps/data_studio/www/rdesk.js` or modified `inst/templates/hello/www/rdesk.js` appears in `git status` after running tests or apps.
- **Cause**: `App$new()` copies `inst/www/rdesk.js` into `www/rdesk.js` when it doesn't exist at the `www/` root (`data_studio` keeps it at `www/js/rdesk.js`).
- **Fix**: Check `git status --short` and clean untracked `www/rdesk.js` copies before committing.

### `devtools::load_all()` Concurrent Recompile Lock on Windows
- **Symptom**: Launching two apps in dev mode simultaneously fails with `Permission denied` on `src/RDesk.dll` or `src/rdesk-launcher.exe` after a `git checkout` touches `src/launcher.cpp`.
- **Fix**: Keep `src/dummy.o`, `src/RDesk.dll`, and `src/rdesk-launcher.exe` timestamps synced after manual builds or branch switches.

---

## 3. Compiler, Installer & CI Gotchas

### GCC 14 `-Wunknown-pragmas` Under `R CMD INSTALL`
- **Cause**: MSVC-only `#pragma comment(lib, ...)` in `src/launcher.cpp` and `#pragma warning(...)` in `WebView2.h` trigger warnings under MinGW `g++ -Wall -pedantic`.
- **Fix**: Guard all MSVC pragmas with `#ifdef _MSC_VER ... #endif`.

### Inno Setup 64-Bit WebView2 Registry Detection & Install Scope
- **Cause**: Edge WebView2 registers under `Software\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}` on 64-bit Windows.
- **Fix**: Check both 64-bit and `WOW6432Node` keys across `HKLM` and `HKCU` in `inst/installer/template.iss`, and use `{autopf}\{#AppName}` for `DefaultDirName`.

### Ubuntu GitHub Actions `r-lib/actions/setup-r@v2` Exit Code 100
- **Symptom**: `E: Unable to fetch some archives, maybe run apt update or try with --fix-missing?` inside `setup-r@v2` on `ubuntu-latest`.
- **Fix**: Before `setup-r@v2`, write `Acquire::Retries "5";` and `APT::Get::Fix-Missing "true";` to `/etc/apt/apt.conf.d/80-retries` and run `sudo apt-get update --fix-missing`.

### Unix Executable Bit on `exec/rdesk.R`
- **Cause**: Creating `exec/rdesk.R` on Windows commits it with mode `100644`.
- **Fix**: Run `git update-index --chmod=+x exec/rdesk.R` so git tracks it as `100755` for macOS and Linux.

### `rdesk.send("__toast__")` Direction Trap in JS Apps
- **Cause**: `__toast__` is an **R $\rightarrow$ JS** event handled by `rdesk.js`, not a JS $\rightarrow$ R handler. Calling `rdesk.send("__toast__", ...)` from client JS silently drops unless registered on the R side.
- **Fix**: Render client-initiated toasts directly in DOM/JS (e.g., `#studio-toast-stack`), and reserve `app$toast()` for R-initiated notifications.

### macOS Bundled App Segfault via Host `R_LIBS_USER` Dual-`libR.dylib` Load
- **Symptom**: A bundled macOS `.app` crashes with `*** caught segfault *** address 0x3ea50, cause 'invalid permissions'` inside `dyn.load()` when an optional hook (e.g., `ggplot2::.onLoad()` calling `requireNamespace("dplyr", quietly = TRUE)`) runs for a package not bundled in the app.
- **Cause**: Setting only `R_LIBS` without pinning `R_LIBS_USER` and `R_LIBS_SITE` lets R's `Renviron` (`R_LIBS_USER=${R_LIBS_USER:-~/Library/R/...}`) keep the host user's library in `.libPaths()`. Loading a host `.so` linked to `/Library/Frameworks/R.framework/.../libR.dylib` inside a bundled R process (using `Contents/Resources/R-runtime/R/lib/libR.dylib`) loads two `libR.dylib` instances and segfaults on ARM64.
- **Fix**: `inst/stub/stub_macos.c`, `src/stub_macos.c`, and `inst/stub/stub_linux.c` explicitly pin `R_LIBS_USER` and `R_LIBS_SITE` to the bundled library paths so `.libPaths()` is 100% hermetically isolated from the host machine.

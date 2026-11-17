# RDesk Windows Review (v1.0.7)

> [!NOTE]
> Findings originally came from source inspection on `main` @ `e59d161`. Items marked **[Implemented]** below have since been implemented and verified with unit tests and native compilation (`rdesk-launcher.exe`). Line numbers below refer to the original baseline before fixes.
> **SAFE** means a low-risk fix that doesn't change the public API.

## Summary

| # | Sev | Area | Finding | Status |
|---|---|---|---|---|
| 1 | HIGH | Auto-update | No https enforcement, checksum or signature check before running the downloaded installer | **Implemented** (`https://` in `rdesk_auto_update` & `check_update`, optional `sha256` & `verify_signature`) |
| 2 | HIGH | Auto-update | Installer launch fails silently (unquoted path; admin elevation), then the app quits anyway | **Implemented** (`cmd /c start ""`, `shQuote`, quit only on success) |
| 3 | HIGH | Launcher | No navigation or message-origin filtering: a remote page could call R handlers | **Implemented** (`NavigationStarting`, `NewWindowRequested`, `get_Source` origin check) |
| 4 | HIGH | Launcher | DevTools and debug menu are on in every shipped app | **Implemented** (gated on `RDESK_DEBUG`, `AreDevToolsEnabled`/`AreDefaultContextMenusEnabled` FALSE) |
| 5 | MED | Installer | `PrivilegesRequired=admin`, so there's no per-user install | **Implemented** (`PrivilegesRequired=lowest` + override allowed) |
| 6 | MED | Installer | Missing 64-bit install mode, so the app lands in `Program Files (x86)` | **Implemented** (`x64compatible` + `UninstallDisplayIcon`) |
| 7 | MED | Installer | `AppId` comes from crc32 of the name, so renaming the app breaks upgrades | **Implemented** (`Config/RDesk/AppId` or `AppId` in DESCRIPTION, fallback preserved) |
| 8 | MED | Build | `.iss` and stub C++ values aren't escaped (quote/backslash injection) | **Implemented** (`app_name` validation + C++/ISS escaping helpers) |
| 9 | MED | Build | g++ and ISCC exit codes are ignored, so a broken bundle still reports "Done" | **Implemented** (exit codes and output binaries checked) |
| 10 | MED | Launcher | A second launch shows an error dialog instead of focusing the open window | **Implemented** (`ALREADY_RUNNING` signal + title/www hash mutex) |
| 11 | MED | Runtime | No friendly message when the WebView2 Runtime is missing | **Implemented** (`webview.h` loader check + prompt + Inno `[Code]` check) |
| 12 | MED | IPC | Launcher stderr is piped but never drained, so the UI can hang | **Implemented** (`stderr = log_file`) |
| 13 | MED | Logging | Log never rotates; every message logged, payloads included (privacy) | **Implemented** (5 MB rotation, `rdesk.log_level`, launcher byte-count logging) |
| 14 | MED | Auto-update | Installer is saved in R's session `tempdir()`, which is deleted on quit | **Implemented** (`Sys.getenv("TEMP")`) |
| 15 | MED | Storage | `storage.json` is written in place, so a crash can corrupt it | **Implemented** (write `.tmp` + atomic rename) |
| 16 | MED | Stub | No Job Object, so killing the stub leaves Rscript orphaned | **Implemented** (Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` + `CloseApplications=force`) |
| 17 | LOW | Stub/Launcher | `MAX_PATH` buffers truncate long install paths | **Implemented** (dynamic growing `GetModuleFileNameW` buffers) |
| 18 | LOW | Launcher | `std::stoi` on window size args runs outside try/catch | **Implemented** (try/catch with `1200x800` defaults) |
| 19 | LOW | Stub | Hard-coded `C:\Temp` fallback | **Implemented** (`GetTempPathW` fallback) |
| 20 | LOW | Build | ISCC and Rtools discovery is narrow | **Implemented** (ProgramFiles, Inno registry lookup, `RTOOLS43_HOME`, `pkgbuild::rtools_path()`) |
| 21 | LOW | Build | `icon_file` doc promises a shortcut/exe icon, but only the setup icon is set | **Implemented** (`windres` `.ico` embedding into stub exe) |
| 22 | LOW | Build | Runtime/library pruning is minimal (30–50% size could be saved) | **Implemented** (`rdesk_prune_package_lib` for runtime and bundle libs, kept `share/locale`) |
| 23 | LOW | Build | `Makevars.win`: no optimisation flags, x64-only SDK, writes into the source tree | **Partially implemented** (`$(ALL_CPPFLAGS) $(ALL_CXXFLAGS)`, builds in `src/`; x64 SDK unchanged as SDK only ships `x64` libs) |
| 24 | LOW | IPC | Final events are dropped when the launcher exits | **Implemented** (drains stdout even after `!proc$is_alive()`) |
| 25 | LOW | Auto-update | No timeout on update checks, so the UI loop can block for 60 s | **Implemented** (local `timeout` option in `rdesk_auto_update` & `check_update`) |

---

## Remaining / Manual Verification Items

- Test a real `RDesk::build_app(..., build_installer = TRUE)` end-to-end on Windows (including a per-user install without admin rights, shortcut icon, and missing-WebView2 prompt).
- Test WebView2 origin filtering and external link handling (`ShellExecuteW`) interactively in a running app window.
- Windows ARM64 WebView2 SDK binaries are not currently vendored under `src/webview2_sdk/build/native/`.

---

## HIGH

### 1. Auto-updater runs unverified downloads
[App.R:985-1036](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/App.R#L985-L1036)

**Problem:**
- `url(version_url)` and `download.file(download_url, …)` accept `http://`.
- There is no checksum or Authenticode check before `system2(dest, "/SILENT"…)`.
- The roxygen example at App.R:136 even shows `"url": "http://..."`.

**Fix:**
- Reject URLs that aren't `https://`.
- Add an optional `sha256 = NULL` argument and verify it with `digest::digest(file = dest, algo = "sha256")`.
- Optionally require `Get-AuthenticodeSignature … Status == "Valid"`.
- Fix the doc example.

### 2. Installer launch fails silently, then the app quits
[App.R:1035](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/App.R#L1035)

**Problem:**
- `dest` is passed unquoted, so a user name with a space breaks the path.
- The installer needs admin (#5). Starting it through CreateProcess fails with error 740.
- `wait = FALSE` hides the failure, and the app then calls `quit()` anyway.

**Fix:**
- Launch with `system2("cmd", c("/c","start",'""', shQuote(dest), "/SILENT", …), wait = TRUE)`. This goes through ShellExecute, which handles UAC.
- Only quit if the launch succeeded.

### 3. No WebView navigation or message-origin filtering
[launcher.cpp:1575-1612](file:///c:/Users/Janak/OneDrive/Documents/RDesk/src/launcher.cpp#L1575-L1612)

**Problem:**
- Every `WebMessageReceived` is forwarded to R whatever the page origin.
- If a link or redirect loads a remote page, that page can call `chrome.webview.postMessage`. That includes `__dialog_result_web__` (App.R:91-106), which writes base64 data to disk.

**Fix:**
- Drop messages whose `get_Source` isn't `https://app.rdesk/`.
- Add a `NavigationStarting` handler that cancels external URIs and opens them with `ShellExecuteW`.
- Add a `NewWindowRequested` handler that calls `put_Handled(TRUE)` and opens the link in the system browser.

### 4. DevTools enabled in production
[launcher.cpp:1559](file:///c:/Users/Janak/OneDrive/Documents/RDesk/src/launcher.cpp#L1559)

**Problem:** the launcher calls `webview::webview w(true, nullptr);`. The first argument is `debug`, so DevTools and the debug menu are always on.

**Fix:** `w(std::getenv("RDESK_DEBUG") != nullptr, nullptr)`, or have R pass `--debug` only when `!rdesk_is_bundle()`.

---

## MEDIUM

### 5. Admin-only installer
[template.iss:44](file:///c:/Users/Janak/OneDrive/Documents/RDesk/inst/installer/template.iss#L44)

**Fix:**
```ini
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog commandline
```
`{autopf}` then resolves to `%LOCALAPPDATA%\Programs` for a per-user install. This also resolves the elevation failure in #2.

### 6. 32-bit install mode
**Problem:** without 64-bit mode, Inno Setup puts the x64 R runtime in `Program Files (x86)` and uses the 32-bit registry view.

**Fix:**
```ini
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExeName}
```

### 7. Fragile AppId
[build.R:831](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/build.R#L831)

**Problem:** `RDesk-App-<crc32(app_name)>` can collide, and renaming the app orphans earlier installs.

**Fix:** accept an optional GUID (for example a `Config/RDesk/AppId` field in DESCRIPTION) and fall back to the current value. In the `.iss`, write it as `{{GUID}`.

### 8. Unescaped template substitution
[build.R:804](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/build.R#L804), [build.R:823-835](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/build.R#L823-L835)

**Problem:** a `"` or `\` in `app_name` or `publisher` breaks the ISPP preprocessor or the C++ string literal in the stub.

**Fix:**
- Validate `app_name` against `^[A-Za-z0-9 ._-]+$`.
- Double `"` in `.iss` values.
- Escape `\` and `"` for C++.

### 9. Build failures not detected
[build.R:809](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/build.R#L809), [build.R:837](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/build.R#L837)

**Problem:** the `system2()` exit codes for g++ and ISCC are ignored. A zip with no `<app>.exe` still reports "Done!".

**Fix:**
- Check `rc` and that the output file exists, and `stop()` otherwise.
- Raise a clear error when ISCC is `NULL`.

### 10. Second launch looks like a crash
[launcher.cpp:1537-1551](file:///c:/Users/Janak/OneDrive/Documents/RDesk/src/launcher.cpp#L1537-L1551)

**Problem:**
- When the mutex exists, the launcher exits without printing `READY`.
- R then raises "Launcher failed to start correctly", and the stub shows an error dialog.
- The mutex is keyed on the window title only, so two apps with the same title block each other.

**Fix:**
- Print `ALREADY_RUNNING` before exiting, and have R treat it as a clean exit.
- Key the mutex on title plus bundle root.

### 11. Missing WebView2 Runtime
**Problem:** the user sees a raw error, or a generic "Code: 1" dialog.

**Fix:**
- Call `GetAvailableCoreWebView2BrowserVersionString` before constructing the webview.
- On failure, show a `MessageBoxW` with the Evergreen bootstrapper link.
- Optionally add an Inno `[Code]` registry check at install time.

### 12. Undrained stderr pipe
[window.R:76](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/window.R#L76)

**Problem:** `stderr = "|"` is only read on failure. If the launcher writes about 4 KB+ to stderr, the pipe fills and the launcher's UI thread blocks.

**Fix:** redirect stderr to the log file, and read that file in the failure branch.

### 13. Unbounded logging
[utils.R:60-74](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/utils.R#L60-L74), launcher.cpp:87, 1446

**Problem:**
- The log has no size cap.
- Every send and receive is logged at INFO.
- The launcher logs full payloads (a privacy concern).

**Fix:**
- Rotate at about 5 MB.
- Gate per-message logs on `getOption("rdesk.log_level")`.
- In the launcher, log only the message type and length unless debug is on.

### 14. Update file in session tempdir
[App.R:1021](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/App.R#L1021)

**Problem:** R deletes its session `tempdir()` on `quit()`, which races with the installer it just started.

**Fix:** save to `Sys.getenv("TEMP")` instead.

### 15. Non-atomic storage writes
[storage.R:161-168](file:///c:/Users/Janak/OneDrive/Documents/RDesk/R/storage.R#L161-L168)

**Problem:** `storage.json` is overwritten in place, so a crash mid-write corrupts it.

**Fix:** write to `.tmp`, then `file.rename()`. If the rename fails, `unlink` the target and retry.

### 16. Orphaned Rscript
[stub.cpp:118-138](file:///c:/Users/Janak/OneDrive/Documents/RDesk/inst/stub/stub.cpp#L118-L138)

**Problem:** the Rscript child isn't tied to the stub. Killing the stub (Task Manager, or the installer during an update) leaves Rscript running with its files locked.

**Fix:**
- Put the child in a Job Object with `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`.
- Optionally add `CloseApplications=force` in the `.iss`.

---

## LOW

17. **`MAX_PATH` buffers** (stub.cpp:40, launcher.cpp:1584): `GetModuleFileNameW` silently truncates long paths. Grow the buffer in a loop.
18. **`std::stoi`** (launcher.cpp:1516-1517): bad width/height arguments crash the launcher. Wrap in try/catch with defaults.
19. **TEMP fallback** (stub.cpp:90): replace the hard-coded `C:\Temp` with `GetTempPathW`.
20. **ISCC/Rtools discovery** (build.R:812-817, 841-847):
    - Add `%ProgramFiles%\Inno Setup 6`.
    - Read the Inno Setup install location from the registry.
    - Use `pkgbuild::rtools_path()` when available.
21. **Icon** (build.R:32-35): the stub exe has no icon resource. Either compile one in with `windres`, or correct the doc.
22. **Pruning** (build.R:671-676): delete each package's `help/`, `html/`, `doc/`, `tests/`, `demo/` and `po/` folders, plus `include/`. Make it opt-in.
23. **Makevars.win:18-20**:
    - Add `$(ALL_CXXFLAGS) -O2`.
    - Pick the WebView2 SDK lib folder by architecture (ARM64).
    - Build into `.` and copy to `$(R_PACKAGE_DIR)` instead of writing into `inst/`.
24. **Lost final events** (window.R:170-171): don't return early on `!is_alive()`; drain stdout whenever `proc` isn't NULL.
25. **Update timeouts** (App.R:154, 986): set `options(timeout = 10–30)` locally around the network calls.

---

## Corrections to existing claims

- **Per-user install (no UAC):** not supported today; the template forces admin (#5). Call it *planned* until it ships.
- **Silent auto-update:** implemented, but on Windows the launch path is currently broken (#2). Fix it before advertising it.
- **`icon_file` doc:** it promises an application shortcut icon that isn't produced (#21).

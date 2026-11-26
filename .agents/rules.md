# RDesk Agent Rules

Behavioral, branching, and engineering guidelines for AI coding agents working on the RDesk repository.

---

## 1. Branching & Release Policy

> [!IMPORTANT]
> **Windows CRAN Track (`release/v1.0.7-windows` $\rightarrow$ `main`):**
> - `main` is strictly reserved for the live **CRAN release** (`OS_type: windows` in `DESCRIPTION`) and must **only be updated right before a CRAN submission**. Never commit or push routine changes directly to `main`.
> - Do **NOT** merge Unix-only build files (`configure`, `cleanup`, `src/Makevars`, `src/stub_macos.c`, `inst/stub/stub_linux.c`) into `main` or `release/*-windows`.
> - Windows hardening fixes, showcase app updates, `Rapp` CLI improvements, and Windows CI repairs land on `release/v1.0.7-windows` first, and are merged into `main` only when preparing a CRAN release.
>
> **Cross-Platform Development Track (`dev`):**
> - All macOS and Linux support (`src/Makevars`, `configure`, `cleanup`, `WKWebView` / `WebKitGTK` bridges, Mach-O dylib relocation, Linux/macOS native stubs, and cross-platform CI workflows) resides strictly on `dev`.
> - Platform-neutral improvements (demo apps in `inst/apps/`, templates in `inst/templates/`, `R/cli.R`, `exec/rdesk.R`, `src/launcher.cpp` Win32/shared fixes) should be cherry-picked cleanly onto `dev` after verifying on `release/v1.0.7-windows`.

---

## 2. Architecture Invariants

1. **Zero Network Ports**: RDesk never binds TCP/UDP sockets (`httpuv`, `WebSockets`, `shiny` servers).
   - Static frontend assets (`www/`) are mapped via WebView2 `SetVirtualHostNameToFolderMapping("app.rdesk", ...)` on Windows (`https://app.rdesk/index.html`) and custom URI scheme handlers (`rdesk://app/index.html`) on macOS (`WKURLSchemeHandler`) and Linux (`WebKitURISchemeRequest`).
   - Dynamic JS $\leftrightarrow$ R communication uses stdin/stdout JSON envelopes (`rdesk_message()` / `rdesk_parse_message()`).
2. **Path & Origin Security**:
   - Never relax origin allowlists in `src/launcher.cpp` (`is_allowed_app_uri` / `is_allowed_message_source`).
   - Keep canonical path-traversal guards intact on macOS (`stringByStandardizingPath`) and Linux (`realpath()`).
   - Validate remote URLs (e.g., `https://` in `App$check_update()`).
3. **Scaffold Unit Test Contracts**:
   - Any change to `inst/templates/app_skeleton/` must preserve:
     - `init_data()` returning a `data.frame` (`R/data.R.builtin`)
     - `get_app_kpis()` and 1-argument `make_chart(df)` returning `"data:image/png;base64,..."` (`R/plots.R.mixed`)
     - `async(function` in `R/server.R.async`
     - Zero unresolved `{{...}}` placeholders after `rdesk_create_app()` substitution across `light`, `dark`, and `system` themes.
4. **CRAN Compliance**:
   - Keep `Rapp` in `Suggests` (not `Imports`).
   - Never write outside `tempdir()` in tests or examples; only use `tools::R_user_dir("RDesk", ...)` for user-initiated runtime/detached caches.
   - Keep `AGENTS.md`, `.agents/`, and temporary build artifacts excluded in `.Rbuildignore`.

---

## 3. Mandatory Verification Gates Before Push

1. Run `devtools::document()` whenever roxygen comments or exports change; verify `NAMESPACE` did not drop any existing exports (especially `rdesk_message`).
2. Run `devtools::test()` and confirm `0 FAIL`.
3. Run `spelling::spell_check_package()` and confirm `No spelling errors found`.
4. Ensure every new exported function is listed in `_pkgdown.yml` under `reference:`.
5. Keep `exec/rdesk.R` tracked with executable git mode `100755` (`git update-index --chmod=+x exec/rdesk.R`).
6. Check `git status --short` before committing — watch for auto-copied `www/rdesk.js` side effects created by `rdesk_resolve_www()` during app launches.

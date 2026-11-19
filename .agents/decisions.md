# RDesk Architecture Decision Records (ADRs)

Key engineering decisions made during RDesk development so future sessions understand *why* things are built the way they are and avoid reversing settled design choices.

---

## ADR-001: Zero-Port Virtual Host / Custom Scheme + Stdin/Stdout Pipe IPC
- **Decision**: Serve static UI assets via native webview directory mapping (`https://app.rdesk/` via WebView2 `SetVirtualHostNameToFolderMapping` on Windows; `rdesk://app/` via `WKURLSchemeHandler` on macOS and `WebKitURISchemeRequest` on Linux) and exchange runtime data exclusively over stdin/stdout JSON envelopes (`rdesk_message()` / `rdesk_parse_message()`).
- **Rationale**: Eliminates local TCP port binding, firewall prompts, port collisions, and loopback exposure. Apps work completely offline and cannot be accidentally reached from external browsers.
- **Consequences**: Apps cannot be opened via `http://localhost` in Chrome/Edge; opening `www/index.html` directly from disk loads static HTML without R connectivity.

---

## ADR-002: Strict Branch Separation (`main` Windows CRAN vs. `dev` Cross-Platform)
- **Decision**: Keep `release/v1.0.7-windows` and `main` strictly Windows-only (`OS_type: windows`) for CRAN stability while developing and validating macOS (`WKWebView`) and Linux (`WebKitGTK`) support on `dev`.
- **Rationale**: CRAN checks reject broken Unix `configure` scripts or missing system libraries (`webkit2gtk-4.1-dev`) on build farms where WebKitGTK isn't installed. Keeping the CRAN release track isolated allows rapid cross-platform iteration on `dev` without risking CRAN regressions.

---

## ADR-003: Per-App WebView2 User Data Folder Isolation
- **Decision**: In `src/launcher.cpp` and `src/webview/webview.h`, compute a deterministic per-app identifier (`instance_prop = L"RDesk_Instance_" + std::to_wstring(hash(title + "|" + www))`) and set `WEBVIEW2_USER_DATA_FOLDER` to `%APPDATA%\RDesk_WebView2\<instance_prop>` before creating the `webview::webview` instance.
- **Rationale**: `webview.h` defaults to `%APPDATA%\rdesk-launcher.exe`. Because every RDesk app shares the `rdesk-launcher.exe` executable name, launching two different RDesk apps concurrently caused the second app to fail with `WEBVIEW_ERROR_INVALID_STATE` or overwrite the first app's `https://app.rdesk/` virtual host mapping.
- **Consequences**: Multiple distinct RDesk apps can run side-by-side cleanly, while launching the *same* app twice still triggers single-instance focus via the per-app named mutex (`Local\RDesk_Instance_<hash>`) and `SetPropW`/`EnumWindows` window lookup.

---

## ADR-004: Relocatable macOS & Linux App Bundles
- **Decision**: Follow `electricShine`/`delocate`-style packaging in `R/build.R` (on `dev`):
  - `rdesk_fix_macos_rpaths()` sets `0755` on Mach-O binaries before `install_name_tool`, copies non-system external `.dylib` dependencies into `Contents/Resources/R-runtime/R/lib`, and adds `@loader_path/...` rpaths unconditionally.
  - `rdesk_patch_macos_R_shell_script()` relocates `R_HOME_DIR`, `R_SHARE_DIR`, `R_INCLUDE_DIR`, `R_DOC_DIR` and replaces `bin/Rscript` with a portable bash wrapper.
  - Native C stubs (`inst/stub/stub_macos.c`, `src/stub_macos.c`, `inst/stub/stub_linux.c`) call `chdir()` into the bundled `app/` directory before `execv()`.
- **Rationale**: Hardcoded `/Library/Frameworks/R.framework` or Homebrew `/opt/homebrew` paths break when an `.app` bundle is moved to another directory or machine.

---

## ADR-005: `Rapp` CLI Backed by Exported R Functions (`Rapp` in `Suggests`)
- **Decision**: Expose `rdesk_run()`, `rdesk_demo()`, `rdesk_sitrep()`, and `install_rdesk_cli()` as exported R functions in `R/cli.R`, keep `exec/rdesk.R` as a thin `#!/usr/bin/env Rapp` dispatcher (`new`, `run`, `demo`, `build`, `sitrep`), and keep `Rapp` in `Suggests`.
- **Rationale**:
  - RStudio/Positron users can run `RDesk::rdesk_demo("cars")` and `RDesk::rdesk_run(".")` without needing `Rapp`.
  - CLI subcommands stay testable via `Rapp::run()` + `options(rdesk.ci_mode = TRUE)` without opening GUI windows on CRAN.
  - Keeping `Rapp` optional in `Suggests` avoids adding a hard dependency for end users who only use the R API.

---

## ADR-006: Domain-Specific Showcase Apps & Template Contracts
- **Decision**: Maintain three crafted, domain-specific showcase/template apps instead of generic placeholder dashboards:
  1. `inst/apps/mtcars_dashboard/` — **CarsAnalyser** (Automotive Performance & Regression Telemetry Workbench; dark-slate `#1e293b` plots matching UI surfaces, async `broom` Regression Lab, Markdown report export).
  2. `inst/apps/data_studio/` — **Data Intelligence Studio** (Clinical & Biostatistical Trial Explorer + Dataset Profiler; two deterministic built-in cohorts, Table 1 subgroup analysis, Tukey outlier audit, Light/Dark theme-synced charts, standalone HTML report).
  3. `inst/templates/app_skeleton/` — **`rdesk_create_app()` Starter Workbench** (Analytics + live R Runtime & Environment inspector across `light`, `dark`, and `system` themes).
- **Consequences**: All 3 apps must keep 100% DOM ID and `rdesk.send` $\rightarrow$ `app$on_message` contract parity, and `app_skeleton` must continue passing all `tests/testthat/test-scaffold*.R` assertions.

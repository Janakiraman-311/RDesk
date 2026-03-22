This workflow documents the architecture, critical paths, and common pitfalls of the RDesk CI/CD and native build pipeline. Use this as "memory" when performing maintenance or upgrades.

> [!IMPORTANT]
> **VERIFIED CONFIGURATION (2026-03-22)**: The current `4.5.1` + CRAN-only `renv.lock` setup is the only verified working state. Do not change the R version or re-enable Bioconductor repositories in the lockfile without a full audit.

### 1. Architectural Overview
The RDesk build uses the standard R "Source-to-Binary" model to comply with CRAN policies.

*   **Native Launcher**: Source code is located in `src/`. It is compiled automatically during package installation via `src/Makevars.win`.
*   **Compilation Tool**: Uses Rtools `g++` (Mingw-w64).
*   **Static Linking**: WebView2 is linked statically (`-lWebView2LoaderStatic`) to ensure the resulting binary is self-contained and doesn't require separate DLLs.
*   **Dependency Management**: Powered by `renv` in `explicit` mode. CI steps require explicit activation.

### 2. Critical File Paths
| Component | Path | Description |
| :--- | :--- | :--- |
| **CI Workflows** | `.github/workflows/*.yml` | Simple workflows that trust `devtools::install` to build the launcher. |
| **Launcher Source** | `src/launcher.cpp` | Core C++ logic for the WebView2 host. |
| **WebView2 SDK** | `src/webview2_sdk/` | Contained within `src` for on-install compilation. |
| **Build Rules** | `src/Makevars.win` | Windows-specific makefile for building the launcher. |
| **Package Hooks** | `inst/bin/` | Final location for native binaries in the built package. |
| **Lockfile** | `renv.lock` | Sources for all R dependencies. |

### 3. CI/CD Invariants
Follow these rules strictly:

#### Rule A: Use Rscript Shell
Always specify `shell: Rscript {0}` for R code blocks in YAML. This avoids quoting issues.

#### Rule B: Explicit renv Activation
Every R block **MUST** start with `source("renv/activate.R")`.

#### Rule C: R Version Alignment
The `r-version` in workflows **MUST** match `renv.lock`. Current: **4.5.1**.

#### Rule D: Makevars.win Integrity
The launcher build in `Makevars.win` must:
*   Use `$(CXX)` and `$(PKG_CPPFLAGS)`.
*   Link `-lole32 -lshell32 -lshlwapi -luser32 -lversion -lcomdlg32 -loleaut32 -luuid`.
*   Ensure the output is placed in `../inst/bin/rdesk-launcher.exe`.

#### Rule E: CRAN Repo Before renv::restore() (CRITICAL)
Every `Restore renv` step **MUST** set the CRAN repo before calling `renv::restore()`:
```r
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
options(repos = c(CRAN = "https://cloud.r-project.org"))
renv::restore(prompt = FALSE, clean = FALSE)
```
Without the `options(repos = ...)` line, renv tries to auto-initialize Bioconductor, which calls `renv_bioconductor_init_biocmanager()`, which tries to install `BiocVersion` from an empty repo URL — **causing a fatal crash.** This affects ALL workflows, not just pkgdown.

#### Rule F: Pin R Version Explicitly
Every `r-lib/actions/setup-r@v2` step **MUST** specify `r-version: '4.5.1'`. Without it, the runner may resolve to a different R version than the `renv.lock`, causing DLL mismatch errors.

#### Rule G: Runner Environment (OS)
*   **Binary Builds (`build-app`, `R-CMD-check`)**: MUST use `windows-latest`. The launcher compilation depends on Rtools and Win32 APIs.
*   **Documentation (`pkgdown`)**: MUST use `ubuntu-latest`. Using Windows for pkgdown causes fatal `rsync` errors during the deployment step (path mismatch with `D:\a\...`).

### 4. Troubleshooting Memory
*   **"Launcher not found"**: Ensure `devtools::install()` or `R CMD INSTALL` was run. `load_all()` does NOT trigger the `.exe` build by default unless configured.
*   **"WebView2 headers missing"**: Check the `-I` paths in `Makevars.win`.
*   **"Duplicate symbols"**: Ensure `launcher.cpp` is clean and no other `.cpp` files in `src/` are trying to build the same binary.
*   **"Pragma warnings in check"**: The `nlohmann/json` library and `webview.h` contain diagnostic pragmas. These trigger 1 WARNING in `R CMD check`. This is accepted on CRAN as documented in `cran-comments.md`. GHA is configured with `error_on = "error"` to allow this.
*   **"Size Audit"**: The baseline for a v1.0.0 dashboard with Tidyverse and Tiling is **66.5 MB**. If a build suddenly exceeds 100MB, check if `prune_runtime` was disabled or if `renv` grabbed unnecessary large source packages.
*   **`Error: package 'BiocVersion' is not available`**: The `renv::restore()` step is missing `options(repos = c(CRAN = "https://cloud.r-project.org"))` before the restore call. Without it, renv tries to init Bioconductor from an empty repo URL (see **Rule E**). Root cause of the pkgdown CI failure on 2026-03-22.
*   **`rsync error (code 12) at io.c`**: This occurs when `pkgdown` runs on Windows. Switch the `pkgdown` job to `ubuntu-latest` (see **Rule G**).

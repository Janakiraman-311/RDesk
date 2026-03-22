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
| **CI Workflows** | `.github/workflows/*.yml` | Workflows that trust `R CMD INSTALL` to build the launcher. |
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
Without the `options(repos = ...)` line, renv tries to auto-initialize Bioconductor, which causes a fatal crash.

#### Rule F: Pin R Version Explicitly
Every `r-lib/actions/setup-r@v2` step **MUST** specify `r-version: '4.5.1'`.

#### Rule G: Runner Environment (OS)
*   **Binary Builds (`build-app`, `R-CMD-check`)**: MUST use `windows-latest`. The launcher compilation depends on Rtools and Win32 APIs.
*   **Documentation (`pkgdown`)**: MUST use `windows-latest` for Windows-only packages (like RDesk). 
*   **Deployment**: MUST use `peaceiris/actions-gh-pages@v4` on Windows runners. Using `JamesIves` on Windows causes fatal `rsync` errors.

#### Rule H: Workflow Permissions
Every job that deploys to GitHub Pages MUST include explicit write permissions:
```yaml
permissions:
  contents: write
```

#### Rule I: Zero-Dependency Installation
In CI environments, use base R's installation command:
```yaml
- name: Install RDesk
  run: R CMD INSTALL .
  shell: cmd
```

### 4. Troubleshooting
*   **"there is no package called 'devtools'"**: In CI, `devtools` is not in `renv.lock`. Use `R CMD INSTALL .` instead.
*   **"launcher.exe not found"**: Ensure the package is installed into the library before running pkgdown.
*   **"rsync error (code 12) at io.c"**: Switch deploy action to `peaceiris/actions-gh-pages@v4`.
*   **"Permission denied (403)"**: Add `permissions: contents: write` to the GHA job.
*   **"package 'BiocVersion' is not available"**: Check `Rule E` (set CRAN repo before restore).
*   **"Duplicate symbols"**: Ensure `launcher.cpp` is the only source building the binary in `src/`.
*   **"Size Audit"**: Baseline v1.0.0 is ~66.5 MB.

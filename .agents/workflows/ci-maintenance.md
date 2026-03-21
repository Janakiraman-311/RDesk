This workflow documents the architecture, critical paths, and common pitfalls of the RDesk CI/CD and native build pipeline. Use this as "memory" when performing maintenance or upgrades.

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

### 4. Troubleshooting Memory
*   **"Launcher not found"**: Ensure `devtools::install()` or `R CMD INSTALL` was run. `load_all()` does NOT trigger the `.exe` build by default unless configured.
*   **"WebView2 headers missing"**: Check the `-I` paths in `Makevars.win`.
*   **"Duplicate symbols"**: Ensure `launcher.cpp` is clean and no other `.cpp` files in `src/` are trying to build the same binary.
*   **"Pragma warnings in check"**: The `nlohmann/json` library and `webview.h` contain diagnostic pragmas. These trigger 1 WARNING in `R CMD check`. This is accepted on CRAN as documented in `cran-comments.md`. GHA is configured with `error_on = "error"` to allow this.

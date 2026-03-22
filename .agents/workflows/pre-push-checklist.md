Before committing or pushing code to the RDesk repository, follow these steps to ensure CI/CD stability and package integrity.

### 1. Environment & Version Compatibility
*   **Local R Version**: R 4.5.1 is recommended for consistency.
*   **RTools Version**: 
    > [!IMPORTANT]
    > **RTools 4.5** (specifically `rtools45`) is required to compile the native launcher from source.

### 2. Documentation Synchronization
*   **Roxygen Headers**: After modifying `@param`, `@return`, or `@export`, run `devtools::document()`.
*   **Check man/ files**: Ensure generated `.Rd` files are staged.

### 3. Build & Verification
*   **Compiling the Launcher**:
    ```powershell
    # Trigger source build via install (zero dependencies required)
    # This is the verified method for CI environments.
    R CMD INSTALL .
    ```
*   **CI Library Sync**: 
    > [!IMPORTANT]
    > All R steps in `.github/workflows` use `shell: Rscript {0}` and `source("renv/activate.R")`.

### 4. Local Check & Audit
Run the CRAN pre-check and audit the latest hardening features:
```powershell
# 1. Verification of all doc and code
Rscript -e "source('renv/activate.R'); devtools::document(); spelling::spell_check_package()"

# 2. Comprehensive check (0 errors expected)
Rscript -e "source('renv/activate.R'); devtools::check(args = c('--no-manual', '--as-cran'), error_on = 'error')"

# 3. Size and Bundle Audit (Target: < 70MB)
Rscript -e "source('renv/activate.R'); RDesk::build_app(app_dir = 'inst/apps/mtcars_dashboard', prune_runtime = TRUE, dry_run = FALSE)"
```

### 5. Git Hygiene & Final Verification
*   **Stage New Files**: Ensure `src/launcher.cpp` and `src/Makevars.win` are always staged.
*   **Verify Binaries**: Never commit `.exe` files. They are source-built only.
*   **Platform Guard**: Verify `.onAttach` in `R/zzz.R` correctly checks `.Platform$OS.type`.
*   **Clean Workspace**: Remove any temporary `dist/` or `check/` folders before push.

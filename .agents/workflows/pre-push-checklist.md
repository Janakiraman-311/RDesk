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
    # Trigger source build via install
    Rscript -e "devtools::install(pkg = '.', upgrade = FALSE, quick = TRUE)"
    ```
*   **CI Library Sync**: 
    > [!IMPORTANT]
    > All R steps in `.github/workflows` use `shell: Rscript {0}` and `source("renv/activate.R")`.

### 4. Local Check
Run the CRAN pre-check to verify `Makevars.win` and metadata:
```powershell
Rscript -e "source('renv/activate.R'); devtools::check(args = c('--no-manual', '--as-cran'), error_on = 'error')"
```

### 5. Git Hygiene
*   **Stage New Files**: Ensure `src/launcher.cpp` and `src/Makevars.win` are always staged.
*   **Verify Binaries**: Never commit `.exe` files. They are now source-built only.
*   **Clean Workspace**: Remove any temporary `dist/` or `check/` folders before push.

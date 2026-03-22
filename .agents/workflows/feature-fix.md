---
description: Formal Workflow for RDesk Feature Development & Bug Fixes
---

This workflow defines the mandatory, step-by-step process for any change to the RDesk codebase. No "generic patches" or "push-and-pray" fixes are allowed.

### Phase 1: Local Replication & Root Cause
1.  **Isolate the Issue**: Create a minimal reproducible example (MRE) in `tests/reproduce_issue.R`.
2.  **Verify failure**: Run the MRE locally and confirm it fails exactly as reported.
3.  **Analyze**: Match the local failure against GHA logs to ensure the environment difference is understood.

### Phase 2: Implementation (Actual Working Fix)
1.  **The Fix**: Apply the architectural solution, not a localized patch.
2.  **Clean Code**: Remove all debug `print()` or `echo` statements before committing.
3.  **Workspace Hygiene**: Delete any temporary diagnostic files (`diag_*.txt`, `build_log.txt`).

### Phase 3: Systematic Local Verification
// turbo
1.  **Compile & Install**:
    ```r
    # Trigger source build via install
    source("renv/activate.R")
    devtools::install(pkg = ".", upgrade = FALSE, quick = TRUE)
    ```
2.  **Synchronize renv**:
    ```r
    source("renv/activate.R")
    renv::restore()
    ```
3.  **Install & Test Stack**:
    ```r
    source("renv/activate.R")
    devtools::install(pkg = ".", upgrade = FALSE, quick = TRUE)
    # Run the MRE again to prove the fix
    source("tests/reproduce_issue.R")
    ```

### Phase 4: CI & Documentation Maintenance
1.  **Check Workflow Alignment**: Verify if the change requires updates to `.github/workflows/build-app.yml` (e.g. new deps, new R version).
2.  **Use Rscript Shell**: Ensure any new CI steps use `shell: Rscript {0}`.
3.  **Audit Help Files**: Run `devtools::document()` and check the `man/` directory for any "Lost braces" or "Undocumented arguments" warnings in the Rd files.
4.  **Spell Check**: Run `spelling::spell_check_package()` and update `inst/WORDLIST` if new technical terms were introduced.

### Phase 5: GHA Monitoring & Final Polish
1.  **Push**: Commit with a specific "Phase XX" or "Feature: ..." message.
2.  **Full Job Audit**: Verify both `build` and `Verify async stack` steps pass with green checkmarks.
3.  **Hardening Check**: If the feature impacts app lifecycle, verify the **Anti-Zombie Watchdog** and **Platform Guard** are still functional.

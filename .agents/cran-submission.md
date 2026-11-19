# CRAN Submission Checks Workflow

This document outlines the workflow and rules for AI agents (like Antigravity) when assisting with CRAN submissions and checks for the RDesk package.

## 1. Documentation Updation
Before any CRAN check, always ensure the documentation and metadata are up-to-date:
- Run `devtools::document()` to update `NAMESPACE` and `man/` files using `roxygen2`.
- Check that the `DESCRIPTION` file is updated (version bumps, authors, descriptions without trailing periods).
- Check that `NEWS.md` contains the latest release notes.
- Ensure all exported functions have `@return` tags, examples (using base R or guarded `Suggests` packages), and are listed in `_pkgdown.yml` under `reference:`.
- Ensure all non-CRAN top-level files (`AGENTS.md`, `.agents/`, `WINDOWS_REVIEW.md`, etc.) are listed in `.Rbuildignore`.
- Verify `NAMESPACE` exports all expected public functions (including `rdesk_message`, `rdesk_run`, `rdesk_demo`, `rdesk_sitrep`, `install_rdesk_cli`).

## 2. CRAN Requirements Validation
Check the codebase for common CRAN pitfalls:
- **File System**: Ensure no files are written to user directories (`~`, Desktop, Documents) without explicit consent. Use `tempdir()` or `tempfile()` for logs, temp data, and test artifacts.
- **Process Management**: Any background processes spawned via `system2()` or `processx` must be cleaned up properly. Use `cleanup = TRUE` or explicitly kill child processes before the R session exits. No lingering processes should be left behind.
- **Downloads**: If downloading files, implement graceful degradation (e.g., wrap in `tryCatch`) in case the CRAN server has no internet access.
- **Standard Output**: Do not clutter the user console with `print()` or `cat()` unless requested. Use `message()` for standard outputs and `warning()` for warnings.

## 3. Package Infrastructure & Quality Checks
Run these advanced checks to catch issues before `devtools::check()`:
- **Spell Check**: Run `spelling::spell_check_package()` to catch typos in documentation and DESCRIPTION.
- **URL Check**: Run `urlchecker::url_check()` to ensure no dead or broken links exist in the documentation. Use `urlchecker::url_update()` to automatically fix redirects.
- **Missing Tags**: Use `checkhelper::find_missing_tags()` to ensure all functions either have `@noRd` or `@export`.
- **Clean Userspace**: Run `checkhelper::check_clean_userspace()` after testing to guarantee the package leaves the environment exactly as it found it (no leftover files, modified options, or changed working directories).

## 4. Local CRAN Checks
Always verify locally before submitting to CRAN:
1. Run `devtools::check(document = FALSE, manual = TRUE, remote = TRUE)` to simulate a CRAN environment locally.
2. Address all `ERROR` and `WARNING` messages.
3. Aim for 0 `NOTE` messages. If there are unavoidable notes, use `usethis::use_cran_comments()` to explicitly document them for the CRAN team.

## 5. Cross-Platform Checks (macOS/Linux/Windows)
RDesk contains native C++ binaries, so cross-platform checks are critical:
- **Windows Checks**: Use `devtools::check_win_devel()` or `devtools::check_win_release()`.
- **macOS Checks**: Use `devtools::check_mac_release()`. For ARM64/M1 specific builds, manually submit the tarball to the [macOS Builder](https://mac.r-project.org/macbuilder/submit.html).
- **R-hub**: Use `rhub::rhub_check()` (R-hub v2) to test across multiple CRAN-like environments.

## 6. Reverse Dependencies
If RDesk develops a downstream ecosystem, always test reverse dependencies before a major release:
- Run `revdepcheck::revdep_check(num_workers = 4)` to ensure no downstream packages are broken by your updates.

Follow these rules strictly when the user asks you to prepare or run CRAN checks!

# RDesk Maintenance & Development Guide

This document contains critical commands and architectural notes for
RDesk maintainers.

## Verified Environment (v1.0.4)

- **R Version**: `4.5.1` (UCRT)
- **RTools**: `rtools45` (Required for building the launcher from source
  via `Makevars.win`)
- **Dependency Manager**: `renv` (explicit mode)

## Critical Build & Installation Rules

### Rule: Dependency-Free Library Sync

In CI or fresh environments, always define the CRAN repository before
restoring to avoid Bioconductor crashes:

``` r
options(repos = c(CRAN = "https://cloud.r-project.org"))
renv::restore(prompt = FALSE, clean = FALSE)
```

### Rule: Compiling the Native Launcher

To build the native binary into `inst/bin/` from source
(`src/launcher.cpp`), run:

``` powershell
R CMD INSTALL .
```

*Note: Makevars.win handles the static linking of the WebView2 SDK.*

## Development Workflow

### 1. Update Documentation & RD Files

``` r
devtools::document()
```

### 2. Run Comprehensive Checks (CRAN-style)

``` r
devtools::check(args = c("--no-manual", "--as-cran"), error_on = "error")
```

### 3. Spell Check (Technical Terms)

Introduced technical terms should be added to `inst/WORDLIST`.

``` r
spelling::spell_check_package()
```

### 4. Build Bundled Application

``` r
RDesk::build_app(app_dir = "inst/apps/mtcars_dashboard", out_dir = tempdir())
```

## Binary Distribution Policy

- **Never commit `.exe` files**: The `rdesk-launcher.exe` is
  source-built during installation.
- **WebView2**: Linked statically to avoid runtime DLL dependencies on
  the target machine.
- **Size Audit**: Keep the final zip bundle under 70MB where possible.

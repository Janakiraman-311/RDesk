# Build a self-contained distributable from an RDesk application

Build a self-contained distributable from an RDesk application

## Usage

``` r
build_app(
  app_dir = ".",
  out_dir = file.path(tempdir(), "dist"),
  app_name = NULL,
  version = NULL,
  r_version = NULL,
  include_packages = character(0),
  portable_r_method = c("extract_only", "installer"),
  runtime_dir = NULL,
  overwrite = FALSE,
  build_installer = FALSE,
  publisher = "RDesk User",
  website = "https://github.com/Janakiraman-311/RDesk",
  license_file = NULL,
  icon_file = NULL,
  prune_runtime = TRUE,
  dry_run = FALSE
)
```

## Arguments

- app_dir:

  Path to the app directory (must contain app.R and www/)

- out_dir:

  Output directory for the zip file (created if not exists)

- app_name:

  Name of the application. Defaults to name in DESCRIPTION or
  "MyRDeskApp".

- version:

  Version string. Defaults to version in DESCRIPTION or "1.0.0".

- r_version:

  R version to bundle e.g. "4.4.2". Defaults to current R version.

- include_packages:

  Character vector of extra CRAN packages to bundle. RDesk's own
  dependencies are always included automatically.

- portable_r_method:

  How to provision the bundled R runtime when `runtime_dir` is not
  supplied. `"extract_only"` requires standalone 7-Zip and never
  launches the R installer. `"installer"` allows the legacy silent
  installer path explicitly.

- runtime_dir:

  Optional path to an existing portable R runtime root containing
  `bin/`. When supplied, RDesk copies this runtime directly and skips
  the download/extract step.

- overwrite:

  If TRUE, overwrite existing output. Default FALSE.

- build_installer:

  If TRUE, also build a Windows installer (.exe) using InnoSetup.

- publisher:

  Documentation for the application publisher (used in installer).

- website:

  URL for the application website (used in installer).

- license_file:

  Path to a license file (.txt or .rtf) to include in the installer.

- icon_file:

  Path to an .ico file for the installer and application shortcut.

- prune_runtime:

  If TRUE, remove unnecessary files (Tcl/Tk, docs, tests) from the
  bundled R runtime to reduce size (~15-20MB saving). Default TRUE.

- dry_run:

  If TRUE, performs a quick validation of the app structure and
  environment without performing the full build. Default FALSE.

## Value

Path to the created zip file, invisibly.

## Examples

``` r
# Prepare an app directory (following scaffold example)
app_path <- file.path(tempdir(), "MyApp")
rdesk_create_app("MyApp", path = tempdir())
#> 
#> [RDesk] Generating MyApp...
#> [RDesk]   Created 6 directories and 8 files
#> 
#> [RDesk] Successfully created: C:\Users\RUNNER~1\AppData\Local\Temp\RtmpUnpue2\MyApp
#> [RDesk] Your Professional Dashboard includes:
#>   - Mixed visualization (Charts + Tables)
#>   - Built-in KPI cards system
#>   - Sidebar filtering engine
#>   - Background processing (Async Workers)
#> 
#> [RDesk] Run it now:
#>   setwd("C:\Users\runneradmin\AppData\Local\Temp\RtmpUnpue2\MyApp")
#>   source("app.R")
#> 
#> [RDesk] Build your executable when ready:
#>   RDesk::build_app(app_dir = "C:\Users\runneradmin\AppData\Local\Temp\RtmpUnpue2\MyApp", app_name = "MyApp")
#> 

# Perform a dry-run build (fast, no external binaries downloaded)
build_app(app_path, out_dir = tempdir(), dry_run = TRUE)
#> 
#> [RDesk] DRY RUN: Validating app structure...
#> [RDesk]   V Structure OK
#> [RDesk]   V RTools found: C:\rtools45
#> [RDesk] DRY RUN: All checks passed.
```

# Validate build inputs before starting the process

Validate build inputs before starting the process

## Usage

``` r
rdesk_validate_build_inputs(
  app_dir,
  extra_pkgs,
  build_installer = FALSE,
  portable_r_method = c("extract_only", "installer"),
  runtime_dir = NULL,
  use_download = FALSE,
  icon_file = NULL,
  license_file = NULL,
  dry_run = FALSE
)
```

## Arguments

- app_dir:

  Path to app directory.

- extra_pkgs:

  Character vector of packages.

- build_installer:

  Logical.

- portable_r_method:

  Method for R portability.

- runtime_dir:

  Path to pre-existing runtime.

- use_download:

  Logical; whether to download portable R on Windows.

- icon_file:

  Optional resolved icon path.

- license_file:

  Optional resolved license path.

- dry_run:

  Logical; whether running in pre-flight dry-run mode.

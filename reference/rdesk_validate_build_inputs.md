# Validate build inputs before starting the process

Validate build inputs before starting the process

## Usage

``` r
rdesk_validate_build_inputs(
  app_dir,
  extra_pkgs,
  build_installer = FALSE,
  portable_r_method = c("extract_only", "installer"),
  runtime_dir = NULL
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

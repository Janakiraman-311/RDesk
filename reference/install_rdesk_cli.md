# Install RDesk command-line launchers via 'Rapp'

Installs the shell launcher for RDesk's command-line interface (`rdesk`,
with subcommands `rdesk new`, `rdesk run`, `rdesk demo`, `rdesk build`,
and `rdesk sitrep`) onto your system PATH using the `Rapp` package.

## Usage

``` r
install_rdesk_cli(destdir = NULL, ...)
```

## Arguments

- destdir:

  Optional destination directory passed to
  [`Rapp::install_pkg_cli_apps()`](https://rdrr.io/pkg/Rapp/man/install_pkg_cli_apps.html).

- ...:

  Additional arguments passed to
  [`Rapp::install_pkg_cli_apps()`](https://rdrr.io/pkg/Rapp/man/install_pkg_cli_apps.html).

## Value

The return value from
[`Rapp::install_pkg_cli_apps()`](https://rdrr.io/pkg/Rapp/man/install_pkg_cli_apps.html),
invisibly.

## Examples

``` r
if (interactive() && requireNamespace("Rapp", quietly = TRUE)) {
  install_rdesk_cli()
}
```

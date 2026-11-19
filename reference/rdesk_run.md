# Launch an RDesk desktop application

Launches an RDesk application directory (containing `app.R`) or an
explicit `app.R` script in a clean `Rscript` session. Also powers the
`rdesk run` command-line interface.

## Usage

``` r
rdesk_run(app_dir = ".", debug = FALSE, detach = FALSE)
```

## Arguments

- app_dir:

  Path to the application directory containing `app.R`, or a direct path
  to `app.R`. Defaults to the current working directory (`"."`).

- debug:

  Logical. If `TRUE`, sets `RDESK_DEBUG=1` for the launched app to
  enable webview developer tools and verbose IPC logging. Default
  `FALSE`.

- detach:

  Logical. If `TRUE`, starts the app in the background and returns the
  [`processx::process`](http://processx.r-lib.org/reference/process.md)
  handle immediately without blocking. Default `FALSE`.

## Value

When `getOption("rdesk.ci_mode", FALSE)` is `TRUE`, returns a list with
resolved launch metadata invisibly without opening a window. Otherwise
returns the exit status integer (when `detach = FALSE`) or the
[`processx::process`](http://processx.r-lib.org/reference/process.md)
object (when `detach = TRUE`), invisibly.

## Examples

``` r
old <- options(rdesk.ci_mode = TRUE)
demo_dir <- system.file("apps", "mtcars_dashboard", package = "RDesk")
if (nzchar(demo_dir)) {
  rdesk_run(demo_dir)
}
#> [RDesk] CI Mode: Skipping launch of D:/a/_temp/Library/RDesk/apps/mtcars_dashboard/app.R
options(old)
```

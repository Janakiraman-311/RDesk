# Launch or list built-in RDesk showcase demo applications

Lists or launches the showcase desktop applications bundled with RDesk:

- cars:

  `CarsAnalyser` — Automotive performance and regression telemetry
  workbench.

- studio:

  `Data Intelligence Studio` — Clinical trial explorer and dataset
  profiling workbench.

- starter:

  `RDeskStarterWorkbench` — Freshly scaffolded
  [`rdesk_create_app()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_create_app.md)
  starter workbench.

Also powers the `rdesk demo` command-line interface.

## Usage

``` r
rdesk_demo(name = NULL, theme = "dark", debug = FALSE, detach = FALSE)
```

## Arguments

- name:

  Optional character string naming the demo to launch: `"cars"`,
  `"studio"`, or `"starter"`. When `NULL` (default), prints the catalog
  of available demos and returns it invisibly.

- theme:

  Theme used for the `"starter"` demo: `"light"`, `"dark"`, or
  `"system"`. Default `"dark"`.

- debug:

  Logical. If `TRUE`, sets `RDESK_DEBUG=1` to enable webview developer
  tools and verbose IPC logging. Default `FALSE`.

- detach:

  Logical. If `TRUE`, launches the demo in the background and returns
  immediately. Default `FALSE`.

## Value

When `name` is `NULL`, returns a `data.frame` describing the available
demos invisibly. Otherwise returns the result of
[`rdesk_run()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_run.md),
invisibly.

## Examples

``` r
demos <- rdesk_demo()
#> [RDesk] Available built-in demos:
#>   cars     - CarsAnalyser (Automotive Performance & Regression Telemetry Workbench)
#>   studio   - Data Intelligence Studio (Clinical Trial Explorer & Dataset Profiler)
#>   starter  - RDeskStarterWorkbench (rdesk_create_app() Starter Template)
#> Run a demo with: RDesk::rdesk_demo('cars')  or  rdesk demo cars
print(demos$name)
#> [1] "cars"    "studio"  "starter"
```

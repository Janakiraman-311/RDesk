# Enable live hot reloading for an RDesk application

`rdesk_watch` enables live monitoring of R source files and UI asset
files (HTML, CSS, JS). When a UI file changes, the application
automatically reloads the page. When an R script changes, the framework
sources the modified module and automatically re-binds application event
handlers.

## Usage

``` r
rdesk_watch(app, enabled = TRUE)
```

## Arguments

- app:

  The RDesk `App` instance to monitor.

- enabled:

  Logical. If `TRUE` (default), enables live monitoring. Set to `FALSE`
  to disable.

## Value

The `App` instance (invisible), to allow method chaining.

## Details

RDesk hot reload works by polling file modification times once per event
loop iteration (roughly every 10 ms). When a change is detected:

- R files:

  The modified file is [`source()`](https://rdrr.io/r/base/source.html)d
  in the global environment. If a function named `init_handlers` exists
  in the global environment, it is called with the App instance so that
  message handlers are re-registered.

- HTML/CSS/JS files:

  A `__reload_ui__` message is sent to the frontend, triggering a full
  page reload in the WebView.

Hot reloading is designed for development only. It should not be enabled
in bundled production builds.

## See also

[App](https://janakiraman-311.github.io/RDesk/reference/App.md)

## Examples

``` r
if (interactive()) {
  app <- App$new(title = "My App")
  rdesk_watch(app)  # or equivalently: app$watch(TRUE)
  app$run()
}
```

# Wrap a message handler to run asynchronously with zero configuration

`async()` is the simplest way to make an RDesk message handler
non-blocking. Wrap any handler function with `async()` and RDesk
automatically handles background execution, loading states, error
toasts, and result routing.

`async()` transforms a standard RDesk message handler into a background
task. The UI remains responsive while the task runs. When finished, a
result message (e.g., `get_data_result`) is automatically sent back to
the UI.

## Usage

``` r
async(
  fn,
  app = NULL,
  loading_message = "Working...",
  cancellable = TRUE,
  error_message = "Error: "
)
```

## Arguments

- fn:

  The handler function, taking a `payload` argument.

- app:

  The RDesk `App` instance. If NULL, tries to resolve from the global
  registry.

- loading_message:

  Message to display in the UI overlay while working.

- cancellable:

  Whether the UI should show a 'Cancel' button.

- error_message:

  Prefix for toast notifications if the task fails.

## Value

A wrapped handler function suitable for `app$on_message()`.

## Details

To ensure the background worker has access to all application logic,
RDesk automatically sources every `.R` file in the application's `R/`
directory before executing the task. It also snapshots currently loaded
packages (excluding system packages) to recreate the environment.

## Examples

``` r
if (interactive()) {
  app$on_message("filter_cars", async(function(payload) {
    mtcars[mtcars$cyl == payload$cylinders, ]
  }, app = app))
}
```

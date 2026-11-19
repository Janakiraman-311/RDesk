# Update progress of a background async task

`async_progress` allows a long-running background task to send progress
updates back to the main application thread. The main thread will
automatically capture these updates and refresh the UI loading overlay.

## Usage

``` r
async_progress(value, message = NULL)
```

## Arguments

- value:

  Numeric value from 0 to 100 representing the progress percentage.

- message:

  Optional character string describing the current step/state. Shown
  beneath the progress bar in the loading overlay.

## Value

Invisible `TRUE` if progress was written successfully, `FALSE` if the
progress file path is not set (e.g. outside a background task).

## Details

Call this function from inside the function passed to
[`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md)
or
[`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md).
It writes a JSON progress record to a temporary file that the main event
loop polls every iteration. The file is cleaned up automatically when
the job completes.

The progress value should increase monotonically from 0 to 100. The
loading overlay in the frontend updates with each new value received.

## See also

[`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md),
[`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md)

## Examples

``` r
if (interactive()) {
  app$on_message("heavy_task", async(function(payload) {
    for (i in 1:10) {
      Sys.sleep(0.5)
      async_progress(i * 10, paste("Step", i, "of 10"))
    }
    "done"
  }, app = app))
}
```

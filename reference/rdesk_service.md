# Service all active RDesk applications

Processes native OS events for all open windows and polls all pending
background jobs for completion. This is the single function you need to
call periodically when running apps in non-blocking mode
(`block = FALSE`).

In blocking mode (`block = TRUE`, the default) `app$run()` calls this
function automatically inside its event loop and you do not need to call
it manually.

## Usage

``` r
rdesk_service()
```

## Value

`invisible(NULL)`

## See also

[App](https://janakiraman-311.github.io/RDesk/reference/App.md) for the
full application API.

## Examples

``` r
if (interactive()) {
  app <- App$new(title = "My App")
  app$run(block = FALSE)  # non-blocking
  # ... do other work here ...
  rdesk_service()         # poll for events
}
```

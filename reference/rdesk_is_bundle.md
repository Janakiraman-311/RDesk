# Check if the app is running in a bundled (standalone) environment

Returns `TRUE` when the current R process was launched by the RDesk stub
binary as part of a compiled standalone application. The stub sets the
`R_BUNDLE_APP` environment variable to `"1"` before starting R. Use this
predicate to switch between development-time and runtime paths (e.g.
logging directories, asset resolution).

## Usage

``` r
rdesk_is_bundle()
```

## Value

`TRUE` if running inside a bundled .exe or .app, `FALSE` otherwise.

## Examples

``` r
# Returns FALSE in a normal interactive R session
rdesk_is_bundle()
#> [1] FALSE
```

# Create a multi-user storage manager

`rdesk_storage` provides file-based persistent storage for desktop
applications. On Windows, it handles multi-user data isolation by
mapping key-value stores to the correct system folder depending on the
requested type.

## Usage

``` r
rdesk_storage(app_name, type = c("local", "roaming", "shared"))
```

## Arguments

- app_name:

  Character string. The application name, used as the subfolder name.

- type:

  Storage type: one of `"roaming"` (user roaming folder, APPDATA),
  `"local"` (user local folder, LOCALAPPDATA), or `"shared"`
  (machine-wide folder, PROGRAMDATA).

## Value

An `RDeskStorage` R6 instance with
[`get()`](https://rdrr.io/r/base/get.html), `set()`,
[`remove()`](https://rdrr.io/r/base/rm.html), `clear()`, `keys()`, and
`path()` methods.

## Details

The three storage types correspond to different Windows user profile
folders:

- roaming:

  User roaming folder (APPDATA). Suitable for per-user preferences that
  should follow the user across machines when roaming profiles are
  enabled.

- local:

  User local folder (LOCALAPPDATA). Suitable for cache, history, or data
  that is specific to one machine.

- shared:

  Machine-wide folder (PROGRAMDATA). Suitable for configuration shared
  by all users on the same computer.

Outside a bundled application (e.g. during development or R CMD check),
all storage types fall back to a subdirectory of
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) to comply with CRAN
policies on persistent file writes.

## See also

[RDeskStorage](https://janakiraman-311.github.io/RDesk/reference/RDeskStorage.md)
for the full method reference.

## Examples

``` r
# Create a local storage manager for an app called "MyApp"
s <- rdesk_storage("MyApp", "local")

# Store and retrieve a value
s$set("last_filter", "cyl == 6")
stopifnot(s$get("last_filter") == "cyl == 6")

# List all keys
s$keys()
#> [1] "last_filter"

# Remove a specific key
s$remove("last_filter")
```

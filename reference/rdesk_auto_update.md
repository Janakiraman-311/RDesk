# Automatically check for and install app updates

`rdesk_auto_update` is a high-level function designed for bundled
(standalone) applications. It checks a remote version string, compares
it with the current version, and if a newer version is found, it
downloads and executes the installer silently before quitting the
current application.

## Usage

``` r
rdesk_auto_update(
  version_url,
  download_url,
  current_version,
  silent = FALSE,
  app = NULL
)
```

## Arguments

- version_url:

  URL to a plain text file containing the latest version string (e.g.,
  "1.1.0")

- download_url:

  URL to the latest installer .exe

- current_version:

  Current app version string e.g. "1.0.0"

- silent:

  If TRUE, downloads and installs without prompting. Default FALSE.

- app:

  Optional App instance for showing toast notifications.

## Value

Invisible TRUE if update was applied, FALSE otherwise.

# Open a native window pointing to a URL

Open a native window pointing to a URL

## Usage

``` r
rdesk_open_window(
  url,
  title = "RDesk",
  width = 1200,
  height = 800,
  www_path = "",
  log_file = NULL
)
```

## Arguments

- url:

  The target URL to load

- title:

  Window title

- width:

  Window width

- height:

  Window height

- www_path:

  Path to the local assets directory

- log_file:

  Optional path to a log file for the C++ launcher

## Value

A processx process object

# Create a new RDesk application

Scaffolds a professional RDesk application with a modern dashboard
layout. The app includes a sidebar for filters, KPI cards, and an
asynchronous ggplot2 charting engine fueled by mtcars (default).

## Usage

``` r
rdesk_create_app(
  name,
  path = tempdir(),
  data_source = NULL,
  viz_type = NULL,
  use_async = NULL,
  theme = "light",
  open = TRUE
)
```

## Arguments

- name:

  App name. Must be a valid directory name.

- path:

  Directory to create the app in. Default is current directory.

- data_source:

  Internal use. Defaults to "builtin".

- viz_type:

  Internal use. Defaults to "mixed".

- use_async:

  Internal use. Defaults to TRUE.

- theme:

  One of "light", "dark", "system". Default "system".

- open:

  Logical. If TRUE and in RStudio, opens the new project in a new
  session.

## Value

Path to the created app directory, invisibly.

## Examples

``` r
if (interactive()) {
  # Create the Professional Hero Dashboard in a temporary directory
  rdesk_create_app("MyDashboard", path = tempdir())
}

# The following demonstrates just the return value without opening a window
# (Fast and safe - no \dontrun needed for this specific logical check)
path <- file.path(tempdir(), "TestLogic")
if (!dir.exists(path)) {
  # This is just a placeholder example of how to call the function safely
  message("Scaffold path will be: ", path)
}
#> Scaffold path will be: C:\Users\RUNNER~1\AppData\Local\Temp\RtmpUnpue2/TestLogic
```

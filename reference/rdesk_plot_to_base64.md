# Convert a ggplot2 object to a base64-encoded PNG string

Convert a ggplot2 object to a base64-encoded PNG string

## Usage

``` r
rdesk_plot_to_base64(plot, width = 6, height = 4, dpi = 96)
```

## Arguments

- plot:

  A ggplot2 object

- width:

  Width in inches (default 6)

- height:

  Height in inches (default 4)

- dpi:

  DPI resolution (default 96)

## Value

A base64-encoded PNG string or a fallback error plot

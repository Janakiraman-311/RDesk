# Generate a base64-encoded error plot

Renders a minimal ggplot2 plot containing the supplied error message
text and returns it as a Base64 data URI. Used as a safe fallback by
[`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md)
when plot generation fails. Returns `NULL` silently if ggplot2 is not
installed.

## Usage

``` r
rdesk_error_plot(message = "Error generating plot")
```

## Arguments

- message:

  Character string to display on the error plot. Defaults to
  `"Error generating plot"`.

## Value

A single-element character string (data URI) or `NULL` if ggplot2 is not
available.

## See also

[`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md)

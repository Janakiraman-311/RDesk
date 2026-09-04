# Convert a ggplot2 object to a base64-encoded PNG string

Renders a ggplot2 object to a temporary PNG file and returns the result
as a Base64-encoded data URI string (`data:image/png;base64,...`). This
format can be assigned directly to an `<img>` tag `src` attribute in the
JavaScript frontend via `app$send()`.

If ggplot2 is not installed, the function stops with a helpful message.
If rendering fails, a fallback error plot is returned instead of `NULL`.

## Usage

``` r
rdesk_plot_to_base64(plot, width = 6, height = 4, dpi = 96)
```

## Arguments

- plot:

  A ggplot2 object to render.

- width:

  Width of the rendered image in inches. Default `6`.

- height:

  Height of the rendered image in inches. Default `4`.

- dpi:

  Dots per inch resolution. Default `96`.

## Value

A single-element character string containing the data URI, or the output
of
[`rdesk_error_plot()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_error_plot.md)
if rendering fails.

## See also

[`rdesk_error_plot()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_error_plot.md)
for the fallback error plot.

## Examples

``` r
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
       ggplot2::geom_point()
  b64 <- rdesk_plot_to_base64(p)
  stopifnot(grepl("^data:image/png;base64,", b64))
}
```

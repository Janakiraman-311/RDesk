# Convert a data frame to a list suitable for JSON serialization

Converts a data frame into the two-part list structure that `rdesk.js`
expects: a `rows` component (list of per-row named lists) and a `cols`
component (character vector of column names). Empty or NULL data frames
return empty containers rather than an error.

## Usage

``` r
rdesk_df_to_list(df)
```

## Arguments

- df:

  A data frame to convert. NULL or zero-row data frames are handled
  gracefully.

## Value

A list with two elements:

- rows:

  A list of named lists, one per row.

- cols:

  A character vector of column names.

## See also

[`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md)
for converting plot output.

## Examples

``` r
result <- rdesk_df_to_list(head(mtcars, 3))
stopifnot(length(result$rows) == 3)
stopifnot("mpg" %in% result$cols)

# NULL input returns empty containers
empty <- rdesk_df_to_list(NULL)
stopifnot(length(empty$rows) == 0)
```

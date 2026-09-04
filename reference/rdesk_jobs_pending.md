# Check if any background jobs are pending

Returns the number of background jobs currently registered in the RDesk
job registry. A value greater than zero means at least one task is still
running or has been submitted but not yet polled for completion.

This function is safe to call from the event loop or from tests without
opening a window.

## Usage

``` r
rdesk_jobs_pending()
```

## Value

Integer. Number of pending jobs (0 means all tasks are complete).

## See also

[`rdesk_jobs_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_list.md)
for more detail about each pending job.

## Examples

``` r
# Fast, non-interactive task check (safe to run unconditionally)
rdesk_jobs_pending()
#> [1] 0
```

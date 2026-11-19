# List currently pending background jobs

Returns a data frame snapshot of all jobs currently registered in the
RDesk job registry. Useful for debugging and monitoring from the R
console while an application is running.

## Usage

``` r
rdesk_jobs_list()
```

## Value

A `data.frame` with the following columns:

- job_id:

  Character. Unique job identifier.

- started:

  POSIXct. Time the job was submitted.

- backend:

  Character. Either `"mirai"` or `"callr"`.

- app_id:

  Character. ID of the App instance that owns the job, or `NA`.

Returns a zero-row data frame when no jobs are pending.

## See also

[`rdesk_jobs_pending()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_pending.md),
[`rdesk_cancel_job()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_cancel_job.md)

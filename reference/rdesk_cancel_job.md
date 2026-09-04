# Cancel a running background job

Attempts to stop a background job and remove it from the job registry.
The behaviour differs between the two async backends:

- callr:

  The subprocess is killed immediately via `process$kill()`.

- mirai:

  The task inside the persistent daemon cannot be interrupted. The job
  is removed from the registry only, so its `on_done` and `on_error`
  callbacks are suppressed. The daemon itself keeps running.

## Usage

``` r
rdesk_cancel_job(job_id)
```

## Arguments

- job_id:

  Character string. The job ID returned by
  [`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md).

## Value

`invisible(TRUE)` if the job was found and cancelled, `invisible(FALSE)`
if no job with that ID exists.

## See also

[`rdesk_async()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_async.md),
[`rdesk_jobs_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_jobs_list.md)

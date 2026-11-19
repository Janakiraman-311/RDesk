# Run a task in the background

Automatically switches between 'mirai' (persistent daemons) and 'callr'
(on-demand processes).

## Usage

``` r
rdesk_async(
  task,
  args = list(),
  on_done = NULL,
  on_error = NULL,
  timeout_sec = NULL,
  app_id = NULL
)
```

## Arguments

- task:

  A function to run in the background.

- args:

  A list of arguments to pass to the task.

- on_done:

  Callback function(result) called when the task finishes successfully.

- on_error:

  Callback function(error) called if the task fails.

- timeout_sec:

  Optional timeout in seconds. If exceeded, the job is cancelled and
  `on_error()` receives a timeout error.

- app_id:

  Optional App ID used to associate a job with a specific app.

## Value

Invisible job ID.

## Examples

``` r
# Fast, non-interactive task check (safe to unwrap)
rdesk_jobs_pending()
#> [1] 0

if (interactive()) {
  # Run a long-running computation in the background
  rdesk_async(
    task = function(n) { Sys.sleep(2); sum(runif(n)) },
    args = list(n = 1e6),
    on_done = function(res) message("Task finished: ", res),
    on_error = function(err) message("Task failed: ", err$message)
  )
}
```

# High-Performance Asynchronous Processing with mirai

``` r

RDesk::rdesk_jobs_pending()
#> [1] 0
```

In a native desktop application, maintaining a highly responsive user
interface is a primary design goal. If a user clicks a button to load a
large dataset, compile a plot, or run a statistical model, and the user
interface freezes while R computes, the user experience degrades.

To address this, RDesk implements a non-blocking asynchronous processing
engine. Under the hood, RDesk utilizes the **mirai** package to offload
intensive computations to persistent background worker processes,
ensuring the frontend UI remains interactive at all times.

------------------------------------------------------------------------

## The Asynchronous Architecture

RDesk operates as a parent process managing the main R6 event loop,
while launching WebView2 as a native child window. To keep communication
fast and secure, RDesk avoids loopback network stacks and HTTP overhead,
relying instead on standard I/O pipes.

When a long-running task is submitted, RDesk offloads the work to
**mirai background daemons**.

The diagrams below illustrate how RDesk, standard input/output pipes,
and the `mirai` daemon pool interact to process background operations.

### 1. Architectural Component Map

This diagram illustrates the process and memory boundaries between the
frontend user interface, the main R process event loop, and the
pre-warmed background worker processes.

``` mermaid
graph TD
    subgraph Core [Main Application Event Flow]
        Loop[R6 Event Loop] -->|1. Submit Job| Poller[Unresolved Job Poller]
        Poller -->|2. Offload Task| Workers[mirai Daemon Pool]
        Workers -->|3. Complete Job| Poller
        Poller -->|4. Push Results| Loop
    end

    UI[Client UI <br/> WebView2 Shell] <-->|stdin / stdout pipes| Loop
```

### 2. Message Lifecycle Sequence

This sequence diagram outlines the chronological flow of a message, from
a user action in the UI, through the stdin pipe to R, submission to a
mirai background daemon, non-blocking state polling, and the final
return of results to the frontend.

``` mermaid
sequenceDiagram
    autonumber
    participant UI as WebView2 UI (HTML/JS)
    participant Main as Main R Process (Event Loop)
    participant Workers as mirai Daemon Pool

    UI->>Main: 1. Send action with payload
    Note over Main: Receives message envelope<br/>and schedules handler
    Main->>Workers: 2. Offload computation
    Note over Workers: Worker process executes task<br/>in the background (non-blocking)
    loop Event Loop
        Main->>Main: 3. Non-blocking job polling
    end
    Workers-->>Main: 4. Complete task and return results
    Main->>UI: 5. Push results back to UI
```

------------------------------------------------------------------------

## Persistent Daemons vs On-Demand Processes

RDesk implements a **dual-backend** async mechanism that automatically
selects the best available engine:

1.  **mirai (Persistent Daemons - Default)**: Starts a pool of
    pre-warmed background workers at application launch using
    [`mirai::daemons()`](https://mirai.r-lib.org/reference/daemons.html).
    When an asynchronous task is submitted, it is dispatched to an
    existing worker instantly.
2.  **callr (On-Demand Processes - Fallback)**: Spins up a fresh R
    process for each task and terminates it upon completion. This is
    utilized in headless CI environments or systems where background
    daemons are unavailable.

### Why mirai is the preferred backend:

- **Zero Startup Latency**: Pre-warmed background workers start
  executing tasks in milliseconds, whereas spawning a fresh R process on
  demand via `callr` adds 1–2 seconds of process-creation overhead for
  each execution.
- **Resource Preservation**: A fixed pool of persistent workers ensures
  background memory usage remains flat and predictable, avoiding spikes
  from concurrent process launches.
- **Automatic Lifecycle Handling**: Daemons are automatically spun up on
  `App$run()` startup and cleanly terminated on application shutdown,
  preventing orphaned zombie processes.

------------------------------------------------------------------------

## Under the Hood: The Developer Experience

For the application developer, RDesk abstracts this multi-process
coordination into the standard
[`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md)
wrapper.

``` r

# In R/server.R
app$on_message("run_model", async(function(payload) {
  # This code runs entirely in an isolated mirai worker.
  # The UI remains 100% interactive and responsive.
  Sys.sleep(3) # Simulate a heavy statistical modeling task
  result <- kmeans(mtcars, centers = payload$centers)
  
  list(centers = result$centers, size = result$size)
}, app = app, loading_message = "Running K-Means..."))
```

### Critical Rules for Async Workers:

Because the
[`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md)
handler runs in an isolated `mirai` background process: \* **No `app$`
Access**: Background workers cannot reach the main R process. Do not
call `app$send()`, `app$toast()`, or `app$dialog_*` inside the worker
closure. Return the final data as a list, and the wrapper handles
routing. \* **Scoped Closures**: Ensure any package dependencies are
explicitly imported (using
[`library()`](https://rdrr.io/r/base/library.html) inside the worker, or
listed in the `DESCRIPTION` Imports) and variables are passed via the
payload or explicitly bound in the local closure.

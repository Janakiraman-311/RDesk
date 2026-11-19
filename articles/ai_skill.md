# AI Coding Assistant

``` r

packageVersion("RDesk")
#> [1] '1.0.7'
```

## RDesk AI Skill Reference File (v1.0.7)

This reference file serves as the definitive engineering and behavioral
blueprint for AI coding agents developing, debugging, or maintaining
RDesk applications. It maps out the package’s multi-directory structure,
core contracts, API behaviors, design constraints, and common
implementation pitfalls.

------------------------------------------------------------------------

### SECTION 1: Architecture & Process Model

RDesk applications utilize a dual-process desktop architecture:

    [rdesk-launcher.exe] (Frontend Shell)  <--Standard I/O Pipes-->  [R Process] (Backend Logic)
       - WebView2 rendering control                                  - R6 event loop (App$run())
       - Virtual HTTPS folder mapping                                - Logic handlers (on_message())
       - Native windows, tray & menus                                - Background tasks (mirai)
       - Watchdog process cleanup                                    - Offline computation

#### Core Architectural Layers:

- **Layer 5 (Application Code)**: R logic (`R/server.R`) and UI assets
  (`www/`). Developers only write and modify this layer.
- **Layer 4 (High-Level Plugin API)**: Package utilities like
  [`async()`](https://janakiraman-311.github.io/RDesk/reference/async.md),
  [`rdesk_auto_update()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_auto_update.md),
  and hot-reloading watchers.
- **Layer 3 (R Core Event Loop)**: The R6 `App` class that services
  messaging callbacks.
- **Layer 2 (Zero-Port IPC Bridge)**: Low-level message passing using
  WebView2’s native bridge (stdin/stdout pipes). No network sockets are
  ever opened.
- **Layer 1 (Native Launcher)**: Lightweight C++ shell compiled during
  package installation.

#### Key Development Rules:

1.  **Process Isolation**: Do not attempt to modify or recompile Layer 1
    or Layer 2. Layer 1 C++ is compiled automatically during standard R
    package installation.
2.  **Zero Network Exposure**: RDesk operates fully offline and binds to
    no network ports (`httpuv`, `WebSockets`). Communication uses
    standard I/O streams. Never introduce code that opens local TCP/UDP
    ports.
3.  **Explicit Messaging**: State is not implicitly reactive. State
    synchronisation between R and the UI must be triggered via explicit
    message envelopes.

------------------------------------------------------------------------

### SECTION 2: Project Directory Mappings

Every RDesk application must adhere to this standardized file layout:

    MyApp/
    ├── app.R              # Main application entry point (keep thin)
    ├── DESCRIPTION        # Application metadata and dependency list
    ├── R/                 # Backend R modules
    │   ├── server.R       # Message handlers & initialization (primary logic file)
    │   ├── data.R         # Data loading, extraction, and transformation
    │   └── plots.R        # ggplot2 and base chart generation functions
    └── www/               # Frontend UI assets
        ├── index.html     # HTML5 markup structure
        ├── css/
        │   └── style.css  # Application styling
        └── js/
            ├── app.js     # Client event handlers and UI updates
            └── rdesk.js   # RDesk frontend runtime bridge (NEVER EDIT THIS FILE)

#### Standard `app.R` Entry Point:

``` r

app_dir <- tryCatch(
  if (nzchar(Sys.getenv("R_BUNDLE_APP"))) getwd()
  else dirname(rstudioapi::getActiveDocumentContext()$path),
  error = function(e) getwd()
)

library(RDesk)

# Dynamically source all backend modules
lapply(
  list.files(file.path(app_dir, "R"), pattern = "\\.R$", full.names = TRUE),
  source
)

app <- App$new(
  title  = "My RDesk App",
  width  = 1100L,
  height = 740L,
  www    = file.path(app_dir, "www")
)

init_handlers(app)
app$run()
```

#### Directory & File Rules:

- **Thin Entry Point**: Never place business logic directly in `app.R`.
  Sourcing modular R files and calling `init_handlers(app)` must be the
  only operations in `app.R`.
- **Dynamic Sourcing**: Always source backend files using the
  `lapply(list.files(...))` pattern. Individual explicit
  [`source()`](https://rdrr.io/r/base/source.html) calls by filename
  break RDesk’s directory packaging and hot-reloading hooks.
- **Local Runtime File**: `www/js/rdesk.js` is the framework client
  library. Never import it from a CDN or alter its contents.

------------------------------------------------------------------------

### SECTION 3: The IPC Message Envelope Contract

All messaging across the R-to-JS bridge uses this exact JSON envelope
structure:

``` json
{
  "id": "msg_unique_hash",
  "type": "message_type",
  "version": "1.0",
  "payload": {},
  "timestamp": 1716382104.123
}
```

#### Protocol & Handler Rules:

1.  **Response Routing**: A message sent from JS of type `"foo"`
    automatically returns its response payload to a JS listener
    registered for `"foo_result"`.
2.  **Handler Output**: R `on_message()` handlers must return a standard
    R `list` or `NULL`. The framework automatically serialises and wraps
    the output in the envelope. Do not wrap return values in
    [`rdesk_message()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_message.md)
    inside handlers.
3.  **Envelope Serialization**: Never construct JSON strings manually.
    Use `app$send()` on the R side, and `rdesk.send()` on the JS side.
4.  **System Messaging**: Message types starting with a double
    underscore (e.g., `__loading__`, `__progress__`, `__reload_ui__`)
    are reserved for core framework signaling. Never define custom
    application messages with the `__` prefix.

------------------------------------------------------------------------

### SECTION 4: Backend Event Handlers (`R/server.R`)

Define event handlers inside `init_handlers(app)` in `R/server.R`.

``` r

init_handlers <- function(app) {
  
  # Triggered once when the UI window is fully initialized
  app$on_ready(function() {
    # Define native window menu
    app$set_menu(list(
      File = list(
        "Open..." = function() app$send("trigger_open", list()),
        "---",
        "Exit"    = app$quit
      ),
      Help = list(
        "About"   = function() app$toast("RDesk v1.0.7", type = "info")
      )
    ))
    
    # Push initial dataset
    df <- load_initial_data()
    app$send("data_ready", rdesk_df_to_list(df))
  })
  
  # Standard request-response handler
  app$on_message("get_filtered_data", function(payload) {
    # payload matches the JS payload object
    df <- load_subset(payload$filter_val)
    rdesk_df_to_list(df)
  })
}
```

#### Low-Level Native APIs:

- **Toasts**:
  `app$toast("message", type = "success" | "error" | "info" | "warning")`
- **Native Dialogs**:
  - `app$dialog_open(title = "Open", filters = "CSV (*.csv)|*.csv")` -\>
    Returns character path or `NULL`
  - `app$dialog_save(title = "Save", filters = "CSV (*.csv)|*.csv", default = "export.csv")`
  - `app$dialog_folder(title = "Select Folder")`
- **Loading Overlays**: `app$loading_start("text", cancellable = TRUE)`,
  `app$loading_progress(50)`, `app$loading_done()`

------------------------------------------------------------------------

### SECTION 5: Asynchronous Execution & Task Tiers

To prevent blocking the single-threaded R event loop during computation,
RDesk utilizes a three-tier async architecture:

#### Tier 1: Asynchronous Handler Wrapper (`async()`)

Applies to 95% of background processing needs. Automatically manages
loading overlays, routing, and task cancellation.

``` r

app$on_message("compute_stats", async(function(payload) {
  # Executed inside an isolated background worker process
  # DO NOT call app$ methods inside this closure
  # DO NOT access global variables; pass them via payload or capture them explicitly
  df <- load_raw_data(payload$source)
  result <- run_calculation(df)
  list(stats = result)
}, app = app, loading_message = "Processing calculation..."))
```

#### Asynchronous Progress Updates:

To push real-time progress updates from a background worker:

``` r

app$on_message("heavy_loop", async(function(payload) {
  steps <- payload$steps
  for (i in seq_along(steps)) {
    process_step(steps[[i]])
    async_progress(
      value   = round(i / length(steps) * 100),
      message = paste("Processing step", i, "of", length(steps))
    )
  }
  list(complete = TRUE)
}, app = app))
```

#### Tier 2: Explicit Async Control (`rdesk_async()`)

Used when fine-grained callback control is required.

``` r

job_id <- rdesk_async(
  task     = function(x) run_heavy(x),
  args     = list(x = data),
  on_done  = function(res) app$send("done", res),
  on_error = function(err) app$toast(err$message, type = "error")
)
app$loading_start("Running...", cancellable = TRUE, job_id = job_id)
```

#### Tier 3: Direct Asynchronous Workers (`mirai`)

For expert use cases requiring direct interaction with background
processes.

``` r

m <- mirai::mirai(
  slow_function(x),
  slow_function = slow_function,
  x = input_data
)
```

------------------------------------------------------------------------

### SECTION 6: Client-Side JavaScript Integration

Communicate with the backend R process using the globally available
`rdesk` object:

``` javascript
// Wrap initialization inside ready() to ensure bridge is fully established
rdesk.ready(function() {
  rdesk.send("get_initial_state", {})
    .then(res => renderUI(res))
    .catch(err => console.error(err));
});

// Listen for push notifications from R
rdesk.on("update_data", function(data) {
  updateChart(data);
});

// Clean up listeners
rdesk.off("update_data");
```

#### Standard DOM Mapping Patterns:

- **Base64 Charts**:

  ``` javascript
  rdesk.on("render_chart_result", data => {
    document.getElementById("chart-img").src = "data:image/png;base64," + data.chart;
  });
  ```

- **Structured Tables**:

  ``` javascript
  rdesk.on("render_table_result", data => {
    const rows = data.rows.map(r => `<tr>${data.cols.map(c => `<td>${r[c]}</td>`).join('')}</tr>`).join('');
    document.getElementById("table-body").innerHTML = rows;
  });
  ```

#### JS Bridging Rules:

1.  Always wrap initial page-load `send()` calls inside `rdesk.ready()`.
    Calling `send()` before the native bridge is established throws
    silent errors.
2.  Never attempt to use `fetch()`, `XMLHttpRequest`, or `WebSocket` to
    communicate with the R process. Always use `rdesk.send()` and
    `rdesk.on()`.

------------------------------------------------------------------------

### SECTION 7: Charts & Data Serialisation

#### 1. Generating Base64 Plot Strings

Convert plots to strings for transmission over the standard input/output
pipe:

``` r

# In R/plots.R
generate_trend_plot <- function(df) {
  p <- ggplot2::ggplot(df, ggplot2::aes(x = date, y = value)) +
    ggplot2::geom_line(colour = "#1a1a2e", linewidth = 1) +
    ggplot2::theme_minimal()
  rdesk_plot_to_base64(p)
}

# In R/server.R handler
app$on_message("get_trend", function(payload) {
  df <- load_data()
  list(chart = generate_trend_plot(df))
})
```

#### 2. Formatting Data Frames for JSON

Data frames must be converted to `$rows` (list of row-lists) and `$cols`
(column names) for clean client-side parsing:

``` r

# In R/server.R handler
app$on_message("get_raw_table", function(payload) {
  df <- head(mtcars)
  rdesk_df_to_list(df)
})
```

------------------------------------------------------------------------

### SECTION 8: Shiny Migration Guide

#### Side-by-Side Architectural Mapping

| Shiny Concept | RDesk Desktop Equivalent |
|:---|:---|
| `input$x` | `payload$x` inside `app$on_message("x_changed", ...)` |
| `reactive({...})` | Standard R function called explicitly by the handler |
| `renderPlot({...})` | [`rdesk_plot_to_base64()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_plot_to_base64.md) returned inside a list |
| `renderTable({...})` | [`rdesk_df_to_list()`](https://janakiraman-311.github.io/RDesk/reference/rdesk_df_to_list.md) returned inside a list |
| `observeEvent(input$x, {...})` | `app$on_message("x_changed", function(payload) {...})` |
| `showNotification()` | `app$toast()` |
| `withProgress()` | `async(..., loading_message = "...")` |
| `fileInput()` | `app$dialog_open()` |
| `downloadHandler()` | `app$dialog_save()` |

#### Complete Migration Blueprint:

``` r

# --- 1. SHINY ORIGINAL (server.R) ---
server <- function(input, output, session) {
  filtered <- reactive({
    mtcars[mtcars$cyl == input$cyl_filter, ]
  })
  output$scatter <- renderPlot({
    ggplot2::ggplot(filtered(), ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
  })
  output$table <- renderTable({ filtered() })
}
```

``` r

# --- 2. RDESK REWRITE (R/server.R) ---
init_handlers <- function(app) {
  app$on_ready(function() {
    app$send("data_ready", rdesk_df_to_list(mtcars))
  })

  app$on_message("filter_changed", async(function(payload) {
    df <- mtcars[mtcars$cyl == payload$cyl_filter, ]
    p  <- ggplot2::ggplot(df, ggplot2::aes(wt, mpg)) + ggplot2::geom_point()
    list(
      chart = rdesk_plot_to_base64(p),
      table = rdesk_df_to_list(df)
    )
  }, app = app))
}
```

``` javascript
// --- 3. RDESK FRONTEND (www/js/app.js) ---
rdesk.ready(function() {
  rdesk.send("get_data", {});
});

document.getElementById("cyl-filter").addEventListener("change", function() {
  rdesk.send("filter_changed", { cyl_filter: parseInt(this.value) });
});

rdesk.on("filter_changed_result", function(data) {
  document.getElementById("chart").src = "data:image/png;base64," + data.chart;
  renderTable(data.table.rows, data.table.cols);
});
```

------------------------------------------------------------------------

### SECTION 9: Common Pitfalls & Solutions

#### Mistake 1: Invoking main-process APIs inside `async()` workers

``` r

# WRONG
app$on_message("task", async(function(payload) {
  res <- run_calculation(payload)
  app$toast("Task Completed!")  # ERROR: app$ is not available in isolated worker processes
  list(data = res)
}, app = app))

# CORRECT
app$on_message("task", async(function(payload) {
  res <- run_calculation(payload)
  list(data = res)  # Return value is pushed automatically to task_result
}, app = app))
```

#### Mistake 2: Accessing unscoped global variables in workers

``` r

# WRONG
dataset <- load_heavy_data()
app$on_message("run", async(function(payload) {
  process(dataset)  # ERROR: dataset is not bound in the worker process environment
}, app = app))

# CORRECT
dataset <- load_heavy_data()
app$on_message("run", async(function(payload) {
  process(payload$data)  # Pass the object explicitly via payload
}, app = app))

# OR
local_data <- dataset
app$on_message("run", async(function(payload) {
  process(local_data)  # Captured in the closure, serialised to the worker
}, app = app))
```

#### Mistake 3: Forgetting to flush the output stream

``` r

# WRONG - Output might buffer in compiled desktop mode
cat(jsonlite::toJSON(msg), "\n")

# CORRECT - Always flush stdout after writing low-level console logs
cat(jsonlite::toJSON(msg), "\n")
flush(stdout())
```

#### Mistake 4: Writing files to the working directory in examples

``` r

# WRONG - Violates CRAN policy
RDesk::build_app(app_dir = "MyApp", out_dir = "dist")

# CORRECT - Always write files inside tempdir()
RDesk::build_app(app_dir = "MyApp", out_dir = file.path(tempdir(), "dist"))
```

#### Mistake 5: Using `installed.packages()` to check dependencies

``` r

# WRONG - Extremely slow and violates CRAN guidelines
if ("ggplot2" %in% installed.packages()[,"Package"]) { ... }

# CORRECT - Fact-based, fast package checking
if (requireNamespace("ggplot2", quietly = TRUE)) { ... }
```

#### Mistake 6: Changing working directory without restoring state

``` r

# WRONG
setwd(build_dir)
# ... tasks ...
setwd(original_dir) # Never executes if an error occurs mid-task

# CORRECT
old_wd <- getwd()
on.exit(setwd(old_wd), add = TRUE)
setwd(build_dir)
```

------------------------------------------------------------------------

### SECTION 10: Development, Testing & Build Verification

#### Local Hot-Reload Workflows

- **Manual Development Loop**: Sourcing `app.R` launches the application
  window. Close the window, edit files in `R/server.R` or `www/`, and
  source `app.R` again.
- **Automatic reloading**: Run `rdesk_watch(app)` during development to
  live-reload UI assets when saved.

#### Headless Verification Mode (`ci_mode`)

To run unit tests on message handlers without spawning a browser window:

``` r

options(rdesk.ci_mode = TRUE)
library(RDesk)

# Source Server handlers and mock dynamic events
source("R/server.R")
# Handlers are initialized without spawning a physical WebView2 window
```

#### Reproducible Bundles via `renv`

- If `renv` is active, RDesk automatically detects the local
  environment.
- [`build_app()`](https://janakiraman-311.github.io/RDesk/reference/build_app.md)
  writes a frozen `renv.lock` into the distributable, copying your exact
  package versions to ensure ABI compatibility and prevent
  package-mismatch crashes.

------------------------------------------------------------------------

### SECTION 11: Quick Reference Card

#### Core R API Functions:

``` r

# Create scaffolding
rdesk_create_app("MyApp")

# Core Window Setup
app <- App$new(title = "App", width = 1100L, height = 740L, www = "www/")
app$on_ready(function() { ... })
app$on_message("msg_type", function(payload) { list(...) })
app$run()

# Server-Side Push
app$send("type", list(key = value))

# Dialogs
app$dialog_open(title = "Open File", filters = "CSV (*.csv)|*.csv")
app$dialog_save(title = "Save File", filters = "CSV (*.csv)|*.csv", default = "data.csv")
app$dialog_folder(title = "Select Export Folder")

# System Control
app$toast("message", type = "success|error|info|warning")
app$notify("Title", "Body Text")
app$maximize()
app$quit()

# Loading States
app$loading_start("Message...", cancellable = TRUE, job_id = "job_1")
app$loading_progress(50)
app$loading_done()

# Async Operations
rdesk_async(task, args, on_done, on_error)
rdesk_cancel_job("job_id")
rdesk_jobs_pending()
```

#### Core JavaScript Client Functions:

``` javascript
// Send data to R, returns Promise
rdesk.send("msg_type", { payload_key: "value" })
  .then(res => { ... })
  .catch(err => { ... });

// Listen for push notifications from R
rdesk.on("push_type", function(data) { ... });

// Run when the browser bridge is active
rdesk.ready(function() { ... });

// Deregister listener
rdesk.off("push_type");
```

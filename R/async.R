# R/async.R
# Background task management for RDesk: Dual Backend (callr + mirai)

#' @importFrom digest digest
#' @importFrom callr r_bg
#' @importFrom stats runif
NULL

# Job registry - a private environment to track running jobs
.rdesk_jobs <- new.env(parent = emptyenv())

#' Start the mirai daemon pool
#'
#' Called once at App$run() startup when rdesk.async_backend is "mirai".
#' @return Invisible number of workers started.
#' @keywords internal
rdesk_start_daemons <- function() {
  if (getOption("rdesk.async_backend", "callr") != "mirai") return(invisible(NULL))
  if (!requireNamespace("mirai", quietly = TRUE)) return(invisible(NULL))

  # Cap at 2 workers for CRAN compliance (avoid Note on CPU vs Elapsed time)
  n <- min(2L, max(1L, parallel::detectCores(logical = FALSE) - 1L))
  mirai::daemons(n)
  message("[RDesk] mirai daemon pool started: ", n, " workers")
  invisible(n)
}

#' Stop the mirai daemon pool
#'
#' Called at App$cleanup().
#' @keywords internal
rdesk_stop_daemons <- function() {
  if (getOption("rdesk.async_backend", "callr") != "mirai") return(invisible(NULL))
  if (!requireNamespace("mirai", quietly = TRUE)) return(invisible(NULL))
  
  mirai::daemons(0)
  message("[RDesk] mirai daemon pool stopped")
  invisible(NULL)
}

#' Run a task in the background
#'
#' Automatically switches between 'mirai' (persistent daemons) and 'callr' (on-demand processes).
#'
#' @param task A function to run in the background.
#' @param args A list of arguments to pass to the task.
#' @param on_done Callback function(result) called when the task finishes successfully.
#' @param on_error Callback function(error) called if the task fails.
#' @param timeout_sec Optional timeout in seconds. If exceeded, the job is
#'   cancelled and \code{on_error()} receives a timeout error.
#' @param app_id Optional App ID used to associate a job with a specific app.
#' @return Invisible job ID.
#' @examples
#' # Fast, non-interactive task check (safe to unwrap)
#' rdesk_jobs_pending()
#' 
#' if (interactive()) {
#'   # Run a long-running computation in the background
#'   rdesk_async(
#'     task = function(n) { Sys.sleep(2); sum(runif(n)) },
#'     args = list(n = 1e6),
#'     on_done = function(res) message("Task finished: ", res),
#'     on_error = function(err) message("Task failed: ", err$message)
#'   )
#' }
#' @export
rdesk_async <- function(task, args = list(), on_done = NULL, on_error = NULL,
                        timeout_sec = NULL, app_id = NULL) {
  if (missing(task) || is.null(task)) stop("Missing task function")
  if (!is.function(task)) stop("task must be a function")

  # Generate a unique job ID
  job_id  <- paste0("job_", digest::digest(runif(1), algo = "crc32"))
  backend <- getOption("rdesk.async_backend", "callr")

  if (backend == "mirai" && requireNamespace("mirai", quietly = TRUE)) {
    # mirai path - submit to persistent daemon pool
    # We use .expr to execute the task with provided args
    m <- mirai::mirai(
      .expr = do.call(task, args),
      task  = task,
      args  = args
    )
    .rdesk_jobs[[job_id]] <- list(
      job      = m,
      backend  = "mirai",
      on_done  = on_done,
      on_error = on_error,
      started  = Sys.time(),
      timeout_sec = timeout_sec,
      app_id = app_id
    )
  } else {
    # callr fallback - on-demand process spawning
    job <- callr::r_bg(task, args = args, supervise = TRUE)
    
    .rdesk_jobs[[job_id]] <- list(
      job      = job,
      backend  = "callr",
      on_done  = on_done,
      on_error = on_error,
      started  = Sys.time(),
      timeout_sec = timeout_sec,
      app_id = app_id
    )
  }
  
  invisible(job_id)
}

#' Poll background jobs
#'
#' This is called internally by the main event loop to check if any 
#' background tasks have finished. Handles both mirai and callr backends.
#'
#' @keywords internal
rdesk_poll_jobs <- function() {
  job_ids <- ls(.rdesk_jobs, pattern = "^job_")
  for (id in job_ids) {
    entry   <- .rdesk_jobs[[id]]
    backend <- entry[["backend"]]
    
    # Strictly validate that entry is a list and contains a job
    if (!is.list(entry) || is.null(entry[["job"]])) {
      rm(list = id, envir = .rdesk_jobs)
      next
    }
    
    job <- entry[["job"]]
    timeout_sec <- entry[["timeout_sec"]]

    if (!is.null(timeout_sec) &&
        difftime(Sys.time(), entry[["started"]], units = "secs") > timeout_sec) {
      rdesk_cancel_job(id)
      if (is.function(entry[["on_error"]])) {
        tryCatch(
          entry[["on_error"]](simpleError(paste0("Job timed out after ", timeout_sec, " seconds"))),
          error = function(e) warning("[RDesk] on_error handler failed: ", e$message)
        )
      }
      next
    }

    # Check completion based on backend API
    is_done <- if (backend == "mirai") {
      !mirai::unresolved(job)
    } else {
      # callr path
      status <- tryCatch(job$poll_io(0), error = function(e) NULL)
      if (is.null(status)) FALSE else !job$is_alive()
    }

    if (!is_done) next

    # Job finished - remove from registry first to avoid re-polling
    rm(list = id, envir = .rdesk_jobs)

    # Extract result or error based on backend
    if (backend == "mirai") {
      result <- job$data
      if (inherits(result, "mirai_error")) {
        if (is.function(entry[["on_error"]])) {
          tryCatch(entry[["on_error"]](simpleError(as.character(result))),
            error = function(e) warning("[RDesk] on_error handler failed: ", e$message))
        }
      } else {
        if (is.function(entry[["on_done"]])) {
          tryCatch(entry[["on_done"]](result),
            error = function(e) warning("[RDesk] on_done handler failed: ", e$message))
        }
      }
    } else {
      # callr path
      result <- tryCatch(job$get_result(), error = function(e) e)
      if (inherits(result, "error")) {
        if (is.function(entry[["on_error"]])) {
          tryCatch(entry[["on_error"]](result),
            error = function(e) warning("[RDesk] on_error handler failed: ", e$message))
        }
      } else {
        if (is.function(entry[["on_done"]])) {
          tryCatch(entry[["on_done"]](result),
            error = function(e) warning("[RDesk] on_done handler failed: ", e$message))
        }
      }
    }
  }
}

#' Cancel a running background job
#'
#' @param job_id The ID of the job to cancel.
#' @return Invisible TRUE if cancelled, FALSE if not found.
#' @export
rdesk_cancel_job <- function(job_id) {
  if (exists(job_id, envir = .rdesk_jobs)) {
    entry <- .rdesk_jobs[[job_id]]
    backend <- entry[["backend"]]
    
    if (backend == "mirai") {
      # mirai has no direct 'kill' for tasks already in a persistent daemon.
      # We simply remove from the registry so the callback never fires.
      # The daemon keeps running until completion, so cancellation here only
      # suppresses callbacks and UI follow-up.
      warning("[RDesk] Cancellation requested for a mirai job. The running task cannot be interrupted; only callbacks are suppressed.")
      rm(list = job_id, envir = .rdesk_jobs)
    } else {
      # callr path: kill the process
      if (is.list(entry) && !is.null(entry[["job"]])) {
        if (entry[["job"]]$is_alive()) entry[["job"]]$kill()
      }
      rm(list = job_id, envir = .rdesk_jobs)
    }
    invisible(TRUE)
  } else {
    invisible(FALSE)
  }
}

#' Check if any background jobs are pending
#'
#' @return Number of pending jobs.
#' @export
rdesk_jobs_pending <- function() {
  length(ls(.rdesk_jobs, pattern = "^job_"))
}

#' List currently pending background jobs
#'
#' @return A data.frame with job ID, started time, backend, and app ID.
#' @export
rdesk_jobs_list <- function() {
  job_ids <- ls(.rdesk_jobs, pattern = "^job_")
  if (length(job_ids) == 0) {
    return(data.frame(
      job_id = character(0),
      started = as.POSIXct(character(0)),
      backend = character(0),
      app_id = character(0),
      stringsAsFactors = FALSE
    ))
  }

  rows <- lapply(job_ids, function(id) {
    entry <- .rdesk_jobs[[id]]
    data.frame(
      job_id = id,
      started = as.POSIXct(entry[["started"]], origin = "1970-01-01"),
      backend = if (is.null(entry[["backend"]])) NA_character_ else entry[["backend"]],
      app_id = if (is.null(entry[["app_id"]])) NA_character_ else entry[["app_id"]],
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, rows)
}

#' Wrap a message handler to run asynchronously with zero configuration
#'
#' @description
#' \code{async()} is the simplest way to make an RDesk message handler
#' non-blocking. Wrap any handler function with \code{async()} and RDesk
#' automatically handles background execution, loading states, error toasts,
#' and result routing.
#'
#' `async()` transforms a standard RDesk message handler into a background task.
#' The UI remains responsive while the task runs. When finished, a result
#' message (e.g., `get_data_result`) is automatically sent back to the UI.
#'
#' @details
#' To ensure the background worker has access to all application logic, RDesk
#' automatically sources every `.R` file in the application's `R/` directory
#' before executing the task. It also snapshots currently loaded packages
#' (excluding system packages) to recreate the environment.
#'
#' @param fn The handler function, taking a `payload` argument.
#' @param app The RDesk `App` instance. If NULL, tries to resolve from the global registry.
#' @param loading_message Message to display in the UI overlay while working.
#' @param cancellable Whether the UI should show a 'Cancel' button.
#' @param error_message Prefix for toast notifications if the task fails.
#' @return A wrapped handler function suitable for `app$on_message()`.
#'
#' @examples
#' if (interactive()) {
#'   app$on_message("filter_cars", async(function(payload) {
#'     mtcars[mtcars$cyl == payload$cylinders, ]
#'   }, app = app))
#' }
#' @export
async <- function(fn,
                  app             = NULL,
                  loading_message = "Working...",
                  cancellable     = TRUE,
                  error_message   = "Error: ") {
  
  if (!is.function(fn)) stop("task must be a function")

  # Capture packages loaded NOW at registration time
  # This is intentional - we snapshot the environment when the
  # developer calls async(), not when the task runs
  base_pkgs <- c("base", "methods", "datasets", "utils",
                 "grDevices", "graphics", "stats", "R6",
                 "jsonlite", "digest", "processx", "callr", "mirai")

  loaded_pkgs <- tryCatch({
    loaded <- search()
    pkg_names <- gsub("^package:", "", grep("^package:", loaded, value = TRUE))
    unique(c(setdiff(pkg_names, base_pkgs), "RDesk"))
  }, error = function(e) character(0))

  # Store the message type for result routing
  # This gets populated when on_message() registers the handler
  msg_type_env <- new.env(parent = emptyenv())
  msg_type_env$type <- NULL

  # Return the actual handler function
  wrapper <- function(payload) {
    # Resolve app reference - try explicit param first, then global registry
    app_obj <- app
    if (is.null(app_obj)) {
      app_ids <- ls(.rdesk_apps)
      if (length(app_ids) > 0) {
        warning("[RDesk] async(): app should be supplied explicitly in multi-window contexts; falling back to the first registered app.")
        app_obj <- .rdesk_apps[[app_ids[1]]]
      }
    }
    if (is.null(app_obj)) {
      warning("[RDesk] async(): could not resolve app reference")
      return(invisible(NULL))
    }

    # Derive result message type from stored type
    result_type <- if (!is.null(msg_type_env$type)) {
      paste0(msg_type_env$type, "_result")
    } else {
      "__async_result__"
    }

    # Launch background task
    job_id <- rdesk_async(
      task = function(.fn, .pkgs, .payload, .app_dir) {
        # Reload packages in isolated worker context
        invisible(lapply(.pkgs, function(p) {
          tryCatch(
            library(p, character.only = TRUE,
                    quietly = TRUE, warn.conflicts = FALSE),
            error = function(e) NULL
          )
        }))
        
        # Source app modules to ensure handlers and helpers (like make_chart) are available
        if (!is.null(.app_dir) && dir.exists(file.path(.app_dir, "R"))) {
          r_files <- list.files(file.path(.app_dir, "R"), pattern = "\\.R$", full.names = TRUE)
          invisible(lapply(r_files, source))
        }
        
        # Run the developer's function
        .fn(.payload)
      },
      args = list(
        .fn      = fn,
        .pkgs    = loaded_pkgs,
        .payload = payload,
        .app_dir = if (!is.null(app_obj)) app_obj$get_dir() else NULL
      ),
      on_done = function(result) {
        app_obj$loading_done()
        app_obj$send(result_type, result)
      },
      on_error = function(err) {
        app_obj$loading_done()
        app_obj$toast(
          paste0(error_message, conditionMessage(err)),
          type = "error"
        )
      },
      app_id = app_obj$.__enclos_env__$private$.id
    )

    # Show loading overlay
    app_obj$loading_start(
      message     = loading_message,
      cancellable = cancellable,
      job_id      = job_id
    )

    invisible(job_id)
  }

  # Tag the wrapper so on_message() can inject the type
  attr(wrapper, "rdesk_async_wrapper") <- TRUE
  attr(wrapper, "rdesk_msg_type_env")  <- msg_type_env
  
  # Metadata for testing and internal identification
  attr(wrapper, "is_rdesk_async")   <- TRUE
  attr(wrapper, "loading_message") <- loading_message

  wrapper
}

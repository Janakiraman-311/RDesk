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

  # Start one worker per physical core (minus 1) for best responsiveness
  n <- max(1L, parallel::detectCores(logical = FALSE) - 1L)
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
#' @return Invisible job ID.
#' @export
rdesk_async <- function(task, args = list(), on_done = NULL, on_error = NULL) {
  # Generate a unique job ID
  job_id  <- paste0("job_", digest::digest(runif(1), algo = "crc32"))
  backend <- getOption("rdesk.async_backend", "callr")

  if (backend == "mirai" && requireNamespace("mirai", quietly = TRUE)) {
    # mirai path — submit to persistent daemon pool
    # We use .expr to execute the task with provided args
    m <- mirai::mirai(
      .expr = task(...args),
      task  = task,
      args  = args
    )
    .rdesk_jobs[[job_id]] <- list(
      job      = m,
      backend  = "mirai",
      on_done  = on_done,
      on_error = on_error,
      started  = Sys.time()
    )
  } else {
    # callr fallback — on-demand process spawning
    job <- callr::r_bg(task, args = args, supervise = TRUE)
    
    .rdesk_jobs[[job_id]] <- list(
      job      = job,
      backend  = "callr",
      on_done  = on_done,
      on_error = on_error,
      started  = Sys.time()
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

    # Check completion based on backend API
    is_done <- if (backend == "mirai") {
      !mirai::unresolved(job)
    } else {
      # callr path
      status <- tryCatch(job$poll_io(0), error = function(e) NULL)
      if (is.null(status)) FALSE else !job$is_alive()
    }

    if (!is_done) next

    # Job finished — remove from registry first to avoid re-polling
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
      err <- tryCatch(job$get_result(), error = function(e) e)
      if (inherits(err, "error")) {
        if (is.function(entry[["on_error"]])) {
          tryCatch(entry[["on_error"]](err),
            error = function(e) warning("[RDesk] on_error handler failed: ", e$message))
        }
      } else {
        if (is.function(entry[["on_done"]])) {
          tryCatch(entry[["on_done"]](err),
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
      # The daemon will recycle automatically after completion.
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

#' Wrap a message handler to run asynchronously with zero configuration
#'
#' @description
#' \code{async()} is the simplest way to make an RDesk message handler
#' non-blocking. Wrap any handler function with \code{async()} and RDesk
#' automatically handles background execution, loading states, error toasts,
#' and result routing.
#'
#' The wrapped function runs in an isolated worker process. All packages
#' loaded in the main session at registration time are automatically
#' reloaded in the worker. The return value is automatically sent back
#' to the UI as a message of type \code{<original_type>_result}.
#'
#' @param fn A function(payload) that performs the computation and returns
#'   a list to send back to the UI. Must be self-contained — do not
#'   reference variables from the parent environment directly.
#' @param loading_message Character string shown in the loading overlay.
#'   Default "Working..."
#' @param cancellable Logical. If TRUE, shows a Cancel button. Default TRUE.
#' @param error_message Character string prefix for error toasts.
#'   Default "Error: "
#'
#' @return A function suitable for use with \code{app$on_message()}
#'
#' @examples
#' \dontrun{
#' app$on_message("filter_cars", async(function(payload) {
#'   mtcars[mtcars$cyl == payload$cylinders, ]
#' }))
#' }
#' @export
async <- function(fn,
                  loading_message = "Working...",
                  cancellable     = TRUE,
                  error_message   = "Error: ") {

  # Capture packages loaded NOW at registration time
  # This is intentional — we snapshot the environment when the
  # developer calls async(), not when the task runs
  base_pkgs <- c("base", "methods", "datasets", "utils",
                 "grDevices", "graphics", "stats", "R6",
                 "jsonlite", "digest", "processx", "callr", "mirai")

  loaded_pkgs <- tryCatch({
    loaded <- search()
    pkg_names <- gsub("^package:", "", grep("^package:", loaded, value = TRUE))
    setdiff(pkg_names, base_pkgs)
  }, error = function(e) character(0))

  # Capture the app reference at registration time
  # async() is always called inside an on_message() context where
  # app exists in the calling frame
  app_ref <- tryCatch(
    get("app", envir = parent.frame(2), inherits = TRUE),
    error = function(e) NULL
  )

  # Store the message type for result routing
  # This gets populated when on_message() registers the handler
  msg_type_env <- new.env(parent = emptyenv())
  msg_type_env$type <- NULL

  # Return the actual handler function
  wrapper <- function(payload) {
    # Resolve app reference — try stored ref first, then global registry
    app_obj <- app_ref
    if (is.null(app_obj)) {
      app_ids <- ls(.rdesk_apps)
      if (length(app_ids) > 0) app_obj <- .rdesk_apps[[app_ids[1]]]
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
      task = function(.fn, .pkgs, .payload) {
        # Reload packages in isolated worker context
        invisible(lapply(.pkgs, function(p) {
          tryCatch(
            library(p, character.only = TRUE,
                    quietly = TRUE, warn.conflicts = FALSE),
            error = function(e) NULL
          )
        }))
        # Run the developer's function
        .fn(.payload)
      },
      args = list(
        .fn      = fn,
        .pkgs    = loaded_pkgs,
        .payload = payload
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
      }
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
  wrapper
}

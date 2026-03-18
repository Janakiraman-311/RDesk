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

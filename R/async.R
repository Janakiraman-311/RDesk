# R/async.R
# Background task management for RDesk

#' @importFrom digest digest
#' @importFrom callr r_bg
NULL

# Job registry - a private environment to track running jobs
.rdesk_jobs <- new.env(parent = emptyenv())

#' Run a task in the background
#'
#' @param task A function to run in the background.
#' @param args A list of arguments to pass to the task.
#' @param on_done Callback function(result) called when the task finishes successfully.
#' @param on_error Callback function(error) called if the task fails.
#' @return Invisible job ID.
#' @export
rdesk_async <- function(task, args = list(), on_done = NULL, on_error = NULL) {
  # Generate a unique job ID
  job_id <- paste0("job_", digest::digest(runif(1), algo = "crc32"))
  
  # Start the background process
  job <- callr::r_bg(task, args = args, supervise = TRUE)
  
  # Ensure cancel flag exists in registry (App handles the actual registration)
  if (!exists("__cancel_registered__", envir = .rdesk_jobs)) {
    assign("__cancel_registered__", TRUE, envir = .rdesk_jobs)
  }

  # Store in registry
  .rdesk_jobs[[job_id]] <- list(
    job      = job,
    on_done  = on_done,
    on_error = on_error,
    started  = Sys.time()
  )
  
  invisible(job_id)
}

#' Poll background jobs
#'
#' This is called internally by the main event loop to check if any 
#' background tasks have finished.
#'
#' @keywords internal
rdesk_poll_jobs <- function() {
  job_ids <- ls(.rdesk_jobs, pattern = "^job_")
  for (id in job_ids) {
    entry <- .rdesk_jobs[[id]]
    
    # Strictly validate that entry is a list and contains a job process
    if (!is.list(entry) || is.null(entry[["job"]])) {
      # This is a malformed entry, remove it to prevent repeat errors
      rm(list = id, envir = .rdesk_jobs)
      next
    }
    
    job <- entry[["job"]]

    # Non-blocking poll — 0ms timeout
    # job$poll_io(0) returns the result of the poll
    status <- tryCatch(job$poll_io(0), error = function(e) NULL)
    if (is.null(status)) next

    if (job$is_alive()) next  # Still running

    # Job finished — remove from registry first to avoid re-polling
    rm(list = id, envir = .rdesk_jobs)

    # Get result or error
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

#' Cancel a running background job
#'
#' @param job_id The ID of the job to cancel.
#' @return Invisible TRUE if cancelled, FALSE if not found.
#' @export
rdesk_cancel_job <- function(job_id) {
  if (exists(job_id, envir = .rdesk_jobs)) {
    entry <- .rdesk_jobs[[job_id]]
    if (is.list(entry) && !is.null(entry[["job"]])) {
      if (entry[["job"]]$is_alive()) entry[["job"]]$kill()
    }
    rm(list = job_id, envir = .rdesk_jobs)
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
  length(ls(.rdesk_jobs))
}

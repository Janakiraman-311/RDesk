# R/window.R
# Bridge to the standalone native window process

.rdesk_window_buffers <- new.env(parent = emptyenv())
.rdesk_req_id_next <- local({
  n <- 0L
  function() {
    n <<- n + 1L
    paste0("req_", n)
  }
})

#' @keywords internal
rdesk_launcher_path <- function() {
  # Check if we are in development mode or installed
  # Source-built launcher is in bin/ after install
  path <- system.file("bin", "rdesk-launcher.exe", package = "RDesk")
  if (path == "") {
    # Fallback for dev: check inst/bin (built by Makevars or build scripts)
    path <- file.path(getwd(), "inst", "bin", "rdesk-launcher.exe")
  }
  
  if (!file.exists(path)) {
    # Check src/ for development convenience if not yet copied to inst/bin
    alt_path <- file.path(getwd(), "src", "rdesk-launcher.exe")
    if (file.exists(alt_path)) return(alt_path)

    stop("[RDesk] Native launcher not found at: ", path, 
         "\nTip: If installing from source, ensure Rtools is installed and Makevars.win executed.")
  }
  path
}

#' Open a native window pointing to a URL
#'
#' @param url The target URL to load
#' @param title Window title
#' @param width Window width
#' @param height Window height
#' @param www_path Path to the local assets directory
#' @return A processx process object
#' @keywords internal
rdesk_open_window <- function(url, title = "RDesk", width = 1200, height = 800, www_path = "") {
  launcher <- rdesk_launcher_path()

  message("[RDesk] Window opened: ", url)

  proc <- processx::process$new(
    command = launcher,
    args    = c(url, title, as.character(width), as.character(height), www_path, as.character(Sys.getpid())),
    stdin   = "|",   # allow writing QUIT and other commands
    stdout  = "|",   # pipe so we can read READY signal and events
    stderr  = "|",
    cleanup = TRUE   # kill window if R session exits
  )

  # Wait for READY signal from launcher stdout
  deadline <- Sys.time() + getOption("rdesk.launcher_timeout", 10)
  ready <- FALSE
  buffered <- character(0)
  while (Sys.time() < deadline) {
    lines <- proc$read_output_lines()
    if (length(lines) > 0) {
      trimmed <- trimws(lines)
      ready_idx <- match("READY", trimmed, nomatch = 0L)
      if (ready_idx > 0) {
        if (ready_idx > 1) {
          buffered <- c(buffered, lines[seq_len(ready_idx - 1L)])
        }
        trailing <- lines[seq.int(ready_idx + 1L, length(lines))]
        if (length(trailing) > 0) {
          buffered <- c(buffered, trailing)
        }
        ready <- TRUE
        break
      }
      buffered <- c(buffered, lines)
    }
    if (!proc$is_alive()) break
    Sys.sleep(0.05)
  }

  if (!ready) {
    err <- paste(proc$read_error_lines(), collapse = "\n")
    proc$kill()
    stop("[RDesk] Launcher failed to start correctly: ", err)
  }

  .rdesk_window_buffers[[as.character(proc$get_pid())]] <- buffered
  proc
}

#' Close the native window process
#'
#' @param proc The processx process object returned by rdesk_open_window
#' @keywords internal
rdesk_close_window <- function(proc) {
  if (is.null(proc) || !proc$is_alive()) return()
  # Send QUIT command via stdin
  rdesk_send_cmd(proc, "QUIT")
  # QUIT should be fast; this short wait is only a safety net before forcing a kill.
  proc$wait(timeout = 500)
  if (proc$is_alive()) proc$kill()
  rm(list = as.character(proc$get_pid()), envir = .rdesk_window_buffers, inherits = FALSE)
}

# ---- Command sender ----------------------------------------------------------

#' Send a JSON command to the launcher process over stdin
#'
#' @param proc Process object
#' @param cmd Command string (e.g., "QUIT", "SET_MENU")
#' @param payload Data to send as JSON
#' @param id Optional request ID for async responses
#' @keywords internal
rdesk_send_cmd <- function(proc, cmd, payload = list(), id = NULL) {
  if (is.null(proc) || !proc$is_alive()) return(invisible(NULL))
  msg        <- list(cmd = cmd, payload = payload)
  if (!is.null(id)) msg$id <- id
  line       <- jsonlite::toJSON(msg, auto_unbox = TRUE, null = "null")
  proc$write_input(paste0(line, "\n"))
  invisible(NULL)
}

#' Generate a unique request ID for dialog round-trips
#'
#' @return A character string ID
#' @keywords internal
rdesk_req_id <- function() {
  .rdesk_req_id_next()
}

# ---- Stdout event reader -----------------------------------------------------

#' Read all pending stdout lines from the launcher without blocking
#'
#' @param proc Process object
#' @return A list of parsed JSON events
#' @keywords internal
rdesk_read_events <- function(proc) {
  if (is.null(proc) || !proc$is_alive()) return(list())
  key <- as.character(proc$get_pid())
  buffered <- if (exists(key, envir = .rdesk_window_buffers, inherits = FALSE)) {
    .rdesk_window_buffers[[key]]
  } else {
    character(0)
  }
  if (exists(key, envir = .rdesk_window_buffers, inherits = FALSE)) {
    rm(list = key, envir = .rdesk_window_buffers, inherits = FALSE)
  }

  lines  <- c(buffered, proc$read_output_lines())
  events <- list()
  for (line in lines) {
    if (length(line) == 0 || is.na(line)) next
    line <- trimws(line)
    if (nchar(line) == 0 || line == "READY" || line == "CLOSED") next
    tryCatch({
      # Any valid JSON from the launcher is an "event" or "message"
      parsed <- jsonlite::fromJSON(line, simplifyVector = FALSE)
      events <- c(events, list(parsed))
    }, error = function(e) NULL)
  }
  events
}

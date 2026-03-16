# R/window.R
# Bridge to the standalone native window process

#' @keywords internal
rdesk_launcher_path <- function() {
  # Check if we are in development mode or installed
  path <- system.file("bin", "rdesk-launcher.exe", package = "RDesk")
  if (path == "") {
    # Fallback for dev: check inst/bin
    path <- file.path(getwd(), "inst", "bin", "rdesk-launcher.exe")
  }
  if (!file.exists(path)) {
    stop("[RDesk] Native launcher not found at: ", path, ". Did you run src/launcher/build.ps1?")
  }
  path
}

#' Open a native window pointing to a URL
#'
#' @param url The target URL to load
#' @param title Window title
#' @param width Window width
#' @param height Window height
#' @return A processx process object
#' @keywords internal
rdesk_open_window <- function(url, title = "RDesk", width = 1200, height = 800) {
  launcher <- rdesk_launcher_path()

  message("[RDesk] Window opened: ", url)

  proc <- processx::process$new(
    command = launcher,
    args    = c(url, title, as.character(width), as.character(height)),
    stdin   = "|",   # allow writing QUIT and other commands
    stdout  = "|",   # pipe so we can read READY signal and events
    stderr  = "|",
    cleanup = TRUE   # kill window if R session exits
  )

  # Wait for READY signal from launcher stdout
  deadline <- Sys.time() + 10
  ready <- FALSE
  while (Sys.time() < deadline) {
    line <- proc$read_output_lines()
    if (length(line) > 0 && any(trimws(line) == "READY")) {
      ready <- TRUE
      break
    }
    if (!proc$is_alive()) break
    Sys.sleep(0.05)
  }

  if (!ready) {
    err <- paste(proc$read_error_lines(), collapse = "\n")
    proc$kill()
    stop("[RDesk] Launcher failed to start correctly: ", err)
  }

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
  proc$wait(timeout = 2000)
  if (proc$is_alive()) proc$kill()
}

# ── Command sender ──────────────────────────────────────────────────────────

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
  # Use double precision for calculation, then cast to integer to avoid overflow
  id_num <- (as.numeric(Sys.time()) * 1000) %% 1e9
  paste0("req_", as.integer(id_num))
}

# ── Stdout event reader ─────────────────────────────────────────────────────

#' Read all pending stdout lines from the launcher without blocking
#'
#' @param proc Process object
#' @return A list of parsed JSON events
#' @keywords internal
rdesk_read_events <- function(proc) {
  if (is.null(proc) || !proc$is_alive()) return(list())
  lines  <- proc$read_output_lines()
  events <- list()
  for (line in lines) {
    line <- trimws(line)
    if (nchar(line) == 0 || line == "READY" || line == "CLOSED") next
    tryCatch({
      parsed <- jsonlite::fromJSON(line, simplifyVector = FALSE)
      if (!is.null(parsed$event)) events <- c(events, list(parsed))
    }, error = function(e) NULL)
  }
  events
}

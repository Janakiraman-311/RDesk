# R/App.R
# RDesk App R6 class - the complete public API
 
# Global registry for multi-window management
.rdesk_apps <- new.env(parent = emptyenv())
 
#' @importFrom R6 R6Class
NULL

#' Create and launch a native desktop application window from R.
#'
#' @description
#' Provides bidirectional native pipe communication between R and the UI.
#'
#' @examples
#' \dontrun{
#' app <- App$new(title = "Car Visualizer", width = 1200, height = 800)
#' 
#' app$on_ready(function() {
#'   message("App is ready!")
#' })
#' 
#' # Handle messages from UI
#' app$on_message("get_data", function(payload) {
#'   list(cars = mtcars[1:5, ])
#' })
#' 
#' # Start the app
#' app$run()
#' }
#' @export
App <- R6::R6Class("App",
 
  public = list(
 
    #' @description Create a new RDesk application
    #' @param title Window title string
    #' @param width Window width in pixels (default 1200)
    #' @param height Window height in pixels (default 800)
    #' @param www Directory containing HTML/CSS/JS assets (default: built-in template)
    #' @param icon Path to window icon file
    #' @return A new App instance
    initialize = function(title,
                          width  = 1200L,
                          height = 800L,
                          www    = NULL,
                          icon   = NULL) {
      if (missing(title)) stop("Title is mandatory")
      if (missing(width)) stop("Width is mandatory")
      if (missing(height)) stop("Height is mandatory")

      private$.title  <- title
      private$.width  <- as.integer(width)
      private$.height <- as.integer(height)
      private$.www    <- rdesk_resolve_www(www)
      private$.icon   <- icon
      private$.router <- rdesk_make_router()
      private$.id     <- paste0("app_", digest::digest(list(
        Sys.time(),
        proc.time(),
        runif(1)
      ), algo = "crc32"))

      # System handler for UI-initiated job cancellation
      private$.router$register("__cancel_job__", function(payload) {
        if (!is.null(payload$job_id)) {
          rdesk_cancel_job(payload$job_id)
          self$loading_done()
          self$toast("Operation cancelled.", type = "warning")
        }
      })
    },
 
    #' @description Register a callback to fire when the window is ready
    #' @param fn A zero-argument function called after the server starts and window opens
    #' @return The App instance (invisible)
    on_ready = function(fn) {
      if (!is.function(fn)) stop("on_ready() requires a function")
      private$.ready_fn <- fn
      invisible(self)
    },
 
    #' @description Register a handler for a UI -> R message type
    #' @param type Character string message type (must match rdesk.send() first arg in JS)
    #' @param fn A function(payload) called when this message type arrives
    #' @return The App instance (invisible)
    on_message = function(type, fn) {
      if (!is.character(type) || length(type) != 1) stop("type must be a single string")
      if (!is.function(fn)) stop("fn must be a function")

      # If fn is an async() wrapper, inject the message type
      # so it can auto-route results as <type>_result
      if (isTRUE(attr(fn, "rdesk_async_wrapper"))) {
        type_env <- attr(fn, "rdesk_msg_type_env")
        if (!is.null(type_env)) type_env$type <- type
      }

      private$.router$register(type, fn)
      invisible(self)
    },
 
    #' @description Send a message from R to the UI
    #' @param type Character string message type (received by rdesk.on() in JS)
    #' @param payload A list or data.frame to serialise as JSON payload
    #' @return The App instance (invisible)
    send = function(type, payload = list()) {
      # Construct the standard envelope
      msg_envelope <- rdesk_message(type, payload)
      msg_json <- jsonlite::toJSON(msg_envelope, auto_unbox = TRUE)

      if (!is.null(private$.window_proc) && private$.window_proc$is_alive()) {
        # Use internal command SEND_MSG to bridge to PostWebMessage
        rdesk_send_cmd(private$.window_proc, "SEND_MSG", payload = msg_json)
      } else if (rdesk_is_bundle()) {
        # Legacy fallback if a bundled app is ever hosted by an external launcher
        cat(msg_json, "\n", sep = "")
        flush(stdout())
      } else {
        # Queue message if launcher not yet ready
        private$.send_queue[[length(private$.send_queue) + 1]] <- msg_envelope
      }
      invisible(self)
    },
 
    #' @description Load an HTML file into the window
    #' @param path Path relative to the www directory (e.g. "index.html")
    #' @return The App instance (invisible)
    load_ui = function(path = "index.html") {
      self$send("__navigate__", list(path = path))
      invisible(self)
    },
 
    #' @description Set the native window menu
    #' @param items A named list of lists defining the menu structure
    #' @return The App instance (invisible)
    set_menu = function(items) {
      # Convert R named list to JSON array the launcher understands
      menu_json <- private$.build_menu_json(items)
      
      private$.send_launcher_cmd("SET_MENU", payload = menu_json, queue_if_unavailable = TRUE)
      
      private$.menu_callbacks <- items
      invisible(self)
    },
 
    #' @description Open a native file-open dialog
    #' @param title Dialog title
    #' @param filters List of file filters, e.g. list("CSV files" = "*.csv")
    #' @return Selected file path (character) or NULL if cancelled
    dialog_open = function(title = "Open File", filters = NULL) {
      filter_str <- private$.build_filter_str(filters)
      req_id     <- rdesk_req_id()
      private$.send_launcher_cmd(
        "DIALOG_OPEN",
        payload = list(title = title, filters = filter_str),
        id = req_id
      )
      private$.wait_dialog_result(req_id)
    },
 
    #' @description Open a native file-save dialog
    #' @param title Dialog title
    #' @param default_name Initial filename
    #' @param filters List of file filters
    #' @return Selected file path (character) or NULL if cancelled
    dialog_save = function(title = "Save File", default_name = "",
                            filters = NULL) {
      filter_str <- private$.build_filter_str(filters)
      
      # Extract default extension (e.g. "csv" from "*.csv")
      def_ext <- NULL
      if (!is.null(filters) && length(filters) > 0) {
        f <- filters[[1]]
        def_ext <- gsub("^.*\\.", "", f)
      }
 
      req_id     <- rdesk_req_id()
      private$.send_launcher_cmd(
        "DIALOG_SAVE",
        payload = list(title        = title,
                       default_name = default_name,
                       filters      = filter_str,
                       default_ext  = def_ext),
        id = req_id
      )
      private$.wait_dialog_result(req_id)
    },
 
    #' @description Send a native desktop notification
    #' @param title Notification title
    #' @param body Notification body text
    #' @return The App instance (invisible)
    notify = function(title, body = "") {
      private$.send_launcher_cmd(
        "NOTIFY",
        payload = list(title = title, body = body),
        queue_if_unavailable = TRUE
      )
      invisible(self)
    },
 
    #' @description Show a loading state in the UI
    #' @param message Text shown under the spinner
    #' @param progress Optional numeric 0-100 for a progress bar
    #' @param cancellable If TRUE, shows a cancel button in the UI
    #' @param job_id Optional job_id from rdesk_async() to wire cancel button
    loading_start = function(message     = "Loading...",
                             progress    = NULL,
                             cancellable = FALSE,
                             job_id      = NULL) {
      self$send("__loading__", list(
        active      = TRUE,
        message     = message,
        progress    = progress,
        cancellable = cancellable,
        job_id      = job_id
      ))
      invisible(self)
    },
 
    #' @description Update progress on an active loading state
    #' @param value Numeric 0-100
    #' @param message Optional updated message
    loading_progress = function(value, message = NULL) {
      payload <- list(active = TRUE, progress = value)
      if (!is.null(message)) payload$message <- message
      self$send("__loading__", payload)
      invisible(self)
    },
 
    #' @description Hide the loading state in the UI
    loading_done = function() {
      self$send("__loading__", list(active = FALSE, message = "", progress = NULL))
      invisible(self)
    },
 
    #' @description Show a non-blocking toast notification in the UI
    #' @param message Text to show
    #' @param type One of "info", "success", "warning", "error"
    #' @param duration_ms How long to show it (default 3000ms)
    toast = function(message, type = "info", duration_ms = 3000L) {
      self$send("__toast__", list(
        message     = message,
        type        = type,
        duration_ms = as.integer(duration_ms)
      ))
      invisible(self)
    },
 
    #' @description Set or update the system tray icon
    #' @param label Tooltip text for the tray icon
    #' @param icon Path to .ico file (optional)
    #' @param on_click Character "left" or "right" or callback function(button)
    #' @return The App instance (invisible)
    set_tray = function(label = "RDesk App", icon = NULL, on_click = NULL) {
      private$.tray_callback <- on_click
      private$.send_launcher_cmd(
        "SET_TRAY",
        payload = list(label = label, icon = icon),
        queue_if_unavailable = TRUE
      )
      invisible(self)
    },
 
    #' @description Remove the system tray icon
    #' @return The App instance (invisible)
    remove_tray = function() {
      private$.tray_callback <- NULL
      private$.send_launcher_cmd("REMOVE_TRAY", queue_if_unavailable = TRUE)
      invisible(self)
    },
 
    #' @description Service this app's pending native events
    #' @return The App instance (invisible)
    service = function() {
      private$.poll_events()
      invisible(self)
    },
 
    #' @description Close the window and stop the app
    quit = function() {
      private$.running <- FALSE
      # Also remove from global registry if present
      if (exists(as.character(private$.id), envir = .rdesk_apps)) {
        rm(list = as.character(private$.id), envir = .rdesk_apps)
      }
      invisible(self)
    },
 
    #' @description Start the application - opens the window
    #' @param block If TRUE (default), blocks with an event loop until the window is closed.
    run = function(block = TRUE) {
      # CI Guard: Skip initialization if running in a headless environment
      if (getOption("rdesk.ci_mode", FALSE)) {
        message("[RDesk] CI Mode: Skipping native window initialization.")
        return(invisible(self))
      }
      private$.running <- TRUE
      if (getOption("rdesk.async_backend", "callr") == "mirai") {
        rdesk_start_daemons()  # Pre-warm worker pool
      }

      url <- "https://app.rdesk/index.html" 

      private$.window_proc <- rdesk_open_window(
        url      = url,
        title    = private$.title,
        width    = private$.width,
        height   = private$.height,
        www_path = private$.www
      )

      # Flush queued messages
      private$.flush_send_queue()
      private$.flush_command_queue()

      if (!is.null(private$.ready_fn)) {
        tryCatch(private$.ready_fn(), error = function(e) warning("[RDesk] on_ready error: ", e$message))
      }

      assign(as.character(private$.id), self, envir = .rdesk_apps)

      if (block) {
        while (private$.running) {
          rdesk_service()
          if (!private$.running) break
          Sys.sleep(0.01)
        }
        private$.cleanup()
        message("[RDesk] App closed.")
      }

      invisible(self)
    }
  ),
 
  private = list(
    .id          = NULL,
    .title       = NULL,
    .width       = NULL,
    .height      = NULL,
    .www         = NULL,
    .icon        = NULL,
    .ready_fn    = NULL,
    .running     = FALSE,
    .window_proc = NULL,
    .router      = NULL,
    .send_queue  = list(),
    .command_queue = list(),
    .menu_callbacks  = list(),   # Stores the action ID -> function mapping
    .pending_dialogs = list(),  # req_id -> result or NULL
    .tray_callback = NULL,      # Function(button)
    .bundle_con = NULL,         # Non-blocking stdin connection in hosted bundle mode
 
    .cleanup = function() {
      if (getOption("rdesk.async_backend", "callr") == "mirai") {
        rdesk_stop_daemons()  # Shut down worker pool cleanly
      }
      if (!is.null(private$.window_proc)) {
        rdesk_close_window(private$.window_proc)
        private$.window_proc <- NULL
      }
      private$.bundle_con <- NULL
      private$.running <- FALSE
    },

    .send_launcher_cmd = function(cmd, payload = list(), id = NULL, queue_if_unavailable = FALSE) {
      if (!is.null(private$.window_proc) && private$.window_proc$is_alive()) {
        rdesk_send_cmd(private$.window_proc, cmd, payload = payload, id = id)
        return(invisible(TRUE))
      }

      msg <- list(cmd = cmd, payload = payload)
      if (!is.null(id)) msg$id <- id

      if (rdesk_is_bundle()) {
        cat(jsonlite::toJSON(msg, auto_unbox = TRUE, null = "null"), "\n", sep = "")
        flush(stdout())
        return(invisible(TRUE))
      }

      if (isTRUE(queue_if_unavailable)) {
        private$.command_queue[[length(private$.command_queue) + 1]] <- msg
        return(invisible(TRUE))
      }

      stop("[RDesk] Launcher is not available for command: ", cmd)
    },

    .flush_send_queue = function() {
      if (length(private$.send_queue) == 0) return(invisible(NULL))
      for (msg_envelope in private$.send_queue) {
        msg_json <- jsonlite::toJSON(msg_envelope, auto_unbox = TRUE)
        if (!is.null(private$.window_proc) && private$.window_proc$is_alive()) {
          rdesk_send_cmd(private$.window_proc, "SEND_MSG", payload = msg_json)
        } else if (rdesk_is_bundle()) {
          cat(msg_json, "\n", sep = "")
          flush(stdout())
        }
      }
      private$.send_queue <- list()
      invisible(NULL)
    },

    .flush_command_queue = function() {
      if (length(private$.command_queue) == 0) return(invisible(NULL))
      pending <- private$.command_queue
      private$.command_queue <- list()
      for (cmd_msg in pending) {
        private$.send_launcher_cmd(
          cmd = cmd_msg$cmd,
          payload = if (is.null(cmd_msg$payload)) list() else cmd_msg$payload,
          id = cmd_msg$id
        )
      }
      invisible(NULL)
    },

    .ensure_bundle_conn = function() {
      if (is.null(private$.bundle_con)) {
        private$.bundle_con <- processx::conn_create_fd(0L, encoding = "")
      }
      private$.bundle_con
    },

    .poll_bundle_input = function() {
      if (!rdesk_is_bundle()) return(invisible(NULL))
      con <- private$.ensure_bundle_conn()
      lines <- tryCatch(
        processx::conn_read_lines(con, n = 100, timeout = 0),
        error = function(e) character(0)
      )
      if (length(lines) == 0) return(invisible(NULL))

      for (line in lines) {
        msg <- rdesk_parse_message(line)
        if (!is.null(msg)) {
          if (!is.null(msg$event)) private$.handle_launcher_event(msg)
          else private$.router$dispatch(msg$type, msg$payload)
        }
      }
      invisible(NULL)
    },
 
    .build_menu_json = function(items) {
      # Convert: list(File = list("Open"=fn, "---", "Exit"=fn))
      # To JSON array of {label, items:[{label, id}]}
      result <- list()
      private$.menu_actions <- list() # Internal ID -> function mapping
      
      for (top_label in names(items)) {
        sub_items <- items[[top_label]]
        sub_json  <- list()
        for (i in seq_along(sub_items)) {
          item <- sub_items[[i]]
          lbl  <- if (is.null(names(sub_items)) || names(sub_items)[i] == "")
                    as.character(item) else names(sub_items)[i]
          if (lbl == "---" || identical(item, "---")) {
            sub_json <- c(sub_json, list(list(label = "---")))
          } else {
            item_id <- paste0("menu_", top_label, "_", i)
            # Store callback in a flattened map for easier lookup
            private$.menu_actions[[item_id]] <- item
            sub_json <- c(sub_json, list(list(label = lbl, id = item_id)))
          }
        }
        result <- c(result, list(list(label = top_label, items = sub_json)))
      }
      result
    },
 
    .build_filter_str = function(filters) {
      # Convert list("CSV Files"="*.csv") to
      # "CSV Files|*.csv|All Files|*.*|" (launcher converts | to \0)
      if (is.null(filters)) return("All Files|*.*|")
      parts <- character(0)
      for (nm in names(filters)) {
        parts <- c(parts, nm, filters[[nm]])
      }
      parts <- c(parts, "All Files", "*.*")
      paste0(paste(parts, collapse = "|"), "||")
    },
 
    .wait_dialog_result = function(req_id, timeout_sec = 60) {
      private$.pending_dialogs[[req_id]] <- NULL
      deadline <- Sys.time() + timeout_sec
      while (Sys.time() < deadline) {
        if (!is.null(private$.window_proc) && private$.window_proc$is_alive()) {
          events <- rdesk_read_events(private$.window_proc)
          for (evt in events) private$.handle_launcher_event(evt)
        } else if (rdesk_is_bundle()) {
          private$.poll_bundle_input()
        }
        
        result <- private$.pending_dialogs[[req_id]]
        if (!is.null(result)) {
          private$.pending_dialogs[[req_id]] <- NULL
          return(if (result == "__CANCEL__") NULL else result)
        }
        Sys.sleep(0.05)
      }
      NULL  # timeout
    },
 
    .handle_launcher_event = function(evt) {
      if (!is.null(evt$event)) {
        if (evt$event == "MENU_CLICK") {
          callback <- private$.menu_actions[[evt$id]]
          if (is.function(callback)) {
            tryCatch(callback(),
                     error = function(e) warning("[RDesk] menu handler error: ", e$message))
          }
        } else if (evt$event == "DIALOG_RESULT") {
          private$.pending_dialogs[[evt$id]] <- evt$path
        } else if (evt$event == "DIALOG_CANCEL") {
          private$.pending_dialogs[[evt$id]] <- "__CANCEL__"
        } else if (evt$event == "TRAY_CLICK") {
          if (is.function(private$.tray_callback)) {
            tryCatch(private$.tray_callback(evt$button),
                     error = function(e) warning("[RDesk] tray handler error: ", e$message))
          }
        }
      } else if (!is.null(evt$type)) {
        # It's a JS -> R message forwarded by launcher
        private$.router$dispatch(evt$type, evt$payload)
      }
    },
 
    .poll_events = function() {
      if (!is.null(private$.window_proc)) {
        events <- rdesk_read_events(private$.window_proc)
        for (evt in events) {
          private$.handle_launcher_event(evt)
        }
        if (!private$.window_proc$is_alive()) {
          self$quit()
        }
      }
    },
    .menu_actions = list()
  )
)
 
#' Service all active RDesk applications
#' 
#' Processes native OS events for all open windows.
#' Call this periodically if you are running apps with \code{block = FALSE}.
#' 
#' @export
rdesk_service <- function() {
  # 1. Poll any background jobs
  rdesk_poll_jobs()

  # 2. Service each registered app
  app_ids <- ls(.rdesk_apps)
  for (id in app_ids) {
    app <- .rdesk_apps[[id]]
    app$service()
  }
}

# R/App.R
# RDesk App R6 class - the complete public API
 
# Global registry for multi-window management
.rdesk_apps <- new.env(parent = emptyenv())
 
#' @title RDesk Application
#' @description
#' Create and launch a native desktop application window from R.
#' Provides bidirectional native pipe communication between R and the UI.
#'
#' @examples
#' \dontrun{
#' app <- App$new(title = "My App", width = 1200, height = 800)
#' app$on_ready(function() {
#'   app$load_ui("www/index.html")
#' })
#' app$on_message("ping", function(msg) {
#'   app$send("pong", list(ts = Sys.time()))
#' })
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
    initialize = function(title  = "RDesk App",
                          width  = 1200L,
                          height = 800L,
                          www    = NULL,
                          icon   = NULL) {
      private$.title  <- title
      private$.width  <- as.integer(width)
      private$.height <- as.integer(height)
      private$.www    <- rdesk_resolve_www(www)
      private$.icon   <- icon
      private$.router <- rdesk_make_router()
      private$.id     <- as.character(as.numeric(Sys.time()) * 1000)

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

      if (rdesk_is_bundle()) {
        # Bundled mode: write directly to stdout (launcher reads this)
        cat(msg_json, "\n")
        flush(stdout())
      } else {
        # Dev mode: write to the launcher process's stdin
        if (!is.null(private$.window_proc) && private$.window_proc$is_alive()) {
          # Use internal command SEND_MSG to bridge to PostWebMessage
          rdesk_send_cmd(private$.window_proc, "SEND_MSG", payload = msg_json)
        } else {
          # Queue message if launcher not yet ready
          private$.send_queue[[length(private$.send_queue) + 1]] <- msg_envelope
        }
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
      
      if (rdesk_is_bundle()) {
        cat(jsonlite::toJSON(list(cmd = "SET_MENU", payload = menu_json), auto_unbox = TRUE), "\n")
        flush(stdout())
      } else {
        rdesk_send_cmd(private$.window_proc, "SET_MENU", payload = menu_json)
      }
      
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
      rdesk_send_cmd(private$.window_proc, "DIALOG_OPEN",
                     payload = list(title = title, filters = filter_str),
                     id      = req_id)
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
      rdesk_send_cmd(private$.window_proc, "DIALOG_SAVE",
                     payload = list(title        = title,
                                    default_name = default_name,
                                    filters      = filter_str,
                                    default_ext  = def_ext),
                     id      = req_id)
      private$.wait_dialog_result(req_id)
    },
 
    #' @description Send a native desktop notification
    #' @param title Notification title
    #' @param body Notification body text
    #' @return The App instance (invisible)
    notify = function(title, body = "") {
      rdesk_send_cmd(private$.window_proc, "NOTIFY",
                     payload = list(title = title, body = body))
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
      rdesk_send_cmd(private$.window_proc, "SET_TRAY",
                     payload = list(label = label, icon = icon))
      invisible(self)
    },
 
    #' @description Remove the system tray icon
    #' @return The App instance (invisible)
    remove_tray = function() {
      private$.tray_callback <- NULL
      rdesk_send_cmd(private$.window_proc, "REMOVE_TRAY")
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

      if (rdesk_is_bundle()) {
        # BUNDLED MODE: R is the child process.
        if (!is.null(private$.ready_fn)) {
          tryCatch(private$.ready_fn(), error = function(e) warning("[RDesk] on_ready error: ", e$message))
        }

        # Initialize non-blocking stdin
        con <- processx::conn_create_fd(0L, encoding = "")

        # Main non-blocking loop
        repeat {
          # 1. Poll any background jobs
          rdesk_poll_jobs()

          # 2. Read next message from launcher (non-blocking)
          line <- tryCatch(
            processx::conn_read_lines(con, n = 1, timeout = 10),
            error = function(e) character(0)
          )

          if (length(line) == 0) {
             # No message yet, check if stdin is actually closed
             if (processx::conn_is_closed(con)) break
             
             # If not closed, check if running and continue
             if (!private$.running) break
             next
          }

          # 3. Process the message
          msg <- rdesk_parse_message(line)
          if (!is.null(msg)) {
             if (!is.null(msg$type)) {
               private$.router$dispatch(msg$type, msg$payload)
             } else if (!is.null(msg$event)) {
               private$.handle_launcher_event(msg)
             }
          }
          if (!private$.running) break
        }
        return(invisible(self))
      }

      # DEV MODE: R is the parent process.
      url <- "https://app.rdesk/index.html" 

      private$.window_proc <- rdesk_open_window(
        url      = url,
        title    = private$.title,
        width    = private$.width,
        height   = private$.height,
        www_path = private$.www
      )

      # Flush queued messages
      for (msg_envelope in private$.send_queue) {
        msg_json <- jsonlite::toJSON(msg_envelope, auto_unbox = TRUE)
        rdesk_send_cmd(private$.window_proc, "SEND_MSG", payload = msg_json)
      }
      private$.send_queue <- list()

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
    .menu_callbacks  = list(),   # Stores the action ID -> function mapping
    .pending_dialogs = list(),  # req_id -> result or NULL
    .tray_callback = NULL,      # Function(button)
 
    .cleanup = function() {
      if (!rdesk_is_bundle()) {
        # Dev mode: Close window
        rdesk_close_window(private$.window_proc)
        private$.window_proc <- NULL
      }
      private$.running <- FALSE
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
        if (rdesk_is_bundle()) {
           # Process stdin to find the dialog result
           line <- readLines(stdin(), 1)
           if (length(line) > 0) {
             msg <- rdesk_parse_message(line)
             if (!is.null(msg)) {
               if (!is.null(msg$event)) private$.handle_launcher_event(msg)
               else private$.router$dispatch(msg$type, msg$payload)
             }
           }
        } else {
          if (!is.null(private$.window_proc)) {
            events <- rdesk_read_events(private$.window_proc)
            for (evt in events) private$.handle_launcher_event(evt)
          }
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
    app$.__enclos_env__$private$.poll_events()
  }
}

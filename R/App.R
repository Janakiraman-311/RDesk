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
#' # Safe logical check (unwrapped)
#' app_dir <- system.file("templates/hello", package = "RDesk")
#' if (nzchar(app_dir)) {
#'   message("Built-in app directory: ", app_dir)
#' }
#' 
#' if (interactive()) {
#'   app <- App$new(title = "Car Visualizer", width = 1200, height = 800)
#'   
#'   app$on_ready(function() {
#'     message("App is ready!")
#'   })
#'   
#'   # Handle messages from UI
#'   app$on_message("get_data", function(payload) {
#'     list(cars = mtcars[1:5, ])
#'   })
#'   
#'   # Start the app
#'   app$run()
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
      private$.hotkey_callbacks <- new.env(parent = emptyenv())

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

    #' @description Register a callback to fire when the user attempts to close the window
    #' @param fn A zero-argument function. Should return TRUE to allow closing, FALSE to cancel.
    #' @return The App instance (invisible)
    on_close = function(fn) {
      if (!is.function(fn)) stop("on_close() requires a function")
      private$.on_close_fn <- fn
      # Tell the launcher to start intercepting WM_CLOSE
      private$.send_launcher_cmd("INTERCEPT_CLOSE", list(enabled = TRUE))
      invisible(self)
    },

    #' @description Check for application updates from a remote URL
    #' @param version_url URL to a JSON metadata file (e.g. \verb{\{"version": "1.1.0", "url": "http://..."\}})
    #' @param current_version Optional version string to compare against. Defaults to app description version.
    #' @return A list with update status and metadata
    check_update = function(version_url, current_version = NULL) {
      if (is.null(current_version)) {
        desc_path <- file.path(self$get_dir(), "DESCRIPTION")
        if (file.exists(desc_path)) {
          desc <- read.dcf(desc_path)
          current_version <- as.character(desc[1, "Version"])
        } else {
          current_version <- "1.0.0"
        }
      }

      tmp <- tempfile(fileext = ".json")
      on.exit(unlink(tmp), add = TRUE)

      tryCatch({
        utils::download.file(version_url, tmp, mode = "wb", quiet = TRUE)
        latest <- jsonlite::fromJSON(tmp)

        has_update <- utils::compareVersion(latest$version, current_version) > 0

        list(
          update_available = has_update,
          current_version  = current_version,
          latest_version   = latest$version,
          download_url     = latest$url
        )
      }, error = function(e) {
        warning("[RDesk] Update check failed: ", e$message)
        list(update_available = FALSE, error = e$message)
      })
    },

    #' @description Register a global keyboard shortcut (hotkey)
    #' @param keys Character string representing the key combination (e.g., "Ctrl+Shift+A")
    #' @param fn A zero-argument function to be called when the hotkey is pressed
    #' @return The App instance (invisible)
    register_hotkey = function(keys, fn) {
      if (!is.character(keys) || length(keys) != 1) stop("keys must be a single string")
      if (!is.function(fn)) stop("fn must be a function")

      parsed <- rdesk_parse_hotkey(keys)
      if (is.null(parsed) || parsed$vk == 0) stop("Invalid hotkey format: ", keys)

      hotkey_id <- as.integer(sample.int(9999, 1))
      private$.hotkey_callbacks[[as.character(hotkey_id)]] <- fn
      
      private$.send_launcher_cmd("REGISTER_HOTKEY", payload = list(
        id = hotkey_id,
        modifiers = parsed$modifiers,
        vk = parsed$vk,
        label = keys
      ))
      invisible(self)
    },

    #' @description Set the native system tray menu
    #' @param items A named list of lists defining the menu structure
    #' @return The App instance (invisible)
    set_tray_menu = function(items) {
      # Convert R named list to JSON array the launcher understands
      menu_json <- private$.build_menu_json(items, prefix = "tray_menu")

      private$.send_launcher_cmd("SET_TRAY_MENU", payload = menu_json, queue_if_unavailable = TRUE)

      invisible(self)
    },

    #' @description Write text to the system clipboard
    #' @param text Character string to copy
    #' @return The App instance (invisible)
    clipboard_write = function(text) {
      private$.send_launcher_cmd("CLIPBOARD_WRITE", payload = list(text = as.character(text)))
      invisible(self)
    },

    #' @description Read text from the system clipboard
    #' @return Character string from clipboard or NULL
    clipboard_read = function() {
      req_id <- rdesk_req_id()
      private$.send_launcher_cmd("CLIPBOARD_READ", id = req_id)
      private$.wait_dialog_result(req_id)
    },

    #' @description Register a handler for a UI -> R message type
    #' @param type Unique message identifier string
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

    #' @description Set the window size dynamically
    #' @param width New width (pixels)
    #' @param height New height (pixels)
    #' @return The App instance (invisible)
    set_size = function(width, height) {
      private$.send_launcher_cmd("SET_SIZE", list(width = as.integer(width), height = as.integer(height)))
      private$.width  <- as.integer(width)
      private$.height <- as.integer(height)
      invisible(self)
    },

    #' @description Set the window position dynamically
    #' @param x Horizontal position from left (pixels)
    #' @param y Vertical position from top (pixels)
    #' @return The App instance (invisible)
    set_position = function(x, y) {
      private$.send_launcher_cmd("SET_POS", list(x = as.integer(x), y = as.integer(y)))
      invisible(self)
    },

    #' @description Set the window title dynamically
    #' @param title New title
    #' @return The App instance (invisible)
    set_title = function(title) {
      private$.send_launcher_cmd("SET_TITLE", list(title = as.character(title)))
      private$.title <- as.character(title)
      invisible(self)
    },

    #' @description Minimize the window to the taskbar
    #' @return The App instance (invisible)
    minimize = function() {
      private$.send_launcher_cmd("MINIMIZE")
      invisible(self)
    },

    #' @description Maximize the window to fill the screen
    #' @return The App instance (invisible)
    maximize = function() {
      private$.send_launcher_cmd("MAXIMIZE")
      invisible(self)
    },

    #' @description Restore the window from minimize/maximize
    #' @return The App instance (invisible)
    restore = function() {
      private$.send_launcher_cmd("RESTORE")
      invisible(self)
    },

    #' @description Toggle fullscreen mode
    #' @param enabled If TRUE, enters fullscreen. If FALSE, exits.
    #' @return The App instance (invisible)
    fullscreen = function(enabled = TRUE) {
      private$.send_launcher_cmd("FULLSCREEN", list(enabled = isTRUE(enabled)))
      invisible(self)
    },

    #' @description Set the window to stay always on top of others
    #' @param enabled If TRUE, always on top.
    #' @return The App instance (invisible)
    always_on_top = function(enabled = TRUE) {
      private$.send_launcher_cmd("TOPMOST", list(enabled = isTRUE(enabled)))
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

    #' @description Open a native folder selection dialog
    #' @param title Dialog title
    #' @return Selected directory path (character) or NULL if cancelled
    dialog_folder = function(title = "Select Folder") {
      req_id <- rdesk_req_id()
      private$.send_launcher_cmd(
        "DIALOG_FOLDER",
        payload = list(title = title),
        id = req_id
      )
      private$.wait_dialog_result(req_id)
    },

    #' @description Show a native message box / alert
    #' @param message The message text
    #' @param title The dialog title
    #' @param type One of "ok", "okcancel", "yesno", "yesnocancel"
    #' @param icon One of "info", "warning", "error", "question"
    #' @return The button pressed (character: "ok", "cancel", "yes", "no")
    message_box = function(message, title = "RDesk", type = "ok", icon = "info") {
      req_id <- rdesk_req_id()
      private$.send_launcher_cmd(
        "MESSAGE_BOX",
        payload = list(message = message, title = title, type = type, icon = icon),
        id = req_id
      )
      private$.wait_dialog_result(req_id)
    },

    #' @description Open a native color selection dialog
    #' @param initial_color Optional hex color to start with (e.g. "#FF0000")
    #' @return Selected hex color code or NULL if cancelled
    dialog_color = function(initial_color = "#FFFFFF") {
      req_id <- rdesk_req_id()
      private$.send_launcher_cmd(
        "DIALOG_COLOR",
        payload = list(color = initial_color),
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

    #' @description Close the window and stop the app's event loop.
    #' @return The App instance (invisible)
    quit = function() {
      private$.running <- FALSE
      # Also remove from global registry if present
      if (exists(as.character(private$.id), envir = .rdesk_apps)) {
        rm(list = as.character(private$.id), envir = .rdesk_apps)
      }
      invisible(self)
    },

    #' @description Get the application root directory (where www/ and R/ are located).
    #' @return Character string path.
    get_dir = function() {
      dirname(private$.www)
    },

    #' @description Start the application - opens the window
    #' @param block If TRUE (default), blocks with an event loop until the window is closed.
    run = function(block = TRUE) {
      # CI Guard: Skip initialization if running in a headless environment
      if (getOption("rdesk.ci_mode", FALSE)) {
        message("[RDesk] CI Mode: Skipping native window initialization.")
        return(invisible(self))
      }

      rdesk_log(sprintf("Starting application: %s", private$.title), level = "INFO", app_name = private$.title)

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
        tryCatch(private$.ready_fn(), error = function(e) {
          rdesk_log(sprintf("Startup Error (on_ready): %s", e$message), level = "ERROR", app_name = private$.title)
          warning("[RDesk] on_ready error: ", e$message)
        })
      }

      assign(as.character(private$.id), self, envir = .rdesk_apps)

      if (block) {
        on.exit(private$.cleanup())
        tryCatch({
          while (private$.running) {
            rdesk_service()
            if (!private$.running) break
            Sys.sleep(0.01)
          }
        }, error = function(e) {
          rdesk_log(sprintf("Application CRASHED: %s", e$message), level = "ERROR", app_name = private$.title)
          warning("[RDesk] Fatal error: ", e$message)
          private$.running <- FALSE
        })
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
    .on_close_fn = NULL,
    .running     = FALSE,
    .window_proc = NULL,
    .router      = NULL,
    .send_queue  = list(),
    .command_queue = list(),
    .menu_actions  = new.env(parent = emptyenv()), # Stores the action ID -> function mapping for menus and tray menus
    .pending_dialogs = list(),  # req_id -> result or NULL
    .tray_callback = NULL,      # Function(button)
    .hotkey_callbacks = NULL,
    .bundle_con = NULL,         # Non-blocking stdin connection in hosted bundle mode

    .cleanup = function() {
      if (getOption("rdesk.async_backend", "callr") == "mirai") {
        rdesk_stop_daemons()  # Shut down worker pool cleanly
      }
      if (!is.null(private$.window_proc)) {
        rdesk_close_window(private$.window_proc)
        private$.window_proc <- NULL
      }
      rdesk_log(sprintf("Application closed: %s", private$.title), level = "INFO", app_name = private$.title)
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
 
    .build_menu_json = function(items, prefix = "menu") {
      # Use an environment to ensure we don't clear existing actions from other menus (e.g. tray vs bar)
      if (is.null(private$.menu_actions)) private$.menu_actions <- new.env(parent = emptyenv())
      
      recurse <- function(it, parent_label = prefix) {
        res <- list()
        for (i in seq_along(it)) {
          val  <- it[[i]]
          lbl  <- if (is.null(names(it)) || names(it)[i] == "") as.character(val) else names(it)[i]
          
          # Support both simple list("L"=fn) and detailed list("L"=list(checked=T, callback=fn))
          item_callback <- val
          item_checked  <- FALSE
          is_submenu    <- is.list(val) && !is.function(val) && ("items" %in% names(val))
          is_detailed   <- is.list(val) && !is.function(val) && (any(c("callback", "checked") %in% names(val)))

          if (lbl == "---" || identical(val, "---")) {
            res <- c(res, list(list(label = "---")))
          } else if (is_submenu) {
            # Submenu with items
            sub_items <- if (is.list(val$items)) val$items else val
            res <- c(res, list(list(label = lbl, items = recurse(sub_items, paste0(parent_label, "_", lbl)))))
          } else if (is.list(val) && !is.function(val) && !is_detailed) {
            # Default to treat any list without 'callback'/'checked' as a submenu (backward compat)
            res <- c(res, list(list(label = lbl, items = recurse(val, paste0(parent_label, "_", lbl)))))
          } else {
            # Menu item
            if (is_detailed) {
               item_callback <- val$callback
               item_checked  <- isTRUE(val$checked)
            }
            item_id <- paste0(parent_label, "_", i, "_", digest::digest(lbl, algo="crc32"))
            private$.menu_actions[[item_id]] <- item_callback
            res <- c(res, list(list(label = lbl, id = item_id, checked = item_checked)))
          }
        }
        res
      }

      # Top level is special - it's a list of top-level menus
      final <- list()
      for (top_label in names(items)) {
        sub_items <- items[[top_label]]
        final <- c(final, list(list(label = top_label, items = recurse(sub_items, paste0(prefix, "_", top_label)))))
      }
      final
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
          private$.pending_dialogs[[evt$id]] <- if (!is.null(evt$path)) evt$path else evt$result
        } else if (evt$event == "DIALOG_CANCEL") {
          private$.pending_dialogs[[evt$id]] <- "__CANCEL__"
        } else if (evt$event == "TRAY_CLICK") {
          if (is.function(private$.tray_callback)) {
            tryCatch(private$.tray_callback(evt$button),
                     error = function(e) warning("[RDesk] tray handler error: ", e$message))
          }
        } else if (evt$event == "WINDOW_CLOSING") {
          res <- TRUE
          if (is.function(private$.on_close_fn)) {
            res <- tryCatch(private$.on_close_fn(), error = function(e) {
              warning("[RDesk] on_close error: ", e$message)
              TRUE 
            })
          }
          if (isTRUE(res)) {
            self$quit()
          }
        } else if (evt$event == "HOTKEY") {
          callback <- private$.hotkey_callbacks[[as.character(evt$id)]]
          if (is.function(callback)) {
            tryCatch(callback(), error = function(e) warning("[RDesk] hotkey handler error: ", e$message))
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
    }
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
}#' Automatically check for and install app updates
#'
#' @description
#' \code{rdesk_auto_update} is a high-level function designed for bundled (standalone)
#' applications. It checks a remote version string, compares it with the current
#' version, and if a newer version is found, it downloads and executes the installer
#' silently before quitting the current application.
#'
#' @param version_url URL to a plain text file containing the latest version string (e.g., "1.1.0")
#' @param download_url URL to the latest installer .exe
#' @param current_version Current app version string e.g. "1.0.0"
#' @param silent If TRUE, downloads and installs without prompting. Default FALSE.
#' @param app Optional App instance for showing toast notifications.
#' @return Invisible TRUE if update was applied, FALSE otherwise.
#' @export
rdesk_auto_update <- function(version_url,
                               download_url,
                               current_version,
                               silent  = FALSE,
                               app     = NULL) {
  if (!rdesk_is_bundle()) {
    # Only acts in bundled mode
    return(invisible(FALSE))
  }

  latest <- tryCatch({
    con <- url(version_url)
    on.exit(close(con))
    trimws(readLines(con, n = 1, warn = FALSE))
  }, error = function(e) {
    warning("[RDesk] Could not fetch remote version: ", e$message)
    return(invisible(NULL))
  })

  if (is.null(latest) || !nzchar(latest)) {
    return(invisible(FALSE))
  }

  if (utils::compareVersion(latest, current_version) <= 0) {
    # No update needed
    return(invisible(FALSE))
  }

  # Update available
  if (!is.null(app) && !silent) {
    app$toast(
      paste0("Version ", latest, " is available. Downloading..."),
      type = "info"
    )
  }

  # Temporary path for the new installer
  dest <- file.path(tempdir(), paste0("update-", latest, "-setup.exe"))

  tryCatch({
    message("[RDesk] Downloading update version ", latest, "...")
    utils::download.file(download_url, dest, mode = "wb", quiet = TRUE)

    if (!is.null(app) && !silent) {
      app$toast("Update downloaded. Restarting...", type = "success")
      Sys.sleep(1.5)
    }

    # Launch installer silently and quit
    # /SILENT /SUPPRESSMSGBOXES /NORESTART is standard for InnoSetup
    message("[RDesk] Executing silent installer: ", dest)
    system2(dest, args = c("/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART"),
            wait = FALSE)

    if (!is.null(app)) {
      app$quit()
    } else {
      # Fallback if no app object - just tell the user we are exiting
      message("[RDesk] Update triggered. Closing application.")
      quit(save = "no")
    }

    invisible(TRUE)

  }, error = function(e) {
    if (!is.null(app)) {
      app$toast(paste("Update failed:", e$message), type = "error")
    }
    warning("[RDesk] Update failed: ", e$message)
    invisible(FALSE)
  })
}

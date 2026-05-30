# R/hotreload.R
# Hot reloading system for RDesk: Watches R/ and www/ directories for live developer updates

#' Initialize hot reloading tracking
#'
#' @param app_dir Path to the application root directory.
#' @return A list containing file paths as names and modification times (POSIXct) as values.
#' @keywords internal
rdesk_hotreload_init <- function(app_dir) {
  files <- character(0)
  
  # Track R directory
  r_dir <- file.path(app_dir, "R")
  if (dir.exists(r_dir)) {
    files <- c(files, list.files(r_dir, pattern = "\\.R$", full.names = TRUE, recursive = TRUE))
  }
  
  # Track www directory
  www_dir <- file.path(app_dir, "www")
  if (dir.exists(www_dir)) {
    # Track HTML, CSS, JS files
    files <- c(files, list.files(www_dir, pattern = "\\.(html|css|js)$", full.names = TRUE, recursive = TRUE))
  }
  
  env <- new.env(parent = emptyenv())
  if (length(files) == 0) {
    return(env)
  }
  
  # Normalize paths and retrieve mtimes
  files <- normalizePath(files, mustWork = FALSE)
  mtimes <- file.info(files)$mtime
  
  for (i in seq_along(files)) {
    env[[files[i]]] <- mtimes[i]
  }
  env
}

#' Poll for file modifications and execute hot reloads
#'
#' @param app The RDesk App instance.
#' @param tracking_env An environment containing file paths and their cached mtimes.
#' @return Invisible NULL.
#' @keywords internal
rdesk_hotreload_poll <- function(app, tracking_env) {
  app_dir <- app$get_dir()
  
  # Get all current files to watch
  current_files <- character(0)
  r_dir <- file.path(app_dir, "R")
  if (dir.exists(r_dir)) {
    current_files <- c(current_files, list.files(r_dir, pattern = "\\.R$", full.names = TRUE, recursive = TRUE))
  }
  www_dir <- file.path(app_dir, "www")
  if (dir.exists(www_dir)) {
    current_files <- c(current_files, list.files(www_dir, pattern = "\\.(html|css|js)$", full.names = TRUE, recursive = TRUE))
  }
  
  if (length(current_files) == 0) return(invisible(NULL))
  current_files <- normalizePath(current_files, mustWork = FALSE)
  
  # Get mtimes for all current files
  info <- file.info(current_files)
  current_mtimes <- info$mtime
  names(current_mtimes) <- current_files
  
  ui_changed <- FALSE
  r_changed <- character(0)
  
  # 1. Check for modified or newly added files
  for (f in current_files) {
    cached_mtime <- tracking_env[[f]]
    current_mtime <- current_mtimes[[f]]
    
    if (is.null(cached_mtime) || is.na(cached_mtime)) {
      # New file added
      tracking_env[[f]] <- current_mtime
      if (grepl("\\.R$", f)) {
        r_changed <- c(r_changed, f)
      } else {
        ui_changed <- TRUE
      }
    } else if (current_mtime > cached_mtime) {
      # File modified
      tracking_env[[f]] <- current_mtime
      if (grepl("\\.R$", f)) {
        r_changed <- c(r_changed, f)
      } else {
        ui_changed <- TRUE
      }
    }
  }
  
  # 2. Check for deleted files
  cached_files <- ls(tracking_env, all.names = TRUE)
  deleted_files <- setdiff(cached_files, current_files)
  for (f in deleted_files) {
    rm(list = f, envir = tracking_env)
    # If a UI file was deleted, we should reload
    if (!grepl("\\.R$", f)) {
      ui_changed <- TRUE
    }
  }
  
  # 3. Apply updates
  if (length(r_changed) > 0) {
    for (f in r_changed) {
      message("[RDesk Hot Reload] Sourcing changed file: ", basename(f))
      tryCatch({
        # Source the file in global environment so that the handlers can be updated/replaced
        source(f, local = .GlobalEnv)
      }, error = function(e) {
        warning("[RDesk Hot Reload] Failed to source R file: ", f, "\nError: ", e$message)
        app$toast(paste0("Hot Reload: Error in R file: ", e$message), type = "error")
      })
    }
    
    # If the app defined 'init_handlers', call it to re-bind event handlers!
    if (exists("init_handlers", envir = .GlobalEnv, inherits = FALSE)) {
      message("[RDesk Hot Reload] Re-binding event handlers...")
      tryCatch({
        init_handlers <- get("init_handlers", envir = .GlobalEnv)
        init_handlers(app)
        app$toast("Hot Reload: Backend modules updated.", type = "success")
      }, error = function(e) {
        warning("[RDesk Hot Reload] Failed to execute init_handlers: ", e$message)
        app$toast(paste0("Hot Reload: Bind error: ", e$message), type = "error")
      })
    }
  }
  
  if (ui_changed) {
    message("[RDesk Hot Reload] UI file changed. Refreshing WebView2...")
    app$send("__reload_ui__")
  }
  
  invisible(NULL)
}

#' Enable live hot reloading for an RDesk application
#'
#' @description
#' `rdesk_watch` enables live monitoring of R source files and UI asset files (HTML, CSS, JS).
#' When a UI file changes, the application automatically reloads the page. When an R script changes,
#' the framework sources the modified module and automatically re-binds application event handlers.
#'
#' @param app The RDesk `App` instance to monitor.
#' @param enabled Logical. If `TRUE` (default), enables live monitoring. Set to `FALSE` to disable.
#' @return The `App` instance (invisible).
#' @export
rdesk_watch <- function(app, enabled = TRUE) {
  if (!inherits(app, "App")) stop("app must be an RDesk App instance")
  app$watch(enabled)
  invisible(app)
}

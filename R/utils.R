# R/utils.R

#' Check if the app is running in a bundled (standalone) environment
#' @return TRUE if running in a bundle, FALSE otherwise
#' @export
rdesk_is_bundle <- function() {
  # This environment variable is set by stub.cpp
  Sys.getenv("R_BUNDLE_APP") == "1"
}

#' Sanitize an app name for filesystem-safe bundled log paths
#' @keywords internal
rdesk_sanitize_log_component <- function(x) {
  x <- gsub("[^[:alnum:]_.-]+", "_", x, perl = TRUE)
  x <- trimws(x)
  if (!nzchar(x)) "RDeskApp" else x
}

#' Resolve the bundled log directory for an app
#' @keywords internal
rdesk_log_dir <- function(app_name = Sys.getenv("R_APP_NAME", "RDeskApp")) {
  # If running as a standalone bundle, use LocalAppData
  if (rdesk_is_bundle()) {
    base_dir <- Sys.getenv("LOCALAPPDATA")
    if (nzchar(base_dir)) {
      return(file.path(base_dir, "RDesk", rdesk_sanitize_log_component(app_name)))
    }
  }
  
  # Default/Fallback: Always use tempdir() per CRAN policy
  # for non-bundled or check environments
  file.path(tempdir(), "RDesk", rdesk_sanitize_log_component(app_name))
}

#' Log a message to the app's log file
#'
#' @param message Message to log
#' @param level Log level ("INFO", "WARN", "ERROR")
#' @param app_name Optional app name to determine log file
#' @keywords internal
rdesk_log <- function(message, level = "INFO", app_name = Sys.getenv("R_APP_NAME", "RDeskApp")) {
  log_dir <- rdesk_log_dir(app_name)
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
  
  log_file <- file.path(log_dir, "app.log")
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%OS3")
  line <- sprintf("[%s] [%s] %s\n", timestamp, level, message)
  
  cat(line, file = log_file, append = TRUE)
}

#' Resolve the www directory for an app
#'
#' @param www_dir User-provided path to www directory (character)
#'   Passing an explicit absolute path is the most reliable option and skips
#'   the best-effort call-stack search.
#' @return Normalized absolute path to a valid www directory
#' @keywords internal
rdesk_resolve_www <- function(www_dir) {
  # 1. Default to built-in template if NULL
  if (is.null(www_dir)) {
    path <- system.file("templates", "hello", "www", package = "RDesk")
    if (path == "" || !dir.exists(path)) {
      path <- file.path(getwd(), "inst", "templates", "hello", "www")
    }
    www_dir <- path
  }

  # 2. Ensure rdesk.js is present and up-to-date in the target www directory
  path <- normalizePath(www_dir, mustWork = FALSE)
  if (dir.exists(path)) {
    target_js <- file.path(path, "rdesk.js")
    
    # In dev mode, always copy to reflect library changes
    src_js <- system.file("www", "rdesk.js", package = "RDesk")
    if (src_js == "" || !file.exists(src_js)) {
      src_js <- file.path(getwd(), "inst", "www", "rdesk.js")
    }
    
    should_copy <- file.exists(src_js) && (
      !file.exists(target_js) ||
        !identical(unname(tools::md5sum(src_js)), unname(tools::md5sum(target_js)))
    )

    if (should_copy) {
      file.copy(src_js, target_js, overwrite = TRUE)
    }
    return(path)
  }

  # 3. Best-effort search for the calling script.
  # This relies on source() implementation details and is intentionally a fallback
  # when the caller did not provide an explicit path.
  frames <- sys.frames()
  calls <- sys.calls()
  
  # Method A: Look for 'ofile' or 'file' in frames (standard source() behavior)
  for (f in rev(frames)) {
    for (var in c("ofile", "file")) {
      if (exists(var, envir = f)) {
        val <- get(var, envir = f)
        if (is.character(val) && length(val) == 1 && file.exists(val)) {
          script_dir <- dirname(normalizePath(val))
          p <- normalizePath(file.path(script_dir, www_dir), mustWork = FALSE)
          if (dir.exists(p)) return(p)
          
          # Fallback: Is the user just saying "www" but it's in a sibling folder?
          p_alt <- normalizePath(file.path(script_dir, "www"), mustWork = FALSE)
          if (dir.exists(p_alt)) return(p_alt)
        }
      }
    }
  }

  # Method B: Regex the call stack for source("...") calls
  for (cl in rev(as.character(calls))) {
     # Use a flexible regex for source(file="...") or source("...")
     m <- regmatches(cl, regexec("source\\s*\\(\\s*(?:file\\s*=\\s*)?[\"'](.+?)[\"']", cl))
     if (length(m[[1]]) >= 2) {
        potential_script <- m[[1]][2]
        if (file.exists(potential_script)) {
           script_dir <- dirname(normalizePath(potential_script))
           p <- normalizePath(file.path(script_dir, www_dir), mustWork = FALSE)
           if (dir.exists(p)) return(p)
        }
     }
  }

  # 4. INST/APPS SCAN (Dev fallback)
  # If we provide "ts_creator" or "www", look inside the project structure
  apps_root <- file.path(getwd(), "inst", "apps")
  if (dir.exists(apps_root)) {
    # Check if www_dir IS one of the apps (e.g. App$new(www="ts_creator"))
    app_p <- file.path(apps_root, www_dir, "www")
    if (dir.exists(app_p)) return(app_p)
    
    # Recursive search for any folder named 'www' that has an index.html.
    # Refuse to guess if there is more than one candidate.
    all_wwws <- list.dirs(apps_root, recursive = TRUE)
    all_wwws <- all_wwws[basename(all_wwws) == "www"]
    all_wwws <- all_wwws[file.exists(file.path(all_wwws, "index.html"))]
    if (length(all_wwws) == 1) {
      return(all_wwws)
    }
    if (length(all_wwws) > 1) {
      stop("[RDesk] Multiple candidate www directories were found under inst/apps.\n",
           "Input provided: ", www_dir, "\n",
           "Candidates:\n  - ", paste(normalizePath(all_wwws), collapse = "\n  - "), "\n",
           "Tip: Pass an explicit absolute path to the correct www directory.")
    }
  }

  stop("[RDesk] www directory not found.\n",
       "Input provided: ", www_dir, "\n",
       "Working Directory: ", getwd(), "\n",
       "Tip: Try using an absolute path or ensure your 'www' folder is next to your script.")
}

#' Convert a data frame to a list suitable for JSON serialization
#'
#' @param df Data frame to convert
#' @return A list with 'rows' (list of lists) and 'cols' (character vector)
#' @export
rdesk_df_to_list <- function(df) {
  if (is.null(df) || nrow(df) == 0) {
    return(list(rows = list(), cols = character(0)))
  }
  list(
    rows = lapply(seq_len(nrow(df)), function(i) as.list(df[i, ])),
    cols = names(df)
  )
}

#' Convert a ggplot2 object to a base64-encoded PNG string
#'
#' @param plot A ggplot2 object
#' @param width Width in inches (default 6)
#' @param height Height in inches (default 4)
#' @param dpi DPI resolution (default 96)
#' @return A base64-encoded PNG string or a fallback error plot
#' @export
rdesk_plot_to_base64 <- function(plot, width = 6, height = 4, dpi = 96) {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp), add = TRUE)
  
  res <- tryCatch({
    ggplot2::ggsave(tmp, plot = plot, width = width, height = height, dpi = dpi)
    TRUE
  }, error = function(e) {
    warning("[RDesk] Failed to save plot: ", e$message)
    FALSE
  })
  
  if (isTRUE(res) && file.exists(tmp)) {
    raw <- readBin(tmp, "raw", file.info(tmp)$size)
    return(paste0("data:image/png;base64,", base64enc::base64encode(raw)))
  }
  
  # Fallback to error plot
  rdesk_error_plot("Plot generation failed")
}

#' Generate a base64-encoded error plot
#'
#' @param message Error message to display (optional)
#' @return A base64-encoded PNG string
#' @export
rdesk_error_plot <- function(message = "Error generating plot") {
  tmp <- tempfile(fileext = ".png")
  on.exit(unlink(tmp), add = TRUE)
  
  p <- ggplot2::ggplot() +
    ggplot2::annotate("text", x = 1, y = 1, label = message, color = "red", size = 5) +
    ggplot2::theme_void()
    
  ggplot2::ggsave(tmp, plot = p, width = 4, height = 2, dpi = 72)
  
  if (file.exists(tmp)) {
    raw <- readBin(tmp, "raw", file.info(tmp)$size)
    return(paste0("data:image/png;base64,", base64enc::base64encode(raw)))
  }
  NULL
}

#' Parse a hotkey string into modifiers and virtual key codes
#' @param keys String like "Ctrl+Shift+A" or "Alt+F4"
#' @return List with modifiers and vk
#' @keywords internal
rdesk_parse_hotkey <- function(keys) {
  parts <- trimws(tolower(strsplit(keys, "[+ ]")[[1]]))
  mod <- 0
  vk  <- 0
  
  if ("alt"   %in% parts) mod <- mod + 1
  if ("ctrl"  %in% parts || "control" %in% parts) mod <- mod + 2
  if ("shift" %in% parts) mod <- mod + 4
  if ("win"   %in% parts) mod <- mod + 8
  
  # Remove modifiers to find the main key
  main <- setdiff(parts, c("alt", "ctrl", "control", "shift", "win"))
  if (length(main) == 0) return(list(modifiers = mod, vk = 0))
  
  key <- main[1]
  if (nchar(key) == 1) {
    vk <- as.integer(charToRaw(toupper(key)))
  } else if (grepl("^f[0-9]+$", key)) {
    f_num <- as.integer(substring(key, 2))
    vk <- 0x70 + (f_num - 1) # F1 is 0x70
  } else {
    # Common special keys
    vk <- switch(key,
      "space"  = 0x20,
      "enter"  = 0x0D,
      "return" = 0x0D,
      "escape" = 0x1B,
      "tab"    = 0x09,
      "backspace" = 0x08,
      "delete" = 0x2E,
      "insert" = 0x2D,
      "home"   = 0x24,
      "end"    = 0x23,
      "pageup" = 0x21,
      "pagedown" = 0x22,
      "left"   = 0x25,
      "up"     = 0x26,
      "right"  = 0x27,
      "down"   = 0x28,
      0
    )
  }
  
  list(modifiers = mod, vk = vk)
}

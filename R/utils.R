# R/utils.R

#' Check if the app is running in a bundled (standalone) environment
#'
#' @description
#' Returns \code{TRUE} when the current R process was launched by the RDesk
#' stub binary as part of a compiled standalone application. The stub sets the
#' \code{R_BUNDLE_APP} environment variable to \code{"1"} before starting R.
#' Use this predicate to switch between development-time and runtime paths
#' (e.g. logging directories, asset resolution).
#'
#' @return \code{TRUE} if running inside a bundled .exe or .app, \code{FALSE} otherwise.
#' @examples
#' # Returns FALSE in a normal interactive R session
#' rdesk_is_bundle()
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
  # If running as a standalone bundle, use OS-appropriate user data directory
  if (rdesk_is_bundle()) {
    base_dir <- if (.Platform$OS.type == "windows") {
      Sys.getenv("LOCALAPPDATA")
    } else if (Sys.info()[["sysname"]] == "Darwin") {
      file.path(Sys.getenv("HOME"), "Library/Application Support")
    } else {
      # Linux/Unix - XDG standard
      Sys.getenv("XDG_DATA_HOME", file.path(Sys.getenv("HOME"), ".local/share"))
    }
    
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

  # Console mirroring for developers
  if (isTRUE(getOption("rdesk.verbose_log", TRUE)) && !rdesk_is_bundle()) {
    console_line <- sprintf("[RDesk %s] %s", level, message)
    message(console_line)
  }
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
  # If we provide "data_studio" or "www", look inside the project structure
  apps_root <- file.path(getwd(), "inst", "apps")
  if (dir.exists(apps_root)) {
    # Check if www_dir IS one of the apps (e.g. App$new(www="data_studio"))
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
#' @description
#' Converts a data frame into the two-part list structure that \code{rdesk.js}
#' expects: a \code{rows} component (list of per-row named lists) and a
#' \code{cols} component (character vector of column names). Empty or NULL
#' data frames return empty containers rather than an error.
#'
#' @param df A data frame to convert. NULL or zero-row data frames are handled gracefully.
#' @return A list with two elements:
#'   \describe{
#'     \item{rows}{A list of named lists, one per row.}
#'     \item{cols}{A character vector of column names.}
#'   }
#' @seealso [rdesk_plot_to_base64()] for converting plot output.
#' @examples
#' result <- rdesk_df_to_list(head(mtcars, 3))
#' stopifnot(length(result$rows) == 3)
#' stopifnot("mpg" %in% result$cols)
#'
#' # NULL input returns empty containers
#' empty <- rdesk_df_to_list(NULL)
#' stopifnot(length(empty$rows) == 0)
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
#' @description
#' Renders a ggplot2 object to a temporary PNG file and returns the result as a
#' Base64-encoded data URI string (\code{data:image/png;base64,...}). This
#' format can be assigned directly to an \code{<img>} tag \code{src} attribute
#' in the JavaScript frontend via \code{app$send()}.
#'
#' If ggplot2 is not installed, the function stops with a helpful message.
#' If rendering fails, a fallback error plot is returned instead of \code{NULL}.
#'
#' @param plot   A ggplot2 object to render.
#' @param width  Width of the rendered image in inches. Default \code{6}.
#' @param height Height of the rendered image in inches. Default \code{4}.
#' @param dpi    Dots per inch resolution. Default \code{96}.
#' @return A single-element character string containing the data URI,
#'   or the output of [rdesk_error_plot()] if rendering fails.
#' @seealso [rdesk_error_plot()] for the fallback error plot.
#' @examples
#' if (requireNamespace("ggplot2", quietly = TRUE)) {
#'   p <- ggplot2::ggplot(mtcars, ggplot2::aes(wt, mpg)) +
#'        ggplot2::geom_point()
#'   b64 <- rdesk_plot_to_base64(p)
#'   stopifnot(grepl("^data:image/png;base64,", b64))
#' }
#' @export
rdesk_plot_to_base64 <- function(plot, width = 6, height = 4, dpi = 96) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    stop("Package 'ggplot2' is required for rdesk_plot_to_base64(). ",
         "Install it with: install.packages('ggplot2')")
  }
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
#' @description
#' Renders a minimal ggplot2 plot containing the supplied error message text and
#' returns it as a Base64 data URI. Used as a safe fallback by
#' [rdesk_plot_to_base64()] when plot generation fails. Returns \code{NULL}
#' silently if ggplot2 is not installed.
#'
#' @param message Character string to display on the error plot.
#'   Defaults to \code{"Error generating plot"}.
#' @return A single-element character string (data URI) or \code{NULL} if
#'   ggplot2 is not available.
#' @seealso [rdesk_plot_to_base64()]
#' @export
rdesk_error_plot <- function(message = "Error generating plot") {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    return(NULL)  # ggplot2 absent: silently return NULL
  }
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

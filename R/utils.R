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
  base_dir <- Sys.getenv("LOCALAPPDATA")
  if (!nzchar(base_dir)) {
    base_dir <- Sys.getenv("TEMP", "C:/Temp")
  }
  file.path(base_dir, "RDesk", rdesk_sanitize_log_component(app_name))
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

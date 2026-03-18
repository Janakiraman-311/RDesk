# R/utils.R

#' Check if the app is running in a bundled (standalone) environment
#' @return TRUE if running in a bundle, FALSE otherwise
#' @export
rdesk_is_bundle <- function() {
  # This environment variable is set by stub.cpp
  Sys.getenv("R_BUNDLE_APP") == "1"
}

#' Resolve the www directory for an app
#'
#' @param www_dir User-provided path to www directory (character)
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
    
    if (file.exists(src_js)) {
      file.copy(src_js, target_js, overwrite = TRUE)
    }
    return(path)
  }

  # 3. TRIPLE-LOCK SEARCH FOR SOURCE SCRIPT
  # We climb the stack to find where the call came from
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
    
    # Recursive search for any folder named 'www' that has an index.html
    all_wwws <- list.dirs(apps_root, recursive = TRUE)
    all_wwws <- all_wwws[basename(all_wwws) == "www"]
    for (w in all_wwws) {
       if (file.exists(file.path(w, "index.html"))) {
          # If we have multiple, we might pick the wrong one, 
          # but usually during dev there is only one "active" one being sourced.
          return(w)
       }
    }
  }

  stop("[RDesk] www directory not found.\n",
       "Input provided: ", www_dir, "\n",
       "Working Directory: ", getwd(), "\n",
       "Tip: Try using an absolute path or ensure your 'www' folder is next to your script.")
}

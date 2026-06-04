# R/storage.R
# Persistent storage system with multi-user isolation on Windows

#' @importFrom R6 R6Class
#' @importFrom jsonlite fromJSON write_json
NULL

#' RDesk Storage Manager
#'
#' @description
#' Provides a lightweight, JSON-backed key-value store for application state,
#' preferences, and settings. Handles multi-user data isolation automatically.
#'
#' @export
RDeskStorage <- R6::R6Class("RDeskStorage",
  public = list(
    #' @description Initialize a new RDeskStorage manager
    #' @param app_name Application name
    #' @param storage_type Storage type: "roaming", "local", or "shared"
    initialize = function(app_name, storage_type = "local") {
      private$.app_name <- rdesk_sanitize_log_component(app_name)
      private$.type <- match.arg(storage_type, c("roaming", "local", "shared"))
      private$.dir <- private$.resolve_dir()
      private$.file <- file.path(private$.dir, "storage.json")
      private$.load()
    },

    #' @description Set a key-value pair in storage
    #' @param key Character string key
    #' @param value Value to store (must be JSON serializable)
    #' @return The RDeskStorage instance (invisible)
    set = function(key, value) {
      private$.data[[key]] <- value
      private$.save()
      invisible(self)
    },

    #' @description Retrieve a value from storage
    #' @param key Character string key
    #' @param default Default value to return if the key is not found
    #' @return The stored value, or the default value
    get = function(key, default = NULL) {
      if (exists(key, envir = private$.data, inherits = FALSE)) {
        private$.data[[key]]
      } else {
        default
      }
    },

    #' @description Remove a key from storage
    #' @param key Character string key
    #' @return The RDeskStorage instance (invisible)
    remove = function(key) {
      if (exists(key, envir = private$.data, inherits = FALSE)) {
        rm(list = key, envir = private$.data)
        private$.save()
      }
      invisible(self)
    },

    #' @description Clear all data in this storage domain
    #' @return The RDeskStorage instance (invisible)
    clear = function() {
      private$.data <- new.env(parent = emptyenv())
      private$.save()
      invisible(self)
    },

    #' @description List all keys currently in storage
    #' @return Character vector of keys
    keys = function() {
      ls(private$.data, all.names = TRUE)
    },

    #' @description Get the directory path containing the storage file
    #' @return Character string directory path
    path = function() {
      private$.dir
    }
  ),

  private = list(
    .app_name = NULL,
    .type = NULL,
    .dir = NULL,
    .file = NULL,
    .data = NULL,

    .resolve_dir = function() {
      if (rdesk_is_bundle()) {
        base_dir <- switch(private$.type,
          "roaming" = Sys.getenv("APPDATA"),
          "local"   = Sys.getenv("LOCALAPPDATA"),
          "shared"  = Sys.getenv("PROGRAMDATA")
        )
        if (nzchar(base_dir)) {
          target <- file.path(base_dir, "RDesk", private$.app_name)
          
          # Test if target dir is writable. If not, fallback to tempdir
          is_writable <- tryCatch({
            if (!dir.exists(target)) dir.create(target, recursive = TRUE, showWarnings = FALSE)
            # Try writing a dummy test file
            test_file <- file.path(target, ".write_test")
            writeLines("test", test_file)
            unlink(test_file)
            TRUE
          }, error = function(e) FALSE)
          
          if (is_writable) {
            return(target)
          }
        }
      }
      
      # Default/Fallback: Always use tempdir() per CRAN policy
      # for non-bundled or check environments
      target <- file.path(tempdir(), "RDesk", private$.app_name, private$.type)
      dir.create(target, recursive = TRUE, showWarnings = FALSE)
      target
    },

    .load = function() {
      private$.data <- new.env(parent = emptyenv())
      if (file.exists(private$.file)) {
        tryCatch({
          raw <- jsonlite::fromJSON(private$.file, simplifyVector = FALSE)
          for (nm in names(raw)) {
            private$.data[[nm]] <- raw[[nm]]
          }
        }, error = function(e) {
          warning("[RDesk Storage] Failed to load storage from ", private$.file, ": ", e$message)
        })
      }
    },

    .save = function() {
      raw <- as.list(private$.data)
      tryCatch({
        jsonlite::write_json(raw, private$.file, auto_unbox = TRUE, pretty = TRUE)
      }, error = function(e) {
        warning("[RDesk Storage] Failed to write storage to ", private$.file, ": ", e$message)
      })
    }
  )
)

#' Create a multi-user storage manager
#'
#' @description
#' `rdesk_storage` provides file-based persistent storage for desktop applications.
#' On Windows, it handles multi-user data isolation by mapping key-value stores to the
#' correct system folder depending on the requested type.
#'
#' @details
#' The three storage types correspond to different Windows user profile folders:
#' \describe{
#'   \item{roaming}{User roaming folder (APPDATA). Suitable for per-user preferences
#'     that should follow the user across machines when roaming profiles are enabled.}
#'   \item{local}{User local folder (LOCALAPPDATA). Suitable for cache, history,
#'     or data that is specific to one machine.}
#'   \item{shared}{Machine-wide folder (PROGRAMDATA). Suitable for configuration
#'     shared by all users on the same computer.}
#' }
#' Outside a bundled application (e.g. during development or R CMD check), all
#' storage types fall back to a subdirectory of \code{tempdir()} to comply with
#' CRAN policies on persistent file writes.
#'
#' @param app_name Character string. The application name, used as the subfolder name.
#' @param type Storage type: one of \code{"roaming"} (user roaming folder, APPDATA),
#'   \code{"local"} (user local folder, LOCALAPPDATA), or \code{"shared"}
#'   (machine-wide folder, PROGRAMDATA).
#' @return An \code{RDeskStorage} R6 instance with \code{get()}, \code{set()},
#'   \code{remove()}, \code{clear()}, \code{keys()}, and \code{path()} methods.
#' @seealso [RDeskStorage] for the full method reference.
#' @examples
#' # Create a local storage manager for an app called "MyApp"
#' s <- rdesk_storage("MyApp", "local")
#'
#' # Store and retrieve a value
#' s$set("last_filter", "cyl == 6")
#' stopifnot(s$get("last_filter") == "cyl == 6")
#'
#' # List all keys
#' s$keys()
#'
#' # Remove a specific key
#' s$remove("last_filter")
#' @export
rdesk_storage <- function(app_name, type = c("local", "roaming", "shared")) {
  type <- match.arg(type)
  RDeskStorage$new(app_name, type)
}

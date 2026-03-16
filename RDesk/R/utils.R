# R/utils.R

#' Find a free TCP port
#'
#' Uses httpuv's built-in utility — more reliable than manual socket tricks
#' @return A free port number (integer)
#' @keywords internal
rdesk_free_port <- function() {
  httpuv::randomPort(min = 49152L, max = 65535L)
}

#' Resolve the www directory for an app
#'
#' @param www_dir User-provided path to www directory (character)
#' @return Normalized absolute path to a valid www directory
#' @keywords internal
rdesk_resolve_www <- function(www_dir) {
  if (is.null(www_dir)) {
    # Fall back to built-in hello-world template
    path <- system.file("templates", "hello", "www", package = "RDesk")
    # During dev if not installed
    if (path == "") {
      path <- file.path(getwd(), "inst", "templates", "hello", "www")
    }
    return(path)
  }
  path <- normalizePath(www_dir, mustWork = FALSE)
  if (!dir.exists(path)) {
    stop("[RDesk] www directory not found: ", www_dir)
  }
  path
}

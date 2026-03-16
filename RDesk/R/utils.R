# R/utils.R

#' Find a free TCP port
#' Uses httpuv's built-in utility — more reliable than manual socket tricks
#' @keywords internal
rdesk_free_port <- function() {
  httpuv::randomPort(min = 49152L, max = 65535L)
}

#' Resolve the www directory for an app
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

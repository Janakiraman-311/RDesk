# {{PKG_NAME}} — R wrappers
# Thin R-level wrappers around compiled C++ functions.
# Keep this file minimal — business logic belongs in src/*.cpp

#' Check licence validity
#'
#' @return TRUE if licence is valid, FALSE otherwise
#' @keywords internal
pkg_licence_valid <- function() {
  tryCatch({
    # Try calling a compiled function — if licence check passes, we are valid
    {{ALGORITHM_NAME}}(numeric(0), 1.0)
    TRUE
  }, error = function(e) {
    if (grepl("Licence", e$message)) FALSE else stop(e)
  })
}

#' Set licence key for this session
#'
#' @param key Character string licence key
#' @return Invisible TRUE
#' @export
set_licence_key <- function(key) {
  Sys.setenv("{{PKG_NAME}}_LICENCE_KEY" = key)
  if (!pkg_licence_valid()) {
    Sys.unsetenv("{{PKG_NAME}}_LICENCE_KEY")
    stop("[{{PKG_NAME}}] Invalid licence key.")
  }
  message("[{{PKG_NAME}}] Licence key accepted.")
  invisible(TRUE)
}

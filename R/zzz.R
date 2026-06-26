#' @importFrom base64enc base64encode
NULL

# R/zzz.R
# Package initialization hooks (.onLoad / .onAttach).
# .onLoad  - runs when the package is loaded (library(RDesk) or require(RDesk)).
# .onAttach - runs after .onLoad and is used for startup messages visible to the user.

.onLoad <- function(libname, pkgname) {
  # Pin IPC contract version so downstream code has a stable default.
  options(rdesk.ipc_version = "1.0")

  # CI guard: GitHub Actions runners are headless daemon sessions.
  # WKWebView cannot open a real window there, so we set ci_mode = TRUE
  # and force the callr backend (mirai persistent daemons can hang in CI).
  if (Sys.getenv("GITHUB_ACTIONS") == "true") {
    options(rdesk.ci_mode    = TRUE)
    options(rdesk.async_backend = "callr")
  } else {
    # In a normal user session prefer mirai (persistent daemon pool) when
    # available because it reuses workers across tasks. Fall back to callr
    # (on-demand subprocess) when mirai is not installed.
    backend <- if (requireNamespace("mirai", quietly = TRUE)) "mirai" else "callr"
    options(rdesk.async_backend = backend)
  }

  # Clear any stale job/app state that might persist between R sessions
  # when the package is reloaded without a fresh R process.
  rm(list = ls(envir = .rdesk_jobs), envir = .rdesk_jobs)
  rm(list = ls(envir = .rdesk_apps), envir = .rdesk_apps)
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "[RDesk] v", utils::packageVersion("RDesk"), " ready."
  )
  # Verify that the native launcher binary was compiled and installed.
  # rdesk_launcher_path() calls stop(), so we replicate the file check here
  # to produce a friendlier message instead of an error at attach time.
  bin_name <- if (.Platform$OS.type == "windows") "rdesk-launcher.exe" else "rdesk-launcher"
  path <- system.file("bin", bin_name, package = "RDesk")
  if (path == "" || !file.exists(path)) {
     packageStartupMessage(
       "\n[WARNING] Native launcher binary not found in the installed package library.\n",
       "Tip: If you installed RDesk from source, ensure you have Rtools installed and\n",
       "run `devtools::install(pkg = '.', upgrade = FALSE, quick = TRUE)` to build it."
     )
  }
}

# Suppress R CMD check notes about unbound variables in mirai expressions
if (getRversion() >= "2.15.1") {
  utils::globalVariables(c(
    "progress_file_path",
    "task_fn",
    "task_args",
    ".lib_paths"
  ))
}


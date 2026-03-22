#' @importFrom base64enc base64encode
NULL

# R/zzz.R
# Package initialization logic

.onLoad <- function(libname, pkgname) {
  # Set default IPC version for the contract
  options(rdesk.ipc_version = "1.0")

  # CI Guard: Detect if running in GitHub Actions and set async backend
  if (Sys.getenv("GITHUB_ACTIONS") == "true") {
    options(rdesk.ci_mode    = TRUE)
    options(rdesk.async_backend = "callr")  # mirai daemons fail in CI headless
  } else {
    # Default to mirai if available, fallback to callr
    backend <- if (requireNamespace("mirai", quietly = TRUE)) "mirai" else "callr"
    options(rdesk.async_backend = backend)
  }

  # Ensure clean job registry on load to prevent stale state across sessions
  rm(list = ls(envir = .rdesk_jobs), envir = .rdesk_jobs)
  rm(list = ls(envir = .rdesk_apps), envir = .rdesk_apps)
}

.onAttach <- function(libname, pkgname) {
  # Platform Guard: Provide a clear message on non-Windows platforms
  if (.Platform$OS.type != "windows") {
    packageStartupMessage(
      "[RDesk] RDesk requires Windows 10 or later.\n",
      "  macOS and Linux support is planned for v2.0.\n",
      "  See: https://github.com/Janakiraman-311/RDesk"
    )
  }

  packageStartupMessage(
    "[RDesk] v", utils::packageVersion("RDesk"), " ready."
  )
  
  # Check for launcher presence
  # Note: rdesk_launcher_path() would stop() here, so we use file.exists manually
  path <- system.file("bin", "rdesk-launcher.exe", package = "RDesk")
  if (path == "" || !file.exists(path)) {
     packageStartupMessage(
       "\n[WARNING] Native launcher binary not found in the installed package library.\n",
       "Tip: If you installed RDesk from source, ensure you have Rtools installed and\n",
       "run `devtools::install(pkg = '.', upgrade = FALSE, quick = TRUE)` to build it."
     )
  }
}

# R/zzz.R
# Package initialization logic

.onLoad <- function(libname, pkgname) {
  # Set default IPC version for the contract
  options(rdesk.ipc_version = "1.0")

  # CI Guard: Detect if running in GitHub Actions to skip windowed operations
  if (Sys.getenv("GITHUB_ACTIONS") == "true") {
     options(rdesk.ci_mode = TRUE)
  }
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "[RDesk] v", utils::packageVersion("RDesk"),
    " ready. Build apps with RDesk::build_app()"
  )
}

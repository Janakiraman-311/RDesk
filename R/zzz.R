# R/zzz.R
# Package initialization logic

.onLoad <- function(libname, pkgname) {
  # Set default IPC version for the contract
  options(rdesk.ipc_version = "1.0")

  # CI Guard: Detect if running in GitHub Actions to skip windowed operations
  if (Sys.getenv("GITHUB_ACTIONS") == "true") {
     options(rdesk.ci_mode = TRUE)
  }

  # Hard reset all registries to prevent stale state across sessions
  if (exists(".rdesk_jobs")) rm(list = ls(envir = .rdesk_jobs), envir = .rdesk_jobs)
  if (exists(".rdesk_apps")) rm(list = ls(envir = .rdesk_apps), envir = .rdesk_apps)
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "[RDesk] v", utils::packageVersion("RDesk"),
    " ready. Build apps with RDesk::build_app()"
  )
}

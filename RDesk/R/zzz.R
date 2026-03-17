# R/zzz.R
# Package initialization logic

.onLoad <- function(libname, pkgname) {
  # Set default IPC version for the contract
  options(rdesk.ipc_version = "1.0")
}

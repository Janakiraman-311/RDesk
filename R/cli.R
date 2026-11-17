#' Check RDesk environment and toolchain readiness
#'
#' @description
#' Reports the current R version, RDesk package version, native launcher
#' binary location, WebView2 Runtime availability (on Windows), C++ compiler
#' (`g++`), Inno Setup (`ISCC.exe`), and 7-Zip (`7z.exe`).
#'
#' @return A named list of detected paths and status values (invisibly).
#' @examples
#' info <- rdesk_sitrep()
#' str(info)
#' @export
rdesk_sitrep <- function() {
  or_empty <- function(x) {
    if (is.null(x) || length(x) == 0 || is.na(x[1])) {
      ""
    } else {
      as.character(x[1])
    }
  }

  launcher <- tryCatch(rdesk_launcher_path(), error = function(e) "")
  gpp      <- tryCatch(rdesk_find_gpp(), error = function(e) "")
  iscc     <- if (.Platform$OS.type == "windows") or_empty(rdesk_find_iscc()) else ""
  szip     <- if (.Platform$OS.type == "windows") or_empty(rdesk_find_7zip()) else ""

  wv2_ver <- ""
  if (.Platform$OS.type == "windows") {
    wv2_keys <- c(
      "SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}",
      "SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    )
    for (hive in c("HLM", "HCU")) {
      for (subkey in wv2_keys) {
        reg <- tryCatch(
          utils::readRegistry(subkey, hive = hive, view = "default"),
          error = function(e) NULL
        )
        if (!is.null(reg) && !is.null(reg$pv) && nzchar(reg$pv)) {
          wv2_ver <- as.character(reg$pv)
          break
        }
      }
      if (nzchar(wv2_ver)) break
    }
  }

  info <- list(
    r_version     = paste0(R.version$major, ".", R.version$minor),
    platform      = Sys.info()[["sysname"]],
    rdesk_version = as.character(utils::packageVersion("RDesk")),
    launcher_path = launcher,
    webview2      = wv2_ver,
    gpp_path      = gpp,
    iscc_path     = iscc,
    sevenzip_path = szip
  )

  fmt <- function(val) {
    if (nzchar(val)) val else "not found"
  }
  message(
    "[RDesk sitrep] R: ", info$r_version,
    " (", info$platform, ") | RDesk: ", info$rdesk_version
  )
  message("  Launcher : ", fmt(info$launcher_path))
  if (.Platform$OS.type == "windows") {
    message("  WebView2 : ", fmt(info$webview2))
    message("  g++      : ", fmt(info$gpp_path))
    message("  ISCC.exe : ", fmt(info$iscc_path))
    message("  7-Zip    : ", fmt(info$sevenzip_path))
  }

  invisible(info)
}

#' Install RDesk command-line launchers via 'Rapp'
#'
#' @description
#' Installs the shell launcher for RDesk's command-line interface (`rdesk`, with
#' subcommands `rdesk new`, `rdesk build`, and `rdesk sitrep`) onto your system
#' PATH using the `Rapp` package.
#'
#' @param destdir Optional destination directory passed to
#'   `Rapp::install_pkg_cli_apps()`.
#' @param ... Additional arguments passed to `Rapp::install_pkg_cli_apps()`.
#' @return The return value from `Rapp::install_pkg_cli_apps()`, invisibly.
#' @examples
#' if (interactive() && requireNamespace("Rapp", quietly = TRUE)) {
#'   install_rdesk_cli()
#' }
#' @export
install_rdesk_cli <- function(destdir = NULL, ...) {
  if (!requireNamespace("Rapp", quietly = TRUE)) {
    stop(
      "[RDesk] Package 'Rapp' is required to install CLI launchers. ",
      "Install it with: install.packages('Rapp')",
      call. = FALSE
    )
  }
  invisible(Rapp::install_pkg_cli_apps(package = "RDesk", destdir = destdir, ...))
}

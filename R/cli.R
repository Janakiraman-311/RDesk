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
#' subcommands `rdesk new`, `rdesk run`, `rdesk demo`, `rdesk build`, and
#' `rdesk sitrep`) onto your system PATH using the `Rapp` package.
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

#' Resolve an RDesk app directory or app.R path
#'
#' @param app_dir Path to an application directory or an `app.R` script.
#' @return A list with normalized `app_dir` and `app_script` paths.
#' @keywords internal
rdesk_resolve_app_script <- function(app_dir = ".") {
  if (!is.character(app_dir) || length(app_dir) != 1L || is.na(app_dir) || !nzchar(trimws(app_dir))) {
    stop("[RDesk] 'app_dir' must be a single non-empty path.", call. = FALSE)
  }

  target <- trimws(app_dir)
  if (!file.exists(target)) {
    stop("[RDesk] Application path not found: ", target, call. = FALSE)
  }

  if (dir.exists(target)) {
    dir_norm <- normalizePath(target, winslash = "/", mustWork = TRUE)
    script <- file.path(dir_norm, "app.R")
    if (!file.exists(script)) {
      stop("[RDesk] No app.R found in: ", dir_norm, call. = FALSE)
    }
    return(list(app_dir = dir_norm, app_script = script))
  }

  script_norm <- normalizePath(target, winslash = "/", mustWork = TRUE)
  list(app_dir = dirname(script_norm), app_script = script_norm)
}

#' Launch an RDesk desktop application
#'
#' @description
#' Launches an RDesk application directory (containing `app.R`) or an explicit
#' `app.R` script in a clean `Rscript` session. Also powers the `rdesk run`
#' command-line interface.
#'
#' @param app_dir Path to the application directory containing `app.R`, or a
#'   direct path to `app.R`. Defaults to the current working directory (`"."`).
#' @param debug Logical. If `TRUE`, sets `RDESK_DEBUG=1` for the launched app
#'   to enable webview developer tools and verbose IPC logging. Default `FALSE`.
#' @param detach Logical. If `TRUE`, starts the app in the background and
#'   returns the `processx::process` handle immediately without blocking.
#'   Default `FALSE`.
#' @return When `getOption("rdesk.ci_mode", FALSE)` is `TRUE`, returns a list
#'   with resolved launch metadata invisibly without opening a window.
#'   Otherwise returns the exit status integer (when `detach = FALSE`) or the
#'   `processx::process` object (when `detach = TRUE`), invisibly.
#' @examples
#' old <- options(rdesk.ci_mode = TRUE)
#' demo_dir <- system.file("apps", "mtcars_dashboard", package = "RDesk")
#' if (nzchar(demo_dir)) {
#'   rdesk_run(demo_dir)
#' }
#' options(old)
#' @export
rdesk_run <- function(app_dir = ".", debug = FALSE, detach = FALSE) {
  resolved <- rdesk_resolve_app_script(app_dir)
  debug <- isTRUE(debug)
  detach <- isTRUE(detach)

  if (isTRUE(getOption("rdesk.ci_mode", FALSE))) {
    message("[RDesk] CI Mode: Skipping launch of ", resolved$app_script)
    return(invisible(list(
      app_dir    = resolved$app_dir,
      app_script = resolved$app_script,
      debug      = debug,
      detach     = detach
    )))
  }

  rscript_bin <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  if (!file.exists(rscript_bin)) {
    stop("[RDesk] Rscript executable not found at: ", rscript_bin, call. = FALSE)
  }

  child_env <- Sys.getenv()
  child_env <- child_env[names(child_env) != "R_DEFAULT_PACKAGES"]
  if (debug) {
    child_env[["RDESK_DEBUG"]] <- "1"
  }

  if (detach) {
    proc <- processx::process$new(
      command                  = rscript_bin,
      args                     = c(resolved$app_script),
      wd                       = resolved$app_dir,
      env                      = child_env,
      cleanup                  = FALSE,
      windows_detached_process = (.Platform$OS.type == "windows")
    )
    message(
      "[RDesk] Launched ", basename(resolved$app_dir),
      " in background (PID: ", proc$get_pid(), ")."
    )
    return(invisible(proc))
  }

  res <- processx::run(
    command         = rscript_bin,
    args            = c(resolved$app_script),
    wd              = resolved$app_dir,
    env             = child_env,
    echo            = TRUE,
    error_on_status = FALSE
  )
  invisible(res$status)
}

#' Launch or list built-in RDesk showcase demo applications
#'
#' @description
#' Lists or launches the showcase desktop applications bundled with RDesk:
#' \describe{
#'   \item{cars}{`CarsAnalyser` — Automotive performance and regression telemetry workbench.}
#'   \item{studio}{`Data Intelligence Studio` — Clinical trial explorer and dataset profiling workbench.}
#'   \item{starter}{`RDeskStarterWorkbench` — Freshly scaffolded `rdesk_create_app()` starter workbench.}
#' }
#' Also powers the `rdesk demo` command-line interface.
#'
#' @param name Optional character string naming the demo to launch: `"cars"`,
#'   `"studio"`, or `"starter"`. When `NULL` (default), prints the catalog of
#'   available demos and returns it invisibly.
#' @param theme Theme used for the `"starter"` demo: `"light"`, `"dark"`, or
#'   `"system"`. Default `"dark"`.
#' @param debug Logical. If `TRUE`, sets `RDESK_DEBUG=1` to enable webview
#'   developer tools and verbose IPC logging. Default `FALSE`.
#' @param detach Logical. If `TRUE`, launches the demo in the background and
#'   returns immediately. Default `FALSE`.
#' @return When `name` is `NULL`, returns a `data.frame` describing the
#'   available demos invisibly. Otherwise returns the result of [rdesk_run()],
#'   invisibly.
#' @examples
#' demos <- rdesk_demo()
#' print(demos$name)
#' @export
rdesk_demo <- function(name = NULL, theme = "dark", debug = FALSE, detach = FALSE) {
  catalog <- data.frame(
    name        = c("cars", "studio", "starter"),
    title       = c(
      "CarsAnalyser (Automotive Performance & Regression Telemetry Workbench)",
      "Data Intelligence Studio (Clinical Trial Explorer & Dataset Profiler)",
      "RDeskStarterWorkbench (rdesk_create_app() Starter Template)"
    ),
    stringsAsFactors = FALSE
  )

  if (is.null(name) || length(name) == 0L || is.na(name[1]) || !nzchar(trimws(name[1]))) {
    message("[RDesk] Available built-in demos:")
    for (i in seq_len(nrow(catalog))) {
      message(sprintf("  %-8s - %s", catalog$name[i], catalog$title[i]))
    }
    message("Run a demo with: RDesk::rdesk_demo('cars')  or  rdesk demo cars")
    return(invisible(catalog))
  }

  key <- tolower(trimws(as.character(name[1])))
  canonical <- switch(
    key,
    cars             = "cars",
    mtcars           = "cars",
    mtcars_dashboard = "cars",
    studio           = "studio",
    data_studio      = "studio",
    starter          = "starter",
    skeleton         = "starter",
    template         = "starter",
    stop(
      "[RDesk] Unknown demo '", name[1], "'. Choose one of: ",
      paste(catalog$name, collapse = ", "), ".",
      call. = FALSE
    )
  )

  if (canonical == "starter") {
    valid_themes <- c("light", "dark", "system")
    theme <- tolower(trimws(as.character(theme[1])))
    if (!(theme %in% valid_themes)) {
      stop(
        "[RDesk] Invalid theme '", theme, "'. Choose one of: ",
        paste(valid_themes, collapse = ", "), ".",
        call. = FALSE
      )
    }
    demo_root <- if (isTRUE(detach) && !isTRUE(getOption("rdesk.ci_mode", FALSE))) {
      file.path(tools::R_user_dir("RDesk", which = "cache"), "demos", paste0("starter_", theme))
    } else {
      file.path(tempdir(), paste0("rdesk_demo_starter_", theme))
    }
    if (dir.exists(demo_root)) unlink(demo_root, recursive = TRUE)
    dir.create(demo_root, recursive = TRUE, showWarnings = FALSE)
    app_dir <- suppressMessages(
      rdesk_create_app(
        name  = "RDeskStarterWorkbench",
        path  = demo_root,
        theme = theme,
        open  = FALSE
      )
    )
  } else {
    sub_dir <- if (canonical == "cars") "mtcars_dashboard" else "data_studio"
    app_dir <- system.file("apps", sub_dir, package = "RDesk")
    if (!nzchar(app_dir) || !dir.exists(app_dir)) {
      stop("[RDesk] Built-in demo directory not found for '", canonical, "'.", call. = FALSE)
    }
  }

  rdesk_run(app_dir = app_dir, debug = debug, detach = detach)
}

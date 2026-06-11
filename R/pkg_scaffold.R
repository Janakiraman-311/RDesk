#' Create a new proprietary R package with Rcpp support
#'
#' Scaffolds a complete R package structure with C++ source files
#' ready for proprietary algorithm development. The package is
#' designed to be compiled and distributed without source code
#' using build_app(proprietary_packages = ...).
#'
#' @param name Package name. Must be a valid R package name.
#'   No dots, starts with a letter, letters/numbers/underscores only.
#' @param path Directory to create the package in. Default is
#'   the parent directory of the current working directory.
#' @param algorithm_name Name of the first algorithm file to scaffold.
#'   Default "core_algorithm".
#' @param licence One of "Proprietary", "MIT", "GPL-3". Default
#'   "Proprietary" for commercial packages.
#' @param open Logical. Open in RStudio after creation. Default FALSE.
#' @return Path to created package directory, invisibly.
#' @export
rdesk_new_pkg <- function(name,
                            path           = "..",
                            algorithm_name = "core_algorithm",
                            licence        = "Proprietary",
                            open           = FALSE) {

  # == Validation ========================================================
  if (missing(name) || !nzchar(trimws(name))) {
    stop("[RDesk] Package name required. Example: rdesk_new_pkg('MyAnalytics')")
  }
  name <- trimws(name)
  if (!grepl("^[A-Za-z][A-Za-z0-9_.]*$", name)) {
    stop("[RDesk] Invalid package name '", name, "'.\n",
         "Must start with a letter and contain only letters, ",
         "numbers, dots, and underscores.")
  }
  if (grepl("\\.", name)) {
    warning("[RDesk] Dots in package names can cause issues. ",
            "Consider using: ", gsub("\\.", "", name))
  }

  pkg_dir <- normalizePath(file.path(path, name), mustWork = FALSE)

  if (dir.exists(pkg_dir)) {
    stop("[RDesk] Directory already exists: ", pkg_dir,
         "\nDelete it or choose a different name.")
  }

  # == Check required tools ==============================================
  if (!requireNamespace("Rcpp", quietly = TRUE)) {
    stop("[RDesk] Rcpp is required. Install it with: install.packages('Rcpp')")
  }
  if (!requireNamespace("devtools", quietly = TRUE)) {
    stop("[RDesk] devtools is required. Install with: install.packages('devtools')")
  }

  message("[RDesk] Creating proprietary package: ", name)

  # == Directory structure ===============================================
  dirs <- c(
    pkg_dir,
    file.path(pkg_dir, "R"),
    file.path(pkg_dir, "src"),
    file.path(pkg_dir, "man"),
    file.path(pkg_dir, "tests", "testthat")
  )
  lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE)

  # == Template variables ================================================
  vars <- list(
    PKG_NAME       = name,
    ALGORITHM_NAME = algorithm_name,
    LICENCE        = licence,
    DATE           = format(Sys.Date(), "%Y-%m-%d"),
    AUTHOR         = Sys.info()["user"],
    R_VERSION      = paste0(R.version$major, ".", R.version$minor)
  )

  # == Write all files ===================================================
  rdesk_write_pkg_file("DESCRIPTION",        pkg_dir, vars)
  rdesk_write_pkg_file("NAMESPACE",          pkg_dir, vars)
  rdesk_write_pkg_file("R/wrappers.R",       pkg_dir, vars)
  rdesk_write_pkg_file("src/algorithm.cpp",  pkg_dir, vars,
                         dest_name = paste0("src/", algorithm_name, ".cpp"))
  rdesk_write_pkg_file("src/Makevars.win",   pkg_dir, vars)
  rdesk_write_pkg_file("src/Makevars",       pkg_dir, vars)
  rdesk_write_pkg_file("tests/testthat.R",   pkg_dir, vars)
  rdesk_write_pkg_file("tests/testthat/test-algorithm.R", pkg_dir, vars,
                         dest_name = paste0(
                           "tests/testthat/test-", algorithm_name, ".R"))
  rdesk_write_pkg_file(".gitignore",         pkg_dir, vars)

  # == Generate Rcpp bindings ============================================
  tryCatch({
    Rcpp::compileAttributes(pkg_dir)
    message("[RDesk]   Rcpp bindings generated")
  }, error = function(e) {
    message("[RDesk]   Note: Run Rcpp::compileAttributes('", name, "') ",
            "after editing src/", algorithm_name, ".cpp")
  })

  # == Success message ===================================================
  cat("\n[RDesk] Created:", pkg_dir, "\n")
  cat("[RDesk] Package structure:\n")
  cat("  ", name, "/\n")
  cat("  |-- DESCRIPTION         <- package metadata\n")
  cat("  |-- NAMESPACE            <- auto-managed by Rcpp\n")
  cat("  |-- R/\n")
  cat("  |   +-- wrappers.R      <- thin R wrappers (optional)\n")
  cat("  |-- src/\n")
  cat("  |   +-- ", algorithm_name, ".cpp  <- YOUR ALGORITHM GOES HERE\n",
      sep = "")
  cat("  +-- tests/\n")
  cat("      +-- testthat/       <- unit tests\n")
  cat("\n[RDesk] Next steps:\n")
  cat("  1. Write your algorithm in src/", algorithm_name, ".cpp\n", sep = "")
  cat("  2. Run Rcpp::compileAttributes('", pkg_dir, "') after changes\n",
      sep = "")
  cat("  3. Test locally: devtools::load_all('", pkg_dir, "')\n", sep = "")
  cat("  4. Bundle in your app:\n")
  cat("     RDesk::build_app(\n")
  cat("       app_dir              = 'YourApp',\n")
  cat("       proprietary_packages = '", pkg_dir, "'\n", sep = "")
  cat("     )\n\n")

  # == Open in RStudio ===================================================
  if (open && requireNamespace("rstudioapi", quietly = TRUE)) {
    if (rstudioapi::isAvailable()) {
      rstudioapi::openProject(pkg_dir, newSession = FALSE)
    }
  }

  invisible(pkg_dir)
}


# Internal — write a template file with variable substitution
# @keywords internal
rdesk_write_pkg_file <- function(template_name, pkg_dir,
                                  vars, dest_name = NULL) {
  template_dir <- system.file("templates/proprietary_pkg",
                               package = "RDesk")
  if (!nzchar(template_dir)) {
    template_dir <- file.path(find.package("RDesk"),
                              "inst", "templates", "proprietary_pkg")
  }

  template_path <- file.path(template_dir, template_name)
  if (!file.exists(template_path)) {
    warning("[RDesk] Template not found: ", template_name, " -- skipping")
    return(invisible(NULL))
  }

  content <- paste(readLines(template_path, warn = FALSE), collapse = "\n")

  for (nm in names(vars)) {
    val     <- as.character(vars[[nm]])
    content <- gsub(paste0("\\{\\{", nm, "\\}\\}"), val, content)
  }

  dest_file <- file.path(pkg_dir, if (!is.null(dest_name)) dest_name
                                   else template_name)
  dir.create(dirname(dest_file), recursive = TRUE, showWarnings = FALSE)
  writeLines(content, dest_file)
  invisible(dest_file)
}

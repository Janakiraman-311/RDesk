# R/build.R
# rdesk::build_app() — packages an RDesk app into a self-contained distributable

#' Build a self-contained distributable from an RDesk application
#'
#' @param app_dir Path to the app directory (must contain app.R and www/)
#' @param out_dir Output directory for the zip file (created if not exists)
#' @param app_name Name of the application (used for folder and exe names)
#' @param version Version string e.g. "1.0.0"
#' @param r_version R version to bundle e.g. "4.4.2". Defaults to current R version.
#' @param include_packages Character vector of extra CRAN packages to bundle.
#'   RDesk's own dependencies are always included automatically.
#' @param overwrite If TRUE, overwrite existing output. Default FALSE.
#' @return Path to the created zip file, invisibly.
#' @export
build_app <- function(app_dir,
                      out_dir  = "dist",
                      app_name = "MyRDeskApp",
                      version  = "1.0.0",
                      r_version = NULL,
                      include_packages = character(0),
                      overwrite = FALSE) {

  options(timeout = max(1200, getOption("timeout")))
  app_dir <- normalizePath(app_dir, mustWork = TRUE)

  # ── Validate inputs ────────────────────────────────────────────────────────
  if (!file.exists(file.path(app_dir, "app.R")))
    stop("[build_app] app_dir must contain app.R: ", app_dir)

  if (is.null(r_version))
    r_version <- "4.5.1" # Default to user's known version for consistency

  # ── Staging directory ──────────────────────────────────────────────────────
  dist_name  <- paste0(app_name, "-", version, "-windows")
  stage_root <- file.path(tempdir(), dist_name)
  if (dir.exists(stage_root)) unlink(stage_root, recursive = TRUE)
  dir.create(stage_root, recursive = TRUE)

  message("[RDesk] Building: ", dist_name)
  message("[RDesk] Staging in: ", stage_root)

  # ── Step 1: Copy app files ─────────────────────────────────────────────────
  message("[RDesk] Step 1/6 — copying app files...")
  app_stage <- file.path(stage_root, "app")
  dir.create(app_stage)
  rdesk_copy_dir(app_dir, app_stage)

  # ── Step 2: Copy RDesk binaries ────────────────────────────────────────────
  message("[RDesk] Step 2/6 — copying launcher binaries...")
  bin_src   <- system.file("bin", package = "RDesk")
  bin_stage <- file.path(stage_root, "bin")
  dir.create(bin_stage)
  rdesk_copy_dir(bin_src, bin_stage)

  # ── Step 3: Download and extract portable R ────────────────────────────────
  message("[RDesk] Step 3/6 — downloading portable R ", r_version, "...")
  runtime_dir <- file.path(stage_root, "runtime", "R")
  dir.create(runtime_dir, recursive = TRUE)
  rdesk_fetch_portable_r(r_version, runtime_dir)

  # ── Step 4: Bundle packages ────────────────────────────────────────────────
  message("[RDesk] Step 4/6 — bundling R packages...")
  pkg_lib <- file.path(stage_root, "packages", "library")
  dir.create(pkg_lib, recursive = TRUE)

  # Always include RDesk and its hard deps
  core_pkgs <- c("RDesk", "R6", "httpuv", "jsonlite",
                 "processx", "base64enc", "ggplot2", "dplyr")
  all_pkgs  <- unique(c(core_pkgs, include_packages))

  rdesk_install_packages_to(all_pkgs, pkg_lib, r_version)

  # CRITICAL: Install the local RDesk package properly so it's a "valid package"
  message("[RDesk]   Bundling local RDesk package...")
  rdesk_src <- getwd()
  # Build a binary version of RDesk for the current session's platform (Windows)
  # This ensures all Meta/ and other files are created correctly.
  rdesk_bin_zip <- devtools::build(path = rdesk_src, binary = TRUE)
  on.exit(unlink(rdesk_bin_zip), add = TRUE)
  
  # Use zip::unzip to bypass "in use" locks of install.packages()
  zip::unzip(rdesk_bin_zip, exdir = pkg_lib)
  
  # ── Step 5: Build the launcher stub ───────────────────────────────────────
  message("[RDesk] Step 5/6 — building launcher stub...")
  # In development, system.file might not work correctly if not installed
  stub_src <- system.file("stub", "stub.cpp", package = "RDesk")
  if (stub_src == "") {
    stub_src <- file.path(getwd(), "inst/stub/stub.cpp")
  }
  
  stub_exe <- file.path(stage_root, paste0(app_name, ".exe"))
  rdesk_build_stub(stub_src, stub_exe, app_name)

  # ── Step 6: Zip everything ─────────────────────────────────────────────────
  message("[RDesk] Step 6/6 — creating zip archive...")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  zip_path <- file.path(normalizePath(out_dir), paste0(dist_name, ".zip"))
  if (file.exists(zip_path)) {
    if (!overwrite) stop("[build_app] Output already exists: ", zip_path,
                         "\nUse overwrite=TRUE to replace.")
    file.remove(zip_path)
  }

  old_wd <- setwd(dirname(stage_root))
  on.exit(setwd(old_wd), add = TRUE)
  zip::zip(zip_path, files = basename(stage_root), recurse = TRUE)
  setwd(old_wd)

  size_mb <- round(file.info(zip_path)$size / 1024^2, 1)
  message("[RDesk] Done! ", zip_path, " (", size_mb, " MB)")
  message("[RDesk] Distribute this zip — no R installation needed on the target machine.")

  invisible(zip_path)
}

# ── Internal helpers ────────────────────────────────────────────────────────

#' @keywords internal
rdesk_copy_dir <- function(from, to) {
  files <- list.files(from, recursive = TRUE, full.names = TRUE)
  for (f in files) {
    rel  <- substring(f, nchar(from) + 2)
    dest <- file.path(to, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, dest, overwrite = TRUE)
  }
}

#' Download and extract a portable R installation
#' Uses the official CRAN Windows binary installer, extracted via 7-Zip
#' @keywords internal
rdesk_fetch_portable_r <- function(r_version, dest_dir) {
  # Use Cloud mirror for better reliability
  # Note: Latest version is in /base/, older versions move to /base/old/
  url <- paste0("https://cloud.r-project.org/bin/windows/base/R-", r_version, "-win.exe")
  
  tmp_exe  <- file.path(tempdir(), paste0("R-", r_version, "-win.exe"))

  if (!file.exists(tmp_exe)) {
    message("[RDesk]   Downloading R installer (~80MB)...")
    success <- tryCatch({
      utils::download.file(url, tmp_exe, mode = "wb", quiet = FALSE, method = "libcurl")
      TRUE
    }, error = function(e) {
      # Fallback to old/ directory if it's an older release
      url_alt <- paste0("https://cloud.r-project.org/bin/windows/base/old/", r_version, "/R-", r_version, "-win.exe")
      message("[RDesk]   Retrying from: ", url_alt)
      tryCatch({
        utils::download.file(url_alt, tmp_exe, mode = "wb", quiet = FALSE, method = "libcurl")
        TRUE
      }, error = function(e2) FALSE)
    })
    
    if (!success) stop("[build_app] Failed to download R installer from Cloud mirror (tried current and old).")
  } else {
    message("[RDesk]   Using cached R installer: ", tmp_exe)
  }

  sevenzip <- rdesk_find_7zip()

  message("[RDesk]   Installing R runtime (this takes ~60 seconds)...")
  tmp_extract <- file.path(tempdir(), paste0("R-", r_version, "-extract"))
  if (dir.exists(tmp_extract)) unlink(tmp_extract, recursive = TRUE)
  dir.create(tmp_extract, recursive = TRUE)

  # Run official installer in silent mode to "extract"
  # /SILENT : no UI
  # /DIR    : target directory
  # /COMPONENTS : minimum needed for Rscript to work
  install_cmd <- sprintf('"%s" /SILENT /DIR="%s" /COMPONENTS="main,x64"',
                         normalizePath(tmp_exe),
                         normalizePath(tmp_extract))
  
  message("[RDesk]   Running: ", install_cmd)
  ret <- system(install_cmd, wait = TRUE, show.output.on.console = FALSE)
  
  if (ret != 0) stop("[build_app] Silent installation of R failed.")

  rdesk_copy_dir(tmp_extract, dest_dir)
  message("[RDesk]   R runtime installed: ", dest_dir)
}

#' @keywords internal
rdesk_find_7zip <- function() {
  candidates <- c(
    Sys.which("7z"),
    Sys.which("7za"),
    "C:/Program Files/7-Zip/7z.exe",
    "C:/Program Files (x86)/7-Zip/7z.exe",
    file.path(Sys.getenv("RTOOLS45_HOME", "C:/rtools45"), "usr/lib/p7zip/7z.exe"),
    file.path(Sys.getenv("RTOOLS44_HOME", "C:/rtools44"), "usr/lib/p7zip/7z.exe"),
    file.path(Sys.getenv("RTOOLS45_HOME", "C:/rtools45"), "usr/bin/7z.exe"),
    file.path(Sys.getenv("RTOOLS44_HOME", "C:/rtools44"), "usr/bin/7z.exe")
  )
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  if (length(found) == 0)
    stop("[build_app] 7-Zip not found.\n",
         "Install from https://7-zip.org or add 7z.exe to PATH.\n",
         "On Rtools: pacman -S p7zip")
  found[1]
}

#' Convert a Windows path to MSYS2-style path for Rtools binaries
#' @keywords internal
rdesk_to_msys_path <- function(path) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  # Change "C:/foo" to "/c/foo"
  if (grepl("^[A-Za-z]:", path)) {
    drive <- tolower(substring(path, 1, 1))
    path  <- paste0("/", drive, substring(path, 3))
  }
  path
}

#' @keywords internal
rdesk_find_r_dir <- function(extracted_root) {
  all_rscripts <- list.files(extracted_root,
                              pattern     = "Rscript.exe",
                              recursive   = TRUE,
                              full.names  = TRUE)
  if (length(all_rscripts) == 0) return(NULL)
  r_root <- dirname(dirname(all_rscripts[1]))
  r_root
}

#' Install packages into a target library using the bundled R
#' Downloads binary .zip packages from CRAN and installs offline
#' @keywords internal
rdesk_install_packages_to <- function(pkgs, lib_dir, r_version) {
  minor <- paste(strsplit(r_version, "\\.")[[1]][1:2], collapse = ".")
  
  message("[RDesk]   Resolving package dependencies...")
  avail <- tryCatch(
    utils::available.packages(repos = "https://cloud.r-project.org",
                               type  = "win.binary",
                               filters = list()),
    error = function(e) {
      warning("[build_app] Could not fetch package list: ", e$message)
      NULL
    }
  )

  all_deps <- rdesk_resolve_deps(pkgs, avail)
  message("[RDesk]   Installing ", length(all_deps), " packages into bundle...")

  # Construct the exact URL for the target R version's binary repository
  # e.g. https://cloud.r-project.org/bin/windows/contrib/4.4/
  target_repos <- sprintf("https://cloud.r-project.org/bin/windows/contrib/%s", minor)

  utils::install.packages(
    all_deps,
    lib      = lib_dir,
    contriburl = target_repos,
    type     = "win.binary",
    quiet    = TRUE,
    dependencies = FALSE
  )

  installed <- list.dirs(lib_dir, recursive = FALSE, full.names = FALSE)
  message("[RDesk]   Installed: ", paste(installed, collapse = ", "))
}

#' Resolve package dependency tree (excluding base/recommended packages)
#' @keywords internal
rdesk_resolve_deps <- function(pkgs, avail) {
  base_pkgs <- rownames(utils::installed.packages(priority = c("base", "recommended")))
  resolved  <- character(0)
  queue     <- pkgs

  while (length(queue) > 0) {
    pkg   <- queue[1]
    queue <- queue[-1]
    if (pkg %in% resolved || pkg %in% base_pkgs || pkg == "RDesk") {
        if (pkg == "RDesk") resolved <- c(resolved, pkg) # Ensure RDesk is in the list
        next
    }
    resolved <- c(resolved, pkg)

    if (!is.null(avail) && pkg %in% rownames(avail)) {
      deps_str <- avail[pkg, "Imports"]
      if (!is.na(deps_str) && nchar(deps_str) > 0) {
        dep_names <- trimws(gsub("\\s*\\(.*?\\)", "",
                                  strsplit(deps_str, ",")[[1]]))
        dep_names <- dep_names[nchar(dep_names) > 0]
        new_deps  <- setdiff(dep_names, c(resolved, base_pkgs))
        queue     <- c(queue, new_deps)
      }
    }
  }
  resolved
}

#' Build the stub launcher exe using g++ from Rtools
#' @keywords internal
rdesk_build_stub <- function(stub_cpp, out_exe, app_name) {
  gpp <- rdesk_find_gpp()

  ret <- system2(gpp,
    args = c("-std=c++17", "-O2", "-mwindows",
             shQuote(stub_cpp),
             "-o", shQuote(out_exe),
             "-lstdc++fs"),
    stdout = FALSE, stderr = FALSE)

  if (ret != 0 || !file.exists(out_exe))
    stop("[build_app] Failed to compile launcher stub.\n",
         "Check that Rtools g++ is working: ", gpp)

  message("[RDesk]   Stub compiled: ", basename(out_exe))
}

#' @keywords internal
rdesk_find_gpp <- function() {
  candidates <- c(
    Sys.which("g++"),
    file.path(Sys.getenv("RTOOLS45_HOME", "C:/rtools45"), "x86_64-w64-mingw32.static.posix/bin/g++.exe"),
    file.path(Sys.getenv("RTOOLS44_HOME", "C:/rtools44"), "x86_64-w64-mingw32.static.posix/bin/g++.exe"),
    "C:/rtools45/mingw64/bin/g++.exe",
    "C:/rtools44/mingw64/bin/g++.exe"
  )
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  if (length(found) == 0)
    stop("[build_app] g++ not found. Install Rtools45 from https://cran.r-project.org/bin/windows/Rtools/")
  found[1]
}

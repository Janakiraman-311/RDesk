# R/build.R
# rdesk::build_app() - packages an RDesk app into a self-contained distributable

#' Build a self-contained distributable from an RDesk application
#'
#' @param app_dir Path to the app directory (must contain app.R and www/)
#' @param out_dir Output directory for the zip file (created if not exists)
#' @param app_name Name of the application. Defaults to name in DESCRIPTION or "MyRDeskApp".
#' @param version Version string. Defaults to version in DESCRIPTION or "1.0.0".
#' @param r_version R version to bundle e.g. "4.4.2". Defaults to current R version.
#' @param include_packages Character vector of extra CRAN packages to bundle.
#'   RDesk's own dependencies are always included automatically.
#' @param portable_r_method How to provision the bundled R runtime when
#'   `runtime_dir = "download"` is used explicitly. `"extract_only"` requires
#'   standalone 7-Zip and never launches the R installer. `"installer"` allows
#'   the legacy silent installer path explicitly.
#' @param runtime_dir Controls which R runtime is bundled with the app.
#'   \itemize{
#'     \item `NULL` (default) -- copies the developer's currently running R
#'       installation. Guarantees the bundled packages and the runtime are the
#'       same R version, eliminating renv version-mismatch crashes.
#'     \item A filesystem path -- copies that R installation root directly.
#'     \item `"download"` -- downloads a portable R installer from CRAN
#'       (legacy behaviour; requires network; risks version mismatch with renv).
#'   }
#' @param overwrite If TRUE, overwrite existing output. Default FALSE.
#' @param build_installer If TRUE, also build a Windows installer (.exe) using InnoSetup.
#' @param publisher Documentation for the application publisher (used in installer).
#' @param website URL for the application website (used in installer).
#' @param license_file Path to a license file (.txt or .rtf) to include in the installer.
#' @param icon_file Path to an .ico file for the installer and application shortcut.
#' @param prune_runtime If TRUE, remove unnecessary files (Tcl/Tk, docs, tests) from 
#'   the bundled R runtime to reduce size (~15-20MB saving). Default TRUE.
#' @param dry_run If TRUE, performs a quick validation of the app structure and 
#'   environment without performing the full build. Default FALSE.
#' @return Path to the created zip file, invisibly.
#' @examples
#' # Prepare an app directory (following scaffold example)
#' app_path <- file.path(tempdir(), "MyApp")
#' rdesk_create_app("MyApp", path = tempdir())
#' 
#' # Perform a dry-run build (fast, no external binaries downloaded)
#' build_app(app_path, out_dir = tempdir(), dry_run = TRUE)
#' 
#' # Clean up
#' unlink(app_path, recursive = TRUE)
#' @export
build_app <- function(app_dir = ".",
                      out_dir  = file.path(tempdir(), "dist"),
                      app_name = NULL,
                      version  = NULL,
                      r_version = NULL,
                      include_packages = character(0),
                      portable_r_method = c("extract_only", "installer"),
                      runtime_dir = NULL,
                      overwrite = FALSE,
                      build_installer = FALSE,
                      publisher = "RDesk User",
                      website   = "https://github.com/Janakiraman-311/RDesk",
                      license_file = NULL,
                      icon_file    = NULL,
                      prune_runtime = TRUE,
                      dry_run       = FALSE) {

  # Restore options on exit
  old_opts <- options(timeout = max(1200, getOption("timeout")))
  on.exit(options(old_opts), add = TRUE)
  portable_r_method <- match.arg(portable_r_method)
  app_dir <- normalizePath(app_dir, mustWork = TRUE)
  # Normalise runtime_dir:
  #   NULL      -> auto-detect (copy developer's R)
  #   "download" -> legacy download behaviour
  #   <path>    -> copy that path directly
  use_download <- identical(runtime_dir, "download")
  user_runtime_dir <- if (use_download || is.null(runtime_dir)) NULL else
    normalizePath(path.expand(runtime_dir), mustWork = TRUE)

  if (dry_run) {
    message("\n[RDesk] DRY RUN: Validating app structure...")
    if (!file.exists(file.path(app_dir, "app.R"))) stop("[dry_run] Missing app.R")
    if (!dir.exists(file.path(app_dir, "www"))) stop("[dry_run] Missing www/")
    message("[RDesk]   V Structure OK")
    
    # Check RTools
    rtools_path <- Sys.getenv("RTOOLS45_HOME", Sys.getenv("RTOOLS44_HOME", ""))
    if (nzchar(rtools_path)) {
      message("[RDesk]   V RTools found: ", rtools_path)
    } else {
      message("[RDesk]   ! RTools not found (Optional if using pre-built binaries)")
    }
    
    message("[RDesk] DRY RUN: All checks passed.")
    return(invisible(TRUE))
  }

  # Auto-detect metadata and dependencies from DESCRIPTION if possible
  desc_path <- file.path(app_dir, "DESCRIPTION")
  if (file.exists(desc_path)) {
    desc <- read.dcf(desc_path)
    if (is.null(app_name)) {
      if ("Package" %in% colnames(desc)) app_name <- as.character(desc[1, "Package"])
      else if ("AppName" %in% colnames(desc)) app_name <- as.character(desc[1, "AppName"])
    }
    if (is.null(version) && "Version" %in% colnames(desc)) {
      version <- as.character(desc[1, "Version"])
    }
    # Auto-detect package dependencies from DESCRIPTION
    detected_pkgs <- character(0)
    for (field in c("Depends", "Imports", "Suggests")) {
      if (field %in% colnames(desc)) {
        val <- as.character(desc[1, field])
        # Clean up version numbers, e.g. "haven (>= 2.0.0)"
        val_clean <- gsub("\\([^)]+\\)", "", val)
        pkgs <- trimws(unlist(strsplit(val_clean, ",")))
        pkgs <- pkgs[pkgs != "" & pkgs != "R" & pkgs != "RDesk"]
        detected_pkgs <- c(detected_pkgs, pkgs)
      }
    }
    include_packages <- unique(c(include_packages, detected_pkgs))
  }

  # Fallbacks
  if (is.null(app_name)) app_name <- "MyRDeskApp"
  if (is.null(version))  version  <- "1.0.0"

  # Route to macOS/Linux bundler on non-Windows platforms
  if (Sys.info()["sysname"] == "Darwin") {
    return(rdesk_build_macos_app(
      app_dir     = app_dir,
      app_name    = app_name,
      app_version = version,
      out_dir     = out_dir,
      sign        = TRUE
    ))
  } else if (.Platform$OS.type != "windows") {
    return(rdesk_build_linux_app(
      app_dir     = app_dir,
      app_name    = app_name,
      app_version = version,
      out_dir     = out_dir
    ))
  }

  # ---- Pre-flight Validation -----------------------------------------------
  rdesk_validate_build_inputs(
    app_dir = app_dir,
    extra_pkgs = include_packages,
    build_installer = build_installer,
    portable_r_method = portable_r_method,
    runtime_dir = user_runtime_dir,
    use_download = use_download
  )

  if (is.null(r_version))
    r_version <- paste0(R.version$major, ".", R.version$minor)

  # ---- Staging directory ----------------------------------------------------
  dist_name  <- paste0(app_name, "-", version, "-windows")
  stage_root <- file.path(tempdir(), dist_name)
  if (dir.exists(stage_root)) unlink(stage_root, recursive = TRUE)
  dir.create(stage_root, recursive = TRUE)
  on.exit(unlink(stage_root, recursive = TRUE, force = TRUE), add = TRUE)

  message("[RDesk] Building: ", dist_name)
  message("[RDesk] Staging in: ", stage_root)

  # ---- Step 1: Copy app files ----------------------------------------------
  message("[RDesk] Step 1/6 - copying app files...")
  app_stage <- file.path(stage_root, "app")
  dir.create(app_stage)
  rdesk_copy_dir(app_dir, app_stage, exclude = rdesk_app_exclusions())

  # ---- Step 2: Copy RDesk binaries -----------------------------------------
  message("[RDesk] Step 2/6 - copying launcher binaries...")
  bin_src   <- system.file("bin", package = "RDesk")
  if (bin_src == "" || !dir.exists(bin_src)) {
    bin_src <- rdesk_resolve_launcher_bin_dir(getwd())
  }
  if (!dir.exists(bin_src)) {
    stop("[build_app] Could not locate launcher binaries under installed package or source tree.")
  }
  bin_stage <- file.path(stage_root, "bin")
  dir.create(bin_stage)
  rdesk_copy_dir(bin_src, bin_stage)

  # ---- Step 3: Provision R runtime -----------------------------------------
  stage_runtime_dir <- file.path(stage_root, "runtime", "R")
  dir.create(stage_runtime_dir, recursive = TRUE)

  if (!is.null(user_runtime_dir)) {
    # Explicit path supplied by developer
    message("[RDesk] Step 3/6 - copying provided R runtime: ", user_runtime_dir)
    rdesk_copy_r_runtime(user_runtime_dir, stage_runtime_dir)
    if (prune_runtime) rdesk_prune_runtime(stage_runtime_dir)

  } else if (use_download) {
    # Explicit "download" sentinel - legacy behaviour
    message("[RDesk] Step 3/6 - downloading portable R ", r_version, " (legacy mode)...")
    message("[RDesk]   NOTE: Consider using the default (runtime_dir = NULL) to avoid")
    message("[RDesk]   version-mismatch crashes between the downloaded R and your renv packages.")
    r_version <- rdesk_fetch_portable_r(
      r_version = r_version,
      dest_dir  = stage_runtime_dir,
      prune     = prune_runtime,
      method    = portable_r_method
    )

  } else {
    # Default: copy the developer's own R installation
    r_home <- rdesk_detect_r_home()
    message("[RDesk] Step 3/6 - copying your R ", r_version, " installation as app runtime...")
    message("[RDesk]   This guarantees renv packages and the runtime are the same version.")
    rdesk_copy_r_runtime(r_home, stage_runtime_dir)
    if (prune_runtime) rdesk_prune_runtime(stage_runtime_dir)
  }

  # ---- Step 4: Bundle packages ---------------------------------------------
  message("[RDesk] Step 4/6 - bundling R packages...")
  pkg_lib <- file.path(stage_root, "packages", "library")
  dir.create(pkg_lib, recursive = TRUE)

  # Always include RDesk and its hard deps that might not be on CRAN
  core_pkgs <- c("RDesk", "R6", "jsonlite", "processx", "base64enc", 
                 "ggplot2", "dplyr", "digest", "zip", "callr", "httpuv", 
                 "mirai", "nanonext", "rcmdcheck", "renv", "rstudioapi")
  all_pkgs  <- unique(c(core_pkgs, include_packages))

  rdesk_install_packages_to(all_pkgs, pkg_lib, r_version)

  # Install RDesk separately from the local source tree or the installed package.
  message("[RDesk]   Bundling RDesk package...")
  rdesk_src <- normalizePath(getwd(), mustWork = FALSE)
  is_rdesk_source <- FALSE
  if (file.exists(file.path(rdesk_src, "DESCRIPTION"))) {
    desc_check <- read.dcf(file.path(rdesk_src, "DESCRIPTION"))
    if ("Package" %in% colnames(desc_check) && desc_check[1, "Package"] == "RDesk") {
      is_rdesk_source <- TRUE
    }
  }

  if (is_rdesk_source) {
    message("[RDesk]     Source tree detected.")
    # Build to binary zip to avoid 'in use' installation errors
    tmp_bin <- file.path(tempdir(), "RDesk_bundle.zip")
    suppressMessages(devtools::build(rdesk_src, binary = TRUE, path = tempdir(), quiet = TRUE))
    # devtools::build returns the path, but find it just in case
    zip_files <- list.files(tempdir(), pattern = "^RDesk_.*\\.zip$", full.names = TRUE)
    if (length(zip_files) > 0) {
      zip::unzip(zip_files[1], exdir = pkg_lib)
      file.remove(zip_files)
    } else {
      # Fallback to direct library copy if build fails
      installed_rdesk <- system.file(package = "RDesk")
      if (nzchar(installed_rdesk)) {
        rdesk_copy_dir(installed_rdesk, file.path(pkg_lib, "RDesk"))
      } else {
        stop("[build_app] Failed to build RDesk binary for bundling.")
      }
    }
  } else {
    installed_rdesk <- system.file(package = "RDesk")
    if (!nzchar(installed_rdesk)) {
      stop("[build_app] Could not locate the installed RDesk package to bundle.")
    }
    message("[RDesk]     Installed package detected.")
    rdesk_copy_dir(installed_rdesk, file.path(pkg_lib, "RDesk"))
  }

  # ---- Step 4b: Snapshot package versions into bundle ---------------------
  message("[RDesk] Step 4b/6 - snapshotting package versions...")
  rdesk_snapshot_bundle(pkg_lib, stage_root)
  
  # ---- Step 5: Build the launcher stub ------------------------------------
  message("[RDesk] Step 5/6 - building launcher stub...")
  # In development, system.file might not work correctly if not installed
  stub_src <- system.file("stub", "stub.cpp", package = "RDesk")
  if (stub_src == "") {
    stub_src <- file.path(getwd(), "inst/stub/stub.cpp")
  }
  
  stub_exe <- file.path(stage_root, paste0(app_name, ".exe"))
  rdesk_build_stub(stub_src, stub_exe, app_name)

  # ---- Step 6: Zip everything ----------------------------------------------
  message("[RDesk] Step 6/6 - creating zip archive...")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  zip_path <- file.path(normalizePath(out_dir), paste0(dist_name, ".zip"))
  if (file.exists(zip_path)) {
    if (!overwrite) stop("[build_app] Output already exists: ", zip_path,
                         "\nUse overwrite=TRUE to replace.")
    file.remove(zip_path)
  }

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(dirname(stage_root))
  zip::zip(zip_path, files = basename(stage_root), recurse = TRUE)

  size_mb <- round(file.info(zip_path)$size / 1024^2, 1)
  message("[RDesk] Done! ", zip_path, " (", size_mb, " MB)")

  # ---- Step 7: Build installer (Optional) ----------------------------------
  if (build_installer) {
    message("[RDesk] Step 7/7 - building Windows setup executable...")
    rdesk_build_installer(
      stage_root = stage_root,
      out_dir    = out_dir,
      app_name   = app_name,
      version    = version,
      publisher  = publisher,
      website    = website,
      license_file = license_file,
      icon_file    = icon_file
    )
  }

  message("[RDesk] Distribute the output - no R installation needed on the target machine.")

  invisible(zip_path)
}

#' Validate build inputs before starting the process
#' @keywords internal
#' @param app_dir Path to app directory.
#' @param extra_pkgs Character vector of packages.
#' @param build_installer Logical.
#' @param portable_r_method Method for R portability.
#' @param runtime_dir Path to pre-existing runtime.
rdesk_validate_build_inputs <- function(app_dir,
                                        extra_pkgs,
                                        build_installer = FALSE,
                                        portable_r_method = c("extract_only", "installer"),
                                        runtime_dir = NULL,
                                        use_download = FALSE) {
  portable_r_method <- match.arg(portable_r_method)
  message("[RDesk] Pre-flight validation...")

  # 1. Essential files
  if (!file.exists(file.path(app_dir, "app.R")))
    stop("[Validation Failed] app.R not found in: ", app_dir)
  if (!dir.exists(file.path(app_dir, "www")))
    stop("[Validation Failed] www/ directory not found in: ", app_dir)

  # 2. Package check
  core_pkgs <- c("R6", "jsonlite", "processx", "base64enc", "ggplot2", "dplyr", "zip")
  all_pkgs  <- unique(c(core_pkgs, extra_pkgs))
  missing   <- all_pkgs[!vapply(all_pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop("[Validation Failed] The following required packages are not available in your R library:\n",
         paste("  -", missing, collapse = "\n"),
         "\nPlease install them before building.")
  }

  # 3. Rtools check (needed for stub compilation)
  tryCatch(rdesk_find_gpp(), error = function(e) {
    stop("[Validation Failed] Rtools (g++) is required to build the launcher stub.\n",
         "Error: ", e$message)
  })

  # 3b. Runtime provisioning validation
  if (!is.null(runtime_dir)) {
    # Explicit path supplied - must contain bin/
    if (!dir.exists(file.path(runtime_dir, "bin"))) {
      stop("[Validation Failed] runtime_dir must point to an R installation root containing bin/.\n",
           "Provided path: ", runtime_dir)
    }
  } else if (use_download && portable_r_method == "extract_only") {
    # Download path requested - check for 7-Zip
    sevenzip <- rdesk_find_7zip()
    if (is.null(sevenzip)) {
      message("[RDesk]   Warning: Standalone 7-Zip not found.")
      message("[RDesk]   Switching to portable_r_method='installer' (no extra tools needed).")
      assign("portable_r_method", "installer", envir = parent.frame())
    }
  } else {
    # Default auto-detect path - validate R.home() is accessible
    r_home <- R.home()
    if (!dir.exists(file.path(r_home, "bin"))) {
      stop("[Validation Failed] Cannot locate your R installation at R.home(): ", r_home,
           "\nIf this is unexpected, supply runtime_dir = R.home() explicitly.")
    }
    message("[RDesk]   Runtime: your R ",
            paste0(R.version$major, ".", R.version$minor),
            " at ", r_home)
  }

  # 4. InnoSetup check
  if (build_installer) {
    iscc <- rdesk_find_iscc()
    if (is.null(iscc)) {
      stop("[Validation Failed] InnoSetup (ISCC.exe) not found.\n",
           "It is required to build the .exe installer.\n",
           "Download it from: https://jrsoftware.org/isdl.php")
    }
    message("[RDesk]   InnoSetup found: ", iscc)
  }

  message("[RDesk] Pre-flight check passed.")
}

# ---- Internal helpers --------------------------------------------------------

#' Auto-detect the current R installation root
#' @keywords internal
rdesk_detect_r_home <- function() {
  r_home    <- R.home()
  r_version <- paste0(R.version$major, ".", R.version$minor)
  if (!dir.exists(file.path(r_home, "bin"))) {
    stop("[RDesk] rdesk_detect_r_home: R.home() returned '" , r_home,
         "' but bin/ was not found there. Supply runtime_dir explicitly.")
  }
  message("[RDesk] Detected R ", r_version, " at: ", r_home)
  r_home
}

#' Copy an R installation into the bundle staging directory
#'
#' Copies `bin/`, `library/`, `etc/`, `modules/`, and `include/` from
#' \code{r_home} into \code{dest_dir}. Skips heavyweight directories
#' (Tcl/Tk, docs, tests) that are already pruned by \code{rdesk_prune_runtime()}.
#' @keywords internal
rdesk_copy_r_runtime <- function(r_home, dest_dir) {
  # ---- bin/ : copy only x64 executables, skip i386 -------------------------
  bin_src  <- file.path(r_home, "bin")
  bin_dest <- file.path(dest_dir, "bin")
  if (dir.exists(bin_src)) {
    message("[RDesk]   Copying bin/ (x64 only)")
    dir.create(bin_dest, recursive = TRUE, showWarnings = FALSE)
    # Copy top-level bin files (R.exe, Rscript.exe, etc.)
    top_files <- list.files(bin_src, full.names = TRUE, recursive = FALSE)
    top_files <- top_files[!file.info(top_files)$isdir]
    file.copy(top_files, bin_dest, overwrite = TRUE)
    # Copy only x64 subdirectory, not i386
    x64_src  <- file.path(bin_src, "x64")
    x64_dest <- file.path(bin_dest, "x64")
    if (dir.exists(x64_src)) {
      dir.create(x64_dest, recursive = TRUE, showWarnings = FALSE)
      file.copy(list.files(x64_src, full.names = TRUE), x64_dest, overwrite = TRUE)
    }
  }

  # ---- library/ : copy only base + recommended packages --------------------
  lib_src  <- file.path(r_home, "library")
  lib_dest <- file.path(dest_dir, "library")
  if (dir.exists(lib_src)) {
    message("[RDesk]   Copying library/ (base + recommended only)")
    dir.create(lib_dest, recursive = TRUE, showWarnings = FALSE)
    pkgs <- list.dirs(lib_src, recursive = FALSE, full.names = TRUE)
    for (p in pkgs) {
      desc_path <- file.path(p, "DESCRIPTION")
      keep <- FALSE
      if (file.exists(desc_path)) {
        d <- tryCatch(read.dcf(desc_path), error = function(e) NULL)
        if (!is.null(d) && "Priority" %in% colnames(d)) {
          priority <- trimws(as.character(d[1, "Priority"]))
          keep <- priority %in% c("base", "recommended")
        }
      }
      # Also keep 'translations' which has no Priority but ships with R
      if (!keep && basename(p) == "translations") keep <- TRUE
      if (keep) {
        file.copy(p, lib_dest, recursive = TRUE, overwrite = TRUE)
      }
    }
  }

  # ---- etc/, modules/, include/ : copy fully (small, essential) ------------
  for (d in c("etc", "modules", "include")) {
    src <- file.path(r_home, d)
    if (dir.exists(src)) {
      message("[RDesk]   Copying ", d, "/")
      file.copy(src, dest_dir, recursive = TRUE, overwrite = TRUE)
    }
  }

  invisible(dest_dir)
}

# Returns the list of top-level file/directory name patterns that must
# never be packaged into a bundled RDesk app. Each element is a regex
# matched against the top-level path component only (basename).
#
# Rationale for each entry:
#   .Rprofile    - would hijack R's libPaths at startup via renv/activate.R
#   .Renviron    - contains developer API keys / credentials
#   renv         - local sandbox metadata; bundled packages live in packages/
#   renv.lock    - dev lockfile; irrelevant inside the bundle
#   .git         - full VCS history; large and irrelevant
#   .gitignore   - VCS config
#   .gitattributes - VCS config
#   .Rproj.user  - RStudio user-state cache
#   .Rhistory    - console command history
#   .RData       - developer workspace snapshot
#   tests        - unit tests not needed at runtime
#   .DS_Store    - macOS finder metadata
#' @keywords internal
rdesk_app_exclusions <- function() {
  c(
    "^[.]Rprofile$",
    "^[.]Renviron$",
    "^renv$",
    "^renv[.]lock$",
    "^[.]git$",
    "^[.]gitignore$",
    "^[.]gitattributes$",
    "^[.]Rproj[.]user$",
    "^[.]Rhistory$",
    "^[.]RData$",
    "^tests$",
    "^[.]DS_Store$"
  )
}

# Copy a directory tree from `from` to `to`, optionally excluding
# top-level entries whose basenames match any regex in `exclude`.
#' @keywords internal
rdesk_copy_dir <- function(from, to, exclude = character(0)) {
  # Build a combined regex for the top-level exclusion list (if any)
  excl_re <- if (length(exclude)) paste(exclude, collapse = "|") else NULL

  # Helper: is this path (relative to `from`) excluded?
  is_excluded <- function(rel_path) {
    if (is.null(excl_re)) return(FALSE)
    # Match only the first path component (top-level name).
    # This ensures renv/activate.R is excluded via "^renv$" on "renv".
    top <- strsplit(rel_path, "[/\\\\]", perl = TRUE)[[1]][1]
    grepl(excl_re, top, perl = TRUE)
  }

  dirs <- list.dirs(from, recursive = TRUE, full.names = TRUE)
  for (d in dirs) {
    rel <- substring(d, nchar(from) + 2)
    if (nzchar(rel) && !is_excluded(rel)) {
      dir.create(file.path(to, rel), recursive = TRUE, showWarnings = FALSE)
    }
  }

  files <- list.files(from, recursive = TRUE, full.names = TRUE,
                      all.files = TRUE, no.. = TRUE)
  skipped <- character(0)
  for (f in files) {
    if (dir.exists(f)) next
    rel  <- substring(f, nchar(from) + 2)
    if (is_excluded(rel)) {
      skipped <- c(skipped, rel)
      next
    }
    dest <- file.path(to, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, dest, overwrite = TRUE)
  }

  if (length(skipped) > 0) {
    top_names <- unique(vapply(
      strsplit(skipped, "[/\\\\]", perl = TRUE),
      function(x) x[1],
      character(1)
    ))
    message("[RDesk]   Excluded ", length(skipped),
            " dev artifact(s) from bundle: ",
            paste(top_names, collapse = ", "))
  }
}

rdesk_fetch_portable_r <- function(r_version,
                                   dest_dir,
                                   prune = TRUE,
                                   method = c("extract_only", "installer")) {
  method <- match.arg(method)
  
  # Try primary first
  url_primary <- paste0("https://cloud.r-project.org/bin/windows/base/R-", r_version, "-win.exe")
  tmp_exe_primary <- file.path(tempdir(), paste0("R-", r_version, "-win.exe"))
  
  success <- FALSE
  actual_v <- r_version
  
  if (file.exists(tmp_exe_primary)) {
    success <- TRUE
    final_exe <- tmp_exe_primary
  } else {
    message("[RDesk]   Downloading R installer (~80MB)...")
    success <- tryCatch({
      suppressWarnings(utils::download.file(url_primary, tmp_exe_primary, mode = "wb", quiet = FALSE, method = "libcurl"))
      final_exe <- tmp_exe_primary
      TRUE
    }, error = function(e) { FALSE })
    
    if (!success && grepl("4.5", r_version)) {
      message("[RDesk]   R 4.5.x not found on mirror. Falling back to stable R 4.4.2...")
      actual_v <- "4.4.2"
      url_fallback <- "https://cloud.r-project.org/bin/windows/base/old/4.4.2/R-4.4.2-win.exe"
      tmp_exe_fallback <- file.path(tempdir(), "R-4.4.2-win.exe")
      
      if (file.exists(tmp_exe_fallback)) {
        final_exe <- tmp_exe_fallback
        success <- TRUE
      } else {
        success <- tryCatch({
          suppressWarnings(utils::download.file(url_fallback, tmp_exe_fallback, mode = "wb", quiet = FALSE, method = "libcurl"))
          final_exe <- tmp_exe_fallback
          TRUE
        }, error = function(e2) FALSE)
      }
    }
  }
  
  if (!success) stop("[build_app] Failed to download R installer (tried 4.5.x and 4.4.2).")
  
  message("[RDesk]   Preparing R runtime (", actual_v, ") (this takes ~60 seconds)...")
  tmp_extract <- file.path(tempdir(), paste0("R-", actual_v, "-extract"))
  if (dir.exists(tmp_extract)) unlink(tmp_extract, recursive = TRUE)
  dir.create(tmp_extract, recursive = TRUE)

  if (method == "extract_only") {
    sevenzip <- rdesk_find_7zip()
    ret <- system2(sevenzip, args = c("x", "-y", paste0("-o", normalizePath(tmp_extract, winslash = "\\")), normalizePath(final_exe, winslash = "\\")), stdout = FALSE, stderr = FALSE)
    if (!identical(ret, 0L)) stop("[build_app] Failed to extract the R installer with standalone 7-Zip.")
  } else {
    install_cmd <- sprintf('"%s" /SILENT /DIR="%s" /COMPONENTS="main,x64"', normalizePath(final_exe), normalizePath(tmp_extract))
    ret <- system(install_cmd, wait = TRUE, show.output.on.console = FALSE)
    if (!identical(ret, 0L)) stop("[build_app] Silent installation of R failed.")
  }

  r_root <- rdesk_find_r_dir(tmp_extract)
  if (is.null(r_root)) stop("[build_app] Could not locate the extracted R runtime.")
  rdesk_copy_dir(r_root, dest_dir)
  if (prune) rdesk_prune_runtime(dest_dir)
  
  return(actual_v)
}

rdesk_prune_runtime <- function(runtime_dir) {
  prune <- c("doc", "tests", "Tcl", "share/locale", "library/tcltk", "library/KernSmooth", "library/spatial")
  for (p in prune) {
    target <- file.path(runtime_dir, p)
    if (dir.exists(target)) unlink(target, recursive = TRUE)
  }
}

rdesk_find_7zip <- function() {
  candidates <- c(Sys.which("7z"), Sys.which("7za"), "C:/Program Files/7-Zip/7z.exe", "C:/Program Files (x86)/7-Zip/7z.exe")
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  found <- found[!grepl("rtools", found, ignore.case = TRUE)]
  if (length(found) == 0) return(NULL)
  found[1]
}

rdesk_find_r_dir <- function(extracted_root) {
  all_rscripts <- list.files(extracted_root, pattern = "Rscript.exe", recursive = TRUE, full.names = TRUE)
  if (length(all_rscripts) == 0) return(NULL)
  dirname(dirname(all_rscripts[1]))
}

rdesk_install_packages_to <- function(pkgs, lib_dir, r_version) {
  minor <- paste(strsplit(r_version, "\\.")[[1]][1:2], collapse = ".")
  
  # Determine package type and repository URL based on operating system
  if (.Platform$OS.type == "windows") {
    pkg_type <- "win.binary"
    target_repos <- sprintf("https://cloud.r-project.org/bin/windows/contrib/%s", minor)
  } else if (Sys.info()["sysname"] == "Darwin") {
    pkg_type <- "binary"
    target_repos <- NULL
  } else {
    pkg_type <- "source"
    target_repos <- NULL
  }

  if (is.null(target_repos)) {
    avail <- tryCatch(utils::available.packages(repos = "https://cloud.r-project.org", type = pkg_type, filters = list()), error = function(e) NULL)
  } else {
    avail <- tryCatch(utils::available.packages(contriburl = target_repos, type = pkg_type, filters = list()), error = function(e) NULL)
  }

  all_deps <- rdesk_resolve_deps(pkgs, avail)
  all_deps <- setdiff(all_deps, "RDesk")
  
  if (length(all_deps) > 0) {
    message("[RDesk]   Downloading ", length(all_deps), " packages...")
    if (is.null(target_repos)) {
      utils::install.packages(all_deps, lib = lib_dir, repos = "https://cloud.r-project.org", type = pkg_type, quiet = FALSE, dependencies = FALSE)
    } else {
      utils::install.packages(all_deps, lib = lib_dir, contriburl = target_repos, type = pkg_type, quiet = FALSE, dependencies = FALSE)
    }
  }

  # Final verification of bundled critical packages
  critical <- intersect(all_deps, c("callr", "mirai", "nanonext", "ggplot2", "processx"))
  found <- list.dirs(lib_dir, full.names = FALSE, recursive = FALSE)
  missing <- setdiff(critical, found)
  if (length(missing) > 0) {
    stop("[build_app] CRITICAL FAILURE: The following core dependencies failed to bundle:\n",
         paste("  -", missing, collapse = "\n"),
         "\nThis is likely due to a CRAN mirror issue or package availability for R ", r_version)
  }
}

rdesk_resolve_deps <- function(pkgs, avail) {
  base_pkgs <- c("base", "compiler", "datasets", "graphics", "grDevices", "grid", 
                 "methods", "parallel", "splines", "stats", "stats4", "tcltk", 
                 "tools", "utils", "MASS", "lattice", "boot", "class", "cluster", 
                 "codetools", "foreign", "KernSmooth", "mgcv", "nlme", "nnet", 
                 "rpart", "spatial", "survival")
  resolved  <- character(0)
  queue     <- pkgs
  while (length(queue) > 0) {
    pkg <- queue[1]; queue <- queue[-1]
    if (pkg %in% resolved || pkg %in% base_pkgs || pkg == "RDesk") next
    resolved <- c(resolved, pkg)
    if (!is.null(avail) && pkg %in% rownames(avail)) {
      # Check both Depends and Imports for binary transparency
      dep_fields <- avail[pkg, c("Depends", "Imports")]
      dep_fields <- dep_fields[!is.na(dep_fields) & nchar(dep_fields) > 0]
      deps_str <- paste(dep_fields, collapse = ", ")
      
      if (nchar(deps_str) > 0) {
        dep_names <- trimws(gsub("\\s*\\(.*?\\)", "", strsplit(deps_str, ",")[[1]]))
        # Filter out R itself from Depends
        dep_names <- dep_names[dep_names != "R"]
        queue <- c(queue, setdiff(dep_names[nchar(dep_names) > 0], c(resolved, base_pkgs)))
      }
    }
  }
  resolved
}

rdesk_build_stub <- function(stub_cpp, out_exe, app_name) {
  gpp <- rdesk_find_gpp()
  tmp_cpp <- file.path(tempdir(), paste0("stub_", digest::digest(app_name, algo="crc32"), ".cpp"))
  lines <- readLines(stub_cpp); lines <- gsub("{{APP_NAME}}", app_name, lines, fixed = TRUE); writeLines(lines, tmp_cpp)
  inc_path <- system.file("include", package = "RDesk")
  if (inc_path == "") inc_path <- file.path(getwd(), "inst/include")
  src_inc <- dirname(normalizePath(stub_cpp, mustWork = TRUE))
  sdk_inc <- file.path(src_inc, "webview2_sdk", "build", "native", "include")
  system2(gpp, args = c("-std=c++17", "-O2", "-mwindows", "-I", shQuote(inc_path), "-I", shQuote(src_inc), "-I", shQuote(sdk_inc), shQuote(tmp_cpp), "-o", shQuote(out_exe), "-lole32", "-lcomctl32", "-loleaut32", "-luuid", "-lshlwapi", "-lversion", "-lstdc++fs"))
}

rdesk_find_iscc <- function() {
  candidates <- c(Sys.which("ISCC"), file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Inno Setup 6", "ISCC.exe"), "C:/Program Files (x86)/Inno Setup 6/ISCC.exe")
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  if (length(found) == 0) return(NULL)
  found[1]
}

rdesk_build_installer <- function(stage_root, out_dir, app_name, version, publisher, website, license_file, icon_file) {
  template_path <- system.file("installer", "template.iss", package = "RDesk")
  if (template_path == "") template_path <- file.path(getwd(), "inst/installer/template.iss")
  iss_content <- readLines(template_path)
  iss_content <- gsub("{{AppName}}", app_name, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppVersion}}", version, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppPublisher}}", publisher, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppURL}}", website, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppExeName}}", paste0(app_name, ".exe"), iss_content, fixed = TRUE)
  iss_content <- gsub("{{SourceDir}}", normalizePath(stage_root), iss_content, fixed = TRUE)
  iss_content <- gsub("{{OutputDir}}", normalizePath(out_dir), iss_content, fixed = TRUE)
  iss_content <- gsub("{{SetupBaseName}}", paste0(app_name, "-", version, "-setup"), iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppID}}", sprintf("RDesk-App-%s", digest::digest(app_name, algo = "crc32")), iss_content, fixed = TRUE)
  license_path <- if (!is.null(license_file)) normalizePath(license_file) else ""
  iss_content <- gsub("{{LicenseFile}}", license_path, iss_content, fixed = TRUE)
  icon_path <- if (!is.null(icon_file)) normalizePath(icon_file) else ""
  iss_content <- gsub("{{AppIconFile}}", icon_path, iss_content, fixed = TRUE)
  iss_temp <- file.path(tempdir(), "installer.iss"); writeLines(iss_content, iss_temp)
  system2(rdesk_find_iscc(), args = c("/Q", shQuote(iss_temp)))
}

rdesk_find_gpp <- function() {
  candidates <- c(Sys.which("g++"), "C:/rtools45/mingw64/bin/g++.exe", "C:/rtools44/mingw64/bin/g++.exe")
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  if (length(found) == 0) stop("[build_app] g++ not found.")
  found[1]
}

#' Resolve a source-tree launcher binary directory
#' @keywords internal
rdesk_resolve_launcher_bin_dir <- function(project_root) {
  inst_bin <- file.path(project_root, "inst", "bin")
  if (dir.exists(inst_bin) && file.exists(file.path(inst_bin, "rdesk-launcher.exe"))) return(inst_bin)

  # Check src/ for source-built launcher
  src_bin <- file.path(project_root, "src")
  if (file.exists(file.path(src_bin, "rdesk-launcher.exe"))) {
    temp_bin <- file.path(tempdir(), "rdesk-launcher-bin")
    if (dir.exists(temp_bin)) unlink(temp_bin, recursive = TRUE)
    dir.create(temp_bin, recursive = TRUE)
    file.copy(file.path(src_bin, "rdesk-launcher.exe"), file.path(temp_bin, "rdesk-launcher.exe"))
    return(temp_bin)
  }
  ""
}

rdesk_snapshot_bundle <- function(lib_dir, stage_root) {
  if (!requireNamespace("renv", quietly = TRUE)) return(invisible(NULL))
  pkg_names <- list.dirs(lib_dir, full.names = FALSE, recursive = FALSE)
  if (length(pkg_names) == 0) return(invisible(NULL))
  
  lock_entries <- lapply(pkg_names, function(p_name) {
    ver <- as.character(utils::packageVersion(p_name, lib.loc = lib_dir))
    list(Package = p_name, Version = ver, Source = "Repository", Repository = "CRAN")
  })
  names(lock_entries) <- pkg_names
  lockfile <- list(R = list(Version = paste0(R.version$major, ".", R.version$minor), Repositories = list(list(Name = "CRAN", URL = "https://cloud.r-project.org"))), Packages = lock_entries)
  jsonlite::write_json(lockfile, file.path(stage_root, "renv.lock"), pretty = TRUE, auto_unbox = TRUE)
}

# ---- macOS Bundler and Helpers -----------------------------------------------

rdesk_build_macos_app <- function(app_dir, app_name,
                                  app_version = "1.0.0",
                                  out_dir     = tempdir(),
                                  sign        = TRUE) {

  bundle_name <- paste0(app_name, ".app")
  
  # Correction 4 - DMG staging directory: Route hdiutil through a space-free temp dir
  stage_parent <- file.path(tempdir(), "rdesk_staging")
  if (dir.exists(stage_parent)) unlink(stage_parent, recursive = TRUE)
  dir.create(stage_parent, recursive = TRUE)

  bundle_path <- file.path(stage_parent, bundle_name)
  contents    <- file.path(bundle_path, "Contents")

  message("[RDesk] Building macOS app bundle: ", bundle_name)

  # 1. Create directory structure
  dirs <- c(
    file.path(contents, "MacOS"),
    file.path(contents, "Resources", "app", "www"),
    file.path(contents, "Resources", "bin"),
    file.path(contents, "Resources", "packages", "library"),
    file.path(contents, "Resources", "R-runtime"),
    file.path(contents, "Frameworks")
  )
  lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE)

  # 2. Compile launcher stub on the fly and store at Contents/MacOS/{{APP_NAME}}
  # This acts as the CFBundleExecutable (Correction 2)
  stub_c_src <- system.file("stub", "stub_macos.c", package = "RDesk")
  if (stub_c_src == "") {
    stub_c_src <- file.path(getwd(), "inst", "stub", "stub_macos.c")
  }
  if (!file.exists(stub_c_src)) {
    stop("[build_app] Could not locate macOS stub C source file.")
  }

  tmp_c <- file.path(tempdir(), paste0("stub_", digest::digest(app_name, algo="crc32"), ".c"))
  lines <- readLines(stub_c_src)
  lines <- gsub("{{APP_NAME}}", app_name, lines, fixed = TRUE)
  writeLines(lines, tmp_c)

  stub_dst <- file.path(contents, "MacOS", app_name)
  message("[RDesk] Compiling stub binary on the fly...")
  # Compile as universal stub binary
  ret <- system2("clang", c("-arch", "arm64", "-arch", "x86_64", shQuote(tmp_c), "-o", shQuote(stub_dst)))
  if (ret != 0) {
    message("[RDesk]   Universal stub compilation failed. Falling back to native architecture compilation...")
    ret <- system2("clang", c(shQuote(tmp_c), "-o", shQuote(stub_dst)))
    if (ret != 0) {
      stop("[build_app] Failed to compile macOS launcher stub.")
    }
  }
  Sys.chmod(stub_dst, "0755")
  file.remove(tmp_c)

  # 3. Copy launcher to Resources/bin/ (Correction 2)
  launcher_src <- rdesk_launcher_path()
  launcher_dst <- file.path(contents, "Resources", "bin", "rdesk-launcher")
  file.copy(launcher_src, launcher_dst)
  Sys.chmod(launcher_dst, "0755")

  # 4. Copy app code
  message("[RDesk] Copying app files...")
  rdesk_copy_dir(app_dir, file.path(contents, "Resources", "app"), exclude = rdesk_app_exclusions())

  # 5. Copy R runtime (from developer's installation)
  message("[RDesk] Copying R runtime...")
  r_home     <- R.home()
  r_dst      <- file.path(contents, "Resources", "R-runtime", "R")
  dir.create(r_dst, recursive = TRUE)
  for (d in c("bin", "lib", "library", "etc", "share", "modules")) {
    src <- file.path(r_home, d)
    if (dir.exists(src)) file.copy(src, r_dst, recursive = TRUE)
  }

  # 6. Bundle packages
  message("[RDesk] Bundling packages...")
  pkg_dst <- file.path(contents, "Resources", "packages", "library")
  
  core_pkgs <- c("RDesk", "R6", "jsonlite", "processx", "base64enc", 
                 "ggplot2", "dplyr", "digest", "zip", "callr", "httpuv", 
                 "mirai", "nanonext", "rcmdcheck", "renv", "rstudioapi")
  
  desc_path <- file.path(app_dir, "DESCRIPTION")
  extra_pkgs <- character(0)
  if (file.exists(desc_path)) {
    desc <- read.dcf(desc_path)
    for (field in c("Depends", "Imports", "Suggests")) {
      if (field %in% colnames(desc)) {
        val <- as.character(desc[1, field])
        val_clean <- gsub("\\([^)]+\\)", "", val)
        pkgs <- trimws(unlist(strsplit(val_clean, ",")))
        pkgs <- pkgs[pkgs != "" & pkgs != "R" & pkgs != "RDesk"]
        extra_pkgs <- c(extra_pkgs, pkgs)
      }
    }
  }
  all_pkgs <- unique(c(core_pkgs, extra_pkgs))
  rdesk_install_packages_to(all_pkgs, pkg_dst, paste0(R.version$major, ".", R.version$minor))

  # Copy RDesk package directory directly to pkg_dst
  installed_rdesk <- system.file(package = "RDesk")
  if (nzchar(installed_rdesk)) {
    rdesk_copy_dir(installed_rdesk, file.path(pkg_dst, "RDesk"))
  }

  # 7. Fix dynamic library paths (otool and install_name_tool)
  rdesk_fix_macos_rpaths(bundle_path)

  # 8. Generate Info.plist
  rdesk_write_info_plist(contents, app_name, app_version)

  # 9. Write PkgInfo
  writeLines("APPL????", file.path(contents, "PkgInfo"))

  # 10. Copy icon if exists
  icon_src <- file.path(app_dir, "inst", "assets", "AppIcon.icns")
  if (file.exists(icon_src)) {
    file.copy(icon_src, file.path(contents, "Resources", "AppIcon.icns"))
  } else {
    alt_icon <- file.path(app_dir, "AppIcon.icns")
    if (file.exists(alt_icon)) {
      file.copy(alt_icon, file.path(contents, "Resources", "AppIcon.icns"))
    }
  }

  # 11. Ad-hoc code sign
  if (sign) rdesk_sign_macos_app(bundle_path)

  # 12. Create DMG
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  dmg_path <- file.path(normalizePath(out_dir), paste0(app_name, "-", app_version, ".dmg"))
  if (file.exists(dmg_path)) file.remove(dmg_path)

  message("[RDesk] Packaging DMG...")
  system2("hdiutil", c(
    "create", "-volname", shQuote(app_name),
    "-srcfolder", shQuote(bundle_path),
    "-ov", "-format", "UDZO",
    shQuote(dmg_path)
  ))

  # Copy the .app bundle to out_dir
  out_bundle_path <- file.path(normalizePath(out_dir), bundle_name)
  if (dir.exists(out_bundle_path)) unlink(out_bundle_path, recursive = TRUE)
  if (Sys.info()["sysname"] == "Darwin") {
    system2("cp", c("-R", shQuote(bundle_path), shQuote(out_dir)))
  } else {
    file.rename(bundle_path, out_bundle_path)
  }

  # Clean up staging area
  unlink(stage_parent, recursive = TRUE)

  message("[RDesk] macOS bundle output directory: ", out_dir)
  message("[RDesk] Done! DMG built at: ", dmg_path)
  invisible(list(bundle = file.path(out_dir, bundle_name), dmg = dmg_path))
}

rdesk_fix_macos_rpaths <- function(app_bundle_path) {
  if (.Platform$OS.type != "unix" || Sys.info()["sysname"] != "Darwin") return(invisible(NULL))

  message("[RDesk] Fixing macOS dynamic library paths...")

  libs <- c(
    list.files(app_bundle_path, pattern = "\\.so$", recursive = TRUE, full.names = TRUE),
    list.files(app_bundle_path, pattern = "\\.dylib$", recursive = TRUE, full.names = TRUE)
  )

  for (lib in libs) {
    result <- system2("otool", c("-L", shQuote(lib)), stdout = TRUE, stderr = FALSE)
    has_absolute <- any(grepl("^\\s+/", result) & !grepl("@", result))

    if (has_absolute) {
      system2("install_name_tool",
              c("-add_rpath", "@loader_path/../../../R-runtime/lib", shQuote(lib)),
              stdout = FALSE, stderr = FALSE)
    }
  }

  # Also add rpath to launcher
  launcher_path <- file.path(app_bundle_path, "Contents", "Resources", "bin", "rdesk-launcher")
  if (file.exists(launcher_path)) {
    system2("install_name_tool",
            c("-add_rpath", "@executable_path/../Resources/R-runtime/lib", shQuote(launcher_path)),
            stdout = FALSE, stderr = FALSE)
  }

  message("[RDesk]   Patched ", length(libs), " shared libraries")
  invisible(libs)
}

rdesk_sign_macos_app <- function(app_bundle, identity = "-") {
  if (Sys.info()["sysname"] != "Darwin") return(invisible(NULL))

  result <- system2(
    "codesign",
    c("--force", "--deep", "--sign", shQuote(identity), shQuote(app_bundle)),
    stdout = TRUE, stderr = TRUE
  )
  message("[RDesk] Code signed bundle: ", app_bundle)
  invisible(result)
}

rdesk_write_info_plist <- function(contents_dir, app_name, app_version) {
  plist_path <- file.path(contents_dir, "Info.plist")
  app_name_lower <- tolower(gsub("[^[:alnum:]]+", "", app_name))
  
  plist_content <- c(
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
    '<plist version="1.0">',
    '<dict>',
    '  <key>CFBundleName</key>',
    sprintf('  <string>%s</string>', app_name),
    '  <key>CFBundleDisplayName</key>',
    sprintf('  <string>%s</string>', app_name),
    '  <key>CFBundleIdentifier</key>',
    sprintf('  <string>com.rdesk.%s</string>', app_name_lower),
    '  <key>CFBundleVersion</key>',
    sprintf('  <string>%s</string>', app_version),
    '  <key>CFBundleShortVersionString</key>',
    sprintf('  <string>%s</string>', app_version),
    '  <key>CFBundleExecutable</key>',
    sprintf('  <string>%s</string>', app_name),
    '  <key>CFBundleIconFile</key>',
    '  <string>AppIcon</string>',
    '  <key>CFBundlePackageType</key>',
    '  <string>APPL</string>',
    '  <key>LSMinimumSystemVersion</key>',
    '  <string>12.0</string>',
    '  <key>NSHighResolutionCapable</key>',
    '  <true/>',
    '  <key>NSHumanReadableCopyright</key>',
    '  <string>Built with RDesk</string>',
    '  <key>com.apple.security.cs.allow-jit</key>',
    '  <true/>',
    '  <key>com.apple.security.files.user-selected.read-write</key>',
    '  <true/>',
    '</dict>',
    '</plist>'
  )
  
  writeLines(plist_content, plist_path)
}

#' Build a Linux application bundle
#' @keywords internal
rdesk_build_linux_app <- function(app_dir, app_name,
                                  app_version = "1.0.0",
                                  out_dir     = tempdir()) {

  dist_name <- paste0(app_name, "-", app_version)
  
  stage_parent <- file.path(tempdir(), "rdesk_staging_linux")
  if (dir.exists(stage_parent)) unlink(stage_parent, recursive = TRUE)
  dir.create(stage_parent, recursive = TRUE)

  stage_root <- file.path(stage_parent, dist_name)
  dir.create(stage_root, recursive = TRUE)

  message("[RDesk] Building Linux app bundle: ", dist_name)

  # 1. Create directory structure
  dirs <- c(
    file.path(stage_root, "app", "www"),
    file.path(stage_root, "packages", "library")
  )
  lapply(dirs, dir.create, recursive = TRUE, showWarnings = FALSE)

  # 2. Copy launcher binary
  launcher_src <- rdesk_launcher_path()
  launcher_dst <- file.path(stage_root, "rdesk-launcher")
  file.copy(launcher_src, launcher_dst)
  Sys.chmod(launcher_dst, "0755")

  # 3. Copy app files
  message("[RDesk] Copying app files...")
  rdesk_copy_dir(app_dir, file.path(stage_root, "app"), exclude = rdesk_app_exclusions())

  # 4. Bundle packages
  message("[RDesk] Bundling packages...")
  pkg_dst <- file.path(stage_root, "packages", "library")
  
  core_pkgs <- c("RDesk", "R6", "jsonlite", "processx", "base64enc", 
                 "ggplot2", "dplyr", "digest", "zip", "callr", "httpuv", 
                 "mirai", "nanonext", "rcmdcheck", "renv", "rstudioapi")
  
  desc_path <- file.path(app_dir, "DESCRIPTION")
  extra_pkgs <- character(0)
  if (file.exists(desc_path)) {
    desc <- read.dcf(desc_path)
    for (field in c("Depends", "Imports", "Suggests")) {
      if (field %in% colnames(desc)) {
        val <- as.character(desc[1, field])
        val_clean <- gsub("\\([^)]+\\)", "", val)
        pkgs <- trimws(unlist(strsplit(val_clean, ",")))
        pkgs <- pkgs[pkgs != "" & pkgs != "R" & pkgs != "RDesk"]
        extra_pkgs <- c(extra_pkgs, pkgs)
      }
    }
  }
  all_pkgs <- unique(c(core_pkgs, extra_pkgs))
  rdesk_install_packages_to(all_pkgs, pkg_dst, paste0(R.version$major, ".", R.version$minor))

  # Copy RDesk package directory directly to pkg_dst
  installed_rdesk <- system.file(package = "RDesk")
  if (nzchar(installed_rdesk)) {
    rdesk_copy_dir(installed_rdesk, file.path(pkg_dst, "RDesk"))
  }

  # 5. Generate run.sh startup script
  run_sh_path <- file.path(stage_root, "run.sh")
  run_sh_content <- c(
    "#!/usr/bin/env bash",
    "# ============================================================================",
    sprintf("# RDesk Application Startup Script: %s", app_name),
    "# ============================================================================",
    "",
    "# Find script directory",
    "DIR=\"$( cd \"$( dirname \"${BASH_SOURCE[0]}\" )\" && pwd )\"",
    "",
    "# Check if R is installed",
    "if ! command -v Rscript &> /dev/null; then",
    "    echo \"ERROR: Rscript is not installed or not in your PATH. Please install R to run this application.\"",
    "    exit 1",
    "fi",
    "",
    "# Configure environment for portable/bundled package dependencies",
    "export R_LIBS_USER=\"$DIR/packages/library\"",
    sprintf("export R_APP_NAME=\"%s\"", app_name),
    "export R_BUNDLE_APP=\"1\"",
    "",
    "# Launch binary using system R context",
    "message=\"[RDesk] Launching application...\"",
    "echo \"$message\"",
    sprintf("exec \"$DIR/rdesk-launcher\" \"rdesk://app/index.html\" \"%s\" \"1200\" \"800\" \"$DIR/app/www\" \"$$\"", app_name),
    ""
  )
  writeLines(run_sh_content, run_sh_path)
  Sys.chmod(run_sh_path, "0755")

  # 6. Create tarball (.tar.gz)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  tar_path <- file.path(normalizePath(out_dir), paste0(dist_name, ".tar.gz"))
  if (file.exists(tar_path)) file.remove(tar_path)

  message("[RDesk] Packaging tarball...")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(stage_parent)
  
  # Standard POSIX tar
  ret <- system2("tar", c("-czf", shQuote(tar_path), shQuote(dist_name)))
  if (ret != 0) {
    # Try using R internal tar
    utils::tar(tar_path, files = dist_name, compression = "gzip")
  }

  # Clean up staging area
  setwd(old_wd)
  unlink(stage_parent, recursive = TRUE)

  message("[RDesk] Linux bundle output directory: ", out_dir)
  message("[RDesk] Done! Tarball built at: ", tar_path)
  invisible(list(bundle = file.path(out_dir, dist_name), tarball = tar_path))
}

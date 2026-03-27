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
#'   `runtime_dir` is not supplied. `"extract_only"` requires standalone 7-Zip
#'   and never launches the R installer. `"installer"` allows the legacy silent
#'   installer path explicitly.
#' @param runtime_dir Optional path to an existing portable R runtime root
#'   containing `bin/`. When supplied, RDesk copies this runtime directly and
#'   skips the download/extract step.
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
  user_runtime_dir <- runtime_dir
  if (!is.null(user_runtime_dir)) {
    user_runtime_dir <- normalizePath(path.expand(user_runtime_dir), mustWork = TRUE)
  }

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

  # Auto-detect metadata from DESCRIPTION if possible
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
  }

  # Fallbacks
  if (is.null(app_name)) app_name <- "MyRDeskApp"
  if (is.null(version))  version  <- "1.0.0"

  # ---- Pre-flight Validation -----------------------------------------------
  rdesk_validate_build_inputs(
    app_dir = app_dir,
    extra_pkgs = include_packages,
    build_installer = build_installer,
    portable_r_method = portable_r_method,
    runtime_dir = user_runtime_dir
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
  rdesk_copy_dir(app_dir, app_stage)

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

  # ---- Step 3: Download and extract portable R -----------------------------
  stage_runtime_dir <- file.path(stage_root, "runtime", "R")
  dir.create(stage_runtime_dir, recursive = TRUE)
  actual_r_version <- r_version
  
  if (!is.null(user_runtime_dir)) {
    message("[RDesk] Step 3/6 - copying provided portable R runtime...")
    rdesk_copy_dir(user_runtime_dir, stage_runtime_dir)
    if (prune_runtime) {
      rdesk_prune_runtime(stage_runtime_dir)
    }
  } else {
    message("[RDesk] Step 3/6 - provisioning portable R ", r_version, "...")
    actual_r_version <- rdesk_fetch_portable_r(
      r_version = r_version,
      dest_dir = stage_runtime_dir,
      prune = prune_runtime,
      method = portable_r_method
    )
  }
  
  # Update r_version to the one actually provisioned
  r_version <- actual_r_version

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
                                        runtime_dir = NULL) {
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
  
  missing <- all_pkgs[!vapply(all_pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing) > 0) {
    stop("[Validation Failed] The following required packages are not available in your R library:\n",
         paste("  -", missing, collapse = "\n"),
         "\nPlease install them before building.")
  }

  # 3. Rtools check (needed for stub compilation)
  tryCatch({
    rdesk_find_gpp()
  }, error = function(e) {
    stop("[Validation Failed] Rtools (g++) is required to build the launcher stub.\n",
         "Error: ", e$message)
  })

  # 3b. Portable R provisioning strategy
  if (!is.null(runtime_dir)) {
    if (!dir.exists(file.path(runtime_dir, "bin"))) {
      stop("[Validation Failed] runtime_dir must point to an R runtime root containing bin/.\n",
           "Provided path: ", runtime_dir)
    }
  } else if (portable_r_method == "extract_only") {
    sevenzip <- rdesk_find_7zip()
    if (is.null(sevenzip)) {
        message("[RDesk]   Warning: Standalone 7-Zip not found.")
        message("[RDesk]   Switching to portable_r_method='installer' (no extra tools needed).")
        # Update the calling environment's method (kludge for this call)
        assign("portable_r_method", "installer", envir = parent.frame())
    }
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

rdesk_copy_dir <- function(from, to) {
  dirs <- list.dirs(from, recursive = TRUE, full.names = TRUE)
  for (d in dirs) {
    rel <- substring(d, nchar(from) + 2)
    if (nzchar(rel)) {
      dir.create(file.path(to, rel), recursive = TRUE, showWarnings = FALSE)
    }
  }

  files <- list.files(from, recursive = TRUE, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  for (f in files) {
    if (dir.exists(f)) next
    rel  <- substring(f, nchar(from) + 2)
    dest <- file.path(to, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(f, dest, overwrite = TRUE)
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
  avail <- tryCatch(utils::available.packages(repos = "https://cloud.r-project.org", type = "win.binary", filters = list()), error = function(e) NULL)
  all_deps <- rdesk_resolve_deps(pkgs, avail)
  all_deps <- setdiff(all_deps, "RDesk")
  target_repos <- sprintf("https://cloud.r-project.org/bin/windows/contrib/%s", minor)
  
  if (length(all_deps) > 0) {
    message("[RDesk]   Downloading ", length(all_deps), " packages...")
    utils::install.packages(all_deps, lib = lib_dir, contriburl = target_repos, type = "win.binary", quiet = FALSE, dependencies = FALSE)
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

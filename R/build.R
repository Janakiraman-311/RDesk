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
#' @return Path to the created zip file, invisibly.
#' @export
build_app <- function(app_dir,
                      out_dir  = "dist",
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
                      prune_runtime = TRUE) {

  options(timeout = max(1200, getOption("timeout")))
  portable_r_method <- match.arg(portable_r_method)
  app_dir <- normalizePath(app_dir, mustWork = TRUE)
  user_runtime_dir <- runtime_dir
  if (!is.null(user_runtime_dir)) {
    user_runtime_dir <- normalizePath(path.expand(user_runtime_dir), mustWork = TRUE)
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
  bin_stage <- file.path(stage_root, "bin")
  dir.create(bin_stage)
  rdesk_copy_dir(bin_src, bin_stage)

  # ---- Step 3: Download and extract portable R -----------------------------
  stage_runtime_dir <- file.path(stage_root, "runtime", "R")
  dir.create(stage_runtime_dir, recursive = TRUE)
  if (!is.null(user_runtime_dir)) {
    message("[RDesk] Step 3/6 - copying provided portable R runtime...")
    rdesk_copy_dir(user_runtime_dir, stage_runtime_dir)
    if (prune_runtime) {
      rdesk_prune_runtime(stage_runtime_dir)
    }
  } else {
    message("[RDesk] Step 3/6 - provisioning portable R ", r_version, "...")
    rdesk_fetch_portable_r(
      r_version = r_version,
      dest_dir = stage_runtime_dir,
      prune = prune_runtime,
      method = portable_r_method
    )
  }

  # ---- Step 4: Bundle packages ---------------------------------------------
  message("[RDesk] Step 4/6 - bundling R packages...")
  pkg_lib <- file.path(stage_root, "packages", "library")
  dir.create(pkg_lib, recursive = TRUE)

  # Always include RDesk and its hard deps
  core_pkgs <- c("RDesk", "R6", "jsonlite", "processx", "base64enc", "ggplot2", "dplyr", "digest", "zip")
  all_pkgs  <- unique(c(core_pkgs, include_packages))

  rdesk_install_packages_to(all_pkgs, pkg_lib, r_version)

  # Install RDesk separately from the local source tree or the installed package.
  message("[RDesk]   Bundling local RDesk package...")
  rdesk_src <- normalizePath(getwd(), mustWork = FALSE)
  if (file.exists(file.path(rdesk_src, "DESCRIPTION"))) {
    utils::install.packages(
      rdesk_src,
      lib = pkg_lib,
      repos = NULL,
      type = "source",
      dependencies = FALSE,
      quiet = TRUE
    )
  } else {
    installed_rdesk <- system.file(package = "RDesk")
    if (!nzchar(installed_rdesk)) {
      stop("[build_app] Could not locate the local RDesk package to bundle.")
    }
    rdesk_copy_dir(installed_rdesk, file.path(pkg_lib, "RDesk"))
  }
  
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

  old_wd <- setwd(dirname(stage_root))
  on.exit(setwd(old_wd), add = TRUE)
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
#' @param app_dir App directory to validate.
#' @param extra_pkgs Extra packages requested for bundling.
#' @param build_installer Whether installer prerequisites should be validated.
#' @param portable_r_method Runtime provisioning method used when
#'   `runtime_dir` is not supplied.
#' @param runtime_dir Optional existing runtime directory to validate.
#' @keywords internal
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
  
  missing <- all_pkgs[!all_pkgs %in% rownames(utils::installed.packages())]
  if (length(missing) > 0 && !"RDesk" %in% missing) {
    stop("[Validation Failed] The following required packages are not installed in your local R library:\n",
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
    tryCatch({
      rdesk_find_7zip()
    }, error = function(e) {
      stop("[Validation Failed] portable_r_method='extract_only' requires standalone 7-Zip.\n",
           "Error: ", e$message)
    })
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

#' Deep copy a directory
#'
#' @param from Source directory
#' @param to Destination directory
#' @keywords internal
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

#' Download and extract a portable R installation
#' Uses the official CRAN Windows binary installer, extracted via 7-Zip
#' @param r_version R version string to fetch.
#' @param dest_dir Destination directory for the unpacked runtime.
#' @param prune If TRUE, call rdesk_prune_runtime() after installation.
#' @param method Runtime provisioning method. `"extract_only"` requires
#'   standalone 7-Zip, while `"installer"` explicitly allows silent
#'   installer expansion.
#' @keywords internal
rdesk_fetch_portable_r <- function(r_version,
                                   dest_dir,
                                   prune = TRUE,
                                   method = c("extract_only", "installer")) {
  method <- match.arg(method)
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

  message("[RDesk]   Preparing R runtime (this takes ~60 seconds)...")
  tmp_extract <- file.path(tempdir(), paste0("R-", r_version, "-extract"))
  if (dir.exists(tmp_extract)) unlink(tmp_extract, recursive = TRUE)
  dir.create(tmp_extract, recursive = TRUE)

  if (method == "extract_only") {
    message("[RDesk]   Extracting R runtime with standalone 7-Zip...")
    sevenzip <- rdesk_find_7zip()
    ret <- tryCatch(
      system2(
        sevenzip,
        args = c(
          "x",
          "-y",
          paste0("-o", normalizePath(tmp_extract, winslash = "\\", mustWork = FALSE)),
          normalizePath(tmp_exe, winslash = "\\", mustWork = TRUE)
        ),
        stdout = FALSE,
        stderr = FALSE
      ),
      error = function(e) e
    )
    if (!identical(ret, 0L)) {
      stop(
        "[build_app] Failed to extract the R installer with standalone 7-Zip.\n",
        "Install the official Windows 7-Zip application and ensure `7z.exe` or `7za.exe` is on PATH,\n",
        "or available under `C:/Program Files/7-Zip/`."
      )
    }
  } else {
    message("[RDesk]   Expanding R runtime via explicit installer mode...")
    install_cmd <- sprintf('"%s" /SILENT /DIR="%s" /COMPONENTS="main,x64"',
                           normalizePath(tmp_exe),
                           normalizePath(tmp_extract))
    ret <- system(install_cmd, wait = TRUE, show.output.on.console = FALSE)
    if (!identical(ret, 0L)) {
      stop("[build_app] Silent installation of R failed in portable_r_method='installer' mode.")
    }
  }

  r_root <- rdesk_find_r_dir(tmp_extract)
  if (is.null(r_root)) {
    stop("[build_app] Could not locate the extracted R runtime.")
  }

  rdesk_copy_dir(r_root, dest_dir)
  
  if (prune) {
    rdesk_prune_runtime(dest_dir)
  }
  
  message("[RDesk]   R runtime installed: ", dest_dir)
}

#' Prune unnecessary files from the portable R runtime to reduce size
#' @param runtime_dir Path to the installed R root
#' @keywords internal
rdesk_prune_runtime <- function(runtime_dir) {
  # Directories safe to remove from portable R
  prune <- c(
    "doc",           # R documentation — ~8MB
    "tests",         # R test suite — ~2MB
    "Tcl",           # Tk GUI toolkit — ~8MB, RDesk uses WebView2
    "share/locale",  # Translations — ~3MB
    "library/tcltk", # Tcl/Tk R package
    "library/KernSmooth",  # rarely needed
    "library/spatial"      # rarely needed
  )
  
  message("[RDesk]   Optimizing R runtime size...")
  for (p in prune) {
    target <- file.path(runtime_dir, p)
    if (dir.exists(target)) {
      unlink(target, recursive = TRUE)
      message("[RDesk]     Pruned: ", p)
    }
  }
}

#' Find 7-Zip executable in common Windows locations
#'
#' @return Path to 7z.exe
#' @keywords internal
rdesk_find_7zip <- function() {
  candidates <- c(
    Sys.which("7z"),
    Sys.which("7za"),
    Sys.which("7zr"),
    "C:/Program Files/7-Zip/7z.exe",
    "C:/Program Files/7-Zip/7za.exe",
    "C:/Program Files (x86)/7-Zip/7z.exe",
    "C:/Program Files (x86)/7-Zip/7za.exe"
  )
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  found <- found[!grepl("rtools", found, ignore.case = TRUE)]
  if (length(found) == 0)
    stop("[build_app] Standalone 7-Zip not found.\n",
         "Install the official Windows 7-Zip application from https://7-zip.org\n",
         "and make sure `7z.exe` or `7za.exe` is on PATH or under Program Files.")
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

#' Find the R directory within an extracted installation
#'
#' @param extracted_root Path where R was extracted
#' @return Path to the R root (containing bin/)
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
  all_deps <- setdiff(all_deps, "RDesk")
  message("[RDesk]   Installing ", length(all_deps), " packages into bundle...")
  if (length(all_deps) > 0) {
    message("[RDesk]   Packages: ", paste(all_deps, collapse = ", "))
  }

  # Construct the exact URL for the target R version's binary repository
  # e.g. https://cloud.r-project.org/bin/windows/contrib/4.4/
  target_repos <- sprintf("https://cloud.r-project.org/bin/windows/contrib/%s", minor)

  if (length(all_deps) > 0) {
    utils::install.packages(
      all_deps,
      lib      = lib_dir,
      contriburl = target_repos,
      type     = "win.binary",
      quiet    = FALSE,
      dependencies = FALSE
    )
  }

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
    if (pkg %in% resolved || pkg %in% base_pkgs || pkg == "RDesk") next
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

  # Copy to a temporary file to avoid any potential caching/sync issues with g++ 
  # especially on network/sync folders like OneDrive
  tmp_cpp <- file.path(tempdir(), paste0("stub_", digest::digest(app_name, algo="crc32"), ".cpp"))
  file.copy(stub_cpp, tmp_cpp, overwrite = TRUE)
  on.exit(unlink(tmp_cpp), add = TRUE)

  # Perform template replacement for APP_NAME
  lines <- readLines(tmp_cpp)
  lines <- gsub("{{APP_NAME}}", app_name, lines, fixed = TRUE)
  writeLines(lines, tmp_cpp)

  # Header paths
  inc_path <- system.file("include", package = "RDesk")
  if (inc_path == "") inc_path <- file.path(getwd(), "inst/include")
  
  # Source path for internal headers (e.g. webview.h)
  src_inc <- dirname(normalizePath(stub_cpp, mustWork = TRUE))
  # WebView2 SDK path
  sdk_inc <- file.path(src_inc, "webview2_sdk", "build", "native", "include")

  message("[RDesk]   Compiling launcher stub...")
  
  ret <- system2(gpp,
    args = c("-std=c++17", "-O2", "-mwindows",
             "-I", shQuote(inc_path),
             "-I", shQuote(src_inc),
             "-I", shQuote(sdk_inc),
             shQuote(tmp_cpp),
             "-o", shQuote(out_exe),
             "-lole32", "-lcomctl32", "-loleaut32", "-luuid", "-lshlwapi", "-lversion",
             "-lstdc++fs"),
    stdout = FALSE, stderr = FALSE)

  if (ret != 0 || !file.exists(out_exe)) {
    # If compilation failed, try to capture the error for the user
    err_out <- system2(gpp,
      args = c("-std=c++17", "-O2", "-mwindows",
               "-I", shQuote(inc_path),
               "-I", shQuote(src_inc),
               "-I", shQuote(sdk_inc),
               shQuote(tmp_cpp),
               "-o", shQuote(out_exe),
               "-lstdc++fs"),
      stdout = TRUE, stderr = TRUE)
    
    stop("[build_app] Failed to compile launcher stub.\n",
         "G++ Error:\n", paste(err_out, collapse = "\n"),
         "\n\nCompiler used: ", gpp,
         "\n\nNote: At runtime, logs will be in %LOCALAPPDATA%/RDesk/", app_name)
  }

  message("[RDesk]   Stub compiled: ", basename(out_exe))
}

#' Find InnoSetup compiler (ISCC.exe)
#' @keywords internal
rdesk_find_iscc <- function() {
  candidates <- c(
    Sys.which("ISCC"),
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Inno Setup 6", "ISCC.exe"),
    "C:/Program Files (x86)/Inno Setup 6/ISCC.exe",
    "C:/Program Files/Inno Setup 6/ISCC.exe"
  )
  found <- candidates[nchar(candidates) > 0 & file.exists(candidates)]
  if (length(found) == 0) return(NULL)
  found[1]
}

#' Generate and compile InnoSetup script
#' @keywords internal
rdesk_build_installer <- function(stage_root, out_dir, app_name, version,
                                   publisher, website, license_file, icon_file) {
  template_path <- system.file("installer", "template.iss", package = "RDesk")
  if (template_path == "") {
    template_path <- file.path(getwd(), "inst/installer/template.iss")
  }
  
  iss_content <- readLines(template_path)
  
  # Replace basic placeholders
  iss_content <- gsub("{{AppName}}", app_name, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppVersion}}", version, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppPublisher}}", publisher, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppURL}}", website, iss_content, fixed = TRUE)
  iss_content <- gsub("{{AppExeName}}", paste0(app_name, ".exe"), iss_content, fixed = TRUE)
  iss_content <- gsub("{{SourceDir}}", normalizePath(stage_root), iss_content, fixed = TRUE)
  iss_content <- gsub("{{OutputDir}}", normalizePath(out_dir), iss_content, fixed = TRUE)
  
  setup_basename <- paste0(app_name, "-", version, "-setup")
  iss_content <- gsub("{{SetupBaseName}}", setup_basename, iss_content, fixed = TRUE)
  
  # App ID should be stable but unique for the app name
  # We use a simple hash of the app name for consistency
  app_id <- sprintf("RDesk-App-%s", digest::digest(app_name, algo = "crc32"))
  iss_content <- gsub("{{AppID}}", app_id, iss_content, fixed = TRUE)

  # Optional files
  license_path <- ""
  if (!is.null(license_file)) {
    license_path <- normalizePath(license_file, mustWork = TRUE)
  }
  iss_content <- gsub("{{LicenseFile}}", license_path, iss_content, fixed = TRUE)
  
  icon_path <- ""
  if (!is.null(icon_file)) {
    icon_path <- normalizePath(icon_file, mustWork = TRUE)
  }
  iss_content <- gsub("{{AppIconFile}}", icon_path, iss_content, fixed = TRUE)
  
  iss_temp <- file.path(tempdir(), "installer.iss")
  writeLines(iss_content, iss_temp)
  
  iscc <- rdesk_find_iscc()
  message("[RDesk]   Compiling installer...")
  
  # Run ISCC.exe
  # /Q = Quiet
  res <- system2(iscc, args = c("/Q", shQuote(iss_temp)), stdout = TRUE, stderr = TRUE)
  
  if (!is.null(attr(res, "status")) && attr(res, "status") != 0) {
    cat("[InnoSetup Error Output]:\n")
    cat(paste(res, collapse = "\n"), "\n")
    stop("[RDesk] InnoSetup compilation failed. See output above.")
  }
  
  setup_exe <- file.path(out_dir, paste0(setup_basename, ".exe"))
  message("[RDesk]   Installer created: ", setup_exe)
}

#' Find g++ compiler in common Rtools locations
#'
#' @return Path to g++.exe
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

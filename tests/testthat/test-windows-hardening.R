test_that("Auto-update enforces https:// URLs", {
  expect_warning(
    res <- rdesk_auto_update("http://example.com/v.txt", "https://example.com/a.exe"),
    "https://"
  )
  expect_false(res)

  expect_warning(
    res2 <- rdesk_auto_update("https://example.com/v.txt", "http://example.com/a.exe"),
    "https://"
  )
  expect_false(res2)

  app <- App$new(title = "UpdateTestApp", width = 800, height = 600)
  expect_warning(
    chk <- app$check_update("http://example.com/version.json"),
    "https://"
  )
  expect_false(chk$update_available)
  expect_match(chk$error, "https://")
})

test_that("rdesk_log filters by level and rotates oversized logs", {
  app_name <- "RDeskTestLogRotate"
  withr::defer(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE))
  withr::local_options(
    rdesk.log_level = "WARN",
    rdesk.max_log_bytes = 200,
    rdesk.verbose_log = FALSE
  )

  RDesk:::rdesk_log("debug msg", level = "DEBUG", app_name = app_name)
  RDesk:::rdesk_log("info msg", level = "INFO", app_name = app_name)
  log_file <- file.path(RDesk:::rdesk_log_dir(app_name), "app.log")
  expect_false(file.exists(log_file))

  big_line <- paste(rep("x", 250), collapse = "")
  RDesk:::rdesk_log(big_line, level = "WARN", app_name = app_name)
  expect_true(file.exists(log_file))

  RDesk:::rdesk_log("after rotation", level = "ERROR", app_name = app_name)
  backup <- paste0(log_file, ".1")
  expect_true(file.exists(backup))
  expect_match(paste(readLines(log_file, warn = FALSE), collapse = "\n"), "after rotation")
})

test_that("RDeskStorage performs atomic writes without leaving temp files", {
  app_name <- "RDeskTestAtomicStorage"
  withr::defer(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE))

  st <- rdesk_storage(app_name, "local")
  st$set("k1", "v1")
  st$set("k2", 123L)

  files <- list.files(st$path())
  expect_in("storage.json", files)
  expect_false(any(grepl("\\.tmp$", files)))

  st2 <- rdesk_storage(app_name, "local")
  expect_equal(st2$get("k1"), "v1")
  expect_equal(st2$get("k2"), 123L)
})

test_that("build_app validates app_name and escaping helpers work", {
  expect_equal(RDesk:::rdesk_escape_cpp_wstring('a\\b"c'), 'a\\\\b\\"c')
  expect_equal(RDesk:::rdesk_escape_iss_define('a"b'), 'a""b')

  tmp_dir <- withr::local_tempdir()
  withr::local_dir(tmp_dir)
  file.create("app.R")
  dir.create("www")
  expect_error(
    build_app(".", out_dir = tempdir(), app_name = 'Bad"Name'),
    "app_name"
  )
})

test_that("rdesk_render_iss_template configures user and system install scopes", {
  tmp_dir <- withr::local_tempdir()
  iss_user <- RDesk:::rdesk_render_iss_template(
    stage_root = tmp_dir,
    out_dir = tmp_dir,
    app_name = "DemoApp",
    version = "1.0.0",
    publisher = "Tester",
    website = "https://example.com",
    install_scope = "user"
  )
  txt_user <- paste(iss_user, collapse = "\n")
  expect_match(txt_user, "PrivilegesRequired=lowest", fixed = TRUE)
  expect_match(txt_user, "DefaultDirName={autopf}\\{#AppName}", fixed = TRUE)
  expect_match(txt_user, "Software\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients", fixed = TRUE)

  iss_sys <- RDesk:::rdesk_render_iss_template(
    stage_root = tmp_dir,
    out_dir = tmp_dir,
    app_name = "DemoApp",
    version = "1.0.0",
    publisher = "Tester",
    website = "https://example.com",
    install_scope = "system"
  )
  txt_sys <- paste(iss_sys, collapse = "\n")
  expect_match(txt_sys, "PrivilegesRequired=admin", fixed = TRUE)
  expect_match(txt_sys, "DefaultDirName={autopf}\\{#AppName}", fixed = TRUE)
})

test_that("rdesk_launcher_path resolves R_BUNDLE_ROOT/bin in bundled mode", {
  bundle_dir <- withr::local_tempdir()
  bin_dir <- file.path(bundle_dir, "bin")
  dir.create(bin_dir, recursive = TRUE)
  bin_name <- if (.Platform$OS.type == "windows") "rdesk-launcher.exe" else "rdesk-launcher"
  fake_launcher <- file.path(bin_dir, bin_name)
  file.create(fake_launcher)

  withr::local_envvar(
    R_BUNDLE_APP = "1",
    R_BUNDLE_ROOT = bundle_dir
  )
  resolved <- RDesk:::rdesk_launcher_path()
  expect_equal(
    normalizePath(resolved, winslash = "/"),
    normalizePath(fake_launcher, winslash = "/")
  )
})

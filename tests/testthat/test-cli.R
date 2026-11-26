test_that("rdesk_sitrep returns expected environment fields", {
  info <- suppressMessages(rdesk_sitrep())
  expect_type(info, "list")
  expect_contains(
    names(info),
    c("r_version", "rdesk_version", "launcher_path", "gpp_path", "iscc_path")
  )
})

test_that("install_rdesk_cli errors clearly when Rapp is unavailable", {
  skip_if(requireNamespace("Rapp", quietly = TRUE), "Rapp is installed")
  expect_error(install_rdesk_cli(), "Rapp")
})

test_that("exec/rdesk.R exposes subcommands and parses cleanly", {
  pkg_root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = FALSE)
  exec_dir <- file.path(pkg_root, "exec")
  skip_if_not(dir.exists(exec_dir), "exec/ directory not present")

  rdesk_script <- file.path(exec_dir, "rdesk.R")
  expect_true(file.exists(rdesk_script))
  expect_length(list.files(exec_dir, pattern = "^rdesk-.*\\.R$"), 0L)

  lines <- readLines(rdesk_script, warn = FALSE)
  expect_equal(lines[1], "#!/usr/bin/env Rapp")

  txt <- paste(lines, collapse = "\n")
  expect_match(txt, 'switch\\(\\s*command <- ""', perl = TRUE)
  for (cmd in c("new", "run", "demo", "build", "sitrep")) {
    expect_match(txt, paste0("\\b", cmd, " = \\{"), perl = TRUE)
  }
  expect_no_error(parse(rdesk_script))
})

test_that("rdesk_run validates paths and resolves app directories and app.R files", {
  expect_error(rdesk_run(""), "non-empty")
  expect_error(rdesk_run(file.path(tempdir(), "does_not_exist_rdesk")), "not found")

  empty_dir <- withr::local_tempdir()
  expect_error(rdesk_run(empty_dir), "No app.R found")

  demo_dir <- system.file("apps", "mtcars_dashboard", package = "RDesk")
  skip_if(!nzchar(demo_dir) || !dir.exists(demo_dir), "mtcars_dashboard demo not present")

  withr::local_options(list(rdesk.ci_mode = TRUE))
  res_dir <- suppressMessages(rdesk_run(demo_dir, debug = TRUE, detach = TRUE))
  expect_equal(res_dir$app_dir, normalizePath(demo_dir, winslash = "/", mustWork = TRUE))
  expect_equal(res_dir$app_script, file.path(res_dir$app_dir, "app.R"))
  expect_true(res_dir$debug)
  expect_true(res_dir$detach)

  res_file <- suppressMessages(rdesk_run(file.path(demo_dir, "app.R")))
  expect_equal(res_file$app_script, res_dir$app_script)
  expect_false(res_file$debug)
  expect_false(res_file$detach)
})

test_that("rdesk_demo lists and resolves built-in showcase demos", {
  catalog <- suppressMessages(rdesk_demo())
  expect_s3_class(catalog, "data.frame")
  expect_equal(catalog$name, c("cars", "studio", "starter"))

  expect_error(rdesk_demo("nonexistent_demo"), "Unknown demo")
  expect_error(rdesk_demo("starter", theme = "neon"), "Invalid theme")

  withr::local_options(list(rdesk.ci_mode = TRUE))
  res_cars <- suppressMessages(rdesk_demo("cars"))
  expect_true(grepl("mtcars_dashboard/app\\.R$", res_cars$app_script))

  res_studio <- suppressMessages(rdesk_demo("data_studio", debug = TRUE))
  expect_true(grepl("data_studio/app\\.R$", res_studio$app_script))
  expect_true(res_studio$debug)

  res_starter <- suppressMessages(rdesk_demo("starter", theme = "light"))
  expect_true(file.exists(res_starter$app_script))
  expect_true(grepl("RDeskStarterWorkbench/app\\.R$", res_starter$app_script))
})

test_that("Rapp executes exec/rdesk.R subcommands and install_rdesk_cli installs launcher", {
  skip_if_not_installed("Rapp")

  rdesk_script <- system.file("exec", "rdesk.R", package = "RDesk")
  if (!nzchar(rdesk_script) || !file.exists(rdesk_script)) {
    rdesk_script <- normalizePath(
      file.path(testthat::test_path(), "..", "..", "exec", "rdesk.R"),
      mustWork = FALSE
    )
  }
  skip_if_not(file.exists(rdesk_script), "exec/rdesk.R script not found")

  expect_no_error(capture.output(Rapp::run(rdesk_script, c("--help"))))
  expect_no_error(capture.output(Rapp::run(rdesk_script, c("run", "--help"))))
  expect_no_error(capture.output(Rapp::run(rdesk_script, c("demo", "--help"))))
  expect_no_error(suppressMessages(Rapp::run(rdesk_script, c("sitrep"))))
  expect_no_error(suppressMessages(Rapp::run(rdesk_script, c("demo"))))

  work_dir <- withr::local_tempdir()
  withr::local_dir(work_dir)
  suppressMessages(Rapp::run(rdesk_script, c("new", "CliDemoApp", "--path", work_dir)))
  expect_true(file.exists(file.path(work_dir, "CliDemoApp", "app.R")))
  expect_true(dir.exists(file.path(work_dir, "CliDemoApp", "www")))

  withr::local_options(list(rdesk.ci_mode = TRUE))
  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("run", "CliDemoApp", "--debug", "--detach"))
  ))
  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("demo", "cars"))
  ))
  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("demo", "studio"))
  ))
  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("demo", "starter", "--theme", "dark"))
  ))

  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("build", "--app-dir", "CliDemoApp", "--dry-run"))
  ))

  writeLines("ico", file.path(work_dir, "CliDemoApp", "custom.ico"))
  writeLines("MIT", file.path(work_dir, "CliDemoApp", "LICENSE.txt"))
  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c(
      "build", "--app-dir", "CliDemoApp",
      "--icon", file.path(work_dir, "CliDemoApp", "custom.ico"),
      "--publisher", "CliOrg",
      "--license", file.path(work_dir, "CliDemoApp", "LICENSE.txt"),
      "--no-cache",
      "--dry-run"
    ))
  ))

  bin_dir <- withr::local_tempdir()
  withr::local_envvar(RAPP_NO_MODIFY_PATH = "1")
  suppressMessages(install_rdesk_cli(destdir = bin_dir, overwrite = TRUE))
  installed_files <- list.files(bin_dir)
  expect_in(if (.Platform$OS.type == "windows") "rdesk.bat" else "rdesk", installed_files)
})

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
  for (cmd in c("new", "build", "sitrep")) {
    expect_match(txt, paste0("\\b", cmd, " = \\{"), perl = TRUE)
  }
  expect_no_error(parse(rdesk_script))
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
  expect_no_error(suppressMessages(Rapp::run(rdesk_script, c("sitrep"))))

  work_dir <- withr::local_tempdir()
  withr::local_dir(work_dir)
  suppressMessages(Rapp::run(rdesk_script, c("new", "CliDemoApp", "--path", work_dir)))
  expect_true(file.exists(file.path(work_dir, "CliDemoApp", "app.R")))
  expect_true(dir.exists(file.path(work_dir, "CliDemoApp", "www")))

  expect_no_error(suppressMessages(
    Rapp::run(rdesk_script, c("build", "--app-dir", "CliDemoApp", "--dry-run"))
  ))

  bin_dir <- withr::local_tempdir()
  withr::local_envvar(RAPP_NO_MODIFY_PATH = "1")
  suppressMessages(install_rdesk_cli(destdir = bin_dir, overwrite = TRUE))
  installed_files <- list.files(bin_dir)
  expect_in(if (.Platform$OS.type == "windows") "rdesk.bat" else "rdesk", installed_files)
})

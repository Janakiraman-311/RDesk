test_that("rdesk_validate_build_inputs() stops on missing app.R", {
  withr::with_tempdir({
    dir.create("www")
    expect_error(
      rdesk_validate_build_inputs(".", character(0), FALSE),
      "app.R not found"
    )
  })
})

test_that("rdesk_validate_build_inputs() stops on missing www/", {
  withr::with_tempdir({
    file.create("app.R")
    expect_error(
      rdesk_validate_build_inputs(".", character(0), FALSE),
      "www/"
    )
  })
})

test_that("rdesk_validate_build_inputs() passes with correct structure", {
  withr::with_tempdir({
    file.create("app.R")
    dir.create("www")
    # Either passes (Rtools present) or fails with a launcher-related message -
    # not an app.R / www missing error.
    result <- tryCatch(
      rdesk_validate_build_inputs(".", character(0), FALSE),
      error = function(e) e$message
    )
    if (is.character(result)) {
      # Structural checks passed; it only failed because g++ is not present
      expect_false(grepl("app.R|www/", result))
    } else {
      succeed("rdesk_validate_build_inputs passed with no error")
    }
  })
})

test_that("rdesk_relative_path() resolves same-directory and nested-directory cases correctly", {
  withr::with_tempdir({
    dir.create("a/b/c", recursive = TRUE)
    dir.create("a/b/d", recursive = TRUE)
    
    p_ab <- file.path(getwd(), "a/b")
    p_abc <- file.path(getwd(), "a/b/c")
    p_abd <- file.path(getwd(), "a/b/d")
    
    # Same directory
    expect_equal(rdesk_relative_path(p_abc, p_abc), ".")
    
    # Nested directory (to is deeper)
    expect_equal(rdesk_relative_path(p_ab, p_abc), "c")
    
    # Parent directory (from is deeper)
    expect_equal(rdesk_relative_path(p_abc, p_ab), "..")
    
    # Sibling directory
    expect_equal(rdesk_relative_path(p_abc, p_abd), "../d")
  })
})

test_that("Unix bundler escaping and plist helpers sanitize special characters", {
  expect_equal(RDesk:::rdesk_escape_c_string('a\\b"c'), 'a\\\\b\\"c')
  expect_equal(RDesk:::rdesk_escape_xml('A & B <"C">'), 'A &amp; B &lt;&quot;C&quot;&gt;')

  tmp <- withr::local_tempdir()
  RDesk:::rdesk_write_info_plist(tmp, "App&Demo", "1.0.0")
  plist_txt <- paste(readLines(file.path(tmp, "Info.plist"), warn = FALSE), collapse = "\n")
  expect_match(plist_txt, "App&amp;Demo", fixed = TRUE)

  wrapper <- RDesk:::rdesk_portable_rscript_wrapper_lines()
  expect_equal(wrapper[1], "#!/usr/bin/env bash")
  expect_match(paste(wrapper, collapse = "\n"), "exec \"\\$DIR/R\"", perl = TRUE)
})

test_that("rdesk_prune_package_lib removes non-runtime subdirectories", {
  lib_dir <- withr::local_tempdir()
  pkg_dir <- file.path(lib_dir, "demoPkg")
  for (sub in c("R", "Meta", "help", "html", "doc", "tests", "demo")) {
    dir.create(file.path(pkg_dir, sub), recursive = TRUE)
  }

  RDesk:::rdesk_prune_package_lib(lib_dir)
  expect_true(dir.exists(file.path(pkg_dir, "R")))
  expect_true(dir.exists(file.path(pkg_dir, "Meta")))
  expect_false(dir.exists(file.path(pkg_dir, "help")))
  expect_false(dir.exists(file.path(pkg_dir, "html")))
  expect_false(dir.exists(file.path(pkg_dir, "doc")))
  expect_false(dir.exists(file.path(pkg_dir, "tests")))
  expect_false(dir.exists(file.path(pkg_dir, "demo")))
})

test_that("__bridge_ready__ writes RDESK_SMOKE_SENTINEL JSON for CI GUI smoke tests", {
  sentinel <- withr::local_tempfile(fileext = ".json")
  withr::local_envvar(RDESK_SMOKE_SENTINEL = sentinel)
  withr::defer(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE))

  app <- App$new(title = "SmokeTestApp", width = 800, height = 600)
  app$.__enclos_env__$private$.router$dispatch(
    "__bridge_ready__",
    list(url = "rdesk://app/index.html", title = "SmokeTestApp")
  )

  expect_true(file.exists(sentinel))
  meta <- jsonlite::fromJSON(sentinel)
  expect_equal(meta$status, "BRIDGE_READY")
  expect_equal(meta$app_title, "SmokeTestApp")
  expect_equal(meta$page_url, "rdesk://app/index.html")
})

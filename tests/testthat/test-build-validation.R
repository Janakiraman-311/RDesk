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

test_that("rdesk_app_exclusions() and .rdeskignore prevent dist/ recursion and nested dev leaks", {
  withr::with_tempdir({
    dir.create("src_app/www", recursive = TRUE)
    dir.create("src_app/dist", recursive = TRUE)
    dir.create("src_app/build", recursive = TRUE)
    dir.create("src_app/samples/PDF_Output", recursive = TRUE)
    dir.create("src_app/temp", recursive = TRUE)
    dir.create("dst_app", recursive = TRUE)

    writeLines("app_code()", "src_app/app.R")
    writeLines("<h1>OK</h1>", "src_app/www/index.html")
    writeLines("old zip", "src_app/dist/App-1.0.0-windows.zip")
    writeLines("old build", "src_app/build/out.txt")
    writeLines("ignore me", "src_app/README.md")
    writeLines("proj", "src_app/MyApp.Rproj")
    writeLines("buildignore", "src_app/.Rbuildignore")
    writeLines("pdf", "src_app/samples/PDF_Output/report.pdf")
    writeLines("keep sample", "src_app/samples/sample.xlsx")
    writeLines("debug", "src_app/debug.log")
    writeLines("tmp", "src_app/temp/cache.tmp")
    writeLines(
      c(
        "# Ignore generated outputs and logs",
        "",
        "samples/PDF_Output/",
        "*.log",
        "temp/*.tmp"
      ),
      "src_app/.rdeskignore"
    )

    suppressMessages(rdesk_copy_dir("src_app", "dst_app", exclude = rdesk_app_exclusions()))

    expect_true(file.exists("dst_app/app.R"))
    expect_true(file.exists("dst_app/www/index.html"))
    expect_true(file.exists("dst_app/samples/sample.xlsx"))

    expect_false(dir.exists("dst_app/dist"))
    expect_false(dir.exists("dst_app/build"))
    expect_false(file.exists("dst_app/README.md"))
    expect_false(file.exists("dst_app/MyApp.Rproj"))
    expect_false(file.exists("dst_app/.Rbuildignore"))
    expect_false(file.exists("dst_app/.rdeskignore"))
    expect_false(file.exists("dst_app/samples/PDF_Output/report.pdf"))
    expect_false(file.exists("dst_app/debug.log"))
    expect_false(file.exists("dst_app/temp/cache.tmp"))
  })
})

test_that("rdesk_prune_package_lib() strips dev/demo directories from bundled RDesk", {
  withr::with_tempdir({
    rdesk_dir <- file.path("lib", "RDesk")
    for (sub in c("R", "Meta", "www", "help", "html", "doc", "tests", "demo",
                  "apps", "templates", "stub", "include", "installer", "exec")) {
      dir.create(file.path(rdesk_dir, sub), recursive = TRUE)
      writeLines("x", file.path(rdesk_dir, sub, "file.txt"))
    }
    other_dir <- file.path("lib", "jsonlite")
    for (sub in c("R", "doc", "tests", "templates")) {
      dir.create(file.path(other_dir, sub), recursive = TRUE)
      writeLines("x", file.path(other_dir, sub, "file.txt"))
    }

    rdesk_prune_package_lib("lib")

    expect_true(dir.exists(file.path(rdesk_dir, "R")))
    expect_true(dir.exists(file.path(rdesk_dir, "Meta")))
    expect_true(dir.exists(file.path(rdesk_dir, "www")))
    for (dropped in c("help", "html", "doc", "tests", "demo",
                      "apps", "templates", "stub", "include", "installer", "exec")) {
      expect_false(dir.exists(file.path(rdesk_dir, dropped)), info = dropped)
    }

    expect_true(dir.exists(file.path(other_dir, "R")))
    expect_true(dir.exists(file.path(other_dir, "templates")))
    expect_false(dir.exists(file.path(other_dir, "doc")))
    expect_false(dir.exists(file.path(other_dir, "tests")))
  })
})

test_that("build_app(..., dry_run = TRUE) runs real pre-flight validation and DESCRIPTION defaults", {
  withr::with_tempdir({
    dir.create("app/www", recursive = TRUE)
    writeLines("app_code()", "app/app.R")
    writeLines("<h1>Test</h1>", "app/www/index.html")
    writeLines("ico", "app/app.ico")
    writeLines("MIT", "app/LICENSE.txt")
    writeLines(
      c(
        "Package: DemoPkg",
        "Version: 2.3.4",
        "Imports: jsonlite",
        "Config/RDesk/Publisher: TestOrg",
        "Config/RDesk/InstallScope: user",
        "Config/RDesk/LicenseFile: LICENSE.txt"
      ),
      "app/DESCRIPTION"
    )

    msgs <- capture.output(
      res <- build_app("app", out_dir = "app/dist", dry_run = TRUE),
      type = "message"
    )
    txt <- paste(msgs, collapse = "\n")
    expect_true(res)
    expect_match(txt, "Auto-detected application icon:")
    expect_match(txt, "DemoPkg 2\\.3\\.4")
    expect_match(txt, "Publisher:\\s+TestOrg")
    expect_match(txt, "LICENSE\\.txt")

    expect_error(
      suppressMessages(build_app("app", icon_file = "missing.ico", dry_run = TRUE)),
      "Icon file not found"
    )

    writeLines(
      c("Package: BadPkg", "Version: 1.0.0", "Imports: definitelyMissingPkg999"),
      "app/DESCRIPTION"
    )
    expect_error(
      suppressMessages(build_app("app", dry_run = TRUE)),
      "definitelyMissingPkg999"
    )
  })
})

test_that("build cache helpers compute deterministic keys and round-trip staged trees", {
  withr::with_tempdir({
    withr::local_options(list(rdesk.build_cache_dir = file.path(getwd(), "cache")))
    k1 <- rdesk_compute_build_cache_key("4.5.0", R.home(), TRUE, c("RDesk", "jsonlite"))
    k2 <- rdesk_compute_build_cache_key("4.5.0", R.home(), TRUE, c("jsonlite", "RDesk"))
    k3 <- rdesk_compute_build_cache_key("4.5.0", R.home(), FALSE, c("RDesk", "jsonlite"))
    expect_equal(k1, k2)
    expect_false(identical(k1, k3))

    dir.create("rt_src/bin", recursive = TRUE)
    writeLines("R", "rt_src/bin/R.txt")
    dir.create("lib_src/jsonlite", recursive = TRUE)
    writeLines("jsonlite", "lib_src/jsonlite/DESCRIPTION")

    cache_dir <- file.path(rdesk_build_cache_root(), "env_test123")
    expect_true(rdesk_save_build_cache(cache_dir, "rt_src", "lib_src"))

    dir.create("rt_dst", recursive = TRUE)
    dir.create("lib_dst", recursive = TRUE)
    expect_true(suppressMessages(rdesk_restore_build_cache(cache_dir, "rt_dst", "lib_dst", "test123")))
    expect_true(file.exists("rt_dst/bin/R.txt"))
    expect_true(file.exists("lib_dst/jsonlite/DESCRIPTION"))
  })
})

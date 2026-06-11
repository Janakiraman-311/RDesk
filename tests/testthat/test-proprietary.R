test_that("rdesk_new_pkg validates package name", {
  expect_error(rdesk_new_pkg(""),          "required")
  expect_error(rdesk_new_pkg("123invalid"),"Invalid")
  expect_error(rdesk_new_pkg("has space"), "Invalid")
})

test_that("rdesk_new_pkg creates correct structure", {
  withr::with_tempdir({
    path <- rdesk_new_pkg(
      name  = "TestPkg",
      path  = ".",
      open  = FALSE
    )
    expect_true(dir.exists(path))
    expect_true(file.exists(file.path(path, "DESCRIPTION")))
    expect_true(file.exists(file.path(path, "NAMESPACE")))
    expect_true(dir.exists(file.path(path, "R")))
    expect_true(dir.exists(file.path(path, "src")))
    expect_true(dir.exists(file.path(path, "tests")))
  })
})

test_that("rdesk_new_pkg replaces PKG_NAME placeholder", {
  withr::with_tempdir({
    path <- rdesk_new_pkg("MySpecialPkg", path = ".", open = FALSE)
    desc_content <- readLines(file.path(path, "DESCRIPTION"))
    expect_true(any(grepl("MySpecialPkg", desc_content)))
    expect_false(any(grepl("\\{\\{PKG_NAME\\}\\}", desc_content)))
  })
})

test_that("rdesk_verify_protection detects exposed source", {
  withr::with_tempdir({
    # Create a fake bundle with source exposed
    pkg_dir <- file.path("packages", "library", "FakePkg", "R")
    dir.create(pkg_dir, recursive = TRUE)
    writeLines("x <- 1", file.path(pkg_dir, "FakePkg.R"))

    result <- rdesk_verify_protection(".", "FakePkg")
    expect_false(result["FakePkg"])
  })
})

test_that("rdesk_verify_protection passes for stripped package", {
  withr::with_tempdir({
    # Create a fake bundle with only .rdb (source stripped)
    pkg_dir <- file.path("packages", "library", "SafePkg", "R")
    dir.create(pkg_dir, recursive = TRUE)
    # .rdb is a binary format -- just create an empty file for test
    writeLines("", file.path(pkg_dir, "SafePkg.rdb"))
    writeLines("", file.path(pkg_dir, "SafePkg.rdx"))

    result <- rdesk_verify_protection(".", "SafePkg")
    expect_true(result["SafePkg"])
  })
})

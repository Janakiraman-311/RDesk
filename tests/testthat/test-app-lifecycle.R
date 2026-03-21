library(testthat)
library(RDesk)

test_that("App constructor validates mandatory arguments", {
  expect_error(App$new(width = 800, height = 600), "Title is mandatory")
  expect_error(App$new(title = "Test"), "Width is mandatory")
  expect_error(App$new(title = "Test", width = 800), "Height is mandatory")
})

test_that("App constructor validates resolution and paths", {
  withr::with_tempdir({
    # Test missing www path
    expect_error(App$new("Test", 800, 600, www = "nonexistent_dir"), "www directory not found")
    
    # Test valid initialization
    dir.create("www")
    app <- App$new("Test", 800, 600, www = "www")
    expect_s3_class(app, "App")

  })
})

test_that("App sets default options on load", {
  # These are set in .onLoad in zzz.R
  expect_false(is.null(getOption("rdesk.ipc_version")))
  expect_false(is.null(getOption("rdesk.async_backend")))
})

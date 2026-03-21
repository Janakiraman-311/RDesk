library(testthat)
library(RDesk)

test_that("rdesk_create_app validates app name", {
  expect_error(rdesk_create_app("", open = FALSE), "App name is required")
  expect_error(rdesk_create_app("123App", open = FALSE), "must start with a letter")
  expect_error(rdesk_create_app("App!", open = FALSE), "must start with a letter and contain only")
})

test_that("rdesk_create_app creates directory structure", {
  withr::with_tempdir({
    app_dir <- rdesk_create_app("TestApp", data_source = "builtin", viz_type = "mixed", open = FALSE)
    
    expect_true(dir.exists(app_dir))
    expect_true(dir.exists(file.path(app_dir, "R")))
    expect_true(dir.exists(file.path(app_dir, "www")))
    expect_true(dir.exists(file.path(app_dir, "www", "css")))
    expect_true(dir.exists(file.path(app_dir, "www", "js")))
    
    expect_true(file.exists(file.path(app_dir, "app.R")))
    expect_true(file.exists(file.path(app_dir, "DESCRIPTION")))
    expect_true(file.exists(file.path(app_dir, "R", "server.R")))
    expect_true(file.exists(file.path(app_dir, "www", "index.html")))
    expect_true(file.exists(file.path(app_dir, "www", "js", "rdesk.js")))
  })
})

test_that("template placeholder replacement works", {
  withr::with_tempdir({
    app_dir <- rdesk_create_app("PlaceholderTest", data_source = "csv", viz_type = "charts", open = FALSE)
    
    app_r <- readLines(file.path(app_dir, "app.R"), warn = FALSE)
    expect_true(any(grepl("PlaceholderTest", app_r)))
    expect_false(any(grepl("\\{\\{", app_r)))
    
    desc <- readLines(file.path(app_dir, "DESCRIPTION"), warn = FALSE)
    expect_true(any(grepl("DataSource: csv", desc)))
  })
})

test_that("variant selection picks correct templates", {
  withr::with_tempdir({
    # Test async variant
    async_dir <- rdesk_create_app("AsyncApp", use_async = TRUE, open = FALSE)
    server_async <- readLines(file.path(async_dir, "R", "server.R"), warn = FALSE)
    expect_true(any(grepl("async\\(function", server_async)))
    
    # Test sync variant
    sync_dir <- rdesk_create_app("SyncApp", use_async = FALSE, open = FALSE)
    server_sync <- readLines(file.path(sync_dir, "R", "server.R"), warn = FALSE)
    expect_false(any(grepl("async\\(function", server_sync)))
    expect_true(any(grepl("function\\(payload\\)", server_sync)))
  })
})

test_that("duplicate directory prevention works", {
  withr::with_tempdir({
    dir.create("DuplicateApp")
    expect_error(rdesk_create_app("DuplicateApp", open = FALSE), "already exists")
  })
})

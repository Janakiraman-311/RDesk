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
    app_dir <- rdesk_create_app("PlaceholderTest", open = FALSE)
    
    app_r <- readLines(file.path(app_dir, "app.R"), warn = FALSE)
    expect_true(any(grepl("PlaceholderTest", app_r)))
    expect_false(any(grepl("\\{\\{", app_r)))
    
    desc <- readLines(file.path(app_dir, "DESCRIPTION"), warn = FALSE)
    expect_true(any(grepl("DataSource: builtin", desc)))
  })
})

test_that("scaffolded app is correctly structured", {
  withr::with_tempdir({
    app_dir <- rdesk_create_app("ModernDash", open = FALSE)
    
    # Check default async backend use
    server_R <- readLines(file.path(app_dir, "R", "server.R"), warn = FALSE)
    expect_true(any(grepl("async\\(function", server_R)))
    
    # Check KPI presence
    plots_R <- readLines(file.path(app_dir, "R", "plots.R"), warn = FALSE)
    expect_true(any(grepl("get_app_kpis", plots_R)))
  })
})

test_that("duplicate directory prevention works", {
  withr::with_tempdir({
    dir.create("DuplicateApp")
    expect_error(rdesk_create_app("DuplicateApp", open = FALSE), "already exists")
  })
})

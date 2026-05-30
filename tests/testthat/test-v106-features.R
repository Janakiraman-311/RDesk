context("v1.0.6 Core Foundation Features")

test_that("Storage: set, get, keys, remove, and clear work correctly", {
  app_name <- "RDeskTestStorageApp"
  
  # Initialize storage
  storage <- rdesk_storage(app_name, "local")
  expect_true(inherits(storage, "RDeskStorage"))
  
  # Clean slate
  storage$clear()
  expect_equal(length(storage$keys()), 0)
  
  # Test Set and Get
  storage$set("theme", "dark")
  storage$set("notifications", TRUE)
  storage$set("user_id", 42L)
  
  expect_equal(storage$get("theme"), "dark")
  expect_equal(storage$get("notifications"), TRUE)
  expect_equal(storage$get("user_id"), 42L)
  
  # Test Keys
  expect_setequal(storage$keys(), c("theme", "notifications", "user_id"))
  
  # Test Remove
  storage$remove("notifications")
  expect_null(storage$get("notifications"))
  expect_setequal(storage$keys(), c("theme", "user_id"))
  
  # Test Clear
  storage$clear()
  expect_equal(length(storage$keys()), 0)
})

test_that("Storage: resolve_dir automatically handles permission fallbacks", {
  # Mock an unavailable or custom directory path
  storage <- rdesk_storage("TestPermFallback", "shared")
  expect_true(dir.exists(storage$path()))
})

test_that("Async Progress: async_progress writes progress JSON correctly", {
  progress_file <- tempfile(pattern = "test_progress_", fileext = ".json")
  on.exit(unlink(progress_file), add = TRUE)
  
  # Set the option to hook progress file
  withr::with_options(list(rdesk.progress_file = progress_file), {
    res <- async_progress(45, "Computing predictions...")
    expect_true(res)
    
    expect_true(file.exists(progress_file))
    lines <- readLines(progress_file, warn = FALSE)
    expect_length(lines, 1)
    
    data <- jsonlite::fromJSON(lines)
    expect_equal(data$progress, 45)
    expect_equal(data$message, "Computing predictions...")
    expect_true(!is.null(data$timestamp))
  })
})

test_that("Hot Reload: rdesk_hotreload_init and rdesk_hotreload_poll detect changes", {
  # Create a dummy app directory structure
  temp_app <- file.path(tempdir(), "test_hotreload_app")
  dir.create(temp_app, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(temp_app, "R"), showWarnings = FALSE)
  dir.create(file.path(temp_app, "www"), showWarnings = FALSE)
  on.exit(unlink(temp_app, recursive = TRUE), add = TRUE)
  
  # Create a dummy R file
  r_file <- file.path(temp_app, "R", "test.R")
  writeLines("x <- 10", r_file)
  
  # Create a dummy UI file
  ui_file <- file.path(temp_app, "www", "index.html")
  writeLines("<h1>Test</h1>", ui_file)
  
  # Initialize hotreload tracking
  tracking_env <- rdesk_hotreload_init(temp_app)
  expect_true(exists(normalizePath(r_file, mustWork = FALSE), envir = tracking_env))
  expect_true(exists(normalizePath(ui_file, mustWork = FALSE), envir = tracking_env))
  
  # Mock App instance
  mock_app <- R6::R6Class("MockApp",
    public = list(
      ui_reloaded = FALSE,
      toast_msg = NULL,
      get_dir = function() temp_app,
      send = function(type, payload = list()) {
        if (type == "__reload_ui__") {
          self$ui_reloaded <- TRUE
        }
      },
      toast = function(message, type = "info") {
        self$toast_msg <- message
      }
    )
  )$new()
  
  # Poll without changes - nothing should change
  rdesk_hotreload_poll(mock_app, tracking_env)
  expect_false(mock_app$ui_reloaded)
  
  # Modify UI file
  Sys.sleep(1) # Ensure time difference is detectable
  writeLines("<h1>Modified Test</h1>", ui_file)
  
  # Poll again - UI reload should be triggered
  rdesk_hotreload_poll(mock_app, tracking_env)
  expect_true(mock_app$ui_reloaded)
})

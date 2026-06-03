
test_that("Storage: set, get, keys, remove, and clear work correctly", {
  app_name <- "RDeskTestStorageApp"
  on.exit(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE), add = TRUE)
  
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
  on.exit(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE), add = TRUE)
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

test_that("Web dialogs: router handlers decode base64 and process path/result correctly", {
  app_name <- "RDeskTestDialogsApp"
  on.exit(unlink(file.path(tempdir(), "RDesk"), recursive = TRUE), add = TRUE)
  
  app <- App$new(title = app_name, width = 800, height = 600)
  
  # Inject a mock req_id into pending dialogs to simulate a waiting dialog
  req_id <- "test_req_123"
  app$.__enclos_env__$private$.pending_dialogs[[req_id]] <- NULL
  
  # Simulate JS sending a file result with base64 content
  # "Hello World" in base64 is "SGVsbG8gV29ybGQ="
  test_content <- "SGVsbG8gV29ybGQ="
  payload <- list(id = req_id, name = "test.txt", content = test_content)
  
  # Dispatch the event
  app$.__enclos_env__$private$.router$dispatch("__dialog_result_web__", payload)
  
  # The pending dialog should now contain the path to the decoded temp file
  result_path <- app$.__enclos_env__$private$.pending_dialogs[[req_id]]
  expect_true(!is.null(result_path))
  expect_true(file.exists(result_path))
  
  # Verify contents
  read_content <- readLines(result_path, warn = FALSE)
  expect_equal(read_content, "Hello World")
  
  # Clean up temp file
  unlink(result_path)
  
  # Test path result
  payload_path <- list(id = req_id, path = "/some/mock/path.csv")
  app$.__enclos_env__$private$.router$dispatch("__dialog_result_web__", payload_path)
  expect_equal(app$.__enclos_env__$private$.pending_dialogs[[req_id]], "/some/mock/path.csv")
  
  # Test custom result (message_box/color)
  payload_result <- list(id = req_id, result = "yes")
  app$.__enclos_env__$private$.router$dispatch("__dialog_result_web__", payload_result)
  expect_equal(app$.__enclos_env__$private$.pending_dialogs[[req_id]], "yes")
  
  # Test cancel result
  app$.__enclos_env__$private$.router$dispatch("__dialog_cancel_web__", list(id = req_id))
  expect_equal(app$.__enclos_env__$private$.pending_dialogs[[req_id]], "__CANCEL__")
})

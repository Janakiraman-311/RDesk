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
    # Either passes (Rtools present) or fails with a launcher-related message —
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

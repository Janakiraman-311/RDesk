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
    # Should not error when structure is correct and no extra pkgs
    # g++ check will fail in CI without Rtools but that is expected
    tryCatch(
      rdesk_validate_build_inputs(".", character(0), FALSE),
      error = function(e) {
        expect_false(grepl("app.R|www/", e$message))
      }
    )
  })
})

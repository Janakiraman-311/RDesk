library(testthat)
library(RDesk)
library(ggplot2)

test_that("rdesk_plot_to_base64 handles basic ggplot", {
  p <- ggplot(mtcars, aes(x = mpg, y = wt)) + geom_point()
  b64 <- rdesk_plot_to_base64(p)
  
  expect_true(is.character(b64))
  expect_true(grepl("^data:image/png;base64,", b64))
})

test_that("rdesk_plot_to_base64 falls back to error plot on failure", {
  # Create a plot that will cause an error during save (e.g. invalid object)
  p <- "not a plot"
  
  # Should still return a base64 string because it fails over to rdesk_error_plot
  expect_warning(b64 <- rdesk_plot_to_base64(p), "Failed to save plot")
  expect_true(is.character(b64))
  expect_true(grepl("^data:image/png;base64,", b64))
})

test_that("rdesk_error_plot generates valid base64", {
  b64 <- rdesk_error_plot("Custom Error")
  expect_true(is.character(b64))
  expect_true(grepl("^data:image/png;base64,", b64))
})

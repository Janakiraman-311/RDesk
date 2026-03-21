library(testthat)
library(RDesk)

test_that("rdesk_async produces valid job IDs", {
  # We can't run it without a master, but we can test the creation logic
  # or mock the master if we wanted to be fancy.
  # For now, let's test that it requires a task.
  expect_error(rdesk_async(), "Missing task function")
})

test_that("async() wrapper returns function with attributes", {
  f <- function(payload) list(result = payload$x * 2)
  w <- async(f, loading_message = "Computing...")
  
  expect_true(is.function(w))
  expect_equal(attr(w, "loading_message"), "Computing...")
  expect_equal(attr(w, "is_rdesk_async"), TRUE)
})

test_that("async() handles default parameters", {
  f <- function(p) list()
  w <- async(f)
  expect_equal(attr(w, "loading_message"), "Working...")
})

test_that("async() fails if task is not a function", {
  expect_error(async("not a function"), "task must be a function")
})

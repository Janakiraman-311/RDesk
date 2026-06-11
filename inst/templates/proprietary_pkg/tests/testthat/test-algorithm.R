# Tests for {{PKG_NAME}} compiled functions
# These tests run against the compiled .dll/.so
# They verify the algorithm produces correct output

test_that("{{ALGORITHM_NAME}} returns correct output type", {
  # Set a test licence key before testing
  Sys.setenv("{{PKG_NAME}}_LICENCE_KEY" = "TEST_KEY_LOCAL_ONLY")
  on.exit(Sys.unsetenv("{{PKG_NAME}}_LICENCE_KEY"))

  result <- {{ALGORITHM_NAME}}(c(1.0, 2.0, 3.0), multiplier = 2.0)
  expect_type(result, "double")
  expect_length(result, 3L)
})

test_that("{{ALGORITHM_NAME}} fails without licence key", {
  Sys.unsetenv("{{PKG_NAME}}_LICENCE_KEY")
  expect_error(
    {{ALGORITHM_NAME}}(c(1.0, 2.0), multiplier = 1.0),
    "Licence"
  )
})

test_that("validate_structure passes with correct columns", {
  Sys.setenv("{{PKG_NAME}}_LICENCE_KEY" = "TEST_KEY_LOCAL_ONLY")
  on.exit(Sys.unsetenv("{{PKG_NAME}}_LICENCE_KEY"))

  df <- data.frame(ae_term = "Nausea", treatment = "Drug A")
  expect_true(validate_structure(df, c("ae_term", "treatment")))
})

test_that("validate_structure fails with missing column", {
  Sys.setenv("{{PKG_NAME}}_LICENCE_KEY" = "TEST_KEY_LOCAL_ONLY")
  on.exit(Sys.unsetenv("{{PKG_NAME}}_LICENCE_KEY"))

  df <- data.frame(ae_term = "Nausea")
  expect_error(
    validate_structure(df, c("ae_term", "treatment")),
    "treatment"
  )
})

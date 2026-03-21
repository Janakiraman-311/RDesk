library(testthat)
library(RDesk)

test_that("rdesk_launcher_path handles fallbacks", {
  # In this test environment, it might not find the binary, 
  # but it should at least stop() with a message containing 'not found'
  # rather than a syntax error.
  expect_type(rdesk_launcher_path(), "character")
})

test_that("rdesk_resolve_launcher_bin_dir handles source tree", {
  # Mock a source tree
  withr::with_tempdir({
    dir.create("src")
    file.create("src/rdesk-launcher.exe")
    
    bin_dir <- RDesk:::rdesk_resolve_launcher_bin_dir(getwd())
    expect_true(dir.exists(bin_dir))
    expect_true(file.exists(file.path(bin_dir, "rdesk-launcher.exe")))
    expect_true(grepl("rdesk-launcher-bin", bin_dir)) # Should be in tempdir
  })
})

test_that("internal helpers work as expected", {
  # Check rdesk_df_to_list (internal but used in templates)
  df <- data.frame(a = 1:2, b = c("x", "y"))
  res <- RDesk:::rdesk_df_to_list(df)
  expect_named(res, c("rows", "cols"))
  expect_equal(length(res$rows), 2)
  expect_equal(res$cols, c("a", "b"))
})

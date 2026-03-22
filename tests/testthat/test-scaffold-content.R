test_that("scaffolded R code is syntactically valid and runnable", {
  withr::with_tempdir({
    # 1. Create the app
    RDesk::rdesk_create_app("VerifyCode", path = ".", open = FALSE)
    app_dir <- "VerifyCode"
    
    # 2. Verify files exist
    expect_true(dir.exists(file.path(app_dir, "R")))
    expect_true(file.exists(file.path(app_dir, "R", "plots.R")))
    expect_true(file.exists(file.path(app_dir, "R", "data.R")))
    expect_true(file.exists(file.path(app_dir, "R", "server.R")))
    
    # 3. Source the files in a clean environment to check for syntax errors
    # Note: we need ggplot2 and RDesk in search path because template uses them
    library(ggplot2)
    library(RDesk)
    
    env <- new.env(parent = .GlobalEnv)
    expect_no_error(source(file.path(app_dir, "R", "data.R"), local = env))
    expect_no_error(source(file.path(app_dir, "R", "plots.R"), local = env))
    expect_no_error(source(file.path(app_dir, "R", "server.R"), local = env))
    
    # 4. Functional test of the template code
    # init_data() should return mtcars
    expect_true(exists("init_data", envir = env))
    df <- env$init_data()
    expect_s3_class(df, "data.frame")
    
    # make_chart() should return a base64 string
    expect_true(exists("make_chart", envir = env))
    chart <- env$make_chart(df)
    expect_true(is.character(chart))
    expect_true(grepl("^data:image/png;base64,", chart))
  })
})

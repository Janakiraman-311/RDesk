# inst/apps/mtcars_dashboard/R/data.R
# Data loading and KPI logic

init_data <- function(env) {
  env$df       <- mtcars %>% dplyr::mutate(model = rownames(mtcars), .before = 1)
  env$filtered <- env$df
  env$x_var    <- "wt"
  env$y_var    <- "mpg"
  env$cyl_filter <- c(4, 6, 8)
  env$plot_type  <- "scatter"
}

apply_filters <- function(env) {
  env$filtered <- env$df %>%
    dplyr::filter(cyl %in% env$cyl_filter)
}

kpis <- function(df) {
  list(
    n        = nrow(df),
    mean_mpg = round(mean(df$mpg, na.rm = TRUE), 1),
    mean_hp  = round(mean(df$hp, na.rm = TRUE),  1),
    mean_wt  = round(mean(df$wt, na.rm = TRUE) * 1000, 0)  # lbs
  )
}

summary_stats <- function(df) {
  df %>%
    dplyr::group_by(cyl) %>%
    dplyr::summarise(
      count    = dplyr::n(),
      avg_mpg  = round(mean(mpg, na.rm = TRUE), 1),
      avg_hp   = round(mean(hp, na.rm = TRUE), 1),
      avg_wt   = round(mean(wt, na.rm = TRUE), 2),
      .groups  = "drop"
    )
}

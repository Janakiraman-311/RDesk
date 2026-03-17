# inst/apps/mtcars_dashboard/R/data.R
# Data loading and KPI logic

init_data <- function(env) {
  env$df       <- mtcars %>% dplyr::mutate(model = rownames(mtcars), .before = 1)
  env$filtered <- env$df
  env$x_var    <- "wt"
  env$y_var    <- "mpg"
  env$cyl_filter <- c(4, 6, 8)
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

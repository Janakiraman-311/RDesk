# Pure R data profiling functions
# No RDesk dependencies — fully testable in isolation

profile_overview <- function(df) {
  list(
    n_rows        = nrow(df),
    n_cols        = ncol(df),
    n_numeric     = sum(vapply(df, is.numeric, logical(1))),
    n_character   = sum(vapply(df, is.character, logical(1))),
    n_factor      = sum(vapply(df, is.factor, logical(1))),
    n_logical     = sum(vapply(df, is.logical, logical(1))),
    total_missing = sum(is.na(df)),
    pct_missing   = round(sum(is.na(df)) / prod(dim(df)) * 100, 2),
    memory_kb     = round(as.numeric(object.size(df)) / 1024, 1)
  )
}

profile_variables <- function(df) {
  do.call(rbind, lapply(names(df), function(col) {
    x       <- df[[col]]
    is_num  <- is.numeric(x)
    n_miss  <- sum(is.na(x))
    n_uniq  <- length(unique(x[!is.na(x)]))

    data.frame(
      variable    = col,
      type        = class(x)[1],
      n_missing   = n_miss,
      pct_missing = round(n_miss / length(x) * 100, 1),
      n_unique    = n_uniq,
      mean        = if (is_num) round(mean(x, na.rm = TRUE), 3) else NA_real_,
      sd          = if (is_num) round(sd(x,   na.rm = TRUE), 3) else NA_real_,
      min         = if (is_num) round(min(x,  na.rm = TRUE), 3) else NA_real_,
      max         = if (is_num) round(max(x,  na.rm = TRUE), 3) else NA_real_,
      median      = if (is_num) round(median(x, na.rm = TRUE), 3) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

profile_missing <- function(df) {
  missing_df <- data.frame(
    variable    = names(df),
    n_missing   = vapply(df, function(x) sum(is.na(x)), numeric(1)),
    pct_missing = vapply(df, function(x) round(mean(is.na(x)) * 100, 1), numeric(1)),
    stringsAsFactors = FALSE
  )
  missing_df[order(-missing_df$n_missing), ]
}

detect_outliers <- function(df, threshold = 1.5) {
  num_cols <- names(df)[vapply(df, is.numeric, logical(1))]
  if (length(num_cols) == 0) {
    return(data.frame(variable = character(0),
                      n_outliers = integer(0),
                      pct_outliers = numeric(0),
                      lower_bound = numeric(0),
                      upper_bound = numeric(0)))
  }

  do.call(rbind, lapply(num_cols, function(col) {
    x   <- df[[col]][!is.na(df[[col]])]
    q1  <- quantile(x, 0.25)
    q3  <- quantile(x, 0.75)
    iqr <- q3 - q1
    lo  <- q1 - threshold * iqr
    hi  <- q3 + threshold * iqr
    n_out <- sum(x < lo | x > hi)

    data.frame(
      variable     = col,
      n_outliers   = n_out,
      pct_outliers = round(n_out / length(x) * 100, 1),
      lower_bound  = round(lo, 3),
      upper_bound  = round(hi, 3),
      stringsAsFactors = FALSE
    )
  }))
}

get_top_correlations <- function(df, n = 10, method = "pearson") {
  num_df  <- df[, vapply(df, is.numeric, logical(1)), drop = FALSE]
  if (ncol(num_df) < 2) {
    return(data.frame(var1 = character(0), var2 = character(0),
                      correlation = numeric(0)))
  }
  corr_mat <- cor(num_df, use = "pairwise.complete.obs", method = method)
  corr_mat[lower.tri(corr_mat, diag = TRUE)] <- NA

  corr_df <- as.data.frame(as.table(corr_mat))
  corr_df <- corr_df[!is.na(corr_df$Freq), ]
  corr_df <- corr_df[order(-abs(corr_df$Freq)), ]
  colnames(corr_df) <- c("var1", "var2", "correlation")
  corr_df$correlation <- round(corr_df$correlation, 3)
  head(corr_df, n)
}

generate_html_report <- function(payload, path) {
  overview <- payload$data$overview
  n_rows   <- if (!is.null(payload$data$n_rows)) payload$data$n_rows else "Unknown"
  n_cols   <- if (!is.null(payload$data$n_cols)) payload$data$n_cols else "Unknown"
  
  # KPI cards HTML
  kpi_html <- ""
  if (!is.null(overview)) {
    kpi_html <- paste0(
      "<div class='kpi-grid'>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$n_rows, "</div><div class='kpi-lbl'>Total Rows</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$n_cols, "</div><div class='kpi-lbl'>Total Columns</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$n_numeric, "</div><div class='kpi-lbl'>Numeric Columns</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$total_missing, "</div><div class='kpi-lbl'>Missing Cells</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$pct_missing, "%</div><div class='kpi-lbl'>Missing %</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", overview$memory_kb, " KB</div><div class='kpi-lbl'>Memory Size</div></div>",
      "</div>"
    )
  } else {
    kpi_html <- paste0(
      "<div class='kpi-grid'>",
      "  <div class='kpi-card'><div class='kpi-val'>", n_rows, "</div><div class='kpi-lbl'>Total Rows</div></div>",
      "  <div class='kpi-card'><div class='kpi-val'>", n_cols, "</div><div class='kpi-lbl'>Total Columns</div></div>",
      "</div>"
    )
  }

  # Variable Details Table HTML
  table_html <- ""
  if (!is.null(payload$variable_summary) && !is.null(payload$variable_summary$rows)) {
    cols <- payload$variable_summary$cols
    rows <- payload$variable_summary$rows
    
    # Capitalize column names for headers
    display_cols <- tools::toTitleCase(gsub("_", " ", cols))
    headers_html <- paste0("<tr>", paste0("<th>", display_cols, "</th>", collapse = ""), "</tr>")
    
    row_strings <- sapply(rows, function(row) {
      cells <- sapply(cols, function(col) {
        val <- row[[col]]
        if (is.null(val) || is.na(val)) "" else as.character(val)
      })
      paste0("<tr>", paste0("<td>", cells, "</td>", collapse = ""), "</tr>")
    })
    
    table_html <- paste0(
      "<h2>Variable Details</h2>",
      "<div style='overflow-x: auto;'>",
      "  <table>",
      "    <thead>", headers_html, "</thead>",
      "    <tbody>", paste(row_strings, collapse = "\n"), "</tbody>",
      "  </table>",
      "</div>"
    )
  }

  html <- paste0(
    "<!DOCTYPE html>",
    "<html>",
    "<head>",
    "  <meta charset='UTF-8'>",
    "  <title>Data Profile Report: ", payload$filename, "</title>",
    "  <style>",
    "    body { font-family: system-ui, -apple-system, sans-serif; max-width: 1100px; margin: 40px auto; padding: 0 20px; color: #2c3e50; background: #f8f9fa; line-height: 1.5; }",
    "    header { background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%); color: white; padding: 30px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); margin-bottom: 30px; }",
    "    header h1 { margin: 0; font-size: 2.2rem; font-weight: 700; }",
    "    header p { margin: 10px 0 0 0; opacity: 0.9; font-size: 0.95rem; }",
    "    h2 { font-size: 1.5rem; color: #1e3c72; border-bottom: 2px solid #e9ecef; padding-bottom: 8px; margin-top: 40px; }",
    "    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 20px; margin-bottom: 30px; }",
    "    .kpi-card { background: white; padding: 20px; border-radius: 10px; box-shadow: 0 4px 6px rgba(0,0,0,0.02); border: 1px solid #e9ecef; text-align: center; transition: transform 0.2s; }",
    "    .kpi-card:hover { transform: translateY(-3px); }",
    "    .kpi-val { font-size: 1.8rem; font-weight: 700; color: #1e3c72; margin-bottom: 5px; }",
    "    .kpi-lbl { font-size: 0.85rem; color: #6c757d; font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }",
    "    table { border-collapse: collapse; width: 100%; background: white; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 6px rgba(0,0,0,0.02); border: 1px solid #e9ecef; margin-top: 15px; }",
    "    th, td { padding: 12px 15px; text-align: left; font-size: 0.9rem; }",
    "    th { background: #1e3c72; color: white; font-weight: 600; text-transform: uppercase; font-size: 0.8rem; letter-spacing: 0.5px; }",
    "    tr { border-bottom: 1px solid #eee; }",
    "    tr:last-child { border-bottom: none; }",
    "    tr:nth-child(even) { background-color: #fcfdfe; }",
    "    tr:hover { background-color: #f1f5f9; }",
    "  </style>",
    "</head>",
    "<body>",
    "  <header>",
    "    <h1>Data Profile Report</h1>",
    "    <p><strong>Dataset:</strong> ", payload$filename, " &bull; <strong>Generated:</strong> ", format(Sys.time()), "</p>",
    "  </header>",
    "  <h2>Overview</h2>",
    kpi_html,
    table_html,
    "</body>",
    "</html>"
  )
  writeLines(html, path)
}

#' Generate a rich, complex sample dataset for demonstrations
#' @export
generate_sample_data <- function() {
  set.seed(42)
  n <- 500
  
  # Base columns
  customer_id <- paste0("CUST-", 1000 + 1:n)
  age <- sample(18:80, n, replace = TRUE)
  
  # Deliberate outliers in Age
  age[sample(1:n, 5)] <- sample(110:130, 5)
  age[sample(1:n, 2)] <- sample(-10:-5, 2)
  
  contract <- sample(c("Month-to-month", "One year", "Two year"), n, replace = TRUE, prob = c(0.5, 0.3, 0.2))
  internet <- sample(c("DSL", "Fiber optic", "No"), n, replace = TRUE, prob = c(0.4, 0.5, 0.1))
  
  monthly_charges <- round(runif(n, 20, 120), 2)
  # Deliberate outliers in Monthly Charges
  monthly_charges[sample(1:n, 3)] <- sample(500:600, 3)
  
  # Total charges proportional to monthly charges
  total_charges <- round(monthly_charges * sample(1:24, n, replace = TRUE), 2)
  
  # Deliberate missing values
  age[sample(1:n, 12)] <- NA
  monthly_charges[sample(1:n, 15)] <- NA
  total_charges[sample(1:n, 8)] <- NA
  
  satisfaction <- sample(1:5, n, replace = TRUE, prob = c(0.1, 0.15, 0.25, 0.35, 0.15))
  churn <- ifelse(satisfaction <= 2, sample(c("Yes", "No"), n, replace = TRUE, prob = c(0.7, 0.3)),
                  sample(c("Yes", "No"), n, replace = TRUE, prob = c(0.1, 0.9)))
  
  data.frame(
    Customer_ID        = customer_id,
    Age                = age,
    Contract           = contract,
    Internet_Service   = internet,
    Monthly_Charges    = monthly_charges,
    Total_Charges      = total_charges,
    Satisfaction_Score = satisfaction,
    Churn              = churn,
    stringsAsFactors   = FALSE
  )
}

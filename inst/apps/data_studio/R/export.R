# R/export.R
# Scientific HTML report export and clipboard TSV formatting

html_escape <- function(x) {
  if (is.null(x) || length(x) == 0L) return("")
  s <- as.character(x[1L])
  if (is.na(s)) return("")
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s <- gsub("\"", "&quot;", s, fixed = TRUE)
  s
}

render_rdesk_table_html <- function(tbl_list,
                                   title = NULL,
                                   exclude_cols = character(0),
                                   col_labels = NULL,
                                   footnote = NULL) {
  if (is.null(tbl_list) || is.null(tbl_list$rows) || length(tbl_list$rows) == 0L) {
    return("")
  }
  cols <- setdiff(unlist(tbl_list$cols), exclude_cols)
  if (length(cols) == 0L) return("")
  rows <- tbl_list$rows

  display_cols <- vapply(cols, function(c) {
    lbl <- if (!is.null(col_labels) && c %in% names(col_labels)) {
      col_labels[[c]]
    } else {
      tools::toTitleCase(gsub("_", " ", c))
    }
    html_escape(lbl)
  }, character(1))

  headers_html <- paste0("<tr>", paste0("<th>", display_cols, "</th>", collapse = ""), "</tr>")

  row_strings <- vapply(rows, function(row) {
    cells <- vapply(cols, function(col) {
      val <- row[[col]]
      if (is.null(val) || length(val) == 0L || is.na(val[1L]) || !nzchar(as.character(val[1L]))) {
        "--"
      } else {
        html_escape(val[1L])
      }
    }, character(1))
    paste0("<tr>", paste0("<td>", cells, "</td>", collapse = ""), "</tr>")
  }, character(1))

  heading <- if (!is.null(title) && nzchar(title)) {
    paste0("<h2>", html_escape(title), "</h2>")
  } else {
    ""
  }

  foot_html <- if (!is.null(footnote) && nzchar(footnote)) {
    paste0("<div class='table-footnote'>", html_escape(footnote), "</div>")
  } else {
    ""
  }

  paste0(
    heading,
    "<div class='table-wrap'><table><thead>",
    headers_html,
    "</thead><tbody>",
    paste(row_strings, collapse = "\n"),
    "</tbody></table>",
    foot_html,
    "</div>"
  )
}

render_chart_section_html <- function(src, title) {
  if (is.null(src) || length(src) == 0L || !nzchar(as.character(src[1L]))) {
    return("")
  }
  s <- as.character(src[1L])
  if (!grepl("^data:image/", s)) {
    s <- paste0("data:image/png;base64,", s)
  }
  paste0(
    "<h2>", html_escape(title), "</h2>",
    "<div class='chart-box'><img src='", s, "' alt='", html_escape(title), "' /></div>"
  )
}

generate_html_report <- function(payload, path) {
  data_obj <- if (!is.null(payload$data)) payload$data else list()
  overview <- data_obj$overview
  filename <- if (!is.null(payload$filename) && nzchar(payload$filename)) {
    payload$filename
  } else if (!is.null(data_obj$filename) && nzchar(data_obj$filename)) {
    data_obj$filename
  } else {
    "dataset"
  }

  kpi_html <- ""
  if (!is.null(overview)) {
    comp_val <- if (!is.null(overview$pct_complete_fmt) && nzchar(as.character(overview$pct_complete_fmt))) {
      overview$pct_complete_fmt
    } else if (exists("fmt_pct", mode = "function")) {
      fmt_pct(as.numeric(overview$pct_complete_cases), 1L)
    } else {
      paste0(overview$pct_complete_cases, "%")
    }

    miss_val <- if (!is.null(overview$pct_missing_fmt) && nzchar(as.character(overview$pct_missing_fmt))) {
      overview$pct_missing_fmt
    } else if (exists("fmt_pct", mode = "function")) {
      fmt_pct(as.numeric(overview$pct_missing), 2L)
    } else {
      paste0(overview$pct_missing, "%")
    }

    kpis <- list(
      list(label = "Subjects / Rows",    val = overview$n_rows),
      list(label = "Complete Cases",     val = comp_val),
      list(label = "Variables (Num/Cat)", val = paste0(overview$n_numeric, " / ", overview$n_categorical)),
      list(label = if (!is.null(overview$primary_metric_label)) overview$primary_metric_label else "Primary Signal",
           val   = if (!is.null(overview$primary_metric_value)) overview$primary_metric_value else "N/A"),
      list(label = "Missing Data Rate",  val = miss_val),
      list(label = "Outlier Flags",      val = if (!is.null(overview$total_outliers)) overview$total_outliers else 0)
    )
    cards <- vapply(kpis, function(k) {
      paste0(
        "<div class='kpi-card'>",
        "<div class='kpi-lbl'>", html_escape(k$label), "</div>",
        "<div class='kpi-val'>", html_escape(k$val), "</div>",
        "</div>"
      )
    }, character(1))
    kpi_html <- paste0("<div class='kpi-grid'>", paste(cards, collapse = ""), "</div>")
  }

  overview_chart_html <- render_chart_section_html(data_obj$preview_chart, "Completeness & Quality Audit")
  dist_chart_html     <- render_chart_section_html(data_obj$dist_charts, "Variable Distribution Explorer")
  corr_chart_html     <- render_chart_section_html(data_obj$corr_chart, "Correlation Matrix")
  corr_table_html     <- render_rdesk_table_html(
    data_obj$top_corr,
    "Top Pairwise Correlations (with Benjamini-Hochberg FDR)",
    exclude_cols = c("r", "p_num", "p_adj_num"),
    col_labels = c(
      var1 = "Variable 1", var2 = "Variable 2", r_fmt = "Estimate (r)",
      ci_95 = "95% CI", p_value = "p (Nominal)", p_adj_bh = "FDR q (BH)",
      n_pairs = "Pairs (n)", strength = "Strength", note = "Coupling"
    ),
    footnote = "FDR q-values adjusted via Benjamini-Hochberg across all evaluated numeric pairs. Pairs marked 'Coupled' share a mathematical derivation (e.g., Week-12 change = Week-12 - Baseline)."
  )
  outlier_chart_html  <- render_chart_section_html(data_obj$outlier_chart, "Tukey IQR Outlier Audit")
  outlier_table_html  <- render_rdesk_table_html(
    data_obj$outlier_table,
    "Outlier Summary Table",
    exclude_cols = c("pct_outliers", "lower_bound", "upper_bound"),
    col_labels = c(
      variable = "Variable", n_valid = "Valid N", n_outliers = "Outliers",
      pct_outliers_fmt = "Rate (%)", lower_fmt = "Lower Fence", upper_fmt = "Upper Fence",
      flagged_rows = "Flagged Row Indices"
    )
  )
  var_summary         <- if (!is.null(payload$variable_summary)) payload$variable_summary else data_obj$variable_summary
  var_table_html      <- render_rdesk_table_html(
    var_summary,
    "Variable Dictionary",
    exclude_cols = c("pct_missing", "mean", "sd", "median", "iqr", "min", "max"),
    col_labels = c(
      variable = "Variable", type = "Type", n_valid = "Valid N",
      n_missing = "Missing", pct_missing_fmt = "Missing (%)",
      n_unique = "Unique", mean_sd = "Mean +/- SD / Top Level",
      median_iqr = "Median [Q1, Q3]", min_fmt = "Min", max_fmt = "Max"
    )
  )
  subgroup_foot       <- if (!is.null(data_obj$subgroup_footnote)) as.character(data_obj$subgroup_footnote[1L]) else ""
  subgroup_table_html <- render_rdesk_table_html(
    data_obj$subgroup_table,
    "Subgroup Comparison (Table 1)",
    footnote = subgroup_foot
  )

  html <- paste0(
    "<!DOCTYPE html>\n<html lang='en'>\n<head>\n",
    "  <meta charset='UTF-8'>\n",
    "  <title>Clinical & Biostatistical Profile Report: ", html_escape(filename), "</title>\n",
    "  <style>\n",
    "    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Inter, Roboto, sans-serif; max-width: 1120px; margin: 36px auto; padding: 0 24px; color: #0F172A; background: #F8FAFC; line-height: 1.5; font-variant-numeric: tabular-nums; }\n",
    "    header { background: #0F172A; color: #F8FAFC; padding: 28px 32px; border-radius: 10px; border-left: 5px solid #0F766E; margin-bottom: 28px; }\n",
    "    header .eyebrow { font-size: 11px; text-transform: uppercase; letter-spacing: 0.12em; color: #5EEAD4; font-weight: 600; margin-bottom: 6px; }\n",
    "    header h1 { margin: 0; font-size: 24px; font-weight: 700; letter-spacing: -0.02em; }\n",
    "    header p { margin: 8px 0 0 0; color: #94A3B8; font-size: 13px; }\n",
    "    h2 { font-size: 16px; color: #0F172A; border-bottom: 1px solid #CBD5E1; padding-bottom: 6px; margin-top: 32px; margin-bottom: 14px; font-weight: 700; }\n",
    "    .kpi-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(165px, 1fr)); gap: 12px; margin-bottom: 24px; }\n",
    "    .kpi-card { background: #FFFFFF; padding: 14px 16px; border-radius: 8px; border: 1px solid #DDE3EC; border-top: 3px solid #0F766E; }\n",
    "    .kpi-lbl { font-size: 11px; color: #526071; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; margin-bottom: 6px; }\n",
    "    .kpi-val { font-size: 22px; font-weight: 700; color: #0F172A; }\n",
    "    .chart-box { background: #FFFFFF; border: 1px solid #DDE3EC; border-radius: 8px; padding: 14px; text-align: center; margin-bottom: 18px; }\n",
    "    .chart-box img { max-width: 100%; height: auto; }\n",
    "    .table-wrap { overflow-x: auto; background: #FFFFFF; border: 1px solid #DDE3EC; border-radius: 8px; margin-bottom: 18px; }\n",
    "    table { border-collapse: collapse; width: 100%; font-size: 13px; }\n",
    "    th, td { padding: 9px 12px; text-align: left; border-bottom: 1px solid #E5EAF0; }\n",
    "    th { background: #F1F5F9; color: #334155; font-weight: 600; font-size: 11px; text-transform: uppercase; letter-spacing: 0.04em; }\n",
    "    tr:last-child td { border-bottom: none; }\n",
    "    tr:nth-child(even) td { background: #FAFBFD; }\n",
    "    .table-footnote { padding: 10px 14px; font-size: 12px; color: #475569; background: #F8FAFC; border-top: 1px solid #E5EAF0; line-height: 1.45; }\n",
    "    footer { margin-top: 36px; padding-top: 14px; border-top: 1px solid #DDE3EC; font-size: 12px; color: #64748B; }\n",
    "  </style>\n</head>\n<body>\n",
    "  <header>\n",
    "    <div class='eyebrow'>Data Intelligence Studio &bull; Clinical &amp; Biostatistical Report</div>\n",
    "    <h1>", html_escape(filename), "</h1>\n",
    "    <p>Generated: ", html_escape(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")), "</p>\n",
    "  </header>\n",
    "  <h2>Cohort Overview &amp; Quality Metrics</h2>\n",
    kpi_html,
    overview_chart_html,
    dist_chart_html,
    corr_chart_html,
    corr_table_html,
    outlier_chart_html,
    outlier_table_html,
    var_table_html,
    subgroup_table_html,
    "  <footer>Generated by Data Intelligence Studio (RDesk). Biostatistical standards: ANCOVA primary change-from-baseline model, log-scale PK Geometric Mean Ratio (GMR), ITT-NRI and Observed Case responder summaries, Benjamini-Hochberg FDR correlation control, and SAS half-away-from-zero single-stage display rounding with fixed trailing zeros.</footer>\n",
    "</body>\n</html>\n"
  )

  writeLines(html, path, useBytes = TRUE)
  invisible(path)
}

#' Format a data.frame or rdesk_df_to_list() object as Tab-Separated Values (TSV)
format_table_tsv <- function(tbl) {
  if (is.null(tbl)) return("")

  if (is.data.frame(tbl)) {
    if (nrow(tbl) == 0L) return("")
    hdr <- paste(names(tbl), collapse = "\t")
    body <- apply(tbl, 1L, function(r) {
      vals <- ifelse(is.na(r), "", as.character(r))
      paste(vals, collapse = "\t")
    })
    return(paste(c(hdr, body), collapse = "\n"))
  }

  if (is.list(tbl) && !is.null(tbl$cols) && !is.null(tbl$rows) && length(tbl$rows) > 0L) {
    cols <- unlist(tbl$cols)
    hdr  <- paste(cols, collapse = "\t")
    body <- vapply(tbl$rows, function(row) {
      vals <- vapply(cols, function(col) {
        v <- row[[col]]
        if (is.null(v) || length(v) == 0L || is.na(v[1L])) "" else as.character(v[1L])
      }, character(1))
      paste(vals, collapse = "\t")
    }, character(1))
    return(paste(c(hdr, body), collapse = "\n"))
  }

  ""
}

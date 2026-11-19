# Pure R biostatistical profiling and built-in clinical cohort generators
# Uses only base R (stats, utils) - fully testable in isolation

# ── Built-in Deterministic Scientific Datasets ──────────────────────────────

#' Generate Phase III Cardio-Metabolic Clinical Trial Cohort (n = 480)
#'
#' Deterministic synthetic cohort (set.seed(42)) across Placebo, Low-Dose 10mg,
#' and High-Dose 25mg treatment arms with realistic correlations, clinical
#' efficacy signals, right-skewed biomarkers, outliers, and missing values.
generate_clinical_trial_data <- function() {
  set.seed(42)
  n <- 480L
  arms <- c("Placebo", "Low-Dose 10mg", "High-Dose 25mg")
  treatment_arm <- rep(arms, each = n / 3L)
  treatment_arm <- sample(treatment_arm, n, replace = FALSE)

  subject_id <- sprintf("CMT-%04d", seq_len(n))

  site_region <- sample(
    c("North America", "Western Europe", "Asia-Pacific", "Latin America"),
    n,
    replace = TRUE,
    prob = c(0.38, 0.30, 0.20, 0.12)
  )

  # Demographics & baseline anthropometrics
  age <- round(pmin(84, pmax(36, stats::rnorm(n, mean = 61.4, sd = 9.1))), 1)
  bmi <- round(pmin(48, pmax(19.5, stats::rnorm(n, mean = 29.8, sd = 4.4) +
    stats::rexp(n, rate = 1.2) * 0.9)), 1)

  # Baseline SBP modestly associated with age & BMI
  baseline_sbp <- round(
    118 + 0.34 * age + 0.36 * bmi + stats::rnorm(n, mean = 0, sd = 9.2),
    1
  )

  # Dose-dependent SBP reduction at Week 12
  arm_effect <- ifelse(
    treatment_arm == "High-Dose 25mg", -18.4,
    ifelse(treatment_arm == "Low-Dose 10mg", -11.2, -3.1)
  )
  # Baseline regression-to-mean plus patient-level heterogeneity
  sbp_delta_raw <- arm_effect - 0.12 * (baseline_sbp - 148) +
    stats::rnorm(n, mean = 0, sd = 7.8)
  week12_sbp <- round(pmax(88, baseline_sbp + sbp_delta_raw), 1)

  # Lipid & glycemic cardio-metabolic biomarkers
  ldl_effect <- ifelse(
    treatment_arm == "High-Dose 25mg", -14.5,
    ifelse(treatment_arm == "Low-Dose 10mg", -7.0, 0.5)
  )
  ldl_mg_dl <- round(
    pmax(52, 92 + 1.15 * bmi + ldl_effect + stats::rnorm(n, mean = 0, sd = 24.5)),
    1
  )

  hba1c_effect <- ifelse(
    treatment_arm == "High-Dose 25mg", -0.45,
    ifelse(treatment_arm == "Low-Dose 10mg", -0.22, 0.02)
  )
  hba1c_pct <- round(
    pmax(4.6, 4.35 + 0.082 * bmi + hba1c_effect + stats::rnorm(n, mean = 0, sd = 0.72)),
    2
  )

  # Right-skewed high-sensitivity CRP (mg/L) with anti-inflammatory dose response
  crp_log_shift <- ifelse(
    treatment_arm == "High-Dose 25mg", -0.38,
    ifelse(treatment_arm == "Low-Dose 10mg", -0.18, 0.0)
  )
  crp_mg_l <- round(
    exp(0.55 + 0.028 * (bmi - 28) + crp_log_shift + stats::rnorm(n, mean = 0, sd = 0.62)),
    2
  )

  # Renal function eGFR negatively correlated with age
  eGFR <- round(
    pmin(125, pmax(24, 126 - 0.82 * age + stats::rnorm(n, mean = 0, sd = 12.5))),
    1
  )

  # Realistic clinical extreme values / lab outliers
  bmi[c(14, 118, 297)] <- c(52.4, 54.8, 51.9)
  week12_sbp[c(27, 205, 389)] <- c(204.5, 198.2, 82.0)
  ldl_mg_dl[c(41, 163, 312, 422)] <- c(268.0, 281.5, 259.4, 274.2)
  hba1c_pct[c(73, 249, 411)] <- c(11.8, 12.4, 11.5)
  crp_mg_l[c(19, 95, 214, 338, 445)] <- c(24.6, 31.2, 27.8, 19.9, 28.4)
  eGFR[c(88, 366)] <- c(18.5, 21.0)

  # Primary efficacy endpoint: Week 12 change from baseline
  sbp_change <- round(week12_sbp - baseline_sbp, 1)

  # Realistic clinical missingness (missed Week 12 visits & hemolyzed lab draws)
  miss_w12 <- sample(seq_len(n), 18)
  week12_sbp[miss_w12] <- NA_real_
  sbp_change[miss_w12] <- NA_real_

  crp_mg_l[sample(seq_len(n), 22)] <- NA_real_
  ldl_mg_dl[sample(seq_len(n), 14)] <- NA_real_
  hba1c_pct[sample(seq_len(n), 11)] <- NA_real_
  eGFR[sample(seq_len(n), 9)] <- NA_real_
  bmi[sample(seq_len(n), 6)] <- NA_real_

  # Clinical responder status (>= 10 mmHg reduction or < 130 mmHg achieved)
  responder_status <- ifelse(
    is.na(sbp_change), NA_character_,
    ifelse(sbp_change <= -10 | week12_sbp < 130, "Responder", "Non-Responder")
  )

  data.frame(
    subject_id       = subject_id,
    treatment_arm    = treatment_arm,
    site_region      = site_region,
    age              = age,
    bmi              = bmi,
    baseline_sbp     = baseline_sbp,
    week12_sbp       = week12_sbp,
    sbp_change       = sbp_change,
    ldl_mg_dl        = ldl_mg_dl,
    hba1c_pct        = hba1c_pct,
    crp_mg_l         = crp_mg_l,
    eGFR             = eGFR,
    responder_status = responder_status,
    stringsAsFactors = FALSE
  )
}

#' Generate Pharmacokinetics & Biomarker Longitudinal Assay (n = 360)
generate_pk_biomarker_data <- function() {
  set.seed(42)
  n <- 360L
  cohorts <- c("50 mg QD", "150 mg QD", "300 mg QD")
  dose_cohort <- sample(rep(cohorts, each = n / 3L), n, replace = FALSE)
  dose_mg <- ifelse(dose_cohort == "300 mg QD", 300,
             ifelse(dose_cohort == "150 mg QD", 150, 50))

  sample_id <- sprintf("PKB-%04d", seq_len(n))
  sex <- sample(c("Female", "Male"), n, replace = TRUE, prob = c(0.51, 0.49))

  # Serum creatinine (mg/dL), slightly higher in Male
  renal_creatinine <- round(
    pmax(0.45, ifelse(sex == "Male", 1.02, 0.82) + stats::rnorm(n, mean = 0, sd = 0.18)),
    2
  )

  # Apparent clearance CL/F (L/hr) inversely associated with creatinine
  clearance_l_hr <- round(
    pmax(1.8, 12.6 - 3.4 * renal_creatinine + stats::rnorm(n, mean = 0, sd = 1.65)),
    2
  )

  # Terminal half-life (hr) inversely related to clearance
  half_life_hr <- round(
    pmax(4.5, 19.2 - 0.68 * clearance_l_hr + stats::rnorm(n, mean = 0, sd = 1.45)),
    2
  )

  # Exposure AUC_0_24 (ng*hr/mL) ~ Dose / Clearance * scale
  auc_0_24 <- round(
    (dose_mg / clearance_l_hr) * 145 * exp(stats::rnorm(n, mean = 0, sd = 0.16)),
    1
  )

  # Peak concentration Cmax (ng/mL) tightly correlated with AUC
  cmax_ng_ml <- round(
    auc_0_24 * (0.092 + stats::rnorm(n, mean = 0, sd = 0.014)),
    1
  )

  # Inflammatory cytokine IL-6 (pg/mL) suppressed by drug exposure (Emax-like)
  il6_suppression <- 1.15 * (auc_0_24 / (auc_0_24 + 1600))
  biomarker_il6 <- round(
    exp(2.15 - il6_suppression + stats::rnorm(n, mean = 0, sd = 0.48)),
    2
  )

  # Hepatic ALT (U/L) with modest high-dose elevation
  hepatic_alt <- round(
    exp(3.12 + 0.00075 * dose_mg + stats::rnorm(n, mean = 0, sd = 0.34)),
    1
  )

  # Realistic assay outliers (poor metabolizers, cytokine flares, Grade 2/3 ALT)
  cmax_ng_ml[c(17, 144, 289)] <- c(1180.5, 1245.0, 1095.2)
  auc_0_24[c(17, 144, 289)] <- c(11420.0, 12180.5, 10640.0)
  biomarker_il6[c(33, 185, 299, 341)] <- c(42.8, 55.1, 38.9, 49.4)
  hepatic_alt[c(61, 172, 260, 319)] <- c(148.0, 182.5, 134.2, 165.0)
  renal_creatinine[c(94, 241)] <- c(2.45, 2.68)

  # Realistic bioanalytical missingness (BLQ / insufficient sample volume)
  biomarker_il6[sample(seq_len(n), 15)] <- NA_real_
  hepatic_alt[sample(seq_len(n), 10)] <- NA_real_
  half_life_hr[sample(seq_len(n), 12)] <- NA_real_
  auc_0_24[sample(seq_len(n), 8)] <- NA_real_
  renal_creatinine[sample(seq_len(n), 6)] <- NA_real_

  data.frame(
    sample_id        = sample_id,
    dose_cohort      = dose_cohort,
    sex              = sex,
    cmax_ng_ml       = cmax_ng_ml,
    auc_0_24         = auc_0_24,
    half_life_hr     = half_life_hr,
    clearance_l_hr   = clearance_l_hr,
    biomarker_il6    = biomarker_il6,
    hepatic_alt      = hepatic_alt,
    renal_creatinine = renal_creatinine,
    stringsAsFactors = FALSE
  )
}

#' Preset metadata registry
get_preset_meta <- function(preset = "cardio_trial") {
  presets <- list(
    cardio_trial = list(
      id          = "cardio_trial",
      label       = "Phase III Cardio-Metabolic Clinical Trial",
      short_label = "Phase III Cardio-Metabolic",
      filename    = "phase3_cardio_metabolic_cohort.csv",
      subtitle    = "n = 480 subjects across 3 randomized treatment arms"
    ),
    pk_biomarker = list(
      id          = "pk_biomarker",
      label       = "Pharmacokinetics & Biomarker Longitudinal Assay",
      short_label = "PK & Biomarker Assay",
      filename    = "pk_biomarker_longitudinal_assay.csv",
      subtitle    = "n = 360 bioanalytical observations across 3 dose cohorts"
    )
  )
  if (!is.character(preset) || length(preset) != 1L || !(preset %in% names(presets))) {
    preset <- "cardio_trial"
  }
  presets[[preset]]
}

#' Load a named built-in scientific preset dataset
load_preset_dataset <- function(preset = "cardio_trial") {
  if (identical(preset, "pk_biomarker")) {
    generate_pk_biomarker_data()
  } else {
    generate_clinical_trial_data()
  }
}

#' Backwards-compatible sample dataset generator
generate_sample_data <- function() {
  generate_clinical_trial_data()
}

# ── Statistical Helpers ─────────────────────────────────────────────────────

format_p_value <- function(p) {
  if (is.null(p) || length(p) == 0L || is.na(p) || !is.finite(p)) {
    return("N/A")
  }
  if (p < 0.0001) return("< 0.0001")
  if (p < 0.001)  return(sprintf("%.4f", p))
  sprintf("%.3f", p)
}

compute_skewness <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3L) return(NA_real_)
  s <- stats::sd(x)
  if (is.na(s) || s == 0) return(0)
  m <- mean(x)
  round(mean(((x - m) / s)^3), 3)
}

compute_shapiro_p <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3L || length(unique(x)) < 2L) return(NA_real_)
  if (n > 5000L) {
    set.seed(42)
    x <- sample(x, 5000L)
  }
  tryCatch(
    as.numeric(stats::shapiro.test(x)$p.value),
    error = function(e) NA_real_
  )
}

get_numeric_cols <- function(df) {
  names(df)[vapply(df, is.numeric, logical(1))]
}

get_categorical_cols <- function(df, max_levels = 15L) {
  cols <- names(df)
  keep <- vapply(cols, function(col) {
    x <- df[[col]]
    if (is.numeric(x)) return(FALSE)
    vals <- x[!is.na(x)]
    n_u <- length(unique(vals))
    n_u >= 2L && n_u <= max_levels
  }, logical(1))
  cols[keep]
}

pick_default_var <- function(df) {
  num_cols <- get_numeric_cols(df)
  if (length(num_cols) == 0L) return("")
  preferred <- c("sbp_change", "auc_0_24", "week12_sbp", "cmax_ng_ml")
  hit <- intersect(preferred, num_cols)
  if (length(hit) > 0L) hit[1L] else num_cols[1L]
}

pick_default_group <- function(df) {
  cat_cols <- get_categorical_cols(df, max_levels = 8L)
  if (length(cat_cols) == 0L) return("")
  preferred <- c("treatment_arm", "dose_cohort", "responder_status", "site_region", "sex")
  hit <- intersect(preferred, cat_cols)
  if (length(hit) > 0L) hit[1L] else cat_cols[1L]
}

compute_primary_signal <- function(df, top_corr = NULL) {
  # Clinical Trial primary endpoint: High-Dose 25mg vs Placebo SBP change
  if (all(c("treatment_arm", "sbp_change") %in% names(df))) {
    hi <- df$sbp_change[df$treatment_arm == "High-Dose 25mg"]
    pl <- df$sbp_change[df$treatment_arm == "Placebo"]
    hi <- hi[is.finite(hi)]
    pl <- pl[is.finite(pl)]
    if (length(hi) >= 3L && length(pl) >= 3L) {
      diff_val <- mean(hi) - mean(pl)
      p_val <- tryCatch(stats::t.test(hi, pl)$p.value, error = function(e) NA_real_)
      return(list(
        label = "Primary Endpoint (SBP)",
        value = sprintf("%+.1f mmHg", diff_val),
        sub   = paste0("High-Dose vs Placebo (p ", ifelse(is.na(p_val), "N/A",
                        ifelse(p_val < 0.0001, "< 0.0001", paste("=", format_p_value(p_val)))), ")")
      ))
    }
  }

  # PK Assay primary signal: 300mg vs 50mg AUC exposure ratio
  if (all(c("dose_cohort", "auc_0_24") %in% names(df))) {
    hi <- df$auc_0_24[df$dose_cohort == "300 mg QD"]
    lo <- df$auc_0_24[df$dose_cohort == "50 mg QD"]
    hi <- hi[is.finite(hi)]
    lo <- lo[is.finite(lo)]
    if (length(hi) >= 3L && length(lo) >= 3L && mean(lo) > 0) {
      ratio <- mean(hi) / mean(lo)
      p_val <- tryCatch(stats::t.test(hi, lo)$p.value, error = function(e) NA_real_)
      return(list(
        label = "Dose Exposure Ratio",
        value = sprintf("%.2fx AUC", ratio),
        sub   = paste0("300mg vs 50mg QD (p ", ifelse(is.na(p_val), "N/A",
                        ifelse(p_val < 0.0001, "< 0.0001", paste("=", format_p_value(p_val)))), ")")
      ))
    }
  }

  # General dataset fallback: strongest pairwise correlation
  if (is.null(top_corr)) {
    top_corr <- get_top_correlations(df, n = 5L, method = "pearson")
  }
  if (!is.null(top_corr) && nrow(top_corr) > 0L) {
    r_val <- top_corr$r[1L]
    return(list(
      label = "Top Correlation",
      value = sprintf("r = %.2f", r_val),
      sub   = paste0(top_corr$var1[1L], " vs ", top_corr$var2[1L])
    ))
  }

  list(
    label = "Primary Signal",
    value = "N/A",
    sub   = "Requires >= 2 numeric vars"
  )
}

# ── Core Profiling Functions ────────────────────────────────────────────────

profile_overview <- function(df, top_corr = NULL, outlier_table = NULL) {
  n_rows <- nrow(df)
  n_cols <- ncol(df)
  n_numeric   <- sum(vapply(df, is.numeric, logical(1)))
  n_character <- sum(vapply(df, is.character, logical(1)))
  n_factor    <- sum(vapply(df, is.factor, logical(1)))
  n_logical   <- sum(vapply(df, is.logical, logical(1)))
  n_categorical <- n_cols - n_numeric

  total_cells   <- max(1, as.numeric(n_rows) * as.numeric(n_cols))
  total_missing <- sum(is.na(df))
  pct_missing   <- round(total_missing / total_cells * 100, 2)

  complete_n   <- if (n_rows > 0L) sum(stats::complete.cases(df)) else 0L
  pct_complete <- if (n_rows > 0L) round(complete_n / n_rows * 100, 1) else 0

  signal <- compute_primary_signal(df, top_corr = top_corr)

  total_outliers <- 0L
  vars_with_outliers <- 0L
  if (!is.null(outlier_table) && nrow(outlier_table) > 0L) {
    total_outliers <- as.integer(sum(outlier_table$n_outliers, na.rm = TRUE))
    vars_with_outliers <- as.integer(sum(outlier_table$n_outliers > 0, na.rm = TRUE))
  }

  list(
    n_rows               = n_rows,
    n_cols               = n_cols,
    n_numeric            = n_numeric,
    n_categorical        = n_categorical,
    n_character          = n_character,
    n_factor             = n_factor,
    n_logical            = n_logical,
    complete_cases       = complete_n,
    pct_complete_cases   = pct_complete,
    total_missing        = total_missing,
    pct_missing          = pct_missing,
    memory_kb            = round(as.numeric(utils::object.size(df)) / 1024, 1),
    primary_metric_label = signal$label,
    primary_metric_value = signal$value,
    primary_metric_sub   = signal$sub,
    total_outliers       = total_outliers,
    vars_with_outliers   = vars_with_outliers
  )
}

profile_variables <- function(df) {
  if (ncol(df) == 0L) {
    return(data.frame(
      variable = character(0), type = character(0), n_valid = integer(0),
      n_missing = integer(0), pct_missing = numeric(0), n_unique = integer(0),
      mean_sd = character(0), median_iqr = character(0),
      mean = numeric(0), sd = numeric(0), median = numeric(0), iqr = numeric(0),
      min = numeric(0), max = numeric(0),
      stringsAsFactors = FALSE
    ))
  }

  do.call(rbind, lapply(names(df), function(col) {
    x       <- df[[col]]
    is_num  <- is.numeric(x)
    n_tot   <- length(x)
    n_miss  <- sum(is.na(x))
    n_valid <- n_tot - n_miss
    valid_x <- x[!is.na(x)]
    n_uniq  <- length(unique(valid_x))

    if (is_num && length(valid_x) > 0L) {
      m_val   <- mean(valid_x)
      sd_val  <- if (length(valid_x) > 1L) stats::sd(valid_x) else 0
      med_val <- stats::median(valid_x)
      q1_val  <- as.numeric(stats::quantile(valid_x, 0.25, names = FALSE))
      q3_val  <- as.numeric(stats::quantile(valid_x, 0.75, names = FALSE))
      iqr_val <- q3_val - q1_val
      min_val <- min(valid_x)
      max_val <- max(valid_x)

      mean_sd_str    <- sprintf("%.2f +/- %.2f", m_val, sd_val)
      median_iqr_str <- sprintf("%.2f [%.2f, %.2f]", med_val, q1_val, q3_val)
      type_label     <- "Numeric"
    } else {
      m_val <- sd_val <- med_val <- iqr_val <- min_val <- max_val <- NA_real_
      if (length(valid_x) > 0L) {
        tab <- sort(table(valid_x), decreasing = TRUE)
        top_name <- names(tab)[1L]
        top_pct  <- round(as.numeric(tab[1L]) / length(valid_x) * 100, 1)
        mean_sd_str <- if (n_uniq <= 20L) {
          sprintf("%s (%.1f%%)", top_name, top_pct)
        } else {
          sprintf("%d distinct values", n_uniq)
        }
        median_iqr_str <- if (n_uniq <= 8L) {
          paste0(n_uniq, " levels")
        } else {
          "Identifier / High-card."
        }
      } else {
        mean_sd_str    <- "All missing"
        median_iqr_str <- "--"
      }
      type_label <- if (is.factor(x)) "Factor" else if (is.logical(x)) "Logical" else "Categorical"
    }

    data.frame(
      variable    = col,
      type        = type_label,
      n_valid     = as.integer(n_valid),
      n_missing   = as.integer(n_miss),
      pct_missing = if (n_tot > 0L) round(n_miss / n_tot * 100, 1) else 0,
      n_unique    = as.integer(n_uniq),
      mean_sd     = mean_sd_str,
      median_iqr  = median_iqr_str,
      mean        = if (is.na(m_val)) NA_real_ else round(m_val, 3),
      sd          = if (is.na(sd_val)) NA_real_ else round(sd_val, 3),
      median      = if (is.na(med_val)) NA_real_ else round(med_val, 3),
      iqr         = if (is.na(iqr_val)) NA_real_ else round(iqr_val, 3),
      min         = if (is.na(min_val)) NA_real_ else round(min_val, 3),
      max         = if (is.na(max_val)) NA_real_ else round(max_val, 3),
      stringsAsFactors = FALSE
    )
  }))
}

profile_missing <- function(df) {
  n_rows <- nrow(df)
  missing_df <- data.frame(
    variable     = names(df),
    n_missing    = vapply(df, function(x) sum(is.na(x)), numeric(1)),
    pct_missing  = vapply(df, function(x) {
      if (length(x) == 0L) 0 else round(mean(is.na(x)) * 100, 2)
    }, numeric(1)),
    pct_complete = vapply(df, function(x) {
      if (length(x) == 0L) 100 else round(mean(!is.na(x)) * 100, 2)
    }, numeric(1)),
    n_observed   = vapply(df, function(x) sum(!is.na(x)), numeric(1)),
    n_total      = rep(n_rows, ncol(df)),
    stringsAsFactors = FALSE
  )
  rownames(missing_df) <- NULL
  missing_df[order(-missing_df$pct_missing, missing_df$variable), , drop = FALSE]
}

detect_outliers <- function(df, threshold = 1.5) {
  num_cols <- get_numeric_cols(df)
  if (length(num_cols) == 0L) {
    return(data.frame(
      variable = character(0), n_valid = integer(0), n_outliers = integer(0),
      pct_outliers = numeric(0), lower_bound = numeric(0), upper_bound = numeric(0),
      flagged_rows = character(0),
      stringsAsFactors = FALSE
    ))
  }

  res <- do.call(rbind, lapply(num_cols, function(col) {
    raw_x <- df[[col]]
    valid_idx <- which(!is.na(raw_x) & is.finite(raw_x))
    x <- raw_x[valid_idx]
    if (length(x) < 4L) {
      return(data.frame(
        variable     = col,
        n_valid      = length(x),
        n_outliers   = 0L,
        pct_outliers = 0,
        lower_bound  = NA_real_,
        upper_bound  = NA_real_,
        flagged_rows = "None",
        stringsAsFactors = FALSE
      ))
    }

    q1  <- as.numeric(stats::quantile(x, 0.25, names = FALSE))
    q3  <- as.numeric(stats::quantile(x, 0.75, names = FALSE))
    iqr <- q3 - q1
    lo  <- q1 - threshold * iqr
    hi  <- q3 + threshold * iqr

    out_mask <- (x < lo) | (x > hi)
    out_rows <- valid_idx[out_mask]
    n_out    <- length(out_rows)

    flagged_str <- if (n_out == 0L) {
      "None"
    } else if (n_out <= 10L) {
      paste(out_rows, collapse = ", ")
    } else {
      paste0(paste(head(out_rows, 10L), collapse = ", "),
             sprintf(" (+%d more)", n_out - 10L))
    }

    data.frame(
      variable     = col,
      n_valid      = as.integer(length(x)),
      n_outliers   = as.integer(n_out),
      pct_outliers = round(n_out / length(x) * 100, 2),
      lower_bound  = round(lo, 2),
      upper_bound  = round(hi, 2),
      flagged_rows = flagged_str,
      stringsAsFactors = FALSE
    )
  }))

  rownames(res) <- NULL
  res[order(-res$n_outliers, res$variable), , drop = FALSE]
}

get_top_correlations <- function(df, n = 50L, method = "pearson") {
  num_cols <- get_numeric_cols(df)
  if (length(num_cols) < 2L) {
    return(data.frame(
      var1 = character(0), var2 = character(0), r = numeric(0),
      ci_95 = character(0), p_value = character(0), p_num = numeric(0),
      n_pairs = integer(0), strength = character(0),
      stringsAsFactors = FALSE
    ))
  }

  method <- match.arg(method, c("pearson", "spearman", "kendall"))
  k <- length(num_cols)
  pairs <- list()
  idx <- 0L

  for (i in seq_len(k - 1L)) {
    for (j in seq((i + 1L), k)) {
      v1 <- num_cols[i]
      v2 <- num_cols[j]
      x <- df[[v1]]
      y <- df[[v2]]
      ok <- is.finite(x) & is.finite(y)
      x <- x[ok]
      y <- y[ok]
      np <- length(x)
      if (np < 4L || stats::sd(x) == 0 || stats::sd(y) == 0) next

      ct <- tryCatch(
        suppressWarnings(stats::cor.test(x, y, method = method, exact = FALSE)),
        error = function(e) NULL
      )
      if (is.null(ct)) next

      r_val <- as.numeric(ct$estimate)
      p_val <- as.numeric(ct$p.value)

      # 95% confidence interval
      if (method == "pearson" && !is.null(ct$conf.int) && length(ct$conf.int) == 2L) {
        ci_lo <- as.numeric(ct$conf.int[1L])
        ci_hi <- as.numeric(ct$conf.int[2L])
      } else if (method == "spearman" && np > 3L && abs(r_val) < 0.9999) {
        z  <- atanh(r_val)
        se <- sqrt((1 + (r_val^2) / 2) / (np - 3))
        ci_lo <- max(-1, tanh(z - 1.959964 * se))
        ci_hi <- min( 1, tanh(z + 1.959964 * se))
      } else if (method == "kendall" && np > 3L) {
        se <- sqrt(2 * (2 * np + 5) / (9 * np * (np - 1)))
        ci_lo <- max(-1, r_val - 1.959964 * se)
        ci_hi <- min( 1, r_val + 1.959964 * se)
      } else {
        ci_lo <- NA_real_
        ci_hi <- NA_real_
      }

      ci_str <- if (is.na(ci_lo) || is.na(ci_hi)) {
        "N/A"
      } else {
        sprintf("[%.2f, %.2f]", ci_lo, ci_hi)
      }

      ar <- abs(r_val)
      strength <- if (ar >= 0.70) {
        "Very Strong"
      } else if (ar >= 0.50) {
        "Strong"
      } else if (ar >= 0.30) {
        "Moderate"
      } else if (ar >= 0.15) {
        "Weak"
      } else {
        "Negligible"
      }

      idx <- idx + 1L
      pairs[[idx]] <- data.frame(
        var1     = v1,
        var2     = v2,
        r        = round(r_val, 3),
        ci_95    = ci_str,
        p_value  = format_p_value(p_val),
        p_num    = if (is.na(p_val)) 1 else p_val,
        n_pairs  = as.integer(np),
        strength = strength,
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(pairs) == 0L) {
    return(data.frame(
      var1 = character(0), var2 = character(0), r = numeric(0),
      ci_95 = character(0), p_value = character(0), p_num = numeric(0),
      n_pairs = integer(0), strength = character(0),
      stringsAsFactors = FALSE
    ))
  }

  out <- do.call(rbind, pairs)
  out <- out[order(-abs(out$r), out$p_num), , drop = FALSE]
  rownames(out) <- NULL
  utils::head(out, n)
}

#' Detailed distribution statistics + optional group breakdown & hypothesis test
profile_distribution_stats <- function(df, variable = NULL, group_by = NULL) {
  num_cols <- get_numeric_cols(df)
  if (is.null(variable) || !nzchar(variable) || !(variable %in% num_cols)) {
    variable <- pick_default_var(df)
  }
  if (!nzchar(variable)) {
    return(list(
      variable = "", group_by = "", n = 0L, n_missing = 0L,
      mean = NA_real_, sd = NA_real_, median = NA_real_, iqr = NA_real_,
      q1 = NA_real_, q3 = NA_real_, min = NA_real_, max = NA_real_,
      skewness = NA_real_, shapiro_p = NA_real_, shapiro_label = "N/A",
      normality_status = "N/A",
      group_test = NULL,
      group_table = data.frame()
    ))
  }

  raw_x <- df[[variable]]
  x <- raw_x[is.finite(raw_x)]
  n_valid <- length(x)
  n_miss  <- sum(is.na(raw_x))

  m_val   <- if (n_valid > 0L) round(mean(x), 3) else NA_real_
  sd_val  <- if (n_valid > 1L) round(stats::sd(x), 3) else NA_real_
  med_val <- if (n_valid > 0L) round(stats::median(x), 3) else NA_real_
  q1_val  <- if (n_valid > 0L) round(as.numeric(stats::quantile(x, 0.25, names = FALSE)), 3) else NA_real_
  q3_val  <- if (n_valid > 0L) round(as.numeric(stats::quantile(x, 0.75, names = FALSE)), 3) else NA_real_
  iqr_val <- if (!is.na(q1_val) && !is.na(q3_val)) round(q3_val - q1_val, 3) else NA_real_
  min_val <- if (n_valid > 0L) round(min(x), 3) else NA_real_
  max_val <- if (n_valid > 0L) round(max(x), 3) else NA_real_
  skew    <- compute_skewness(x)
  sw_p    <- compute_shapiro_p(x)
  sw_lbl  <- format_p_value(sw_p)
  norm_st <- if (is.na(sw_p)) "N/A" else if (sw_p >= 0.05) "Consistent w/ Normal" else "Non-Normal"

  # Optional group stratification
  use_group <- !is.null(group_by) && nzchar(group_by) &&
    group_by != "none" && (group_by %in% names(df))
  group_table <- data.frame()
  group_test  <- NULL

  if (use_group) {
    g_raw <- as.character(df[[group_by]])
    ok <- is.finite(raw_x) & !is.na(g_raw) & nzchar(g_raw)
    xv <- raw_x[ok]
    gv <- factor(g_raw[ok])
    lvls <- levels(gv)

    if (length(lvls) >= 2L && length(lvls) <= 15L) {
      group_table <- do.call(rbind, lapply(lvls, function(lv) {
        xi <- xv[gv == lv]
        data.frame(
          group  = lv,
          n      = as.integer(length(xi)),
          mean   = round(mean(xi), 2),
          sd     = if (length(xi) > 1L) round(stats::sd(xi), 2) else 0,
          median = round(stats::median(xi), 2),
          iqr    = round(stats::IQR(xi), 2),
          min    = round(min(xi), 2),
          max    = round(max(xi), 2),
          stringsAsFactors = FALSE
        )
      }))
      rownames(group_table) <- NULL

      # Hypothesis test across groups
      if (length(lvls) == 2L) {
        p_t <- tryCatch(stats::t.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        p_w <- tryCatch(stats::wilcox.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        group_test <- list(
          method      = "Welch t-test",
          p_value     = format_p_value(p_t),
          nonparam    = "Wilcoxon",
          nonparam_p  = format_p_value(p_w)
        )
      } else {
        p_a <- tryCatch(stats::oneway.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        p_k <- tryCatch(stats::kruskal.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        group_test <- list(
          method      = "Welch ANOVA",
          p_value     = format_p_value(p_a),
          nonparam    = "Kruskal-Wallis",
          nonparam_p  = format_p_value(p_k)
        )
      }
    } else {
      use_group <- FALSE
    }
  }

  list(
    variable         = variable,
    group_by         = if (use_group) group_by else "",
    n                = as.integer(n_valid),
    n_missing        = as.integer(n_miss),
    mean             = m_val,
    sd               = sd_val,
    median           = med_val,
    q1               = q1_val,
    q3               = q3_val,
    iqr              = iqr_val,
    min              = min_val,
    max              = max_val,
    skewness         = skew,
    shapiro_p        = sw_p,
    shapiro_label    = sw_lbl,
    normality_status = norm_st,
    group_test       = group_test,
    group_table      = group_table
  )
}

#' Table 1-style subgroup comparison across a categorical stratification variable
profile_subgroup_comparison <- function(df, group_col = NULL) {
  num_cols <- get_numeric_cols(df)
  if (is.null(group_col) || !nzchar(group_col) || !(group_col %in% names(df))) {
    group_col <- pick_default_group(df)
  }
  if (!nzchar(group_col) || length(num_cols) == 0L) {
    return(list(group_col = "", table = data.frame()))
  }

  g_raw <- as.character(df[[group_col]])
  valid_g <- g_raw[!is.na(g_raw) & nzchar(g_raw)]
  lvls <- sort(unique(valid_g))

  # Preserve clinical arm ordering when applicable
  if (all(c("Placebo", "Low-Dose 10mg", "High-Dose 25mg") %in% lvls)) {
    lvls <- c("Placebo", "Low-Dose 10mg", "High-Dose 25mg")
  } else if (all(c("50 mg QD", "150 mg QD", "300 mg QD") %in% lvls)) {
    lvls <- c("50 mg QD", "150 mg QD", "300 mg QD")
  }

  if (length(lvls) < 2L || length(lvls) > 8L) {
    return(list(group_col = "", table = data.frame()))
  }

  rows <- lapply(num_cols, function(col) {
    x <- df[[col]]
    row_list <- list(Variable = col)

    for (lv in lvls) {
      xi <- x[g_raw == lv]
      xi <- xi[is.finite(xi)]
      col_lbl <- sprintf("%s (n=%d)", lv, sum(g_raw == lv, na.rm = TRUE))
      if (length(xi) > 1L) {
        row_list[[col_lbl]] <- sprintf("%.2f +/- %.2f", mean(xi), stats::sd(xi))
      } else if (length(xi) == 1L) {
        row_list[[col_lbl]] <- sprintf("%.2f", xi)
      } else {
        row_list[[col_lbl]] <- "--"
      }
    }

    ok <- is.finite(x) & !is.na(g_raw) & (g_raw %in% lvls)
    xv <- x[ok]
    gv <- factor(g_raw[ok], levels = lvls)
    p_val <- tryCatch({
      if (length(lvls) == 2L) {
        stats::t.test(xv ~ gv)$p.value
      } else {
        stats::oneway.test(xv ~ gv)$p.value
      }
    }, error = function(e) NA_real_)

    row_list[["p-value"]] <- format_p_value(p_val)
    as.data.frame(row_list, stringsAsFactors = FALSE, check.names = FALSE)
  })

  tab <- do.call(rbind, rows)
  rownames(tab) <- NULL
  list(group_col = group_col, table = tab)
}

#' Master dataset profiling pipeline
#'
#' Runs overview, variable dictionary, missingness audit, correlation matrix
#' summary, Tukey outlier scan, distribution stats, and subgroup Table 1.
profile_dataset <- function(df,
                            corr_method = "pearson",
                            outlier_threshold = 1.5,
                            dist_var = NULL,
                            group_by = NULL) {
  if (!is.data.frame(df)) {
    stop("profile_dataset() requires a data.frame.")
  }

  num_vars <- get_numeric_cols(df)
  cat_vars <- get_categorical_cols(df, max_levels = 15L)

  default_var   <- if (!is.null(dist_var) && dist_var %in% num_vars) dist_var else pick_default_var(df)
  default_group <- if (!is.null(group_by) && (group_by == "" || group_by == "none" || group_by %in% cat_vars)) {
    if (group_by == "none") "" else group_by
  } else {
    pick_default_group(df)
  }

  missing_info  <- profile_missing(df)
  variables     <- profile_variables(df)
  correlations  <- get_top_correlations(df, n = 50L, method = corr_method)
  outliers      <- detect_outliers(df, threshold = outlier_threshold)
  overview      <- profile_overview(df, top_corr = correlations, outlier_table = outliers)
  dist_stats    <- profile_distribution_stats(df, variable = default_var, group_by = default_group)
  subgroup_res  <- profile_subgroup_comparison(df, group_col = pick_default_group(df))

  list(
    overview         = overview,
    variables        = variables,
    missing          = missing_info,
    correlations     = correlations,
    outliers         = outliers,
    numeric_vars     = num_vars,
    categorical_vars = cat_vars,
    default_var      = default_var,
    default_group    = default_group,
    dist_stats       = dist_stats,
    subgroup_col     = subgroup_res$group_col,
    subgroup_table   = subgroup_res$table
  )
}

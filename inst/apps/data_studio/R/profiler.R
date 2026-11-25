# Pure R biostatistical profiling and built-in clinical cohort generators
# Uses only base R (stats, utils) - fully testable in isolation

# ── SAS-Compatible Rounding & Clinical Formatting Helpers ───────────────────

#' SAS-compatible half-away-from-zero rounding (BR-001) with signed-zero guard
round_half_away <- function(x, digits = 0L) {
  if (is.null(x) || length(x) == 0L) return(numeric(0))
  d <- as.integer(digits[1L])
  out <- rep(NA_real_, length(x))
  fin <- is.finite(x)
  if (!any(fin)) return(out)
  factor <- 10^d
  xv <- as.numeric(x[fin])
  # Small epsilon avoids IEEE-754 binary representation undershoot at .5 ties
  r <- sign(xv) * trunc(abs(xv) * factor + 0.5 + 1e-12) / factor
  r[r == 0] <- 0
  out[fin] <- r
  out
}

#' Format numbers with fixed trailing zeros using single display rounding (BR-002/003)
fmt_fixed <- function(x, digits = 2L, na_str = "--") {
  if (is.null(x) || length(x) == 0L) return(character(0))
  d <- as.integer(digits[1L])
  out <- rep(na_str, length(x))
  fin <- is.finite(x)
  if (!any(fin)) return(out)
  rounded <- round_half_away(x[fin], d)
  out[fin] <- vapply(rounded, function(v) {
    formatC(v + 0, format = "f", digits = d)
  }, character(1L))
  out
}

#' Format percentage with fixed trailing zeros
fmt_pct <- function(x, digits = 1L, na_str = "--") {
  res <- fmt_fixed(x, digits = digits, na_str = na_str)
  fin <- is.finite(x)
  res[fin] <- paste0(res[fin], "%")
  res
}

#' Format p-value using clinical reporting conventions (< 0.0001 lower bound)
fmt_p_value <- function(p) {
  if (is.null(p) || length(p) == 0L || is.na(p) || !is.finite(p)) {
    return("N/A")
  }
  if (p < 0.0001) return("< 0.0001")
  if (p < 0.001)  return(fmt_fixed(p, digits = 4L))
  fmt_fixed(p, digits = 3L)
}

format_p_value <- fmt_p_value

#' Geometric mean and geometric CV% for strictly positive PK / skewed endpoints
geo_mean <- function(x) {
  xp <- x[is.finite(x) & x > 0]
  if (length(xp) == 0L) return(NA_real_)
  exp(mean(log(xp)))
}

geo_cv_pct <- function(x) {
  xp <- x[is.finite(x) & x > 0]
  if (length(xp) < 2L) return(NA_real_)
  s2 <- stats::var(log(xp))
  if (!is.finite(s2) || s2 < 0) return(NA_real_)
  sqrt(exp(s2) - 1) * 100
}

# ── Built-in Deterministic Scientific Datasets ──────────────────────────────

#' Generate Phase III Cardio-Metabolic Clinical Trial Cohort (n = 480)
#'
#' Deterministic synthetic cohort (set.seed(202604L)) across Placebo,
#' Low-Dose 10mg, and High-Dose 25mg treatment arms with realistic regional
#' heterogeneity, integer blood pressure & age, paired DBP endpoints,
#' MAR informative dropout, and Phase III eGFR >= 30 eligibility adherence.
generate_clinical_trial_data <- function() {
  set.seed(202604L)
  n <- 480L
  arms <- c("Placebo", "Low-Dose 10mg", "High-Dose 25mg")
  treatment_arm <- sample(rep(arms, each = n / 3L), n, replace = FALSE)

  subject_id <- sprintf("CMT-%04d", seq_len(n))
  sex <- sample(c("Female", "Male"), n, replace = TRUE, prob = c(0.52, 0.48))

  site_region <- sample(
    c("North America", "Western Europe", "Asia-Pacific", "Latin America"),
    n,
    replace = TRUE,
    prob = c(0.36, 0.31, 0.20, 0.13)
  )

  # Regional heterogeneity in age & anthropometrics (consistent with multi-regional RCTs)
  reg_age_off <- ifelse(site_region == "Asia-Pacific", 1.5,
                 ifelse(site_region == "Latin America", -2.0, 0.0))
  age <- as.integer(round_half_away(
    pmin(82, pmax(35, stats::rnorm(n, mean = 61.0 + reg_age_off, sd = 8.8))),
    0L
  ))

  reg_bmi_mean <- ifelse(site_region == "North America", 31.8,
                  ifelse(site_region == "Western Europe", 29.4,
                  ifelse(site_region == "Latin America", 29.0, 25.3)))
  sex_bmi_off <- ifelse(sex == "Female", -0.5, 0.0)
  bmi_raw <- pmin(48.0, pmax(18.5,
    reg_bmi_mean + sex_bmi_off + stats::rnorm(n, mean = 0, sd = 4.2)))

  # Baseline SBP (integer mmHg) correlated with age, BMI & region
  reg_sbp_off <- ifelse(site_region == "North America", 2.0,
                 ifelse(site_region == "Asia-Pacific", -1.5, 0.0))
  sbp_base_raw <- pmin(182, pmax(132,
    122 + 0.30 * age + 0.32 * bmi_raw + reg_sbp_off + stats::rnorm(n, mean = 0, sd = 8.0)))
  baseline_sbp <- as.integer(round_half_away(sbp_base_raw, 0L))
  # Subtle clinical digit preference toward even mmHg
  odd_idx <- which((baseline_sbp %% 2L) == 1L)
  nudge_idx <- odd_idx[stats::runif(length(odd_idx)) < 0.35]
  if (length(nudge_idx) > 0L) {
    baseline_sbp[nudge_idx] <- as.integer(pmin(182L, pmax(132L,
      baseline_sbp[nudge_idx] + ifelse(stats::runif(length(nudge_idx)) < 0.5, 1L, -1L))))
  }

  # Baseline DBP (integer mmHg) co-varying with Baseline SBP (r ~ 0.55)
  baseline_dbp <- as.integer(round_half_away(
    pmin(112, pmax(70, 90 + 0.42 * (baseline_sbp - 150) + stats::rnorm(n, mean = 0, sd = 6.2))),
    0L
  ))

  # Week 12 SBP with dose-dependent efficacy + baseline regression-to-mean
  trt_eff <- ifelse(treatment_arm == "High-Dose 25mg", -15.0,
             ifelse(treatment_arm == "Low-Dose 10mg", -8.5, 0.0))
  sbp_delta_raw <- -2.8 + trt_eff - 0.14 * (baseline_sbp - 150) +
    0.4 * reg_sbp_off + stats::rnorm(n, mean = 0, sd = 8.2)
  week12_sbp <- as.integer(round_half_away(
    pmin(205, pmax(92, baseline_sbp + sbp_delta_raw)),
    0L
  ))

  # Week 12 DBP correlated with SBP trajectory
  week12_dbp <- as.integer(round_half_away(
    pmin(120, pmax(52, baseline_dbp + 0.52 * (week12_sbp - baseline_sbp) +
      stats::rnorm(n, mean = 0, sd = 4.2))),
    0L
  ))

  # Cardio-metabolic biomarkers
  ldl_eff <- ifelse(treatment_arm == "High-Dose 25mg", -14.5,
             ifelse(treatment_arm == "Low-Dose 10mg", -7.0, 0.5))
  ldl_raw <- pmax(52, 92 + 1.10 * bmi_raw + ldl_eff + stats::rnorm(n, mean = 0, sd = 24.0))

  hba1c_eff <- ifelse(treatment_arm == "High-Dose 25mg", -0.45,
               ifelse(treatment_arm == "Low-Dose 10mg", -0.22, 0.02))
  hba1c_raw <- pmax(4.6, 4.35 + 0.082 * bmi_raw + hba1c_eff + stats::rnorm(n, mean = 0, sd = 0.70))

  # Right-skewed high-sensitivity CRP (mg/L) with anti-inflammatory dose response
  crp_shift <- ifelse(treatment_arm == "High-Dose 25mg", -0.38,
               ifelse(treatment_arm == "Low-Dose 10mg", -0.18, 0.0))
  crp_raw <- pmin(28.0, pmax(0.15,
    exp(0.55 + 0.028 * (bmi_raw - 28.0) + crp_shift + stats::rnorm(n, mean = 0, sd = 0.62))))

  # Baseline renal function eGFR (sex-dimorphic, age-linked, eligibility >= 30 mL/min/1.73m^2)
  egfr_raw <- pmin(125.0, pmax(30.0,
    108.0 - 0.52 * age - 3.5 * (sex == "Female") -
      0.10 * (baseline_sbp - 150) + stats::rnorm(n, mean = 0, sd = 10.5)))

  # Clinically coherent extreme / audit observations respecting arm & eligibility
  pl_pool <- which(treatment_arm == "Placebo")
  hi_pool <- which(treatment_arm == "High-Dose 25mg")
  if (length(pl_pool) >= 2L) {
    week12_sbp[pl_pool[1:2]] <- as.integer(pmin(202L, baseline_sbp[pl_pool[1:2]] + c(30L, 34L)))
    week12_dbp[pl_pool[1:2]] <- as.integer(pmin(118L, baseline_dbp[pl_pool[1:2]] + c(14L, 16L)))
  }
  if (length(hi_pool) >= 1L) {
    week12_sbp[hi_pool[1L]] <- 98L
    week12_dbp[hi_pool[1L]] <- 60L
  }

  older_pool <- order(age, decreasing = TRUE)
  egfr_raw[older_pool[1:2]] <- c(31.2, 32.4)

  na_pool <- which(site_region == "North America")
  if (length(na_pool) >= 2L) {
    bmi_raw[na_pool[1:2]] <- c(47.2, 46.8)
  }
  ldl_raw[c(41, 163, 312, 422)] <- c(268.0, 281.5, 259.4, 274.2)
  hba1c_raw[c(73, 249, 411)] <- c(11.8, 12.4, 11.5)
  crp_raw[c(19, 95, 214, 338, 445)] <- c(18.6, 22.4, 20.8, 17.5, 24.1)

  bmi       <- round_half_away(bmi_raw, 1L)
  ldl_mg_dl <- round_half_away(ldl_raw, 1L)
  hba1c_pct <- round_half_away(hba1c_raw, 2L)
  crp_mg_l  <- round_half_away(crp_raw, 2L)
  eGFR      <- round_half_away(egfr_raw, 1L)

  # Primary efficacy endpoint: Week 12 change from baseline
  sbp_change <- as.integer(week12_sbp - baseline_sbp)
  dbp_change <- as.integer(week12_dbp - baseline_dbp)

  # Differential / MAR informative Week-12 dropout (tolerability vs lack of efficacy + severity)
  arm_miss_logit <- ifelse(treatment_arm == "High-Dose 25mg", -2.85,
                    ifelse(treatment_arm == "Placebo", -3.00, -3.70)) +
    0.35 * as.numeric(scale(age)) +
    0.30 * as.numeric(scale(baseline_sbp))
  # Protect the two Placebo non-adherent outlier indices so audit examples remain visible
  drop_prob <- stats::plogis(arm_miss_logit)
  if (length(pl_pool) >= 2L) drop_prob[pl_pool[1:2]] <- 0
  if (length(hi_pool) >= 1L) drop_prob[hi_pool[1L]] <- 0
  miss_w12 <- which(stats::rbinom(n, 1L, drop_prob) == 1L)

  week12_sbp[miss_w12] <- NA_integer_
  sbp_change[miss_w12] <- NA_integer_
  week12_dbp[miss_w12] <- NA_integer_
  dbp_change[miss_w12] <- NA_integer_

  # Partial laboratory draw missingness
  crp_mg_l[sample(seq_len(n), 20L)]  <- NA_real_
  ldl_mg_dl[sample(seq_len(n), 14L)] <- NA_real_
  hba1c_pct[sample(seq_len(n), 11L)] <- NA_real_
  eGFR[sample(setdiff(seq_len(n), older_pool[1:2]), 9L)] <- NA_real_
  bmi[sample(setdiff(seq_len(n), if (length(na_pool) >= 2L) na_pool[1:2] else integer(0)), 6L)] <- NA_real_

  # Phase III responder status (>= 10 mmHg reduction AND achieved SBP < 140 mmHg)
  responder_status <- ifelse(
    is.na(sbp_change), NA_character_,
    ifelse(sbp_change <= -10L & week12_sbp < 140L, "Responder", "Non-Responder")
  )

  data.frame(
    subject_id       = subject_id,
    treatment_arm    = treatment_arm,
    sex              = sex,
    site_region      = site_region,
    age              = age,
    bmi              = bmi,
    baseline_sbp     = baseline_sbp,
    baseline_dbp     = baseline_dbp,
    week12_sbp       = week12_sbp,
    sbp_change       = sbp_change,
    week12_dbp       = week12_dbp,
    dbp_change       = dbp_change,
    ldl_mg_dl        = ldl_mg_dl,
    hba1c_pct        = hba1c_pct,
    crp_mg_l         = crp_mg_l,
    eGFR             = eGFR,
    responder_status = responder_status,
    stringsAsFactors = FALSE
  )
}

#' Generate Steady-State PK & Biomarker NCA Cohort (n = 360)
#'
#' One steady-state NCA record per subject across 50 mg, 150 mg, and 300 mg QD
#' with allometric CL/F scaling, compartmental t1/2 = ln(2)*Vd/CL, proportional
#' AUC0-24 = Dose / CL, correlated AST/ALT liver safety, and monotone NCA missingness.
generate_pk_biomarker_data <- function() {
  set.seed(202605L)
  n <- 360L
  cohorts <- c("50 mg QD", "150 mg QD", "300 mg QD")
  dose_cohort <- sample(rep(cohorts, each = n / 3L), n, replace = FALSE)
  dose_mg <- ifelse(dose_cohort == "300 mg QD", 300,
             ifelse(dose_cohort == "150 mg QD", 150, 50))

  sample_id <- sprintf("PKB-%04d", seq_len(n))
  sex <- sample(c("Female", "Male"), n, replace = TRUE, prob = c(0.51, 0.49))

  # Sex-dimorphic body weight (kg) and serum creatinine (mg/dL)
  wt_raw <- pmin(130.0, pmax(44.0,
    ifelse(sex == "Male", 81.0, 67.0) + stats::rnorm(n, mean = 0, sd = 12.0)))
  cr_raw <- pmin(2.40, pmax(0.45,
    exp(ifelse(sex == "Male", log(0.96), log(0.78)) + stats::rnorm(n, mean = 0, sd = 0.18))))

  # Rare CYP poor metabolizers (~3%) shift apparent clearance downward proportionally
  is_pm <- stats::rbinom(n, 1L, 0.03) == 1L
  cyp_factor <- ifelse(is_pm, 0.45, 1.0)

  # Allometric CL/F (L/hr), volume Vd/F (L), and exact compartmental t1/2 = ln(2) * Vd / CL
  cl_raw <- pmin(120.0, pmax(14.0,
    50.0 * (wt_raw / 75.0)^0.75 * (0.90 / cr_raw)^0.25 * cyp_factor *
      exp(stats::rnorm(n, mean = 0, sd = 0.20))))
  vd_raw <- 900.0 * (wt_raw / 75.0) * exp(stats::rnorm(n, mean = 0, sd = 0.14))
  thalf_raw <- log(2) * vd_raw / cl_raw

  # Steady-state exposure AUC0-24 (ng*hr/mL) = Dose (mg -> 1000*ug) / CL/F
  auc_raw <- (dose_mg * 1000.0 / cl_raw) * exp(stats::rnorm(n, mean = 0, sd = 0.08))
  cmax_raw <- (auc_raw / 10.2) * (12.5 / thalf_raw)^0.20 * exp(stats::rnorm(n, mean = 0, sd = 0.13))

  # Inflammatory cytokine IL-6 (pg/mL) suppressed by drug exposure
  il6_raw <- pmin(85.0, pmax(0.40,
    exp(2.05 - 0.28 * log1p(auc_raw / 1000.0) + stats::rnorm(n, mean = 0, sd = 0.42))))

  # Hepatic transaminases ALT & AST (U/L) strongly co-regulated (r > 0.70)
  alt_raw <- exp(3.15 + 0.00055 * dose_mg + stats::rnorm(n, mean = 0, sd = 0.30))
  hi_doses <- which(dose_mg >= 150)
  if (length(hi_doses) >= 3L) {
    alt_raw[hi_doses[1:3]] <- c(132.0, 168.0, 118.0)
  }
  ast_raw <- pmin(260.0, pmax(10.0,
    exp(0.76 * log(alt_raw) + 0.72 + stats::rnorm(n, mean = 0, sd = 0.20))))
  alt_raw <- pmin(260.0, pmax(8.0, alt_raw))

  body_weight_kg   <- round_half_away(wt_raw, 1L)
  renal_creatinine <- round_half_away(cr_raw, 2L)
  clearance_l_hr   <- round_half_away(cl_raw, 2L)
  half_life_hr     <- round_half_away(thalf_raw, 2L)
  auc_0_24         <- round_half_away(auc_raw, 1L)
  cmax_ng_ml       <- round_half_away(cmax_raw, 1L)
  biomarker_il6    <- round_half_away(il6_raw, 2L)
  hepatic_alt      <- round_half_away(alt_raw, 1L)
  hepatic_ast      <- round_half_away(ast_raw, 1L)

  # Monotone NCA missingness: whenever AUC0-24 is non-calculable, terminal t1/2 is also NA
  miss_auc <- sample(seq_len(n), 9L)
  auc_0_24[miss_auc]     <- NA_real_
  half_life_hr[miss_auc] <- NA_real_
  miss_thalf_only <- sample(setdiff(seq_len(n), miss_auc), 5L)
  half_life_hr[miss_thalf_only] <- NA_real_

  biomarker_il6[sample(seq_len(n), 14L)]    <- NA_real_
  hepatic_alt[sample(seq_len(n), 10L)]      <- NA_real_
  hepatic_ast[sample(seq_len(n), 9L)]       <- NA_real_
  renal_creatinine[sample(seq_len(n), 6L)]  <- NA_real_

  data.frame(
    sample_id        = sample_id,
    dose_cohort      = dose_cohort,
    sex              = sex,
    body_weight_kg   = body_weight_kg,
    cmax_ng_ml       = cmax_ng_ml,
    auc_0_24         = auc_0_24,
    half_life_hr     = half_life_hr,
    clearance_l_hr   = clearance_l_hr,
    biomarker_il6    = biomarker_il6,
    hepatic_alt      = hepatic_alt,
    hepatic_ast      = hepatic_ast,
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
      subtitle    = "n = 480 subjects across 3 randomized arms (ANCOVA SBP, DBP, lipids & CRP)"
    ),
    pk_biomarker = list(
      id          = "pk_biomarker",
      label       = "PK & Biomarker Steady-State NCA Cohort",
      short_label = "PK & Biomarker NCA",
      filename    = "pk_biomarker_steady_state_nca.csv",
      subtitle    = "Steady-state NCA cohort (1 row/subject, n = 360 across 3 dose cohorts)"
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

compute_skewness <- function(x) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 3L) return(NA_real_)
  s <- stats::sd(x)
  if (is.na(s) || s == 0) return(0)
  m <- mean(x)
  round_half_away(mean(((x - m) / s)^3), 3L)
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
  # Phase III Clinical Trial primary endpoint: ANCOVA LS mean difference adjusted for baseline SBP
  if (all(c("treatment_arm", "sbp_change", "baseline_sbp") %in% names(df))) {
    ok <- is.finite(df$sbp_change) & is.finite(df$baseline_sbp) & !is.na(df$treatment_arm)
    sub_df <- df[ok, , drop = FALSE]
    if (all(c("Placebo", "High-Dose 25mg") %in% sub_df$treatment_arm)) {
      n_hi <- sum(sub_df$treatment_arm == "High-Dose 25mg")
      n_pl <- sum(sub_df$treatment_arm == "Placebo")
      if (n_hi >= 3L && n_pl >= 3L) {
        sub_df$treatment_arm <- stats::relevel(factor(sub_df$treatment_arm), ref = "Placebo")
        fit <- tryCatch(stats::lm(sbp_change ~ treatment_arm + baseline_sbp, data = sub_df),
                        error = function(e) NULL)
        coef_nm <- "treatment_armHigh-Dose 25mg"
        if (!is.null(fit) && coef_nm %in% rownames(summary(fit)$coefficients)) {
          sf  <- summary(fit)$coefficients
          ci  <- stats::confint(fit)
          est <- as.numeric(sf[coef_nm, "Estimate"])
          lo  <- as.numeric(ci[coef_nm, 1L])
          hi  <- as.numeric(ci[coef_nm, 2L])
          pv  <- as.numeric(sf[coef_nm, "Pr(>|t|)"])
          est_str <- paste0(ifelse(est > 0, "+", ""), fmt_fixed(est, 1L), " mmHg")
          ci_str  <- paste0("[", fmt_fixed(lo, 1L), ", ", fmt_fixed(hi, 1L), "]")
          return(list(
            label = "Primary Endpoint (ANCOVA SBP)",
            value = est_str,
            sub   = paste0("25mg vs Placebo (n=", n_hi, " vs ", n_pl,
                           "), 95% CI ", ci_str,
                           ", p ", ifelse(pv < 0.0001, "< 0.0001", paste("=", fmt_p_value(pv))))
          ))
        }
      }
    }
  }

  # PK NCA Cohort primary signal: log-scale Geometric Mean Ratio (GMR) & dose proportionality
  if (all(c("dose_cohort", "auc_0_24") %in% names(df))) {
    hi <- df$auc_0_24[df$dose_cohort == "300 mg QD"]
    lo <- df$auc_0_24[df$dose_cohort == "50 mg QD"]
    hi <- hi[is.finite(hi) & hi > 0]
    lo <- lo[is.finite(lo) & lo > 0]
    if (length(hi) >= 3L && length(lo) >= 3L) {
      lt <- tryCatch(stats::t.test(log(hi), log(lo)), error = function(e) NULL)
      if (!is.null(lt)) {
        gmr <- exp(mean(log(hi)) - mean(log(lo)))
        ci_lo <- exp(as.numeric(lt$conf.int[1L]))
        ci_hi <- exp(as.numeric(lt$conf.int[2L]))
        dn_ratio <- gmr / 6.0
        pv <- as.numeric(lt$p.value)
        return(list(
          label = "Exposure Ratio (AUC GMR)",
          value = paste0(fmt_fixed(gmr, 2L), "x GMR"),
          sub   = paste0("300 vs 50 mg (n=", length(hi), " vs ", length(lo),
                         "), 95% CI [", fmt_fixed(ci_lo, 2L), ", ", fmt_fixed(ci_hi, 2L),
                         "], DN ", fmt_fixed(dn_ratio, 2L), "x, p ",
                         ifelse(pv < 0.0001, "< 0.0001", paste("=", fmt_p_value(pv))))
        ))
      }
    }
  }

  # Generic dataset fallback: strongest uncoupled correlation if available
  if (is.null(top_corr)) {
    top_corr <- get_top_correlations(df, n = 10L, method = "pearson")
  }
  if (!is.null(top_corr) && nrow(top_corr) > 0L) {
    idx <- 1L
    if ("note" %in% names(top_corr)) {
      uncoupled <- which(top_corr$note == "")
      if (length(uncoupled) > 0L) idx <- uncoupled[1L]
    }
    r_val <- top_corr$r[idx]
    return(list(
      label = "Top Correlation",
      value = paste0("r = ", fmt_fixed(r_val, 2L)),
      sub   = paste0(top_corr$var1[idx], " vs ", top_corr$var2[idx])
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
  pct_missing   <- round_half_away(total_missing / total_cells * 100, 2L)

  complete_n   <- if (n_rows > 0L) sum(stats::complete.cases(df)) else 0L
  pct_complete <- if (n_rows > 0L) round_half_away(complete_n / n_rows * 100, 1L) else 0

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
    pct_complete_fmt     = fmt_pct(pct_complete, 1L),
    total_missing        = total_missing,
    pct_missing          = pct_missing,
    pct_missing_fmt      = fmt_pct(pct_missing, 2L),
    memory_kb            = round_half_away(as.numeric(utils::object.size(df)) / 1024, 1L),
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
      n_missing = integer(0), pct_missing = numeric(0), pct_missing_fmt = character(0),
      n_unique = integer(0), mean_sd = character(0), median_iqr = character(0),
      mean = numeric(0), sd = numeric(0), median = numeric(0), iqr = numeric(0),
      min = numeric(0), max = numeric(0),
      min_fmt = character(0), max_fmt = character(0),
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
      fin_x   <- valid_x[is.finite(valid_x)]
      m_val   <- if (length(fin_x) > 0L) mean(fin_x) else NA_real_
      sd_val  <- if (length(fin_x) > 1L) stats::sd(fin_x) else 0
      med_val <- if (length(fin_x) > 0L) stats::median(fin_x) else NA_real_
      q1_val  <- if (length(fin_x) > 0L) as.numeric(stats::quantile(fin_x, 0.25, names = FALSE)) else NA_real_
      q3_val  <- if (length(fin_x) > 0L) as.numeric(stats::quantile(fin_x, 0.75, names = FALSE)) else NA_real_
      iqr_val <- q3_val - q1_val
      min_val <- if (length(fin_x) > 0L) min(fin_x) else NA_real_
      max_val <- if (length(fin_x) > 0L) max(fin_x) else NA_real_

      mean_sd_str    <- paste0(fmt_fixed(m_val, 2L), " +/- ", fmt_fixed(sd_val, 2L))
      median_iqr_str <- paste0(fmt_fixed(med_val, 2L), " [", fmt_fixed(q1_val, 2L), ", ", fmt_fixed(q3_val, 2L), "]")
      type_label     <- "Numeric"
      min_fmt_str    <- fmt_fixed(min_val, 2L)
      max_fmt_str    <- fmt_fixed(max_val, 2L)
    } else {
      m_val <- sd_val <- med_val <- iqr_val <- min_val <- max_val <- NA_real_
      min_fmt_str <- "--"
      max_fmt_str <- "--"
      if (length(valid_x) > 0L) {
        tab <- sort(table(valid_x), decreasing = TRUE)
        top_name <- names(tab)[1L]
        # Round once directly at display (BR-002)
        top_pct_raw <- as.numeric(tab[1L]) / length(valid_x) * 100
        mean_sd_str <- if (n_uniq <= 20L) {
          paste0(top_name, " (", fmt_pct(top_pct_raw, 1L), ")")
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

    pct_m_raw <- if (n_tot > 0L) n_miss / n_tot * 100 else 0

    data.frame(
      variable        = col,
      type            = type_label,
      n_valid         = as.integer(n_valid),
      n_missing       = as.integer(n_miss),
      pct_missing     = round_half_away(pct_m_raw, 1L),
      pct_missing_fmt = fmt_fixed(pct_m_raw, 1L),
      n_unique        = as.integer(n_uniq),
      mean_sd         = mean_sd_str,
      median_iqr      = median_iqr_str,
      mean            = round_half_away(m_val, 3L),
      sd              = round_half_away(sd_val, 3L),
      median          = round_half_away(med_val, 3L),
      iqr             = round_half_away(iqr_val, 3L),
      min             = round_half_away(min_val, 3L),
      max             = round_half_away(max_val, 3L),
      min_fmt         = min_fmt_str,
      max_fmt         = max_fmt_str,
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
      if (length(x) == 0L) 0 else round_half_away(mean(is.na(x)) * 100, 2L)
    }, numeric(1)),
    pct_complete = vapply(df, function(x) {
      if (length(x) == 0L) 100 else round_half_away(mean(!is.na(x)) * 100, 2L)
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
      pct_outliers = numeric(0), pct_outliers_fmt = character(0),
      lower_bound = numeric(0), upper_bound = numeric(0),
      lower_fmt = character(0), upper_fmt = character(0),
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
        variable         = col,
        n_valid          = length(x),
        n_outliers       = 0L,
        pct_outliers     = 0,
        pct_outliers_fmt = "0.00",
        lower_bound      = NA_real_,
        upper_bound      = NA_real_,
        lower_fmt        = "--",
        upper_fmt        = "--",
        flagged_rows     = "None",
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
    pct_raw  <- n_out / length(x) * 100

    flagged_str <- if (n_out == 0L) {
      "None"
    } else if (n_out <= 10L) {
      paste(out_rows, collapse = ", ")
    } else {
      paste0(paste(head(out_rows, 10L), collapse = ", "),
             sprintf(" (+%d more)", n_out - 10L))
    }

    data.frame(
      variable         = col,
      n_valid          = as.integer(length(x)),
      n_outliers       = as.integer(n_out),
      pct_outliers     = round_half_away(pct_raw, 2L),
      pct_outliers_fmt = fmt_fixed(pct_raw, 2L),
      lower_bound      = round_half_away(lo, 2L),
      upper_bound      = round_half_away(hi, 2L),
      lower_fmt        = fmt_fixed(lo, 2L),
      upper_fmt        = fmt_fixed(hi, 2L),
      flagged_rows     = flagged_str,
      stringsAsFactors = FALSE
    )
  }))

  rownames(res) <- NULL
  res[order(-res$n_outliers, res$variable), , drop = FALSE]
}

is_coupled_var_pair <- function(v1, v2) {
  pair <- sort(c(v1, v2))
  coupled_sets <- list(
    c("baseline_sbp", "sbp_change"),
    c("sbp_change", "week12_sbp"),
    c("baseline_dbp", "dbp_change"),
    c("dbp_change", "week12_dbp"),
    c("auc_0_24", "cmax_ng_ml"),
    c("auc_0_24", "clearance_l_hr"),
    c("clearance_l_hr", "half_life_hr")
  )
  any(vapply(coupled_sets, function(cs) identical(pair, sort(cs)), logical(1L)))
}

get_top_correlations <- function(df, n = 50L, method = "pearson") {
  num_cols <- get_numeric_cols(df)
  empty_df <- data.frame(
    var1 = character(0), var2 = character(0), r = numeric(0), r_fmt = character(0),
    ci_95 = character(0), p_value = character(0), p_num = numeric(0),
    p_adj_bh = character(0), p_adj_num = numeric(0),
    n_pairs = integer(0), strength = character(0), note = character(0),
    stringsAsFactors = FALSE
  )
  if (length(num_cols) < 2L) return(empty_df)

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
        paste0("[", fmt_fixed(ci_lo, 2L), ", ", fmt_fixed(ci_hi, 2L), "]")
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
        var1      = v1,
        var2      = v2,
        r         = round_half_away(r_val, 3L),
        r_fmt     = fmt_fixed(r_val, 3L),
        ci_95     = ci_str,
        p_value   = fmt_p_value(p_val),
        p_num     = if (is.na(p_val)) 1 else p_val,
        p_adj_bh  = "N/A",
        p_adj_num = 1,
        n_pairs   = as.integer(np),
        strength  = strength,
        note      = if (is_coupled_var_pair(v1, v2)) "Coupled" else "",
        stringsAsFactors = FALSE
      )
    }
  }

  if (length(pairs) == 0L) return(empty_df)

  out <- do.call(rbind, pairs)
  # Benjamini-Hochberg FDR across ALL evaluated pairs before ranking/truncating
  out$p_adj_num <- stats::p.adjust(out$p_num, method = "BH")
  out$p_adj_bh  <- vapply(out$p_adj_num, fmt_p_value, character(1L))
  out <- out[order(-abs(out$r), out$p_adj_num, out$p_num), , drop = FALSE]
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
      mean_fmt = "--", sd_fmt = "--", median_fmt = "--", iqr_fmt = "--",
      q1_fmt = "--", q3_fmt = "--", min_fmt = "--", max_fmt = "--", skew_fmt = "--",
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

  # Compute unrounded summary quantities first; round once per display target (BR-002)
  m_raw   <- if (n_valid > 0L) mean(x) else NA_real_
  sd_raw  <- if (n_valid > 1L) stats::sd(x) else NA_real_
  med_raw <- if (n_valid > 0L) stats::median(x) else NA_real_
  q1_raw  <- if (n_valid > 0L) as.numeric(stats::quantile(x, 0.25, names = FALSE)) else NA_real_
  q3_raw  <- if (n_valid > 0L) as.numeric(stats::quantile(x, 0.75, names = FALSE)) else NA_real_
  iqr_raw <- if (!is.na(q1_raw) && !is.na(q3_raw)) q3_raw - q1_raw else NA_real_
  min_raw <- if (n_valid > 0L) min(x) else NA_real_
  max_raw <- if (n_valid > 0L) max(x) else NA_real_

  m_val   <- round_half_away(m_raw, 3L)
  sd_val  <- round_half_away(sd_raw, 3L)
  med_val <- round_half_away(med_raw, 3L)
  q1_val  <- round_half_away(q1_raw, 3L)
  q3_val  <- round_half_away(q3_raw, 3L)
  iqr_val <- round_half_away(iqr_raw, 3L)
  min_val <- round_half_away(min_raw, 3L)
  max_val <- round_half_away(max_raw, 3L)
  skew    <- compute_skewness(x)
  sw_p    <- compute_shapiro_p(x)
  sw_lbl  <- fmt_p_value(sw_p)
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
          mean   = fmt_fixed(mean(xi), 2L),
          sd     = if (length(xi) > 1L) fmt_fixed(stats::sd(xi), 2L) else "0.00",
          median = fmt_fixed(stats::median(xi), 2L),
          iqr    = fmt_fixed(stats::IQR(xi), 2L),
          min    = fmt_fixed(min(xi), 2L),
          max    = fmt_fixed(max(xi), 2L),
          stringsAsFactors = FALSE
        )
      }))
      rownames(group_table) <- NULL

      if (length(lvls) == 2L) {
        p_t <- tryCatch(stats::t.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        p_w <- tryCatch(suppressWarnings(stats::wilcox.test(xv ~ gv)$p.value), error = function(e) NA_real_)
        group_test <- list(
          method     = "Welch t-test",
          p_value    = fmt_p_value(p_t),
          nonparam   = "Wilcoxon",
          nonparam_p = fmt_p_value(p_w)
        )
      } else {
        p_a <- tryCatch(stats::oneway.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        p_k <- tryCatch(stats::kruskal.test(xv ~ gv)$p.value, error = function(e) NA_real_)
        group_test <- list(
          method     = "Welch ANOVA",
          p_value    = fmt_p_value(p_a),
          nonparam   = "Kruskal-Wallis",
          nonparam_p = fmt_p_value(p_k)
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
    mean_fmt         = fmt_fixed(m_raw, 2L),
    sd_fmt           = fmt_fixed(sd_raw, 2L),
    median_fmt       = fmt_fixed(med_raw, 2L),
    q1_fmt           = fmt_fixed(q1_raw, 2L),
    q3_fmt           = fmt_fixed(q3_raw, 2L),
    iqr_fmt          = fmt_fixed(iqr_raw, 2L),
    min_fmt          = fmt_fixed(min_raw, 2L),
    max_fmt          = fmt_fixed(max_raw, 2L),
    skew_fmt         = fmt_fixed(skew, 3L),
    skewness         = skew,
    shapiro_p        = sw_p,
    shapiro_label    = sw_lbl,
    normality_status = norm_st,
    group_test       = group_test,
    group_table      = group_table
  )
}

#' Table 1-style subgroup comparison across a categorical stratification variable
#'
#' Separates Baseline from Post-Baseline variables, reports per-variable evaluable
#' denominators alongside column N, uses distribution-appropriate statistics
#' (Mean +/- SD, Median [Q1, Q3], GeoMean (GeoCV%)), includes categorical and
#' responder (ITT-NRI & Observed Case) rows, and omits p-values on baseline
#' characteristics across randomized arms per CONSORT/ICH E9.
profile_subgroup_comparison <- function(df, group_col = NULL) {
  num_cols <- get_numeric_cols(df)
  cat_cols <- get_categorical_cols(df, max_levels = 6L)

  if (is.null(group_col) || !nzchar(group_col) || !(group_col %in% names(df))) {
    group_col <- pick_default_group(df)
  }
  if (!nzchar(group_col) || (length(num_cols) == 0L && length(cat_cols) <= 1L)) {
    return(list(group_col = "", table = data.frame(), footnote = ""))
  }

  g_raw <- as.character(df[[group_col]])
  valid_g <- g_raw[!is.na(g_raw) & nzchar(g_raw)]
  lvls <- sort(unique(valid_g))

  if (all(c("Placebo", "Low-Dose 10mg", "High-Dose 25mg") %in% lvls)) {
    lvls <- c("Placebo", "Low-Dose 10mg", "High-Dose 25mg")
  } else if (all(c("50 mg QD", "150 mg QD", "300 mg QD") %in% lvls)) {
    lvls <- c("50 mg QD", "150 mg QD", "300 mg QD")
  }

  if (length(lvls) < 2L || length(lvls) > 8L) {
    return(list(group_col = "", table = data.frame(), footnote = ""))
  }

  arm_N <- vapply(lvls, function(lv) sum(!is.na(g_raw) & g_raw == lv), integer(1L))
  names(arm_N) <- lvls
  total_strat_N <- sum(arm_N)
  col_headers <- vapply(lvls, function(lv) sprintf("%s (N=%d)", lv, arm_N[lv]), character(1L))
  names(col_headers) <- lvls

  is_randomized_group <- group_col %in% c("treatment_arm", "dose_cohort")
  baseline_vars <- c("age", "bmi", "baseline_sbp", "baseline_dbp", "eGFR",
                     "body_weight_kg", "renal_creatinine", "sex", "site_region")
  efficacy_vars <- c("week12_sbp", "sbp_change", "week12_dbp", "dbp_change", "responder_status")
  pk_vars       <- c("cmax_ng_ml", "auc_0_24", "half_life_hr", "clearance_l_hr")
  skewed_vars   <- c("crp_mg_l", "biomarker_il6", "hepatic_alt", "hepatic_ast")

  classify_section <- function(col) {
    if (col %in% baseline_vars) return("Baseline")
    if (col %in% efficacy_vars) return("Efficacy")
    if (col %in% pk_vars)       return("PK Exposure")
    if (col %in% c("ldl_mg_dl", "hba1c_pct", "crp_mg_l")) return("Biomarker")
    if (col %in% c("biomarker_il6", "hepatic_alt", "hepatic_ast")) return("PD / Safety")
    "Summary"
  }

  make_row <- function(section, variable, metric, eval_n, cells, p_str) {
    row_list <- list(
      Section   = section,
      Variable  = variable,
      Metric    = metric,
      `Eval N`  = eval_n
    )
    for (lv in lvls) {
      row_list[[col_headers[lv]]] <- cells[[lv]]
    }
    row_list[["p-value"]] <- p_str
    as.data.frame(row_list, stringsAsFactors = FALSE, check.names = FALSE)
  }

  # 1. Numeric variables
  num_rows <- lapply(num_cols, function(col) {
    x <- df[[col]]
    sec <- classify_section(col)
    ok_all <- is.finite(x) & !is.na(g_raw) & (g_raw %in% lvls)
    xv <- x[ok_all]
    gv <- factor(g_raw[ok_all], levels = lvls)

    is_pk_log <- col %in% c("auc_0_24", "cmax_ng_ml") && length(xv) > 0L && all(xv > 0)
    skew_val <- compute_skewness(xv)
    is_skewed <- !is_pk_log && (
      (col %in% skewed_vars) || (!is.na(skew_val) && abs(skew_val) > 1.2)
    )

    metric_lbl <- if (is_pk_log) {
      "GeoMean (GeoCV%)"
    } else if (is_skewed) {
      "Median [Q1, Q3]"
    } else {
      "Mean +/- SD"
    }

    cells <- list()
    for (lv in lvls) {
      xi <- x[!is.na(g_raw) & g_raw == lv]
      xi <- xi[is.finite(xi)]
      n_arm <- length(xi)
      n_tag <- if (n_arm < arm_N[lv]) sprintf(" [n=%d]", n_arm) else ""

      if (n_arm == 0L) {
        cells[[lv]] <- "-- [n=0]"
      } else if (is_pk_log) {
        gm  <- geo_mean(xi)
        gcv <- geo_cv_pct(xi)
        cells[[lv]] <- if (is.finite(gcv)) {
          paste0(fmt_fixed(gm, 1L), " (", fmt_pct(gcv, 1L), ")", n_tag)
        } else {
          paste0(fmt_fixed(gm, 1L), n_tag)
        }
      } else if (is_skewed) {
        q1 <- as.numeric(stats::quantile(xi, 0.25, names = FALSE))
        q3 <- as.numeric(stats::quantile(xi, 0.75, names = FALSE))
        cells[[lv]] <- paste0(fmt_fixed(stats::median(xi), 2L), " [",
                              fmt_fixed(q1, 2L), ", ", fmt_fixed(q3, 2L), "]", n_tag)
      } else {
        cells[[lv]] <- if (n_arm > 1L) {
          paste0(fmt_fixed(mean(xi), 2L), " +/- ", fmt_fixed(stats::sd(xi), 2L), n_tag)
        } else {
          paste0(fmt_fixed(xi, 2L), n_tag)
        }
      }
    }

    eval_str <- sprintf("%d/%d", length(xv), total_strat_N)

    if (is_randomized_group && identical(sec, "Baseline")) {
      p_str <- "-- (Baseline)"
    } else if (group_col == "treatment_arm" && col == "sbp_change" &&
               "baseline_sbp" %in% names(df)) {
      ok_anc <- ok_all & is.finite(df$baseline_sbp)
      p_val <- tryCatch({
        anc_df <- data.frame(y = x[ok_anc], trt = factor(g_raw[ok_anc], levels = lvls),
                             base = df$baseline_sbp[ok_anc])
        m0 <- stats::lm(y ~ base, data = anc_df)
        m1 <- stats::lm(y ~ trt + base, data = anc_df)
        stats::anova(m0, m1)$`Pr(>F)`[2L]
      }, error = function(e) NA_real_)
      p_str <- paste0(fmt_p_value(p_val), " (ANCOVA)")
    } else if (group_col == "treatment_arm" && col == "dbp_change" &&
               "baseline_dbp" %in% names(df)) {
      ok_anc <- ok_all & is.finite(df$baseline_dbp)
      p_val <- tryCatch({
        anc_df <- data.frame(y = x[ok_anc], trt = factor(g_raw[ok_anc], levels = lvls),
                             base = df$baseline_dbp[ok_anc])
        m0 <- stats::lm(y ~ base, data = anc_df)
        m1 <- stats::lm(y ~ trt + base, data = anc_df)
        stats::anova(m0, m1)$`Pr(>F)`[2L]
      }, error = function(e) NA_real_)
      p_str <- paste0(fmt_p_value(p_val), " (ANCOVA)")
    } else if (is_pk_log) {
      p_val <- tryCatch({
        if (length(lvls) == 2L) stats::t.test(log(xv) ~ gv)$p.value
        else stats::oneway.test(log(xv) ~ gv)$p.value
      }, error = function(e) NA_real_)
      p_str <- paste0(fmt_p_value(p_val), " (Log)")
    } else if (is_skewed) {
      p_val <- tryCatch({
        if (length(lvls) == 2L) suppressWarnings(stats::wilcox.test(xv ~ gv)$p.value)
        else stats::kruskal.test(xv ~ gv)$p.value
      }, error = function(e) NA_real_)
      p_str <- paste0(fmt_p_value(p_val), " (KW)")
    } else {
      p_val <- tryCatch({
        if (length(lvls) == 2L) stats::t.test(xv ~ gv)$p.value
        else stats::oneway.test(xv ~ gv)$p.value
      }, error = function(e) NA_real_)
      p_str <- fmt_p_value(p_val)
    }

    make_row(sec, col, metric_lbl, eval_str, cells, p_str)
  })

  # 2. Categorical variables (demographics n(%) and clinical responders ITT-NRI + OC)
  other_cats <- setdiff(cat_cols, group_col)
  cat_rows <- list()
  for (col in other_cats) {
    v_raw <- as.character(df[[col]])
    sec <- classify_section(col)

    if (identical(col, "responder_status")) {
      # Row A: ITT Non-Responder Imputation (NRI) across all randomized subjects
      nri_val <- ifelse(!is.na(v_raw) & v_raw == "Responder", "Responder", "Non-Responder")
      ok_g <- !is.na(g_raw) & (g_raw %in% lvls)
      tab_nri <- table(factor(nri_val[ok_g], levels = c("Responder", "Non-Responder")),
                       factor(g_raw[ok_g], levels = lvls))
      p_nri <- tryCatch(
        suppressWarnings(stats::chisq.test(tab_nri)$p.value),
        error = function(e) NA_real_
      )
      cells_nri <- list()
      for (lv in lvls) {
        cnt <- as.integer(tab_nri["Responder", lv])
        cells_nri[[lv]] <- paste0(cnt, " (", fmt_pct(100 * cnt / arm_N[lv], 1L), ")")
      }
      cat_rows[[length(cat_rows) + 1L]] <- make_row(
        "Efficacy", "responder_status (ITT-NRI)", "n (%) [ITT-NRI]",
        sprintf("%d/%d", total_strat_N, total_strat_N), cells_nri,
        paste0(fmt_p_value(p_nri), " (Chi2)")
      )

      # Row B: Observed Cases (OC) among Week-12 completers
      ok_oc <- ok_g & !is.na(v_raw) & nzchar(v_raw)
      tab_oc <- table(factor(v_raw[ok_oc], levels = c("Responder", "Non-Responder")),
                      factor(g_raw[ok_oc], levels = lvls))
      p_oc <- tryCatch(
        suppressWarnings(stats::chisq.test(tab_oc)$p.value),
        error = function(e) NA_real_
      )
      cells_oc <- list()
      for (lv in lvls) {
        cnt <- as.integer(tab_oc["Responder", lv])
        n_obs_arm <- sum(tab_oc[, lv])
        cells_oc[[lv]] <- if (n_obs_arm > 0L) {
          paste0(cnt, " (", fmt_pct(100 * cnt / n_obs_arm, 1L), ") [n=", n_obs_arm, "]")
        } else {
          "0 (0.0%) [n=0]"
        }
      }
      cat_rows[[length(cat_rows) + 1L]] <- make_row(
        "Efficacy", "responder_status (Observed)", "n (%) [Observed]",
        sprintf("%d/%d", sum(ok_oc), total_strat_N), cells_oc,
        paste0(fmt_p_value(p_oc), " (Chi2)")
      )
    } else {
      ok_c <- !is.na(v_raw) & nzchar(v_raw) & !is.na(g_raw) & (g_raw %in% lvls)
      if (!any(ok_c)) next
      c_lvls <- sort(unique(v_raw[ok_c]))
      tab_c <- table(factor(v_raw[ok_c], levels = c_lvls), factor(g_raw[ok_c], levels = lvls))
      p_cat <- if (is_randomized_group && identical(sec, "Baseline")) {
        NA_real_
      } else {
        tryCatch({
          ct <- suppressWarnings(stats::chisq.test(tab_c))
          if (any(ct$expected < 5)) stats::fisher.test(tab_c, simulate.p.value = TRUE)$p.value
          else ct$p.value
        }, error = function(e) NA_real_)
      }
      # Show primary level for binary sex (Female), or all levels for multi-level region/category
      show_lvls <- if (identical(col, "sex") && "Female" %in% c_lvls) "Female" else c_lvls
      for (k in seq_along(show_lvls)) {
        clv <- show_lvls[k]
        cells_c <- list()
        for (lv in lvls) {
          cnt <- as.integer(tab_c[clv, lv])
          n_obs_arm <- sum(tab_c[, lv])
          n_tag <- if (n_obs_arm < arm_N[lv]) sprintf(" [n=%d]", n_obs_arm) else ""
          cells_c[[lv]] <- if (n_obs_arm > 0L) {
            paste0(cnt, " (", fmt_pct(100 * cnt / n_obs_arm, 1L), ")", n_tag)
          } else {
            "-- [n=0]"
          }
        }
        p_out <- if (k == 1L) {
          if (is_randomized_group && identical(sec, "Baseline")) "-- (Baseline)" else paste0(fmt_p_value(p_cat), " (Chi2)")
        } else {
          ""
        }
        var_lbl <- if (length(show_lvls) == 1L) paste0(col, ": ", clv) else paste0(col, " - ", clv)
        cat_rows[[length(cat_rows) + 1L]] <- make_row(
          sec, var_lbl, "n (%)",
          if (k == 1L) sprintf("%d/%d", sum(ok_c), total_strat_N) else "",
          cells_c, p_out
        )
      }
    }
  }

  all_rows <- c(cat_rows, num_rows)
  if (length(all_rows) == 0L) {
    return(list(group_col = group_col, table = data.frame(), footnote = ""))
  }

  tab <- do.call(rbind, all_rows)
  # Order Baseline -> Efficacy -> PK Exposure -> Biomarker -> PD / Safety -> Categorical/Summary
  sec_order <- match(tab$Section,
    c("Baseline", "Efficacy", "PK Exposure", "Biomarker", "PD / Safety", "Summary"),
    nomatch = 99L)
  tab <- tab[order(sec_order), , drop = FALSE]
  rownames(tab) <- NULL

  footnote <- paste0(
    "Table 1 Notes: Column headers display randomized/stratum N; 'Eval N' and bracketed [n=...] identify variable-specific evaluable counts whenever data are missing. ",
    "Skewed biomarkers use Median [Q1, Q3] with Kruskal-Wallis (KW) test; PK AUC0-24 & Cmax use GeoMean (GeoCV%) with log-scale ANOVA (Log); SBP/DBP change-from-baseline tests use ANCOVA adjusted for baseline. ",
    "Per CONSORT/ICH E9, baseline balance hypothesis tests are omitted (-- Baseline) for randomized arms. ",
    "Responder status reports both ITT Non-Responder Imputation (ITT-NRI, missing = Non-Responder) and Observed Cases (OC). ",
    "Post-baseline secondary/biomarker p-values are nominal and unadjusted for multiplicity; numeric displays follow SAS half-away-from-zero rounding."
  )

  list(group_col = group_col, table = tab, footnote = footnote)
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
    overview          = overview,
    variables         = variables,
    missing           = missing_info,
    correlations      = correlations,
    outliers          = outliers,
    numeric_vars      = num_vars,
    categorical_vars  = cat_vars,
    default_var       = default_var,
    default_group     = default_group,
    dist_stats        = dist_stats,
    subgroup_col      = subgroup_res$group_col,
    subgroup_table    = subgroup_res$table,
    subgroup_footnote = subgroup_res$footnote
  )
}

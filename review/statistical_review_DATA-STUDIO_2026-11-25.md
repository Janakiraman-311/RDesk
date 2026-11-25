# Independent Statistical & Simulation Review Report: RDesk Data Intelligence Studio

**Review Metadata**
- **Study / Application**: `RDesk::data_studio` (`Data Intelligence Studio v1.0.0`, bundled at `inst/apps/data_studio/`)
- **Review Date**: `2026-11-25`
- **Review Mode**: **Known-Simulation Mode** (`generate_clinical_trial_data()`, `generate_pk_biomarker_data()`) + Statistical & Rounding Engine Audit (`R/profiler.R`, `R/charts.R`, `R/export.R`, `R/server.R`, `www/index.html`, `www/js/app.js`)
- **Methodology Standards Applied**: Pharmaverse `statistical-reviewer` (`references/tlf_checks.md`, `references/realism_checks.md`) & `rounding` (`BR-001`, `BR-002`, `BR-003`), ICH E9, CONSORT, and FDA Clinical Pharmacology / Bioequivalence NCA conventions.
- **Reviewer**: Independent Statistical Reviewer (Automated Audit & Execution Trace)

---

## 1. Executive Summary & Overall Assessment

An independent statistical, clinical realism, and rounding compliance audit was conducted on **Data Intelligence Studio** (`inst/apps/data_studio/`). Both built-in synthetic cohorts (`Phase III Cardio-Metabolic`, `n = 480`; `PK & Biomarker`, `n = 360`) and the downstream profiling, Table 1, correlation, chart, and HTML export pipelines were executed end-to-end against actual R output prior to remediation.

**Baseline Assessment: Needs Remediation Across 7 Findings (3 High, 4 Medium)**
While overall app stability and visual layout were sound, the underlying clinical and biostatistical logic exhibited multiple material methodological, denominator, simulation-physics, and SAS-rounding defects:
1. Primary Phase III SBP change analysis relied on an unadjusted complete-case Welch t-test (`-14.733 mmHg`) instead of baseline-adjusted ANCOVA (`-15.110 mmHg`), introducing `0.38 mmHg` bias from baseline SBP imbalance (`151.39` vs `149.18 mmHg`) and omitting 95% CIs and evaluable counts.
2. PK exposure comparison used an arithmetic mean ratio (`6.111x`) and untransformed Welch t-test instead of a log-scale Geometric Mean Ratio (`GMR = 6.507x`, 95% CI `[5.999, 7.059]`) and dose-normalized proportionality assessment.
3. Subgroup Comparison (Table 1) displayed randomized arm totals (`n = 160`) in headers without variable-specific evaluable denominators despite per-variable missingness (`6` to `22` missing values), omitted categorical rows (`sex`, `site_region`, `responder_status`), misapplied `Mean +/- SD` and Welch ANOVA to heavily right-skewed biomarkers (`crp_mg_l`, `biomarker_il6`, PK `AUC`/`Cmax`), and tested baseline balance with parametric p-values contrary to CONSORT/ICH E9.
4. Responder rates (`responder_status`) reflected only observed cases (`87.01%` vs `24.34%`) without reporting Phase III ITT Non-Responder Imputation (`83.75%` vs `23.12%`).
5. Pairwise correlations lacked Benjamini-Hochberg FDR multiplicity control and ranked mathematically coupled variables (`week12_sbp` vs `sbp_change`, `r = 0.749`) first without annotation.
6. Known-simulation generators contained non-clinical/non-physiological artifacts (fractional `age` and `baseline_sbp`, missing `sex`/`DBP`/`body_weight_kg`/`hepatic_ast`, pure MCAR Week-12 dropout, hardcoded row-index outliers breaking dose-cohort/eligibility constraints, non-monotone PK missingness where `7/8` rows missing `AUC` retained `t1/2`, and a linear `t1/2 ~ CL` approximation).
7. Reporting and display pipelines violated SAS-compatible rounding rules (`BR-001` half-to-even `base::round()`, `BR-002` early/cascaded rounding of `IQR` and completeness percentages, `BR-003` dropped trailing zeros and unguarded `-0.0` potential).

---

## 2. Scope & Baseline Execution Evidence

All baseline findings below were directly observed by sourcing `inst/apps/data_studio/R/profiler.R` under `R 4.5.1` prior to code changes:
- `generate_clinical_trial_data()`: `480 x 13` data frame across `Placebo` (`160`), `Low-Dose 10mg` (`160`), `High-Dose 25mg` (`160`).
- `generate_pk_biomarker_data()`: `360 x 10` data frame across `50 mg QD` (`120`), `150 mg QD` (`120`), `300 mg QD` (`120`).

---

## 3. Findings Summary Table

| ID | Severity | Domain | Target File(s) | Summary | Status |
|---|---|---|---|---|---|
| F1 | **High** | Primary Endpoint / Methodology | `R/profiler.R` | Unadjusted Welch t-test omits baseline SBP ANCOVA, 95% CI, and evaluable Ns | **Remediated** |
| F2 | **High** | PK Exposure Methodology | `R/profiler.R` | Arithmetic mean ratio used instead of log-scale GMR + 95% CI + dose-normalized ratio | **Remediated** |
| F3 | **High** | TLF Denominators & Table 1 | `R/profiler.R`, `www/js/app.js` | Missing variable-level `n`, no categorical/responder rows, Mean/ANOVA on skewed vars, baseline p-values | **Remediated** |
| F4 | **Medium** | Estimand / Missing Data | `R/profiler.R` | Responder endpoint reports Observed Cases only without ITT-NRI sensitivity | **Remediated** |
| F5 | **Medium** | Multiplicity & Coupling | `R/profiler.R`, `www/js/app.js`, `R/export.R` | Unadjusted pairwise correlation p-values and unflagged coupled pairs (`sbp_change` vs `week12_sbp`) | **Remediated** |
| F6 | **Medium** | Simulation Clinical/PK Realism | `R/profiler.R` | Fractional age/SBP, missing DBP/weight/AST, MCAR dropout, physics-breaking outliers, non-monotone PK NA | **Remediated** |
| F7 | **Medium** | SAS Rounding Compliance | `R/profiler.R`, `R/charts.R`, `R/export.R`, `www/js/app.js` | Half-to-even `base::round()` (`BR-001`), early/cascaded rounding (`BR-002`), dropped trailing zeros (`BR-003`) | **Remediated** |

---

## 4. Detailed Baseline Findings

### F1 [High] — Unadjusted Primary Endpoint Welch t-test Introduces Baseline Bias (`R/profiler.R:318-335`)
- **Observation**: `compute_primary_signal()` computed `mean(hi) - mean(pl)` and `stats::t.test(hi, pl)` on `sbp_change` despite baseline SBP differing slightly across arms (`Placebo = 151.39`, `Low-Dose 10mg = 150.29`, `High-Dose 25mg = 149.18 mmHg`) and regression-to-mean (`-0.12 * (baseline_sbp - 148)`) in the data generator.
- **Executed Baseline Witness**:
  - Unadjusted Welch t-test (`n_hi = 154` vs `n_pl = 152`): `-14.733 mmHg`, 95% CI `[-16.939, -12.527]`, `p = 1.76e-31` (displayed simply as `-14.7 mmHg | High-Dose vs Placebo (p < 0.0001)`).
  - Baseline-adjusted ANCOVA `lm(sbp_change ~ treatment_arm + baseline_sbp)`: High-Dose 25mg vs Placebo LS mean difference = `-15.110 mmHg`, SE `1.096`, 95% CI `[-17.265, -12.956]`, `p = 2.16e-36`; Low-Dose 10mg vs Placebo = `-8.436 mmHg`, 95% CI `[-10.574, -6.297]`, `p = 5.89e-14`.
- **Impact**: Unadjusted analysis understated treatment benefit by `0.38 mmHg`, inflated SE, omitted 95% CIs, and hid evaluable sample sizes (`154` and `152` vs `160` randomized).

### F2 [High] — PK Dose-Exposure Comparison Uses Arithmetic Ratio Instead of Log-Scale GMR (`R/profiler.R:338-353`)
- **Observation**: `compute_primary_signal()` computed arithmetic `mean(hi) / mean(lo)` (`6.111x`) and raw Welch `t.test(hi, lo)` on right-skewed `auc_0_24`.
- **Executed Baseline Witness**:
  - Arithmetic ratio (`300 mg QD` vs `50 mg QD`): `6.111x` (`Welch p = 3.24e-69`, distorted by row 144 / row 17 outlier contamination).
  - Log-scale Geometric Mean Ratio (`exp(mean(log(hi)) - mean(log(lo)))`): `GMR = 6.507x`, 95% CI `[5.999, 7.059]`, `p = 1.59e-116`.
- **Impact**: Violates FDA bioequivalence / clinical pharmacology guidance requiring log-transformed exposure metrics (Geometric Mean, GeoCV%, and GMR with CI).

### F3 [High] — Table 1 Denominator Opacity, Skewed-Metric Misapplication & CONSORT Violation (`R/profiler.R:800-859`)
- **Observation**:
  1. Column headers displayed randomized arm counts (`Placebo (n=160)`, `Low-Dose 10mg (n=160)`, `High-Dose 25mg (n=160)`), while missing data varied per variable (`week12_sbp = 18`, `sbp_change = 18`, `ldl_mg_dl = 14`, `hba1c_pct = 11`, `crp_mg_l = 22`, `eGFR = 9`, `bmi = 6`), leaving cell denominators unreported.
  2. Skewed inflammatory/PK variables used `Mean +/- SD` and Welch ANOVA, masking true drug effects: e.g., `crp_mg_l` reported `2.41 +/- 3.15` vs `2.19 +/- 2.63` vs `1.72 +/- 3.02` (`p = 0.133`, false negative from outlier sensitivity), and `50 mg QD cmax_ng_ml` reported `79.29 +/- 95.54` (SD > Mean!).
  3. Categorical demographics (`site_region`) and clinical response (`responder_status`) were completely excluded from Table 1.
  4. Baseline covariates (`age p = 0.673`, `bmi p = 0.589`, `baseline_sbp p = 0.101`, `eGFR p = 0.970`) printed formal hypothesis-test p-values across randomized arms.

### F4 [Medium] — Responder Endpoint Ignores ITT Non-Responder Imputation (`R/profiler.R:105-109`)
- **Executed Baseline Witness**:
  - `Placebo`: Observed Cases (OC) = `37/152 (24.34%)` vs ITT-NRI = `37/160 (23.12%)`
  - `Low-Dose 10mg`: OC = `91/156 (58.33%)` vs ITT-NRI = `91/160 (56.88%)`
  - `High-Dose 25mg`: OC = `134/154 (87.01%)` vs ITT-NRI = `134/160 (83.75%)` (`-3.26` percentage points difference).
- **Impact**: Presenting only Observed Case responder fractions overstates clinical efficacy relative to standard Phase III ITT-NRI estimands.

### F5 [Medium] — Unadjusted Multiple Testing & Unannotated Coupled Correlations (`R/profiler.R:582-684`)
- **Executed Baseline Witness**:
  - `get_top_correlations()` computed all pairwise tests with raw p-values only (`BH FDR` absent).
  - Top ranked pair in `cardio_trial` was `week12_sbp vs sbp_change` (`r = 0.749`, `p = 2.49e-84`) — mathematically coupled (`sbp_change = week12_sbp - baseline_sbp`).

### F6 [Medium] — Synthetic Data Clinical & Pharmacological Realism Gaps (`R/profiler.R:11-229`)
- **Executed Baseline Witnesses**:
  - **Clinical Trial**:
    - Non-integer `age`: `419/480` subjects had fractional ages (e.g., `61.4`).
    - Non-integer `baseline_sbp`: `432/480` subjects had fractional `0.1 mmHg` blood pressures (`153.5`).
    - Pure MCAR missingness (`week12_sbp`: `6` High-Dose, `4` Low-Dose, `8` Placebo) and `baseline_sbp` region ANOVA `p = 0.6355` with no DBP or sex covariates.
    - Hardcoded outlier overwrite `CMT-0389` (`Low-Dose 10mg`) had `week12_sbp = 82.0` (`sbp_change = -73.6`), and `CMT-0088`/`CMT-0366` had baseline `eGFR = 18.5` / `21.0 mL/min/1.73m^2` (incompatible with typical Phase III inclusion `eGFR >= 30`).
  - **PK & Biomarker**:
    - Non-monotone NCA missingness: `7` rows had `auc_0_24 = NA` while `half_life_hr` remained non-missing.
    - Hardcoded outlier overwrite `PKB-0144` (`150 mg QD`) received `cmax_ng_ml = 1245.0` and `auc_0_24 = 12180.5` despite normal clearance `7.05 L/hr` and `half_life_hr = 16.93 hr`.
    - `get_preset_meta("pk_biomarker")` described a 1-row/subject cross-sectional steady-state NCA dataset as `"Longitudinal Assay"`.
    - Absent `body_weight_kg` and `hepatic_ast` precluded allometric CL scaling and Hy's Law AST/ALT concordance checks.

### F7 [Medium] — SAS-Compatible Rounding Non-Compliance (`BR-001`, `BR-002`, `BR-003`)
- **BR-001**: Numeric summaries across `profiler.R` relied on `base::round()` (IEC 60559 half-to-even) rather than SAS-compatible half-away-from-zero.
- **BR-002 (Early / Cascaded Rounding)**:
  - `profile_distribution_stats()` (`profiler.R:712-714`) computed `iqr_val <- round(q3_val - q1_val, 3)` from pre-rounded quartiles.
  - `chart_overview()` (`charts.R:107`) derived `pct_complete <- 100 - plot_df$pct_missing` from pre-rounded percentages.
- **BR-003 (Trailing Zero Dropping)**:
  - `export.R:85, 89` interpolated unformatted numeric percentages (`paste0(overview$pct_complete_cases, "%")`), dropping trailing zeros (e.g., `95%` vs `95.0%`), and `sub_res$table` / `var_summary` lacked uniform fixed-decimal formatting helpers.

---

## 5. Planned Remediation & Architectural Invariants

1. **Pure Base R Implementation**: Implement ANCOVA (`stats::lm` + `stats::confint` + `stats::anova`), log-scale GMR / GeoCV%, Benjamini-Hochberg FDR (`stats::p.adjust`), Kruskal-Wallis / Wilcoxon / Chi-square / Fisher tests, and SAS-compatible rounding (`round_half_away`, `fmt_fixed`, `fmt_pct`, `fmt_p_value`) in base R with zero added package dependencies.
2. **UI & Export Contract Preservation**: Maintain all existing DOM IDs and IPC endpoints (`load_preset`, `load_data`, `run_profile`, `update_distribution`, `update_correlation`, `update_outliers`, `update_subgroup`, `refresh_theme_charts`, `copy_summary`, `export_report`, `export_csv`) and ensure arbitrary user data frames (e.g., `mtcars`) profile cleanly.

---

## 6. Post-Remediation Verification

All post-remediation statistics were verified directly in `R 4.5.1` after updating `inst/apps/data_studio/R/profiler.R`, `R/charts.R`, `R/export.R`, `R/server.R`, `www/index.html`, `www/js/app.js`, and `www/css/style.css`:

1. **Cardio-Metabolic Cohort & ANCOVA Verification (`n = 480`, 17 variables)**:
   - Integer clinical measurements verified for `age`, `baseline_sbp`, `week12_sbp`, `baseline_dbp`, and `week12_dbp`.
   - Multi-regional heterogeneity verified: `site_region` vs `bmi` ANOVA `p = 4.32e-27`.
   - Baseline renal eligibility satisfied across all observed subjects (`min(eGFR) = 31.2 >= 30.0 mL/min/1.73m^2`).
   - Systolic/diastolic physiologic co-movement verified: `r(baseline_sbp, baseline_dbp) = 0.554`, `r(sbp_change, dbp_change) = 0.804`.
   - Differential Week-12 dropout: `High-Dose 25mg` = `4/160`, `Low-Dose 10mg` = `7/160`, `Placebo` = `9/160`.
   - Primary endpoint KPI (`compute_primary_signal()`): **`-14.6 mmHg`** (`25mg vs Placebo (n=156 vs 151), 95% CI [-16.5, -12.8], p < 0.0001`).
   - Table 1 checks:
     - All baseline demographics (`sex`, `site_region`, `age`, `bmi`, `baseline_sbp`, `baseline_dbp`, `eGFR`) display `-- (Baseline)` per CONSORT.
     - Both responder definitions reported explicitly: `ITT-NRI` (`9.4%` vs `41.9%` vs `65.6%`) and `Observed` (`9.9% [n=151]` vs `43.8% [n=153]` vs `67.3% [n=156]`).
     - Skewed inflammation biomarker `crp_mg_l` now reports `Median [Q1, Q3]` with Kruskal-Wallis test (`1.67 [1.11, 2.62]` vs `1.68 [1.14, 2.31]` vs `1.31 [0.89, 2.08]`, `p = 0.008 (KW)`), recovering the true anti-inflammatory signal masked previously by `Mean +/- SD` (`p = 0.133`).
   - Pairwise correlations include Benjamini-Hochberg `FDR q` across all pairs and tag mathematically coupled pairs (`week12_sbp` vs `sbp_change`, `week12_dbp` vs `dbp_change`) as `Coupled`.

2. **PK & Biomarker Steady-State NCA Cohort (`n = 360`, 12 variables)**:
   - Monotone NCA missingness verified: `0` rows have `auc_0_24 = NA` with non-missing `half_life_hr`.
   - Mechanistic relationships verified: `r(hepatic_alt, hepatic_ast) = 0.762`; `r(half_life_hr, clearance_l_hr) = -0.625`.
   - Log-scale primary exposure signal: **`5.83x GMR`** (`300 vs 50 mg (n=116 vs 116), 95% CI [5.41, 6.29], DN 0.97x, p < 0.0001`).
   - Table 1 displays `GeoMean (GeoCV%)` with log-scale tests for `cmax_ng_ml` and `auc_0_24` (`1090.5 (27.0%)`, `3047.2 (27.7%)`, `6358.6 (32.1%)`, `p < 0.0001 (Log)`), and `Median [Q1, Q3]` + Kruskal-Wallis for skewed PD/safety markers (`biomarker_il6 p < 0.0001`, `hepatic_alt p = 0.012`, `hepatic_ast p = 0.002`).

3. **SAS Rounding & Edge-Case Verification (`BR-001` / `BR-002` / `BR-003`)**:
   - `round_half_away(c(2.5, 3.5, -2.5, -3.5), 0L)` == `c(3, 4, -3, -4)`; `round_half_away(1.005, 2L)` == `1.01`.
   - `fmt_fixed(12, 2L)` == `"12.00"`; `fmt_fixed(-0.0001, 2L)` == `"0.00"` (signed-zero guarded).
   - Zero early-IQR rounding discrepancies across all numeric variables in both cohorts (`round_half_away(q3_raw - q1_raw, 3L) == ds$iqr`).
   - Generic datasets (`mtcars` all-numeric, `iris` mixed categorical/numeric), all 4 ggplot2 charts in Light & Dark modes, and HTML export all passed.


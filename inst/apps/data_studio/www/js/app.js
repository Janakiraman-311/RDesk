// Data Intelligence Studio — Clinical & Biostatistical Explorer UI Logic

var currentData = null;
var currentFile = null;
var activeDistVar = "";
var activeDistGroup = "";
var activeDistMode = "density";
var activeSubgroupCol = "";

var settings = {
  theme: "light",
  corr_method: "pearson",
  outlier_threshold: 1.5
};

// ── Utilities ───────────────────────────────────────────────────────────────

function escapeHtml(val) {
  if (val === null || val === undefined) return "";
  return String(val)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function toArray(val) {
  if (val === null || val === undefined) return [];
  return Array.isArray(val) ? val : [val];
}

function unwrapScalar(val) {
  if (Array.isArray(val)) return val.length > 0 ? val[0] : null;
  return val;
}

function isCancelled(result) {
  var c = unwrapScalar(result && result.cancelled);
  return c === true || c === "true";
}

function formatBase64Src(src) {
  var srcStr = unwrapScalar(src);
  if (!srcStr || typeof srcStr !== "string") return "";
  if (srcStr.indexOf("data:") === 0) return srcStr;
  return "data:image/png;base64," + srcStr;
}

function formatNum(val, digits) {
  var v = unwrapScalar(val);
  if (v === null || v === undefined || v === "" || isNaN(Number(v))) return "--";
  return Number(v).toFixed(digits !== undefined ? digits : 2);
}

function getSourceDescriptor() {
  if (!currentData) return null;
  return {
    path: unwrapScalar(currentData.path) || "",
    preset_id: unwrapScalar(currentData.preset_id) || "",
    filename: unwrapScalar(currentData.filename) || ""
  };
}

function showToast(message, type) {
  var kind = type || "info";
  var stack = document.getElementById("studio-toast-stack");
  if (!stack) {
    stack = document.createElement("div");
    stack.id = "studio-toast-stack";
    stack.className = "studio-toast-stack";
    stack.setAttribute("role", "status");
    stack.setAttribute("aria-live", "polite");
    document.body.appendChild(stack);
  }

  var toast = document.createElement("div");
  toast.className = "studio-toast tone-" + kind;
  toast.textContent = String(message || "");
  stack.appendChild(toast);

  requestAnimationFrame(function () {
    toast.classList.add("visible");
  });

  setTimeout(function () {
    toast.classList.remove("visible");
    setTimeout(function () {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, 240);
  }, 3400);
}

// ── Initialisation ──────────────────────────────────────────────────────────

rdesk.ready(function () {
  setupNavigation();
  setupButtons();
  setupDistributionControls();
  setupCorrelationControls();
  setupOutlierControls();
  setupVariableControls();
  setupSettingsModal();

  // Trigger startup preferences & auto-load of Phase III Clinical Trial Cohort
  rdesk.send("ready", {});
});

// ── Navigation ──────────────────────────────────────────────────────────────

function setupNavigation() {
  document.querySelectorAll(".nav-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      switchPanel(this.dataset.panel);
    });
  });
}

function switchPanel(name) {
  document.querySelectorAll(".nav-btn").forEach(function (b) {
    b.classList.toggle("active", b.dataset.panel === name);
  });
  document.querySelectorAll(".panel").forEach(function (p) {
    var isTarget = p.id === "panel-" + name;
    p.classList.toggle("hidden", !isTarget);
    p.classList.toggle("active", isTarget);
  });
}

// ── Buttons & Presets ───────────────────────────────────────────────────────

function setupButtons() {
  document.getElementById("btn-open").addEventListener("click", function () {
    rdesk.send("open_file", {});
  });

  document.querySelectorAll(".preset-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var preset = this.dataset.preset;
      rdesk.send("load_preset", { preset: preset, settings: settings });
    });
  });

  var btnSample = document.getElementById("btn-sample");
  if (btnSample) {
    btnSample.addEventListener("click", function () {
      rdesk.send("load_preset", { preset: "cardio_trial", settings: settings });
    });
  }

  var btnEmptyPk = document.getElementById("btn-empty-pk");
  if (btnEmptyPk) {
    btnEmptyPk.addEventListener("click", function () {
      rdesk.send("load_preset", { preset: "pk_biomarker", settings: settings });
    });
  }

  document.getElementById("btn-profile").addEventListener("click", function () {
    if (!currentData) return;
    rdesk.send("run_profile", {
      data: getSourceDescriptor(),
      settings: settings,
      dist_var: activeDistVar,
      group_by: activeDistGroup,
      plot_mode: activeDistMode
    });
  });

  document.getElementById("btn-export").addEventListener("click", triggerExportReport);
  document.getElementById("btn-export-csv").addEventListener("click", triggerExportCsv);

  document.getElementById("btn-theme-toggle").addEventListener("click", function () {
    var nextTheme = settings.theme === "dark" ? "light" : "dark";
    applyThemeUI(nextTheme);
    rdesk.send("refresh_theme_charts", {
      theme: nextTheme,
      source: getSourceDescriptor(),
      corr_method: settings.corr_method,
      outlier_threshold: settings.outlier_threshold,
      variable: activeDistVar,
      group_by: activeDistGroup,
      plot_mode: activeDistMode
    });
  });

  document.getElementById("btn-settings").addEventListener("click", openSettingsModal);
}

function triggerExportReport() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("export_report", {
    data: currentData,
    filename: currentFile,
    variable_summary: currentData.variable_summary
  });
}

function triggerExportCsv() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("export_csv", {
    filename: currentFile,
    variable_summary: currentData.variable_summary
  });
}

function applyThemeUI(mode) {
  var theme = mode === "dark" ? "dark" : "light";
  settings.theme = theme;
  document.documentElement.setAttribute("data-theme", theme);

  var sun = document.getElementById("icon-theme-sun");
  var moon = document.getElementById("icon-theme-moon");
  var lbl = document.getElementById("theme-toggle-label");
  if (sun && moon && lbl) {
    sun.classList.toggle("hidden", theme !== "dark");
    moon.classList.toggle("hidden", theme === "dark");
    lbl.textContent = theme === "dark" ? "Light Mode" : "Dark Mode";
  }
}

// ── Distribution Controls ───────────────────────────────────────────────────

function setupDistributionControls() {
  var varSel = document.getElementById("dist-var-select");
  var grpSel = document.getElementById("dist-group-select");

  varSel.addEventListener("change", function () {
    activeDistVar = this.value;
    requestDistributionUpdate();
  });

  grpSel.addEventListener("change", function () {
    activeDistGroup = this.value === "none" ? "" : this.value;
    requestDistributionUpdate();
  });

  document.querySelectorAll("[data-dist-mode]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      activeDistMode = this.dataset.distMode;
      syncSegmentedButtons("[data-dist-mode]", "distMode", activeDistMode);
      requestDistributionUpdate();
    });
  });
}

function requestDistributionUpdate() {
  if (!currentData || !activeDistVar) return;
  rdesk.send("update_distribution", {
    source: getSourceDescriptor(),
    variable: activeDistVar,
    group_by: activeDistGroup,
    plot_mode: activeDistMode,
    theme: settings.theme
  });
}

// ── Correlation Controls ────────────────────────────────────────────────────

function setupCorrelationControls() {
  document.querySelectorAll("[data-corr-method]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var method = this.dataset.corrMethod;
      settings.corr_method = method;
      syncSegmentedButtons("[data-corr-method]", "corrMethod", method);
      if (!currentData) return;
      rdesk.send("update_correlation", {
        source: getSourceDescriptor(),
        corr_method: method,
        theme: settings.theme
      });
    });
  });

  document.getElementById("corr-search").addEventListener("input", function () {
    if (currentData && currentData.top_corr) {
      renderCorrelationsTable(currentData.top_corr);
    }
  });

  document.getElementById("corr-filter").addEventListener("change", function () {
    if (currentData && currentData.top_corr) {
      renderCorrelationsTable(currentData.top_corr);
    }
  });
}

// ── Outlier Controls ────────────────────────────────────────────────────────

function setupOutlierControls() {
  document.querySelectorAll("[data-outlier-th]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var th = parseFloat(this.dataset.outlierTh);
      settings.outlier_threshold = th;
      syncSegmentedButtons("[data-outlier-th]", "outlierTh", th.toFixed(1));
      if (!currentData) return;
      rdesk.send("update_outliers", {
        source: getSourceDescriptor(),
        outlier_threshold: th,
        theme: settings.theme
      });
    });
  });
}

// ── Variable & Subgroup Controls ────────────────────────────────────────────

function setupVariableControls() {
  document.getElementById("var-search").addEventListener("input", function () {
    if (currentData && currentData.variable_summary) {
      renderVariableDictionary(currentData.variable_summary);
    }
  });

  document.getElementById("var-type-filter").addEventListener("change", function () {
    if (currentData && currentData.variable_summary) {
      renderVariableDictionary(currentData.variable_summary);
    }
  });

  document.getElementById("btn-copy-summary").addEventListener("click", function () {
    if (!currentData) return;
    rdesk.send("copy_summary", {
      target: "variables",
      table_data: currentData.variable_summary,
      source: getSourceDescriptor()
    });
  });

  document.getElementById("btn-copy-subgroup").addEventListener("click", function () {
    if (!currentData) return;
    rdesk.send("copy_summary", {
      target: "subgroup",
      table_data: currentData.subgroup_table,
      group_col: activeSubgroupCol,
      source: getSourceDescriptor()
    });
  });

  document.getElementById("subgroup-select").addEventListener("change", function () {
    activeSubgroupCol = this.value;
    if (!currentData || !activeSubgroupCol) return;
    rdesk.send("update_subgroup", {
      source: getSourceDescriptor(),
      group_col: activeSubgroupCol
    });
  });
}

function syncSegmentedButtons(selector, dataKey, activeVal) {
  document.querySelectorAll(selector).forEach(function (b) {
    b.classList.toggle("active", b.dataset[dataKey] === String(activeVal));
  });
}

// ── Main Data Render Pipeline ───────────────────────────────────────────────

function handleLoadedData(data) {
  if (!data) return;
  if (data.error) {
    showToast("Error: " + data.error, "error");
    return;
  }

  currentData = data;
  currentFile = unwrapScalar(data.filename) || "dataset";

  var presetId = unwrapScalar(data.preset_id) || "";
  var label = unwrapScalar(data.dataset_label) || currentFile;
  var subtitle = unwrapScalar(data.dataset_subtitle) || "";

  // Update active preset indicator in sidebar
  document.querySelectorAll(".preset-btn").forEach(function (btn) {
    btn.classList.toggle("active", presetId !== "" && btn.dataset.preset === presetId);
  });

  // Update top header
  document.getElementById("dataset-name").textContent = label;
  document.getElementById("dataset-badge").textContent = presetId ? "Reference Cohort" : "Local File";
  var dimsText = data.n_rows + " rows \u00D7 " + data.n_cols + " variables";
  document.getElementById("dataset-dims").textContent = subtitle ? (dimsText + "  \u2022  " + subtitle) : dimsText;

  document.getElementById("dataset-info").classList.remove("hidden");
  document.getElementById("no-data-prompt").classList.add("hidden");
  document.getElementById("btn-profile").classList.remove("hidden");
  document.getElementById("btn-export").classList.remove("hidden");
  document.getElementById("btn-export-csv").classList.remove("hidden");

  // Sync estimator controls with payload
  if (data.corr_method) {
    settings.corr_method = unwrapScalar(data.corr_method);
    syncSegmentedButtons("[data-corr-method]", "corrMethod", settings.corr_method);
  }
  if (data.outlier_threshold) {
    settings.outlier_threshold = parseFloat(unwrapScalar(data.outlier_threshold));
    syncSegmentedButtons("[data-outlier-th]", "outlierTh", settings.outlier_threshold.toFixed(1));
  }

  // Overview KPIs & Completeness Audit Chart
  renderKPIs(data.overview);
  if (data.preview_chart) {
    document.getElementById("overview-chart").src = formatBase64Src(data.preview_chart);
  }

  // Sidebar count badges
  updateNavBadges(data.overview);

  // Distributions Explorer controls, stats strip & chart
  populateDistributionDropdowns(data);
  if (data.dist_charts) {
    document.getElementById("dist-chart").src = formatBase64Src(data.dist_charts);
  }
  renderDistributionStats(data.dist_stats);

  // Correlations heatmap & searchable table
  if (data.corr_chart) {
    document.getElementById("corr-chart").src = formatBase64Src(data.corr_chart);
  }
  renderCorrelationsTable(data.top_corr);

  // Outliers chart & table
  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src = formatBase64Src(data.outlier_chart);
  }
  renderOutliersTable(data.outlier_table);
  updateOutlierSummaryBadge(data.outlier_table);

  // Variable Dictionary & Subgroup Table 1
  renderVariableDictionary(data.variable_summary);
  populateSubgroupDropdown(data);
  renderSubgroupTable(data.subgroup_table, data.subgroup_col, data.subgroup_footnote);

  showToast("Profiled " + label, "success");

  rdesk.send("studio_data_rendered", {
    preset_id: presetId,
    n_rows: Number(unwrapScalar(data.n_rows) || 0),
    n_cols: Number(unwrapScalar(data.n_cols) || 0),
    kpi_count: document.querySelectorAll("#kpi-grid .kpi-card").length,
    table1_rows: document.querySelectorAll("#subgroup-tbody tr").length,
    has_overview_chart: (document.getElementById("overview-chart").src || "").indexOf("data:image/png;base64,") === 0,
    has_dist_chart: (document.getElementById("dist-chart").src || "").indexOf("data:image/png;base64,") === 0,
    has_corr_chart: (document.getElementById("corr-chart").src || "").indexOf("data:image/png;base64,") === 0,
    has_outlier_chart: (document.getElementById("outlier-chart").src || "").indexOf("data:image/png;base64,") === 0,
    primary_metric: unwrapScalar(data.overview && data.overview.primary_metric_value) || ""
  });
}

function updateNavBadges(overview) {
  if (!overview) return;
  var outBadge = document.getElementById("nav-badge-outliers");
  var varBadge = document.getElementById("nav-badge-vars");

  var nOut = Number(unwrapScalar(overview.total_outliers) || 0);
  if (outBadge) {
    outBadge.textContent = nOut;
    outBadge.classList.toggle("hidden", false);
  }
  if (varBadge) {
    varBadge.textContent = unwrapScalar(overview.n_cols) || 0;
    varBadge.classList.toggle("hidden", false);
  }
}

// ── KPI Cards Renderer ──────────────────────────────────────────────────────

function renderKPIs(overview) {
  if (!overview) return;
  var grid = document.getElementById("kpi-grid");

  var pctComplete = Number(unwrapScalar(overview.pct_complete_cases) || 0);
  var pctMiss = Number(unwrapScalar(overview.pct_missing) || 0);
  var pctCompleteStr = unwrapScalar(overview.pct_complete_fmt) || (pctComplete.toFixed(1) + "%");
  var pctMissStr = unwrapScalar(overview.pct_missing_fmt) || (pctMiss.toFixed(2) + "%");
  var nOut = Number(unwrapScalar(overview.total_outliers) || 0);
  var varsOut = Number(unwrapScalar(overview.vars_with_outliers) || 0);

  var items = [
    {
      label: "Subjects / Rows",
      value: unwrapScalar(overview.n_rows),
      sub: unwrapScalar(overview.n_cols) + " variables \u00B7 " + unwrapScalar(overview.memory_kb) + " KB",
      tone: ""
    },
    {
      label: "Complete Cases",
      value: pctCompleteStr,
      sub: unwrapScalar(overview.complete_cases) + " of " + unwrapScalar(overview.n_rows) + " complete",
      tone: pctComplete >= 90 ? "tone-success" : "tone-warning"
    },
    {
      label: "Variables (Num / Cat)",
      value: unwrapScalar(overview.n_numeric) + " / " + unwrapScalar(overview.n_categorical),
      sub: "Numeric continuous vs categorical",
      tone: "tone-info"
    },
    {
      label: unwrapScalar(overview.primary_metric_label) || "Primary Signal",
      value: unwrapScalar(overview.primary_metric_value) || "N/A",
      sub: unwrapScalar(overview.primary_metric_sub) || "",
      tone: ""
    },
    {
      label: "Missing Data Rate",
      value: pctMissStr,
      sub: unwrapScalar(overview.total_missing) + " missing cells total",
      tone: pctMiss === 0 ? "tone-success" : (pctMiss < 5 ? "tone-warning" : "tone-danger")
    },
    {
      label: "Tukey Outlier Flags",
      value: nOut + (nOut === 1 ? " flag" : " flags"),
      sub: varsOut + " numeric variable" + (varsOut === 1 ? "" : "s") + " (" + settings.outlier_threshold.toFixed(1) + "\u00D7 IQR)",
      tone: nOut === 0 ? "tone-success" : "tone-danger"
    }
  ];

  grid.innerHTML = items.map(function (item) {
    return (
      "<div class='kpi-card " + item.tone + "'>" +
      "<div class='kpi-label'>" + escapeHtml(item.label) + "</div>" +
      "<div class='kpi-value'>" + escapeHtml(item.value) + "</div>" +
      "<div class='kpi-sub'>" + escapeHtml(item.sub) + "</div>" +
      "</div>"
    );
  }).join("");

  var pill = document.getElementById("overview-status-pill");
  if (pill) {
    if (pctMiss === 0) {
      pill.textContent = "100% Complete";
      pill.className = "status-pill success";
    } else if (pctMiss < 5) {
      pill.textContent = "Completeness " + (100 - pctMiss).toFixed(1) + "%";
      pill.className = "status-pill";
    } else {
      pill.textContent = "Elevated Missingness (" + pctMiss.toFixed(1) + "%)";
      pill.className = "status-pill warn";
    }
  }
}

// ── Distributions Explorer Renderers ────────────────────────────────────────

function populateDistributionDropdowns(data) {
  var numVars = toArray(data.numeric_vars);
  var catVars = toArray(data.categorical_vars);

  activeDistVar = unwrapScalar(data.active_var) || (numVars.length > 0 ? numVars[0] : "");
  activeDistGroup = unwrapScalar(data.active_group) || "";
  activeDistMode = unwrapScalar(data.plot_mode) || "density";

  var varSel = document.getElementById("dist-var-select");
  varSel.innerHTML = numVars.length > 0
    ? numVars.map(function (v) {
        return "<option value='" + escapeHtml(v) + "'>" + escapeHtml(v) + "</option>";
      }).join("")
    : "<option value=''>No numeric variables</option>";
  if (activeDistVar) varSel.value = activeDistVar;

  var grpSel = document.getElementById("dist-group-select");
  var grpOptions = ["<option value='none'>None (Overall Cohort)</option>"];
  catVars.forEach(function (c) {
    grpOptions.push("<option value='" + escapeHtml(c) + "'>" + escapeHtml(c) + "</option>");
  });
  grpSel.innerHTML = grpOptions.join("");
  grpSel.value = activeDistGroup ? activeDistGroup : "none";

  syncSegmentedButtons("[data-dist-mode]", "distMode", activeDistMode);
}

function renderDistributionStats(ds) {
  var strip = document.getElementById("dist-stats-strip");
  var groupCard = document.getElementById("dist-group-card");

  if (!ds || !unwrapScalar(ds.variable)) {
    strip.innerHTML = "";
    groupCard.classList.add("hidden");
    return;
  }

  var nValid = unwrapScalar(ds.n) || 0;
  var nMiss = unwrapScalar(ds.n_missing) || 0;
  var meanStr = (unwrapScalar(ds.mean_fmt) || formatNum(ds.mean, 2)) + " \u00B1 " + (unwrapScalar(ds.sd_fmt) || formatNum(ds.sd, 2));
  var medStr = (unwrapScalar(ds.median_fmt) || formatNum(ds.median, 2)) + " [" + (unwrapScalar(ds.q1_fmt) || formatNum(ds.q1, 2)) + ", " + (unwrapScalar(ds.q3_fmt) || formatNum(ds.q3, 2)) + "]";
  var rangeStr = (unwrapScalar(ds.min_fmt) || formatNum(ds.min, 2)) + " to " + (unwrapScalar(ds.max_fmt) || formatNum(ds.max, 2));
  var skewVal = unwrapScalar(ds.skew_fmt) || formatNum(ds.skewness, 3);
  var iqrStr = unwrapScalar(ds.iqr_fmt) || formatNum(ds.iqr, 2);
  var swLabel = unwrapScalar(ds.shapiro_label) || "N/A";
  var normStatus = unwrapScalar(ds.normality_status) || "";

  var sixthCard;
  if (ds.group_test && unwrapScalar(ds.group_test.method)) {
    sixthCard = {
      label: unwrapScalar(ds.group_test.method),
      value: "p " + (String(unwrapScalar(ds.group_test.p_value)).indexOf("<") === 0
        ? unwrapScalar(ds.group_test.p_value)
        : "= " + unwrapScalar(ds.group_test.p_value)),
      sub: unwrapScalar(ds.group_test.nonparam) + " p " +
        (String(unwrapScalar(ds.group_test.nonparam_p)).indexOf("<") === 0
          ? unwrapScalar(ds.group_test.nonparam_p)
          : "= " + unwrapScalar(ds.group_test.nonparam_p))
    };
  } else {
    sixthCard = {
      label: "Observed Sample",
      value: "n = " + nValid,
      sub: nMiss > 0 ? (nMiss + " missing values") : "0 missing values"
    };
  }

  var cards = [
    { label: "Mean \u00B1 SD", value: meanStr, sub: "n = " + nValid + " valid" },
    { label: "Median [Q1, Q3]", value: medStr, sub: "IQR = " + iqrStr },
    { label: "Observed Range", value: rangeStr, sub: "Min to Max" },
    { label: "Skewness", value: skewVal, sub: Math.abs(Number(unwrapScalar(ds.skewness) || 0)) > 1 ? "Substantially skewed" : "Symmetric / Mild" },
    { label: "Shapiro-Wilk", value: swLabel === "N/A" ? "N/A" : ("p " + (swLabel.indexOf("<") === 0 ? swLabel : "= " + swLabel)), sub: normStatus },
    sixthCard
  ];

  strip.innerHTML = cards.map(function (c) {
    return (
      "<div class='stat-chip'>" +
      "<div class='stat-label'>" + escapeHtml(c.label) + "</div>" +
      "<div class='stat-value'>" + escapeHtml(c.value) + "</div>" +
      "<div class='stat-sub'>" + escapeHtml(c.sub) + "</div>" +
      "</div>"
    );
  }).join("");

  // Per-group breakdown table
  var gt = ds.group_table;
  var grpName = unwrapScalar(ds.group_by) || "";
  if (grpName && gt && gt.rows && gt.rows.length > 0) {
    groupCard.classList.remove("hidden");
    document.getElementById("dist-group-title").textContent =
      unwrapScalar(ds.variable) + " by " + grpName;
    document.getElementById("dist-group-subtitle").textContent =
      "Cohort-stratified descriptive summary across " + gt.rows.length + " strata";
    renderGenericTable("dist-group-thead", "dist-group-tbody", gt, {
      group: "Cohort / Group",
      n: "N",
      mean: "Mean",
      sd: "SD",
      median: "Median",
      iqr: "IQR",
      min: "Min",
      max: "Max"
    });
  } else {
    groupCard.classList.add("hidden");
  }
}

// ── Correlations Table Renderer ─────────────────────────────────────────────

function renderCorrelationsTable(corrData) {
  var thead = document.getElementById("corr-thead");
  var tbody = document.getElementById("corr-tbody");
  var countLbl = document.getElementById("corr-count-label");

  var methodLbl = settings.corr_method === "spearman"
    ? "Spearman \u03C1"
    : (settings.corr_method === "kendall" ? "Kendall \u03C4" : "Pearson r");

  thead.innerHTML =
    "<tr>" +
    "<th>Variable 1</th>" +
    "<th>Variable 2</th>" +
    "<th>" + methodLbl + "</th>" +
    "<th>95% CI</th>" +
    "<th>p (Nominal)</th>" +
    "<th>FDR q (BH)</th>" +
    "<th>Pairs (n)</th>" +
    "<th>Strength</th>" +
    "<th>Note</th>" +
    "</tr>";

  if (!corrData || !corrData.rows || corrData.rows.length === 0) {
    tbody.innerHTML = "<tr><td colspan='9' class='empty-row'>At least two numeric variables are required to compute correlations.</td></tr>";
    if (countLbl) countLbl.textContent = "0 pairs";
    return;
  }

  var q = (document.getElementById("corr-search").value || "").trim().toLowerCase();
  var flt = document.getElementById("corr-filter").value || "all";

  var filtered = corrData.rows.filter(function (row) {
    var v1 = String(unwrapScalar(row.var1) || "");
    var v2 = String(unwrapScalar(row.var2) || "");
    var rVal = Number(unwrapScalar(row.r) || 0);
    var pNum = Number(unwrapScalar(row.p_num) !== null ? unwrapScalar(row.p_num) : 1);
    var pAdjRaw = unwrapScalar(row.p_adj_num);
    var pAdjNum = Number(pAdjRaw !== null && pAdjRaw !== undefined ? pAdjRaw : pNum);

    if (q && v1.toLowerCase().indexOf(q) === -1 && v2.toLowerCase().indexOf(q) === -1) {
      return false;
    }
    if (flt === "sig" && !(pAdjNum < 0.05)) return false;
    if (flt === "moderate" && Math.abs(rVal) < 0.30) return false;
    if (flt === "strong" && Math.abs(rVal) < 0.50) return false;
    return true;
  });

  if (countLbl) {
    countLbl.textContent = "Showing " + filtered.length + " of " + corrData.rows.length + " pairwise correlations (" + methodLbl + ")";
  }

  if (filtered.length === 0) {
    tbody.innerHTML = "<tr><td colspan='9' class='empty-row'>No correlation pairs match the current filter.</td></tr>";
    return;
  }

  tbody.innerHTML = filtered.map(function (row) {
    var rVal = Number(unwrapScalar(row.r) || 0);
    var pct = Math.min(100, Math.round(Math.abs(rVal) * 100));
    var signCls = rVal >= 0 ? "pos" : "neg";
    var rFmt = unwrapScalar(row.r_fmt);
    var rStr = rFmt ? ((rVal >= 0 && rFmt.charAt(0) !== "-" ? "+" : "") + rFmt) : ((rVal >= 0 ? "+" : "") + rVal.toFixed(3));
    var pVal = unwrapScalar(row.p_value) || "N/A";
    var pNum = Number(unwrapScalar(row.p_num) !== null ? unwrapScalar(row.p_num) : 1);
    var pAdjVal = unwrapScalar(row.p_adj_bh) || pVal;
    var pAdjRaw = unwrapScalar(row.p_adj_num);
    var pAdjNum = Number(pAdjRaw !== null && pAdjRaw !== undefined ? pAdjRaw : pNum);
    var strength = unwrapScalar(row.strength) || "";
    var note = String(unwrapScalar(row.note) || "");
    var noteHtml = note === "Coupled"
      ? "<span class='coupled-badge' title='Variables share a mathematical definition'>Coupled</span>"
      : "--";
    var pillCls = (strength === "Very Strong" || strength === "Strong")
      ? "status-pill"
      : (strength === "Moderate" ? "status-pill warn" : "type-badge numeric");

    return (
      "<tr>" +
      "<td class='mono'>" + escapeHtml(unwrapScalar(row.var1)) + "</td>" +
      "<td class='mono'>" + escapeHtml(unwrapScalar(row.var2)) + "</td>" +
      "<td><div class='corr-cell'>" +
        "<span class='corr-num " + signCls + "'>" + escapeHtml(rStr) + "</span>" +
        "<div class='corr-bar-track'><div class='corr-bar-fill " + signCls + "' style='width:" + pct + "%'></div></div>" +
      "</div></td>" +
      "<td class='mono'>" + escapeHtml(unwrapScalar(row.ci_95) || "N/A") + "</td>" +
      "<td class='mono'>" + (pNum < 0.05 ? "<strong>" + escapeHtml(pVal) + "</strong>" : escapeHtml(pVal)) + "</td>" +
      "<td class='mono'>" + (pAdjNum < 0.05 ? "<strong>" + escapeHtml(pAdjVal) + "</strong>" : escapeHtml(pAdjVal)) + "</td>" +
      "<td>" + escapeHtml(unwrapScalar(row.n_pairs)) + "</td>" +
      "<td><span class='" + pillCls + "'>" + escapeHtml(strength) + "</span></td>" +
      "<td>" + noteHtml + "</td>" +
      "</tr>"
    );
  }).join("");
}

// ── Outliers Audit Table Renderer ───────────────────────────────────────────

function renderOutliersTable(outlierData) {
  var thead = document.getElementById("outlier-thead");
  var tbody = document.getElementById("outlier-tbody");

  thead.innerHTML =
    "<tr>" +
    "<th>Variable</th>" +
    "<th>Valid N</th>" +
    "<th>Outliers</th>" +
    "<th>Rate (%)</th>" +
    "<th>Lower Fence</th>" +
    "<th>Upper Fence</th>" +
    "<th>Flagged Row Indices (1-based)</th>" +
    "</tr>";

  if (!outlierData || !outlierData.rows || outlierData.rows.length === 0) {
    tbody.innerHTML = "<tr><td colspan='7' class='empty-row'>No numeric variables available for outlier screening.</td></tr>";
    return;
  }

  tbody.innerHTML = outlierData.rows.map(function (row) {
    var nOut = Number(unwrapScalar(row.n_outliers) || 0);
    var pct = Number(unwrapScalar(row.pct_outliers) || 0);
    var pctStr = unwrapScalar(row.pct_outliers_fmt) || pct.toFixed(2);
    var loStr = unwrapScalar(row.lower_fmt) || formatNum(row.lower_bound, 2);
    var hiStr = unwrapScalar(row.upper_fmt) || formatNum(row.upper_bound, 2);
    var badgeCls = nOut === 0 ? "status-pill success" : (pct >= 3 ? "status-pill danger" : "status-pill warn");

    return (
      "<tr>" +
      "<td class='mono'><strong>" + escapeHtml(unwrapScalar(row.variable)) + "</strong></td>" +
      "<td>" + escapeHtml(unwrapScalar(row.n_valid)) + "</td>" +
      "<td><span class='" + badgeCls + "'>" + escapeHtml(nOut) + "</span></td>" +
      "<td>" + escapeHtml(pctStr) + "%</td>" +
      "<td class='mono'>" + escapeHtml(loStr) + "</td>" +
      "<td class='mono'>" + escapeHtml(hiStr) + "</td>" +
      "<td class='flag-cell'>" + escapeHtml(unwrapScalar(row.flagged_rows) || "None") + "</td>" +
      "</tr>"
    );
  }).join("");
}

function updateOutlierSummaryBadge(outlierData) {
  var badge = document.getElementById("outlier-summary-badge");
  if (!badge || !outlierData || !outlierData.rows) return;

  var total = 0;
  var affected = 0;
  outlierData.rows.forEach(function (r) {
    var n = Number(unwrapScalar(r.n_outliers) || 0);
    total += n;
    if (n > 0) affected += 1;
  });

  badge.textContent = total + " flagged observation" + (total === 1 ? "" : "s") +
    " across " + affected + " variable" + (affected === 1 ? "" : "s");
  badge.className = total === 0 ? "status-pill success" : "status-pill danger";

  var navBadge = document.getElementById("nav-badge-outliers");
  if (navBadge) navBadge.textContent = total;
}

// ── Variable Dictionary & Subgroup Comparison Renderers ─────────────────────

function renderVariableDictionary(varData) {
  var thead = document.getElementById("var-thead");
  var tbody = document.getElementById("var-tbody");

  thead.innerHTML =
    "<tr>" +
    "<th>Variable</th>" +
    "<th>Type</th>" +
    "<th>Valid N</th>" +
    "<th>Missing (%)</th>" +
    "<th>Unique</th>" +
    "<th>Mean &plusmn; SD / Top Level</th>" +
    "<th>Median [Q1, Q3]</th>" +
    "<th>Min</th>" +
    "<th>Max</th>" +
    "</tr>";

  if (!varData || !varData.rows || varData.rows.length === 0) {
    tbody.innerHTML = "<tr><td colspan='9' class='empty-row'>No variables available.</td></tr>";
    return;
  }

  var q = (document.getElementById("var-search").value || "").trim().toLowerCase();
  var typeFlt = document.getElementById("var-type-filter").value || "all";

  var rows = varData.rows.filter(function (row) {
    var vName = String(unwrapScalar(row.variable) || "");
    var vType = String(unwrapScalar(row.type) || "");
    if (q && vName.toLowerCase().indexOf(q) === -1) return false;
    if (typeFlt === "Numeric" && vType !== "Numeric") return false;
    if (typeFlt === "Categorical" && vType === "Numeric") return false;
    return true;
  });

  if (rows.length === 0) {
    tbody.innerHTML = "<tr><td colspan='9' class='empty-row'>No variables match the current filter.</td></tr>";
    return;
  }

  tbody.innerHTML = rows.map(function (row) {
    var vType = String(unwrapScalar(row.type) || "");
    var isNum = vType === "Numeric";
    var badgeCls = isNum ? "type-badge numeric" : "type-badge categorical";
    var nMiss = Number(unwrapScalar(row.n_missing) || 0);
    var pctMiss = Number(unwrapScalar(row.pct_missing) || 0);
    var pctMissStr = unwrapScalar(row.pct_missing_fmt) || pctMiss.toFixed(1);
    var missDisplay = nMiss > 0
      ? (nMiss + " (" + pctMissStr + "%)")
      : "0 (0.0%)";
    var meanSd = String(unwrapScalar(row.mean_sd) || "--").replace("+/-", "\u00B1");
    var medIqr = String(unwrapScalar(row.median_iqr) || "--");
    var minStr = isNum ? (unwrapScalar(row.min_fmt) || formatNum(row.min, 2)) : "--";
    var maxStr = isNum ? (unwrapScalar(row.max_fmt) || formatNum(row.max, 2)) : "--";

    return (
      "<tr>" +
      "<td class='mono'><strong>" + escapeHtml(unwrapScalar(row.variable)) + "</strong></td>" +
      "<td><span class='" + badgeCls + "'>" + escapeHtml(vType) + "</span></td>" +
      "<td>" + escapeHtml(unwrapScalar(row.n_valid)) + "</td>" +
      "<td>" + escapeHtml(missDisplay) + "</td>" +
      "<td>" + escapeHtml(unwrapScalar(row.n_unique)) + "</td>" +
      "<td>" + escapeHtml(meanSd) + "</td>" +
      "<td>" + escapeHtml(medIqr) + "</td>" +
      "<td>" + escapeHtml(minStr) + "</td>" +
      "<td>" + escapeHtml(maxStr) + "</td>" +
      "</tr>"
    );
  }).join("");
}

function populateSubgroupDropdown(data) {
  var catVars = toArray(data.categorical_vars);
  var sel = document.getElementById("subgroup-select");
  var card = document.getElementById("subgroup-card");

  activeSubgroupCol = unwrapScalar(data.subgroup_col) || "";

  if (catVars.length === 0) {
    card.classList.add("hidden");
    sel.innerHTML = "";
    return;
  }

  card.classList.remove("hidden");
  sel.innerHTML = catVars.map(function (c) {
    return "<option value='" + escapeHtml(c) + "'>" + escapeHtml(c) + "</option>";
  }).join("");

  if (activeSubgroupCol && catVars.indexOf(activeSubgroupCol) !== -1) {
    sel.value = activeSubgroupCol;
  } else {
    activeSubgroupCol = catVars[0];
    sel.value = activeSubgroupCol;
  }
}

function renderSubgroupTable(tableData, groupCol, footnote) {
  var thead = document.getElementById("subgroup-thead");
  var tbody = document.getElementById("subgroup-tbody");
  var footEl = document.getElementById("subgroup-footnote");

  if (!tableData || !tableData.rows || tableData.rows.length === 0) {
    thead.innerHTML = "";
    tbody.innerHTML = "<tr><td class='empty-row'>Select a categorical variable with 2 to 8 levels for Table 1 comparison.</td></tr>";
    if (footEl) {
      footEl.textContent = "";
      footEl.classList.add("hidden");
    }
    return;
  }

  var cols = toArray(tableData.cols);
  thead.innerHTML = "<tr>" + cols.map(function (c) {
    return "<th>" + escapeHtml(c) + "</th>";
  }).join("") + "</tr>";

  tbody.innerHTML = tableData.rows.map(function (row) {
    return "<tr>" + cols.map(function (c) {
      var val = unwrapScalar(row[c]);
      var str = (val === null || val === undefined || val === "") ? "--" : String(val).replace("+/-", "\u00B1");
      if (c === "Section") {
        return "<td><span class='section-tag'>" + escapeHtml(str) + "</span></td>";
      }
      if (c === "Variable") {
        return "<td class='mono'><strong>" + escapeHtml(str) + "</strong></td>";
      }
      if (c === "Metric" || c === "Eval N") {
        return "<td class='mono'>" + escapeHtml(str) + "</td>";
      }
      if (c === "p-value") {
        var sig = str !== "--" && str.indexOf("--") !== 0 &&
          (str.indexOf("<") === 0 || (!isNaN(parseFloat(str)) && parseFloat(str) < 0.05));
        return "<td class='mono'>" + (sig ? "<strong>" + escapeHtml(str) + "</strong>" : escapeHtml(str)) + "</td>";
      }
      return "<td>" + escapeHtml(str) + "</td>";
    }).join("") + "</tr>";
  }).join("");

  if (footEl) {
    var footStr = unwrapScalar(footnote) || "";
    if (footStr) {
      footEl.textContent = footStr;
      footEl.classList.remove("hidden");
    } else {
      footEl.textContent = "";
      footEl.classList.add("hidden");
    }
  }
}

function renderGenericTable(headId, bodyId, data, labelMap) {
  var head = document.getElementById(headId);
  var body = document.getElementById(bodyId);
  if (!data || !data.cols || !data.rows) return;
  var cols = toArray(data.cols);

  head.innerHTML = "<tr>" + cols.map(function (c) {
    var lbl = (labelMap && labelMap[c]) ? labelMap[c] : c;
    return "<th>" + escapeHtml(lbl) + "</th>";
  }).join("") + "</tr>";

  body.innerHTML = data.rows.map(function (row) {
    return "<tr>" + cols.map(function (c, idx) {
      var val = unwrapScalar(row[c]);
      var str = (val === null || val === undefined) ? "--" : String(val);
      return idx === 0
        ? "<td><strong>" + escapeHtml(str) + "</strong></td>"
        : "<td>" + escapeHtml(str) + "</td>";
    }).join("") + "</tr>";
  }).join("");
}

// ── RDesk IPC Event Receivers ───────────────────────────────────────────────

rdesk.on("load_data_result", handleLoadedData);
rdesk.on("load_preset_result", handleLoadedData);
rdesk.on("load_sample_result", handleLoadedData);

rdesk.on("smoke_post_load_ping", function (payload) {
  rdesk.send("smoke_post_load_pong", { token: unwrapScalar(payload && payload.token) || "" });
});

rdesk.on("run_profile_result", function (data) {
  handleLoadedData(data);
});

rdesk.on("distribution_updated", function (data) {
  if (data.error) {
    showToast("Distribution error: " + data.error, "error");
    return;
  }
  if (data.dist_charts) {
    document.getElementById("dist-chart").src = formatBase64Src(data.dist_charts);
    if (currentData) currentData.dist_charts = data.dist_charts;
  }
  if (data.dist_stats) {
    renderDistributionStats(data.dist_stats);
    if (currentData) currentData.dist_stats = data.dist_stats;
  }
});

rdesk.on("correlation_updated", function (data) {
  if (data.error) {
    showToast("Correlation error: " + data.error, "error");
    return;
  }
  if (data.corr_chart) {
    document.getElementById("corr-chart").src = formatBase64Src(data.corr_chart);
    if (currentData) currentData.corr_chart = data.corr_chart;
  }
  if (data.top_corr) {
    if (currentData) currentData.top_corr = data.top_corr;
    renderCorrelationsTable(data.top_corr);
  }
});

rdesk.on("run_corr_result", function (data) {
  if (data.corr_chart) {
    document.getElementById("corr-chart").src = formatBase64Src(data.corr_chart);
    if (currentData) currentData.corr_chart = data.corr_chart;
  }
  if (data.top_corr) {
    if (currentData) currentData.top_corr = data.top_corr;
    renderCorrelationsTable(data.top_corr);
  }
  switchPanel("correlations");
});

rdesk.on("outliers_updated", function (data) {
  if (data.error) {
    showToast("Outlier error: " + data.error, "error");
    return;
  }
  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src = formatBase64Src(data.outlier_chart);
    if (currentData) currentData.outlier_chart = data.outlier_chart;
  }
  if (data.outlier_table) {
    if (currentData) currentData.outlier_table = data.outlier_table;
    renderOutliersTable(data.outlier_table);
    updateOutlierSummaryBadge(data.outlier_table);
  }
  if (currentData && currentData.overview && data.total_outliers !== undefined) {
    currentData.overview.total_outliers = data.total_outliers;
    currentData.overview.vars_with_outliers = data.vars_with_outliers;
    renderKPIs(currentData.overview);
  }
});

rdesk.on("run_outliers_result", function (data) {
  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src = formatBase64Src(data.outlier_chart);
    if (currentData) currentData.outlier_chart = data.outlier_chart;
  }
  if (data.outlier_table) {
    if (currentData) currentData.outlier_table = data.outlier_table;
    renderOutliersTable(data.outlier_table);
    updateOutlierSummaryBadge(data.outlier_table);
  }
  switchPanel("outliers");
});

rdesk.on("subgroup_updated", function (data) {
  if (data.error) {
    showToast("Subgroup comparison error: " + data.error, "error");
    return;
  }
  if (currentData) {
    currentData.subgroup_col = data.subgroup_col;
    currentData.subgroup_table = data.subgroup_table;
    currentData.subgroup_footnote = data.subgroup_footnote;
  }
  renderSubgroupTable(data.subgroup_table, data.subgroup_col, data.subgroup_footnote);
});

rdesk.on("theme_charts_updated", function (data) {
  if (!data || data.error) return;
  if (data.preview_chart) {
    document.getElementById("overview-chart").src = formatBase64Src(data.preview_chart);
    if (currentData) currentData.preview_chart = data.preview_chart;
  }
  if (data.dist_charts) {
    document.getElementById("dist-chart").src = formatBase64Src(data.dist_charts);
    if (currentData) currentData.dist_charts = data.dist_charts;
  }
  if (data.corr_chart) {
    document.getElementById("corr-chart").src = formatBase64Src(data.corr_chart);
    if (currentData) currentData.corr_chart = data.corr_chart;
  }
  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src = formatBase64Src(data.outlier_chart);
    if (currentData) currentData.outlier_chart = data.outlier_chart;
  }
});

rdesk.on("open_file_result", function (result) {
  if (isCancelled(result)) return;
  currentFile = unwrapScalar(result.filename);
  rdesk.send("load_data", {
    path: unwrapScalar(result.path),
    settings: settings
  });
});

rdesk.on("export_report_result", function (result) {
  if (isCancelled(result)) return;
  if (result.error) {
    showToast("Error: " + result.error, "error");
  } else if (result.saved_to) {
    showToast("HTML report saved to " + result.saved_to, "success");
  }
});

rdesk.on("export_csv_result", function (result) {
  if (isCancelled(result)) return;
  if (result.error) {
    showToast("Error: " + result.error, "error");
  } else if (result.saved_to) {
    showToast("Variable dictionary saved to " + result.saved_to, "success");
  }
});

// Native Menu Triggers
rdesk.on("menu_open", function () {
  rdesk.send("open_file", {});
});

rdesk.on("menu_preset", function (payload) {
  var preset = unwrapScalar(payload && payload.preset) || "cardio_trial";
  rdesk.send("load_preset", { preset: preset, settings: settings });
});

rdesk.on("menu_copy_summary", function () {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("copy_summary", {
    target: "variables",
    table_data: currentData.variable_summary,
    source: getSourceDescriptor()
  });
});

rdesk.on("close_data", function () {
  currentData = null;
  currentFile = null;
  activeDistVar = "";
  activeDistGroup = "";
  activeSubgroupCol = "";

  document.querySelectorAll(".preset-btn").forEach(function (b) {
    b.classList.remove("active");
  });

  document.getElementById("dataset-info").classList.add("hidden");
  document.getElementById("no-data-prompt").classList.remove("hidden");
  document.getElementById("btn-profile").classList.add("hidden");
  document.getElementById("btn-export").classList.add("hidden");
  document.getElementById("btn-export-csv").classList.add("hidden");

  document.getElementById("kpi-grid").innerHTML = "";
  document.getElementById("dist-stats-strip").innerHTML = "";
  document.getElementById("dist-group-card").classList.add("hidden");
  document.getElementById("overview-chart").src = "";
  document.getElementById("dist-chart").src = "";
  document.getElementById("corr-chart").src = "";
  document.getElementById("outlier-chart").src = "";

  ["var-thead", "var-tbody", "corr-thead", "corr-tbody",
   "outlier-thead", "outlier-tbody", "subgroup-thead", "subgroup-tbody"].forEach(function (id) {
    var el = document.getElementById(id);
    if (el) el.innerHTML = "";
  });

  var subFoot = document.getElementById("subgroup-footnote");
  if (subFoot) {
    subFoot.textContent = "";
    subFoot.classList.add("hidden");
  }

  document.getElementById("nav-badge-outliers").classList.add("hidden");
  document.getElementById("nav-badge-vars").classList.add("hidden");

  rdesk.send("close_data", {});
  showToast("Dataset closed", "info");
});

rdesk.on("run_profile", function () {
  if (!currentData) { showToast("No dataset loaded", "warning"); return; }
  rdesk.send("run_profile", {
    data: getSourceDescriptor(),
    settings: settings,
    dist_var: activeDistVar,
    group_by: activeDistGroup,
    plot_mode: activeDistMode
  });
});

rdesk.on("run_corr", function () {
  if (!currentData) { showToast("No dataset loaded", "warning"); return; }
  rdesk.send("run_corr", { data: getSourceDescriptor(), settings: settings });
});

rdesk.on("run_outliers", function () {
  if (!currentData) { showToast("No dataset loaded", "warning"); return; }
  rdesk.send("run_outliers", { data: getSourceDescriptor(), settings: settings });
});

rdesk.on("export_report", triggerExportReport);
rdesk.on("export_csv", triggerExportCsv);
rdesk.on("open_settings", openSettingsModal);

rdesk.on("apply_theme", function (data) {
  applyThemeUI(unwrapScalar(data && data.mode) || "light");
});

rdesk.on("__theme__", function (data) {
  var mode = unwrapScalar(data && data.mode) || "light";
  applyThemeUI(mode);
  rdesk.send("save_pref", { key: "theme", value: mode });
});

rdesk.on("apply_preferences", function (data) {
  if (!data) return;
  if (data.theme) applyThemeUI(unwrapScalar(data.theme));
  if (data.corr_method) {
    settings.corr_method = unwrapScalar(data.corr_method);
    syncSegmentedButtons("[data-corr-method]", "corrMethod", settings.corr_method);
  }
  if (data.outlier_threshold) {
    settings.outlier_threshold = parseFloat(unwrapScalar(data.outlier_threshold));
    syncSegmentedButtons("[data-outlier-th]", "outlierTh", settings.outlier_threshold.toFixed(1));
  }
});

// ── Settings Modal ──────────────────────────────────────────────────────────

function setupSettingsModal() {
  document.getElementById("btn-settings-cancel").addEventListener("click", closeSettingsModal);
  document.getElementById("btn-settings-close").addEventListener("click", closeSettingsModal);
  document.getElementById("btn-settings-save").addEventListener("click", saveSettings);

  document.getElementById("settings-modal").addEventListener("click", function (e) {
    if (e.target === this) closeSettingsModal();
  });
}

function openSettingsModal() {
  document.getElementById("settings-theme").value = settings.theme;
  document.getElementById("settings-corr").value = settings.corr_method;
  document.getElementById("settings-outlier").value = settings.outlier_threshold.toFixed(1);
  document.getElementById("settings-modal").classList.remove("hidden");
}

function closeSettingsModal() {
  document.getElementById("settings-modal").classList.add("hidden");
}

function saveSettings() {
  var t = document.getElementById("settings-theme").value;
  var c = document.getElementById("settings-corr").value;
  var o = parseFloat(document.getElementById("settings-outlier").value);

  applyThemeUI(t);
  settings.corr_method = c;
  settings.outlier_threshold = o;

  syncSegmentedButtons("[data-corr-method]", "corrMethod", c);
  syncSegmentedButtons("[data-outlier-th]", "outlierTh", o.toFixed(1));

  rdesk.send("save_pref", { key: "theme", value: t });
  rdesk.send("save_pref", { key: "corr_method", value: c });
  rdesk.send("save_pref", { key: "outlier_threshold", value: o.toFixed(1) });

  closeSettingsModal();
  showToast("Preferences saved", "success");

  if (currentData) {
    rdesk.send("run_profile", {
      data: getSourceDescriptor(),
      settings: settings,
      dist_var: activeDistVar,
      group_by: activeDistGroup,
      plot_mode: activeDistMode
    });
  }
}

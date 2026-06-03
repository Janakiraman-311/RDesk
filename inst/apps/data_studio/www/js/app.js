// Data Intelligence Studio — UI logic

var currentData = null;
var currentFile = null;
var settings = {
  theme: "light",
  corr_method: "pearson",
  outlier_threshold: 1.5
};

// ── Initialisation ────────────────────────────────────────────────────
rdesk.ready(function() {
  setupNavigation();
  setupButtons();
  setupSettingsModal();
});


// ── Navigation ────────────────────────────────────────────────────────
function setupNavigation() {
  document.querySelectorAll(".nav-btn").forEach(function(btn) {
    btn.addEventListener("click", function() {
      var panel = this.dataset.panel;
      document.querySelectorAll(".nav-btn").forEach(function(b) {
        b.classList.remove("active");
      });
      document.querySelectorAll(".panel").forEach(function(p) {
        p.classList.add("hidden");
        p.classList.remove("active");
      });
      this.classList.add("active");
      var target = document.getElementById("panel-" + panel);
      if (target) {
        target.classList.remove("hidden");
        target.classList.add("active");
      }
    });
  });
}


function setupButtons() {

  document.getElementById("btn-open").addEventListener("click", function() {
    rdesk.send("open_file", {});
  });

  document.getElementById("btn-sample").addEventListener("click", function() {
    rdesk.send("load_sample", { settings: settings });
  });

  document.getElementById("btn-profile").addEventListener("click", function() {
    if (!currentData) return;
    rdesk.send("run_profile", { data: currentData, settings: settings });
  });

  document.getElementById("btn-export").addEventListener("click", function() {
    if (!currentData) return;
    rdesk.send("export_report", {
      data:             currentData,
      filename:         currentFile,
      variable_summary: currentData.variable_summary
    });
  });
}


// ── Data loading ──────────────────────────────────────────────────────
function renderProfileResults(data) {
  if (data.dist_charts) {
    document.getElementById("dist-chart").src =
      formatBase64Src(data.dist_charts);
  }
  if (data.corr_chart) {
    document.getElementById("corr-chart").src =
      formatBase64Src(data.corr_chart);
  }
  renderTable("corr-thead",    "corr-tbody",    data.top_corr);
  renderTable("outlier-thead", "outlier-tbody", data.outlier_table);
  renderTable("var-thead",     "var-tbody",     data.full_summary);

  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src =
      formatBase64Src(data.outlier_chart);
  }
}

function handleLoadedData(data) {
  if (data.error) {
    showToast("Error: " + data.error, "error");
    return;
  }

  currentData = data;
  currentFile = data.filename;

  // Show dataset info in header
  document.getElementById("dataset-name").textContent = data.filename;
  document.getElementById("dataset-dims").textContent =
    data.n_rows + " rows x " + data.n_cols + " columns";
  document.getElementById("dataset-info").classList.remove("hidden");
  document.getElementById("no-data-prompt").classList.add("hidden");
  document.getElementById("btn-profile").classList.remove("hidden");
  document.getElementById("btn-export").classList.remove("hidden");

  // KPI cards
  renderKPIs(data.overview);

  // Missing values chart
  if (data.preview_chart) {
    document.getElementById("overview-chart").src =
      formatBase64Src(data.preview_chart);
  }

  // Variable summary table
  renderTable("var-thead", "var-tbody", data.variable_summary);

  // Render profile results if they are in the payload
  if (data.dist_charts) {
    renderProfileResults(data);
  }

  showToast("Loaded " + data.filename, "success");
}

rdesk.on("load_data_result", handleLoadedData);
rdesk.on("load_sample_result", handleLoadedData);


// ── Full profile results ──────────────────────────────────────────────
rdesk.on("run_profile_result", function(data) {
  renderProfileResults(data);
  showToast("Full profile complete", "success");
});


// ── Correlation results ───────────────────────────────────────────────
rdesk.on("run_corr_result", function(data) {
  if (data.corr_chart) {
    document.getElementById("corr-chart").src =
      formatBase64Src(data.corr_chart);
  }
  renderTable("corr-thead", "corr-tbody", data.top_corr);
  switchPanel("correlations");
});


// ── Outlier results ───────────────────────────────────────────────────
rdesk.on("run_outliers_result", function(data) {
  renderTable("outlier-thead", "outlier-tbody", data.outlier_table);
  if (data.outlier_chart) {
    document.getElementById("outlier-chart").src =
      formatBase64Src(data.outlier_chart);
  }
  switchPanel("outliers");
});



// ── Theme ─────────────────────────────────────────────────────────────
rdesk.on("apply_theme", function(data) {
  document.documentElement.setAttribute("data-theme", data.mode);
});

rdesk.on("__theme__", function(data) {
  document.documentElement.setAttribute("data-theme", data.mode);
  rdesk.send("save_pref", { key: "theme", value: data.mode });
});


function formatBase64Src(src) {
  if (!src) return "";
  var srcStr = Array.isArray(src) ? src[0] : src;
  if (typeof srcStr !== "string") return "";
  if (srcStr.startsWith("data:")) return srcStr;
  return "data:image/png;base64," + srcStr;
}

// ── Helpers ───────────────────────────────────────────────────────────
function renderKPIs(overview) {
  if (!overview) return;
  var grid = document.getElementById("kpi-grid");
  var items = [
    { label: "Rows",          value: overview.n_rows },
    { label: "Columns",       value: overview.n_cols },
    { label: "Numeric",       value: overview.n_numeric },
    { label: "Missing cells", value: overview.total_missing },
    { label: "Missing %",     value: overview.pct_missing + "%" },
    { label: "Memory (KB)",   value: overview.memory_kb }
  ];
  grid.innerHTML = items.map(function(item) {
    return "<div class='kpi-card'>" +
           "<div class='kpi-value'>" + item.value + "</div>" +
           "<div class='kpi-label'>" + item.label + "</div>" +
           "</div>";
  }).join("");
}

function renderTable(headId, bodyId, data) {
  if (!data || !data.cols || data.cols.length === 0) return;
  var head = document.getElementById(headId);
  var body = document.getElementById(bodyId);
  head.innerHTML = "<tr>" +
    data.cols.map(function(c) { return "<th>" + c + "</th>"; }).join("") +
    "</tr>";
  body.innerHTML = data.rows.map(function(row) {
    return "<tr>" +
      data.cols.map(function(c) {
        return "<td>" + (row[c] !== undefined ? row[c] : "") + "</td>";
      }).join("") +
      "</tr>";
  }).join("");
}

function switchPanel(name) {
  document.querySelectorAll(".nav-btn").forEach(function(b) {
    b.classList.toggle("active", b.dataset.panel === name);
  });
  document.querySelectorAll(".panel").forEach(function(p) {
    var isTarget = p.id === "panel-" + name;
    p.classList.toggle("hidden", !isTarget);
    p.classList.toggle("active", isTarget);
  });
}

// ── RDesk Event Receivers ─────────────────────────────────────────────
rdesk.on("open_file_result", function(result) {
  var cancelled = result.cancelled === true || result.cancelled === "true" || (Array.isArray(result.cancelled) && (result.cancelled[0] === true || result.cancelled[0] === "true"));
  if (cancelled) return;
  currentFile = result.filename;
  rdesk.send("load_data", { path: result.path, settings: settings });
});

rdesk.on("export_report_result", function(result) {
  var cancelled = result.cancelled === true || result.cancelled === "true" || (Array.isArray(result.cancelled) && (result.cancelled[0] === true || result.cancelled[0] === "true"));
  if (!cancelled) {
    if (result.error) {
      showToast("Error: " + result.error, "error");
    } else if (result.saved_to) {
      showToast("Report saved to " + result.saved_to, "success");
    }
  }
});

rdesk.on("export_csv_result", function(result) {
  var cancelled = result.cancelled === true || result.cancelled === "true" || (Array.isArray(result.cancelled) && (result.cancelled[0] === true || result.cancelled[0] === "true"));
  if (!cancelled) {
    if (result.error) {
      showToast("Error: " + result.error, "error");
    } else if (result.saved_to) {
      showToast("CSV summary saved to " + result.saved_to, "success");
    }
  }
});

rdesk.on("menu_open", function() {
  rdesk.send("open_file", {});
});

rdesk.on("close_data", function() {
  currentData = null;
  currentFile = null;
  
  document.getElementById("dataset-info").classList.add("hidden");
  document.getElementById("no-data-prompt").classList.remove("hidden");
  document.getElementById("btn-profile").classList.add("hidden");
  document.getElementById("btn-export").classList.add("hidden");
  
  // Clear KPIs
  document.getElementById("kpi-grid").innerHTML = "";
  
  // Clear charts
  document.getElementById("overview-chart").src = "";
  document.getElementById("dist-chart").src = "";
  document.getElementById("corr-chart").src = "";
  document.getElementById("outlier-chart").src = "";
  
  // Clear tables
  document.getElementById("var-thead").innerHTML = "";
  document.getElementById("var-tbody").innerHTML = "";
  document.getElementById("corr-thead").innerHTML = "";
  document.getElementById("corr-tbody").innerHTML = "";
  document.getElementById("outlier-thead").innerHTML = "";
  document.getElementById("outlier-tbody").innerHTML = "";
  
  showToast("Dataset closed", "info");
});

rdesk.on("run_profile", function() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("run_profile", { data: currentData, settings: settings });
});

rdesk.on("run_corr", function() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("run_corr", { data: currentData, settings: settings });
});

rdesk.on("run_outliers", function() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("run_outliers", { data: currentData, settings: settings });
});

rdesk.on("export_report", function() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("export_report", {
    data:             currentData,
    filename:         currentFile,
    variable_summary: currentData.variable_summary
  });
});

rdesk.on("export_csv", function() {
  if (!currentData) {
    showToast("No dataset loaded", "warning");
    return;
  }
  rdesk.send("export_csv", {
    filename:         currentFile,
    variable_summary: currentData.variable_summary
  });
});

rdesk.on("open_settings", function() {
  openSettingsModal();
});

rdesk.on("apply_preferences", function(data) {
  if (data.theme) {
    document.documentElement.setAttribute("data-theme", data.theme);
    settings.theme = data.theme;
  }
  if (data.corr_method) {
    settings.corr_method = data.corr_method;
  }
  if (data.outlier_threshold) {
    settings.outlier_threshold = parseFloat(data.outlier_threshold);
  }
});

function setupSettingsModal() {
  document.getElementById("btn-settings-cancel").addEventListener("click", closeSettingsModal);
  document.getElementById("btn-settings-save").addEventListener("click", saveSettings);
  
  // Close on overlay click
  document.getElementById("settings-modal").addEventListener("click", function(e) {
    if (e.target === this) closeSettingsModal();
  });
}

function openSettingsModal() {
  document.getElementById("settings-theme").value = settings.theme;
  document.getElementById("settings-corr").value = settings.corr_method;
  document.getElementById("settings-outlier").value = settings.outlier_threshold.toString();
  document.getElementById("settings-modal").classList.remove("hidden");
}

function closeSettingsModal() {
  document.getElementById("settings-modal").classList.add("hidden");
}

function saveSettings() {
  var t = document.getElementById("settings-theme").value;
  var c = document.getElementById("settings-corr").value;
  var o = parseFloat(document.getElementById("settings-outlier").value);
  
  settings.theme = t;
  settings.corr_method = c;
  settings.outlier_threshold = o;
  
  // Apply theme immediately
  document.documentElement.setAttribute("data-theme", t);
  
  // Save preferences persistently in R
  rdesk.send("save_pref", { key: "theme", value: t });
  rdesk.send("save_pref", { key: "corr_method", value: c });
  rdesk.send("save_pref", { key: "outlier_threshold", value: o.toString() });
  
  closeSettingsModal();
  showToast("Settings saved successfully", "success");
  
  // Re-run profiling with the new settings if a dataset is loaded
  if (currentData) {
    rdesk.send("run_profile", { data: currentData, settings: settings });
  }
}

function showToast(message, type) {
  // Route directly to RDesk's premium styled HTML toast overlay system
  rdesk.send("__toast__", { message: message, type: type || "info" });
}

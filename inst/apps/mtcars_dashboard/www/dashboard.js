// inst/apps/mtcars_dashboard/www/dashboard.js
// CarsAnalyser Telemetry Workbench frontend controller

(function () {
  "use strict";

  // ── Shared Application State ─────────────────────────────────────────────
  const state = {
    cyls: [4, 6, 8],
    am: "all",
    hpMin: 52,
    hpMax: 335,
    hpBounds: { min: 52, max: 335 },
    xVar: "wt",
    yVar: "mpg",
    plotType: "scatter",
    smoothMethod: "lm",

    fleetRows: [],
    searchQuery: "",
    sortKey: "mpg",
    sortDir: "desc",

    modelResponse: "mpg",
    modelScope: "all",
    modelPredictors: ["wt", "hp", "cyl"],
    modelInteraction: false,
    lastModel: null
  };

  const VAR_NAMES = {
    mpg:  "Fuel Economy (MPG)",
    wt:   "Curb Weight",
    hp:   "Horsepower",
    disp: "Displacement",
    drat: "Rear Axle Ratio",
    qsec: "1/4 Mile Time"
  };

  const PLOT_LABELS = {
    scatter:    "Scatter",
    boxplot:    "Boxplot",
    density:    "Density",
    efficiency: "Efficiency"
  };

  let hpDebounceTimer = null;

  // ── Utilities ────────────────────────────────────────────────────────────
  function escapeHtml(str) {
    if (str == null) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function asArray(val) {
    if (val == null) return [];
    return Array.isArray(val) ? val : [val];
  }

  function fmtNum(val, digits) {
    if (val == null || Number.isNaN(Number(val))) return "—";
    return Number(val).toFixed(digits);
  }

  function fmtInt(val) {
    if (val == null || Number.isNaN(Number(val))) return "—";
    return Math.round(Number(val)).toLocaleString();
  }

  function fmtPval(val) {
    if (val == null || Number.isNaN(Number(val))) return "—";
    const num = Number(val);
    if (num < 0.0001) return "< 0.0001";
    return num.toFixed(4);
  }

  // ── Navigation ───────────────────────────────────────────────────────────
  function switchSection(id) {
    document.querySelectorAll(".nav-item").forEach(el => {
      el.classList.toggle("active", el.dataset.section === id);
    });
    document.querySelectorAll(".app-section").forEach(el => {
      el.classList.toggle("active", el.id === "section-" + id);
    });
  }

  // ── Explorer Controls & Sync ─────────────────────────────────────────────
  function updateAxisAffordances() {
    const xWrap = document.getElementById("x-axis-wrap");
    const yWrap = document.getElementById("y-axis-wrap");
    const sWrap = document.getElementById("smooth-wrap");

    const pt = state.plotType;
    xWrap.classList.toggle("is-dimmed", pt !== "scatter");
    yWrap.classList.toggle("is-dimmed", pt === "efficiency");
    sWrap.classList.toggle("is-dimmed", pt !== "scatter");

    const titleEl = document.getElementById("chart-title");
    if (pt === "scatter") {
      const fitLabel = state.smoothMethod === "loess" ? "LOESS" : "OLS";
      titleEl.textContent = `${VAR_NAMES[state.yVar] || state.yVar} vs. ${VAR_NAMES[state.xVar] || state.xVar} · ${fitLabel}`;
    } else if (pt === "boxplot") {
      titleEl.textContent = `${VAR_NAMES[state.yVar] || state.yVar} · Cylinder Class Distribution`;
    } else if (pt === "density") {
      titleEl.textContent = `${VAR_NAMES[state.yVar] || state.yVar} · Kernel Density Ridges`;
    } else if (pt === "efficiency") {
      titleEl.textContent = "Power-to-Weight Efficiency Frontier";
    }

    document.getElementById("sb-mode").textContent = PLOT_LABELS[pt] || pt;
  }

  function syncControlsFromState() {
    // Plot type buttons
    document.querySelectorAll("#plot-type-group .seg-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.plot === state.plotType);
    });

    // Cylinder pills
    document.querySelectorAll("#cyl-filter-group .cyl-pill").forEach(pill => {
      const c = Number(pill.dataset.cyl);
      pill.classList.toggle("active", state.cyls.includes(c));
    });

    // Transmission buttons
    document.querySelectorAll("#am-filter-group .seg-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.am === String(state.am));
    });

    // Horsepower sliders
    const minEl = document.getElementById("hp-min-slider");
    const maxEl = document.getElementById("hp-max-slider");
    minEl.min = state.hpBounds.min;
    minEl.max = state.hpBounds.max;
    maxEl.min = state.hpBounds.min;
    maxEl.max = state.hpBounds.max;
    minEl.value = state.hpMin;
    maxEl.value = state.hpMax;
    document.getElementById("hp-readout").textContent = `${state.hpMin} – ${state.hpMax} HP`;

    // Axes & smooth
    document.getElementById("x-var-select").value = state.xVar;
    document.getElementById("y-var-select").value = state.yVar;
    document.querySelectorAll("#smooth-group .seg-btn").forEach(btn => {
      btn.classList.toggle("active", btn.dataset.smooth === state.smoothMethod);
    });

    updateAxisAffordances();
    updateExportMeta();
  }

  function sendFilterUpdate() {
    const loading = document.getElementById("chart-loading");
    if (loading) loading.style.display = "flex";

    rdesk.send("update_filters", {
      cyls:          state.cyls,
      am:            state.am,
      hp_min:        state.hpMin,
      hp_max:        state.hpMax,
      x_var:         state.xVar,
      y_var:         state.yVar,
      plot_type:     state.plotType,
      smooth_method: state.smoothMethod
    });
  }

  // ── Explorer Data Rendering ──────────────────────────────────────────────
  function renderBreakdown(rows) {
    const tbody = document.getElementById("summary-body");
    const list = asArray(rows);
    document.getElementById("breakdown-badge").textContent = `${list.length} groups`;

    if (list.length === 0) {
      tbody.innerHTML = `<tr><td colspan="6" style="text-align:center;color:var(--text-dim);padding:20px;">No groups match active filters</td></tr>`;
      return;
    }

    tbody.innerHTML = list.map(r => {
      const cyl = Number(r.cyl);
      const transShort = r.transmission === "Manual" ? "Man" : "Auto";
      return `
        <tr>
          <td><span class="cyl-badge cyl-badge-${cyl}">${cyl}</span></td>
          <td><span class="trans-tag">${escapeHtml(transShort)}</span></td>
          <td class="num">${r.count}</td>
          <td class="num">${fmtNum(r.avg_mpg, 1)}</td>
          <td class="num">${fmtNum(r.avg_hp_per_ton, 1)}</td>
          <td class="num">${fmtNum(r.avg_qsec, 2)}</td>
        </tr>
      `;
    }).join("");
  }

  function renderFleetTable() {
    const tbody = document.getElementById("fleet-body");
    const q = state.searchQuery.trim().toLowerCase();

    let rows = state.fleetRows.slice();
    if (q) {
      rows = rows.filter(r =>
        String(r.model || "").toLowerCase().includes(q) ||
        String(r.transmission || "").toLowerCase().includes(q) ||
        String(r.cyl || "").includes(q)
      );
    }

    const key = state.sortKey;
    const mult = state.sortDir === "asc" ? 1 : -1;
    rows.sort((a, b) => {
      const va = a[key];
      const vb = b[key];
      if (typeof va === "string" || typeof vb === "string") {
        return String(va || "").localeCompare(String(vb || "")) * mult;
      }
      return (Number(va || 0) - Number(vb || 0)) * mult;
    });

    document.getElementById("ledger-count").textContent =
      q ? `${rows.length} of ${state.fleetRows.length} vehicles` : `${rows.length} vehicles`;

    // Update header sort arrows
    document.querySelectorAll("#fleet-table thead th.sortable").forEach(th => {
      th.classList.remove("sort-asc", "sort-desc");
      if (th.dataset.sort === key) {
        th.classList.add(state.sortDir === "asc" ? "sort-asc" : "sort-desc");
      }
    });

    if (rows.length === 0) {
      tbody.innerHTML = `<tr><td colspan="11" style="text-align:center;color:var(--text-dim);padding:24px;">No vehicles match your search or active filter selection.</td></tr>`;
      return;
    }

    tbody.innerHTML = rows.map(r => {
      const cyl = Number(r.cyl);
      return `
        <tr>
          <td class="model-name">${escapeHtml(r.model)}</td>
          <td class="num"><span class="cyl-badge cyl-badge-${cyl}">${cyl}</span></td>
          <td><span class="trans-tag">${escapeHtml(r.transmission)}</span></td>
          <td class="num" style="color:var(--accent);font-weight:600">${fmtNum(r.mpg, 1)}</td>
          <td class="num">${fmtInt(r.hp)}</td>
          <td class="num">${fmtInt(r.wt_lbs)}</td>
          <td class="num">${fmtNum(r.hp_per_ton, 1)}</td>
          <td class="num">${fmtNum(r.qsec, 2)}</td>
          <td class="num">${fmtNum(r.disp, 1)}</td>
          <td class="num">${fmtNum(r.drat, 2)}</td>
          <td class="num">${r.gear}</td>
        </tr>
      `;
    }).join("");
  }

  function updateExportMeta() {
    const n = state.fleetRows.length;
    document.getElementById("exp-rows").textContent = `${n} rows`;
    document.getElementById("exp-cyls").textContent =
      state.cyls.length > 0 ? state.cyls.slice().sort((a, b) => a - b).join(", ") : "None";

    const amLabel = state.am === "0" ? "Auto" : (state.am === "1" ? "Manual" : "All");
    document.getElementById("exp-filters").textContent = `${amLabel} · ${state.hpMin}–${state.hpMax} HP`;

    const scopeBtn = document.getElementById("btn-scope-filtered");
    if (scopeBtn) scopeBtn.textContent = `Filtered Fleet (${n})`;

    const modelStatus = document.getElementById("exp-model-status");
    const modelFormula = document.getElementById("exp-model-formula");
    if (state.lastModel) {
      modelStatus.textContent = "Included";
      modelStatus.classList.add("status-ok");
      modelFormula.textContent = state.lastModel.formula;
    } else {
      modelStatus.textContent = "Not fitted yet";
      modelStatus.classList.remove("status-ok");
      modelFormula.textContent = "—";
    }
  }

  // ── Regression Lab Builder & Results ─────────────────────────────────────
  function updateFormulaPreview() {
    const preds = state.modelPredictors.filter(p => p !== state.modelResponse);
    const terms = preds.slice();
    if (state.modelInteraction) {
      if (!terms.includes("wt")) terms.push("wt");
      if (!terms.includes("hp")) terms.push("hp");
      terms.push("wt:hp");
    }

    const previewEl = document.getElementById("formula-preview");
    const runBtn = document.getElementById("btn-run-model");

    if (terms.length === 0) {
      previewEl.textContent = `${state.modelResponse} ~ (select at least one predictor)`;
      runBtn.disabled = true;
    } else {
      previewEl.textContent = `${state.modelResponse} ~ ${terms.join(" + ")}`;
      runBtn.disabled = false;
    }

    // Sync predictor chips
    document.querySelectorAll("#predictor-chips .pred-chip").forEach(chip => {
      const p = chip.dataset.pred;
      const isResp = p === state.modelResponse;
      chip.disabled = isResp;
      const isActive = !isResp && (
        state.modelPredictors.includes(p) ||
        (state.modelInteraction && (p === "wt" || p === "hp"))
      );
      chip.classList.toggle("active", isActive);
    });

    const intBtn = document.getElementById("toggle-interaction");
    intBtn.classList.toggle("active", state.modelInteraction);
    intBtn.setAttribute("aria-pressed", state.modelInteraction ? "true" : "false");
  }

  function runRegressionModel() {
    const preds = state.modelPredictors.filter(p => p !== state.modelResponse);
    if (state.modelInteraction) {
      if (!preds.includes("wt")) preds.push("wt");
      if (!preds.includes("hp")) preds.push("hp");
    }
    if (preds.length === 0) return;

    rdesk.send("run_model", {
      response:    state.modelResponse,
      predictors:  preds,
      interaction: state.modelInteraction,
      scope:       state.modelScope,
      cyls:        state.cyls,
      am:          state.am,
      hp_min:      state.hpMin,
      hp_max:      state.hpMax
    });
  }

  function renderModelResults(payload) {
    if (!payload || !payload.metrics) return;

    document.getElementById("model-empty").style.display = "none";
    document.getElementById("model-results").style.display = "flex";

    const m = payload.metrics;
    const r2Val = Number(m.r_squared || 0);
    document.getElementById("m-r2").textContent = fmtNum(r2Val, 4);
    document.getElementById("m-r2-bar").style.width = `${Math.max(0, Math.min(100, r2Val * 100))}%`;
    document.getElementById("m-adj-r2").textContent = fmtNum(m.adj_r_squared, 4);
    document.getElementById("m-sample-meta").textContent = `${payload.scope_label || "Fleet"} · n = ${payload.nobs}`;
    document.getElementById("m-fstat").textContent = fmtNum(m.f_statistic, 2);
    document.getElementById("m-fpval").textContent = `p = ${fmtPval(m.f_p_value)}`;
    document.getElementById("m-aic").textContent = fmtNum(m.aic, 2);
    document.getElementById("m-rse").textContent = fmtNum(m.rse, 4);
    document.getElementById("m-df").textContent = `df_resid = ${payload.df_residual}`;
    document.getElementById("m-formula-badge").textContent = payload.formula || "";

    // Diagnostic charts
    if (payload.plot_actual_pred) {
      document.getElementById("diag-actual-img").src = payload.plot_actual_pred;
    }
    if (payload.plot_residuals) {
      document.getElementById("diag-resid-img").src = payload.plot_residuals;
    }

    // Coefficients table
    const tbody = document.getElementById("coeffs-body");
    const coefs = asArray(payload.coefficients);
    tbody.innerHTML = coefs.map(c => {
      const pval = c.p_value;
      const isSig = pval != null && !Number.isNaN(Number(pval)) && Number(pval) < 0.05;
      const ciStr = (c.conf_low != null && c.conf_high != null)
        ? `[${fmtNum(c.conf_low, 3)}, ${fmtNum(c.conf_high, 3)}]`
        : "—";
      return `
        <tr>
          <td><code class="mono" style="color:var(--text-primary);font-weight:600">${escapeHtml(c.term)}</code></td>
          <td class="num">${fmtNum(c.estimate, 4)}</td>
          <td class="num">${fmtNum(c.std_error, 4)}</td>
          <td class="num">${fmtNum(c.statistic, 2)}</td>
          <td class="num" style="color:var(--text-muted)">${ciStr}</td>
          <td class="num ${isSig ? "pval-sig" : ""}">${fmtPval(pval)}</td>
          <td class="center"><span class="sig-stars">${escapeHtml(c.sig || "")}</span></td>
        </tr>
      `;
    }).join("");

    // Cache model summary & sync to R main thread for Markdown export & clipboard
    state.lastModel = {
      formula:          payload.formula,
      r_squared:        m.r_squared,
      summary_text:     payload.summary_text || "",
      markdown_section: payload.markdown_section || ""
    };

    document.getElementById("sb-r2").textContent = fmtNum(r2Val, 3);
    document.getElementById("btn-copy-summary").disabled = false;
    updateExportMeta();

    rdesk.send("sync_model_result", state.lastModel);
  }

  // ── DOM Event Wiring ─────────────────────────────────────────────────────
  function bindEvents() {
    // Sidebar nav
    document.querySelectorAll(".nav-item").forEach(btn => {
      btn.addEventListener("click", () => switchSection(btn.dataset.section));
    });

    // Plot type selector
    document.querySelectorAll("#plot-type-group .seg-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        state.plotType = btn.dataset.plot;
        syncControlsFromState();
        sendFilterUpdate();
      });
    });

    // Cylinder filter pills
    document.querySelectorAll("#cyl-filter-group .cyl-pill").forEach(pill => {
      pill.addEventListener("click", () => {
        const c = Number(pill.dataset.cyl);
        if (state.cyls.includes(c)) {
          state.cyls = state.cyls.filter(x => x !== c);
        } else {
          state.cyls = [...state.cyls, c].sort((a, b) => a - b);
        }
        syncControlsFromState();
        sendFilterUpdate();
      });
    });

    // Transmission filter
    document.querySelectorAll("#am-filter-group .seg-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        state.am = btn.dataset.am;
        syncControlsFromState();
        sendFilterUpdate();
      });
    });

    // Horsepower dual sliders
    const hpMinEl = document.getElementById("hp-min-slider");
    const hpMaxEl = document.getElementById("hp-max-slider");

    function onHpInput(changed) {
      let lo = Number(hpMinEl.value);
      let hi = Number(hpMaxEl.value);
      if (lo > hi) {
        if (changed === "min") {
          hi = lo;
          hpMaxEl.value = hi;
        } else {
          lo = hi;
          hpMinEl.value = lo;
        }
      }
      state.hpMin = lo;
      state.hpMax = hi;
      document.getElementById("hp-readout").textContent = `${lo} – ${hi} HP`;
      updateExportMeta();

      clearTimeout(hpDebounceTimer);
      hpDebounceTimer = setTimeout(sendFilterUpdate, 140);
    }

    hpMinEl.addEventListener("input", () => onHpInput("min"));
    hpMaxEl.addEventListener("input", () => onHpInput("max"));

    // X / Y Axis selects
    document.getElementById("x-var-select").addEventListener("change", e => {
      state.xVar = e.target.value;
      updateAxisAffordances();
      sendFilterUpdate();
    });

    document.getElementById("y-var-select").addEventListener("change", e => {
      state.yVar = e.target.value;
      updateAxisAffordances();
      sendFilterUpdate();
    });

    // Smooth method toggle
    document.querySelectorAll("#smooth-group .seg-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        state.smoothMethod = btn.dataset.smooth;
        syncControlsFromState();
        sendFilterUpdate();
      });
    });

    // Reset button
    document.getElementById("btn-reset-filters").addEventListener("click", () => {
      state.searchQuery = "";
      document.getElementById("vehicle-search").value = "";
      rdesk.send("reset_filters", {});
    });

    // Ledger search & sort
    document.getElementById("vehicle-search").addEventListener("input", e => {
      state.searchQuery = e.target.value;
      renderFleetTable();
    });

    document.querySelectorAll("#fleet-table thead th.sortable").forEach(th => {
      th.addEventListener("click", () => {
        const key = th.dataset.sort;
        if (state.sortKey === key) {
          state.sortDir = state.sortDir === "asc" ? "desc" : "asc";
        } else {
          state.sortKey = key;
          state.sortDir = (key === "model" || key === "transmission") ? "asc" : "desc";
        }
        renderFleetTable();
      });
    });

    // Regression Lab controls
    document.querySelectorAll("#model-response-group .seg-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        state.modelResponse = btn.dataset.response;
        document.querySelectorAll("#model-response-group .seg-btn").forEach(b => {
          b.classList.toggle("active", b === btn);
        });
        updateFormulaPreview();
      });
    });

    document.querySelectorAll("#model-scope-group .seg-btn").forEach(btn => {
      btn.addEventListener("click", () => {
        state.modelScope = btn.dataset.scope;
        document.querySelectorAll("#model-scope-group .seg-btn").forEach(b => {
          b.classList.toggle("active", b === btn);
        });
      });
    });

    document.querySelectorAll("#predictor-chips .pred-chip").forEach(chip => {
      chip.addEventListener("click", () => {
        const p = chip.dataset.pred;
        if (state.modelPredictors.includes(p)) {
          state.modelPredictors = state.modelPredictors.filter(x => x !== p);
          if (state.modelInteraction && (p === "wt" || p === "hp")) {
            state.modelInteraction = false;
          }
        } else {
          state.modelPredictors.push(p);
        }
        updateFormulaPreview();
      });
    });

    document.getElementById("toggle-interaction").addEventListener("click", () => {
      state.modelInteraction = !state.modelInteraction;
      if (state.modelInteraction) {
        if (!state.modelPredictors.includes("wt")) state.modelPredictors.push("wt");
        if (!state.modelPredictors.includes("hp")) state.modelPredictors.push("hp");
      }
      updateFormulaPreview();
    });

    document.getElementById("btn-run-model").addEventListener("click", runRegressionModel);

    document.getElementById("btn-copy-summary").addEventListener("click", () => {
      if (!state.lastModel) return;
      rdesk.send("copy_model_summary", { text: state.lastModel.summary_text });
    });

    // Export actions
    document.getElementById("btn-export-csv").addEventListener("click", () => {
      rdesk.send("export_csv", {});
    });

    document.getElementById("btn-export-report").addEventListener("click", () => {
      rdesk.send("export_report", { model: state.lastModel });
    });
  }

  // ── RDesk IPC Listeners ──────────────────────────────────────────────────
  rdesk.on("data_update", function (payload) {
    if (payload.kpis) {
      const k = payload.kpis;
      const total = k.total || 32;
      document.getElementById("kpi-n").textContent = k.n;
      document.getElementById("kpi-n-meta").textContent = `of ${total} vehicles`;
      document.getElementById("kpi-mpg").textContent = fmtNum(k.mean_mpg, 1);
      document.getElementById("kpi-hp-ton").textContent = fmtNum(k.mean_hp_per_ton, 1);
      document.getElementById("kpi-qsec").textContent = fmtNum(k.mean_qsec, 2);
      document.getElementById("kpi-best-vehicle").textContent = k.best_vehicle || "—";
      document.getElementById("kpi-best-mpg").textContent =
        k.best_mpg != null ? `${fmtNum(k.best_mpg, 1)} MPG` : "No active vehicles";

      document.getElementById("sb-fleet").textContent = `${k.n} / ${total}`;
      document.getElementById("chart-badge").textContent = `n = ${k.n}`;
    }

    if (payload.chart) {
      const img = document.getElementById("chart-img");
      const loading = document.getElementById("chart-loading");
      img.onload = () => {
        loading.style.display = "none";
        img.style.display = "block";
      };
      img.src = payload.chart;
    }

    renderBreakdown(payload.summary);
    state.fleetRows = asArray(payload.table);
    renderFleetTable();
    updateExportMeta();
  });

  rdesk.on("init_ui_state", function (payload) {
    if (!payload) return;
    if (payload.plot_type) state.plotType = payload.plot_type;
    if (payload.x_var) state.xVar = payload.x_var;
    if (payload.y_var) state.yVar = payload.y_var;
    if (payload.smooth_method) state.smoothMethod = payload.smooth_method;
    if (payload.cyl_filter != null) state.cyls = asArray(payload.cyl_filter).map(Number);
    if (payload.am_filter != null) state.am = String(payload.am_filter);
    if (payload.hp_bounds) {
      state.hpBounds = {
        min: Number(payload.hp_bounds.min),
        max: Number(payload.hp_bounds.max)
      };
    }
    if (payload.hp_min != null) state.hpMin = Number(payload.hp_min);
    if (payload.hp_max != null) state.hpMax = Number(payload.hp_max);

    syncControlsFromState();
  });

  rdesk.on("run_model_result", renderModelResults);

  rdesk.on("switch_section", function (payload) {
    if (payload && payload.section) switchSection(payload.section);
  });

  rdesk.on("__trigger__", function (payload) {
    if (payload && payload.action === "nav" && payload.target) {
      switchSection(payload.target);
    }
  });

  // ── Boot ─────────────────────────────────────────────────────────────────
  document.addEventListener("DOMContentLoaded", function () {
    bindEvents();
    syncControlsFromState();
    updateFormulaPreview();
  });

  rdesk.ready(function () {
    rdesk.send("ready", {});
  });
})();

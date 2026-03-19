// ── navigation ─────────────────────────────────────────────────────────────
function switchSection(id) {
  // Update nav UI
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  document.getElementById('nav-' + id).classList.add('active');

  // Update section UI
  document.querySelectorAll('.app-section').forEach(el => el.classList.remove('active'));
  document.getElementById('section-' + id).classList.add('active');
}

// ── explorer ───────────────────────────────────────────────────────────────
function togglePlot(type, btn) {
  // Update toggle UI
  btn.closest('.toggle-group').querySelectorAll('.toggle-btn').forEach(el => el.classList.remove('active'));
  btn.classList.add('active');

  // Send to R
  document.getElementById('chart-loading').style.display = 'flex';
  rdesk.send('toggle_plot_type', { type: type });
}

rdesk.on("data_update", function (payload) {
  // KPIs
  if (payload.kpis) {
    document.getElementById("kpi-n").textContent   = payload.kpis.n;
    document.getElementById("kpi-mpg").textContent = payload.kpis.mean_mpg;
    document.getElementById("kpi-hp").textContent  = payload.kpis.mean_hp;
  }

  // Chart
  if (payload.chart) {
    const img = document.getElementById("chart-img");
    const loading = document.getElementById("chart-loading");
    img.onload = () => { loading.style.display = 'none'; img.style.display = 'block'; };
    img.src = payload.chart;
  }

  // Summary Table
  if (payload.summary) {
    const tbody = document.getElementById("summary-body");
    tbody.innerHTML = "";
    // payload.summary is R data.frame (object of arrays)
    const n = payload.summary.cyl ? payload.summary.cyl.length : 0;
    for (let i = 0; i < n; i++) {
      const tr = document.createElement("tr");
      tr.innerHTML = `
        <td>${payload.summary.cyl[i]}</td>
        <td>${payload.summary.count[i]}</td>
        <td>${payload.summary.avg_mpg[i].toFixed(1)}</td>
        <td>${payload.summary.avg_hp[i].toFixed(0)}</td>
      `;
      tbody.appendChild(tr);
    }
  }
});

// ── models ────────────────────────────────────────────────────────────────
function runAnalysis() {
  rdesk.send('run_model', {});
}

rdesk.on("run_model_result", function (payload) {
  document.getElementById('model-results').style.display = 'block';
  document.getElementById('model-r2').textContent = payload.r_squared;

  const tbody = document.getElementById("coeffs-body");
  tbody.innerHTML = "";
  const coefs = payload.coefficients;
  const n = coefs.term.length;
  for (let i = 0; i < n; i++) {
    const tr = document.createElement("tr");
    const pval = coefs.p.value[i];
    const pstr = pval < 0.001 ? "< 0.001" : pval.toFixed(4);
    tr.innerHTML = `
      <td><code>${coefs.term[i]}</code></td>
      <td>${coefs.estimate[i].toFixed(4)}</td>
      <td>${coefs.std.error[i].toFixed(4)}</td>
      <td style="color: ${pval < 0.05 ? 'var(--success)' : 'inherit'}">${pstr}</td>
    `;
    tbody.appendChild(tr);
  }
});

// ── shared ────────────────────────────────────────────────────────────────
rdesk.on("__trigger__", function (payload) {
  if (payload.action === "nav") switchSection(payload.target);
});

rdesk.ready(function () {
  rdesk.send("ready", {});
});

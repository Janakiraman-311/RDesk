// dashboard.js — UI logic for the mtcars dashboard

// ── message handlers ─────────────────────────────────────────────────────────
rdesk.on("data_update", function (payload) {
  // KPIs
  var k = payload.kpis;
  document.getElementById("kpi-n").textContent   = k.n;
  document.getElementById("kpi-mpg").textContent = k.mean_mpg;
  document.getElementById("kpi-hp").textContent  = k.mean_hp;
  document.getElementById("kpi-wt").textContent  = k.mean_wt.toLocaleString();

  // Chart
  var img     = document.getElementById("chart-img");
  var loading = document.getElementById("chart-loading");
  img.onload  = function () {
    loading.style.display = "none";
    img.style.display     = "block";
  };
  img.src = payload.chart;

  // Table
  var tbody = document.getElementById("table-body");
  tbody.innerHTML = "";
  var rows = payload.table;
  // rows is an object of arrays (R data.frame JSON) — transpose
  var n = rows.model ? rows.model.length : 0;
  for (var i = 0; i < n; i++) {
    var tr = document.createElement("tr");
    tr.innerHTML =
      "<td>" + rows.model[i]            + "</td>" +
      "<td>" + rows.mpg[i].toFixed(1)   + "</td>" +
      "<td>" + rows.hp[i]               + "</td>" +
      "<td>" + (rows.wt[i]*1000).toFixed(0) + "</td>" +
      "<td>" + rows.cyl[i]              + "</td>" +
      "<td>" + rows.gear[i]             + "</td>";
    tbody.appendChild(tr);
  }
});

rdesk.on("error_msg", function (payload) {
  alert("Error: " + payload.msg);
});

rdesk.on("reset_ui", function () {
  document.getElementById("x-axis").value = "wt";
  document.getElementById("y-axis").value = "mpg";
  document.querySelectorAll(".cyl-group input").forEach(function (cb) {
    cb.checked = true;
  });
});

// Menu-triggered actions forwarded back to JS from R via __trigger__
rdesk.on("__trigger__", function (payload) {
  if (payload.action === "load_csv")   rdesk.send("load_csv",   {});
  if (payload.action === "export_csv") rdesk.send("export_csv", {});
});

// ── control functions ─────────────────────────────────────────────────────────
function setAxes() {
  rdesk.send("set_axes", {
    x: document.getElementById("x-axis").value,
    y: document.getElementById("y-axis").value
  });
}

function setCylFilter() {
  var checked = Array.from(
    document.querySelectorAll(".cyl-group input:checked")
  ).map(function (cb) { return parseFloat(cb.value); });
  rdesk.send("set_cyl_filter", { cyls: checked });
}

// ── startup ───────────────────────────────────────────────────────────────────
rdesk.ready(function () {
  rdesk.send("ready", {});
});

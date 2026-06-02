<?php
session_start();
if (!isset($_SESSION['user_id'])) {
    header('Location: /login.php');
    exit;
}
$userName = htmlspecialchars($_SESSION['user_name'] ?? 'Usuario');
$userRoles = $_SESSION['roles'] ?? [];
?>
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>PublicDMS · registro oficial</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&display=swap" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
:root {
  --paper: #efece4;
  --card:  #f8f6f0;
  --field: #eae6dc;
  --ink-1: #2a2622;
  --ink-2: #5c554c;
  --ink-3: #8a8175;
  --ink-4: #b3a99a;
  --seal:        #0f8a73;
  --seal-bright: #18bc9c;
  --seal-dim:    rgba(15,138,115,0.10);
  --vigente:  #2f8f6b;
  --vencer:   #b9772a;
  --vencer-dim: rgba(185,119,42,0.12);
  --danger:   #b0473f;
  --bd-1: rgba(42,38,34,0.08);
  --bd-2: rgba(42,38,34,0.14);
  --bd-3: rgba(42,38,34,0.24);
  --mono: 'IBM Plex Mono', ui-monospace, monospace;
  --sans: 'IBM Plex Sans', system-ui, sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  background: var(--paper);
  color: var(--ink-1);
  font-family: var(--sans);
  font-size: 14px; line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}
::selection { background: var(--seal-dim); }
a { color: inherit; text-decoration: none; }

/* ── Membrete superior ────────────────────────────────── */
.topbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 28px;
  background: var(--card);
  border-bottom: 1px solid var(--bd-2);
}
.mark { display: flex; align-items: center; gap: 11px; }
.stamp {
  width: 28px; height: 28px; flex: none;
  display: flex; align-items: center; justify-content: center;
  border: 1.5px solid var(--seal); border-radius: 5px;
  color: var(--seal); font-size: 14px; font-weight: 700;
}
.mark .name { font-size: 16px; font-weight: 700; letter-spacing: -0.01em; }
.mark .name .dms { color: var(--seal); }
.mark .sep { color: var(--bd-3); margin: 0 4px; }
.mark .sub { font-family: var(--mono); font-size: 11px; color: var(--ink-3); text-transform: uppercase; letter-spacing: 0.1em; }
.session { display: flex; align-items: center; gap: 16px; }
.session .who { font-family: var(--mono); font-size: 12px; color: var(--ink-2); }
.session .who b { color: var(--ink-1); font-weight: 600; }
.btn-out {
  font-family: var(--mono); font-size: 12px; color: var(--ink-2);
  background: transparent; border: 1px solid var(--bd-2);
  border-radius: 4px; padding: 6px 13px; cursor: pointer;
  transition: border-color .12s ease, color .12s ease;
}
.btn-out:hover { border-color: var(--bd-3); color: var(--ink-1); }

/* ── Lienzo ───────────────────────────────────────────── */
.canvas { max-width: 1120px; margin: 0 auto; padding: 24px 28px 56px; }

/* ── Resumen — tarjetas papel borde plano ─────────────── */
.summary { display: grid; grid-template-columns: 1fr 300px; gap: 16px; margin-bottom: 16px; }
.cardp {
  background: var(--card); border: 1px solid var(--bd-2); border-radius: 6px;
  padding: 18px 20px;
}
.cardp .ct {
  font-family: var(--mono); font-size: 10px; text-transform: uppercase;
  letter-spacing: 0.1em; color: var(--ink-3); margin-bottom: 14px;
}
.dist-wrap { height: 188px; }

.stat-stack { display: grid; grid-template-rows: 1fr 1fr; gap: 16px; }
.stat {
  background: var(--card); border: 1px solid var(--bd-2); border-radius: 6px;
  padding: 16px 20px; display: flex; flex-direction: column; justify-content: center;
}
.stat .lbl { font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.1em; color: var(--ink-3); }
.stat .num { font-size: 34px; font-weight: 700; line-height: 1.1; margin-top: 4px; font-variant-numeric: tabular-nums; }
.stat .ctx { font-family: var(--mono); font-size: 11px; color: var(--ink-4); margin-top: 3px; }
.stat.ok .num  { color: var(--ink-1); }
.stat.ok .lbl::before { content: '\25cf '; color: var(--vigente); }
.stat.warn .num { color: var(--vencer); }
.stat.warn .lbl::before { content: '\25b2 '; color: var(--vencer); }

/* ── Buscador — campo inset ───────────────────────────── */
.search {
  display: flex; align-items: center; gap: 10px;
  background: var(--field); border: 1px solid var(--bd-2);
  border-radius: 6px; padding: 0 16px; height: 48px; margin-bottom: 18px;
  transition: border-color .12s ease;
}
.search:focus-within { border-color: var(--seal); }
.search .caret { font-family: var(--mono); color: var(--seal); font-size: 15px; }
.search input {
  flex: 1; background: transparent; border: none; outline: none;
  color: var(--ink-1); font-family: var(--mono); font-size: 14px;
}
.search input::placeholder { color: var(--ink-4); }

/* ── Registro / ledger ────────────────────────────────── */
.ledger {
  background: var(--card); border: 1px solid var(--bd-2);
  border-radius: 6px; overflow: hidden;
}
.l-head, .l-row {
  display: grid;
  grid-template-columns: 120px 1fr 220px 130px 64px 96px;
  align-items: center; gap: 16px;
}
.l-head {
  padding: 13px 20px; font-family: var(--mono); font-size: 10px;
  text-transform: uppercase; letter-spacing: 0.09em; color: var(--ink-3);
  border-bottom: 1px solid var(--bd-2);
}
.l-row {
  padding: 14px 20px; border-bottom: 1px solid var(--bd-1);
  border-left: 2px solid transparent; transition: background .1s ease;
}
.l-row:last-child { border-bottom: none; }
.l-row:hover { background: var(--field); border-left-color: var(--seal); }

.d-code { font-family: var(--mono); font-size: 13px; font-weight: 600; color: var(--seal); letter-spacing: -0.01em; }
.d-doc { min-width: 0; }
.d-doc .t { font-weight: 600; color: var(--ink-1); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.d-doc .sub { font-family: var(--mono); font-size: 11px; color: var(--ink-4); margin-top: 2px; }
.d-taxo { font-size: 12px; color: var(--ink-2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.d-taxo .slash { color: var(--ink-4); margin: 0 6px; }

.seal-chip {
  display: inline-flex; align-items: center; gap: 6px;
  font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em;
  color: var(--vigente);
}
.seal-chip .led { width: 6px; height: 6px; border-radius: 50%; background: var(--vigente); }

.d-ver { font-family: var(--mono); font-size: 12px; color: var(--ink-2); font-variant-numeric: tabular-nums; }
.d-ver::before { content: 'v'; color: var(--ink-4); }

.d-act { display: flex; gap: 6px; justify-content: flex-end; }
.act {
  font-family: var(--mono); font-size: 11px;
  border: 1px solid var(--bd-2); border-radius: 4px; padding: 5px 9px;
  color: var(--ink-2); cursor: pointer; transition: border-color .12s, color .12s;
}
.act.view:hover { border-color: var(--seal); color: var(--seal); }
.act.dl:hover { border-color: var(--bd-3); color: var(--ink-1); }
.act.off { opacity: 0.4; pointer-events: none; }

/* estados de datos */
.l-state { padding: 56px 20px; text-align: center; font-family: var(--mono); font-size: 12px; color: var(--ink-3); }

/* ── Pie / paginación ─────────────────────────────────── */
.l-foot {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 20px; border-top: 1px solid var(--bd-2);
}
.page-info { font-family: var(--mono); font-size: 11px; color: var(--ink-3); font-variant-numeric: tabular-nums; }
.page-info b { color: var(--seal); font-weight: 600; }
.pager { display: flex; align-items: center; gap: 5px; }
.pg {
  font-family: var(--mono); font-size: 12px; min-width: 30px; text-align: center;
  border: 1px solid var(--bd-2); border-radius: 4px; padding: 5px 9px;
  color: var(--ink-2); cursor: pointer; transition: border-color .12s, color .12s; user-select: none;
}
.pg:hover:not(.off):not(.on) { border-color: var(--bd-3); color: var(--ink-1); }
.pg.on { background: var(--seal-dim); border-color: var(--seal); color: var(--seal); font-weight: 600; cursor: default; }
.pg.off { opacity: 0.4; pointer-events: none; }
.pg.gap { border: none; cursor: default; color: var(--ink-4); }

@media (max-width: 860px) {
  .summary { grid-template-columns: 1fr; }
  .stat-stack { grid-template-rows: none; grid-template-columns: 1fr 1fr; }
  .l-head { display: none; }
  .l-row { grid-template-columns: 1fr auto; gap: 6px 12px; }
  .d-code { grid-column: 1; }
  .seal-chip { grid-column: 2; grid-row: 1; justify-self: end; }
  .d-doc, .d-taxo { grid-column: 1 / -1; }
  .d-ver { grid-column: 1; }
  .d-act { grid-column: 2; }
}
</style>
</head>
<body>

<header class="topbar">
  <div class="mark">
    <span class="stamp">&#10003;</span>
    <span class="name">Public<span class="dms">DMS</span></span>
    <span class="sep">·</span>
    <span class="sub">registro oficial</span>
  </div>
  <div class="session">
    <span class="who"><b><?= $userName ?></b></span>
    <a href="/api/auth.php?action=logout" class="btn-out">salir</a>
  </div>
</header>

<div class="canvas">

  <div class="summary">
    <div class="cardp">
      <div class="ct">distribución por departamento</div>
      <div class="dist-wrap"><canvas id="deptChart"></canvas></div>
    </div>
    <div class="stat-stack">
      <div class="stat ok">
        <span class="lbl">documentos vigentes</span>
        <span class="num" id="totalCount">—</span>
        <span class="ctx" id="totalCtx">copias controladas publicadas</span>
      </div>
      <div class="stat warn">
        <span class="lbl">por vencer · 30 días</span>
        <span class="num" id="expiryCount">0</span>
        <span class="ctx" id="expiryCtx">requieren revisión de vigencia</span>
      </div>
    </div>
  </div>

  <div class="search">
    <span class="caret">&rsaquo;</span>
    <input type="text" id="searchInput" autocomplete="off" spellcheck="false"
           placeholder="buscar por código o nombre de documento…">
  </div>

  <div class="ledger">
    <div class="l-head">
      <div>código</div><div>documento</div><div>clasificación</div>
      <div>vigencia</div><div>ver.</div><div></div>
    </div>
    <div id="resultsTable"></div>
    <div class="l-foot">
      <span class="page-info" id="pageInfo">cargando…</span>
      <div class="pager" id="paginationControls"></div>
    </div>
  </div>

</div>

<script>
let currentPage = 1;
const recordsPerPage = 10;
let deptChart = null;

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

document.addEventListener('DOMContentLoaded', () => { loadData(1); loadReports(); });

async function loadData(page = 1) {
  currentPage = page;
  const search = document.getElementById('searchInput').value;
  const tbody = document.getElementById('resultsTable');
  tbody.innerHTML = '<div class="l-state">consultando registro…</div>';
  try {
    const res = await fetch(`api/documents/documents.php?page=${page}&limit=${recordsPerPage}&search=${encodeURIComponent(search)}`);
    const result = await res.json();
    if (result.status === 'success') {
      renderTable(result.data);
      renderPagination(result.pagination);
    } else {
      tbody.innerHTML = '<div class="l-state">no se pudo cargar el registro</div>';
    }
  } catch (e) {
    tbody.innerHTML = '<div class="l-state">error de conexión</div>';
  }
}

function renderTable(data) {
  const tbody = document.getElementById('resultsTable');
  if (!data.length) {
    tbody.innerHTML = '<div class="l-state">no se encontraron documentos</div>';
    return;
  }
  tbody.innerHTML = data.map(doc => {
    const hasFile  = doc.file_url && doc.file_url !== '';
    const isSeed   = hasFile && doc.file_url.startsWith('seed/');
    const viewUrl  = hasFile ? 'viewer.php?file=' + encodeURIComponent(doc.file_url) : '#';
    const dlUrl    = hasFile && !isSeed ? 'view_pdf.php?file=' + encodeURIComponent(doc.file_url) + '&download=1' : '#';
    const viewOff  = hasFile ? '' : 'off';
    const dlOff    = (hasFile && !isSeed) ? '' : 'off';
    const dlTitle  = isSeed ? 'Documento simulado — sin archivo físico' : 'descargar';
    const simBadge = isSeed ? '<span style="font-size:10px;color:var(--ink-4);font-family:var(--mono);margin-left:6px">[sim]</span>' : '';
    return ''
      + '<div class="l-row">'
      +   '<div class="d-code">' + esc(doc.code) + '</div>'
      +   '<div class="d-doc"><div class="t">' + esc(doc.title) + simBadge + '</div>'
      +     '<div class="sub">sync ' + esc(doc.last_sync || 'n/a') + '</div></div>'
      +   '<div class="d-taxo">' + esc(doc.category_name) + '<span class="slash">/</span>' + esc(doc.department_name) + '</div>'
      +   '<div class="seal-chip"><span class="led"></span>vigente</div>'
      +   '<div class="d-ver">' + esc(doc.version) + '</div>'
      +   '<div class="d-act">'
      +     '<a href="' + viewUrl + '" target="_blank" class="act view ' + viewOff + '" title="ver documento">ver</a>'
      +     '<a href="' + dlUrl + '" class="act dl ' + dlOff + '" title="' + dlTitle + '">&darr;</a>'
      +   '</div>'
      + '</div>';
  }).join('');
}

function renderPagination(meta) {
  document.getElementById('pageInfo').innerHTML =
    'pág <b>' + meta.page + '</b> de ' + meta.pages + ' · ' + Number(meta.total).toLocaleString('es') + ' registros';
  document.getElementById('totalCount').textContent = Number(meta.total).toLocaleString('es');

  const c = document.getElementById('paginationControls');
  let html = '<span class="pg ' + (meta.page === 1 ? 'off' : '') + '" onclick="loadData(' + (meta.page - 1) + ')">&lsaquo;</span>';
  for (let i = 1; i <= meta.pages; i++) {
    if (i === 1 || i === meta.pages || (i >= meta.page - 1 && i <= meta.page + 1)) {
      html += '<span class="pg ' + (i === meta.page ? 'on' : '') + '" onclick="loadData(' + i + ')">' + i + '</span>';
    } else if (i === meta.page - 2 || i === meta.page + 2) {
      html += '<span class="pg gap">…</span>';
    }
  }
  html += '<span class="pg ' + (meta.page === meta.pages ? 'off' : '') + '" onclick="loadData(' + (meta.page + 1) + ')">&rsaquo;</span>';
  c.innerHTML = html;
}

async function loadReports() {
  try {
    const res = await fetch('api/reports/compliance.php');
    const result = await res.json();
    if (result.status === 'success') {
      const n = result.reports.near_expiry.length;
      document.getElementById('expiryCount').textContent = n;
      document.getElementById('expiryCtx').textContent =
        n === 0 ? 'sin vencimientos próximos' : 'requieren revisión de vigencia';
      updateChart(result.reports.by_department);
    }
  } catch (e) { console.error(e); }
}

function updateChart(data) {
  const ctx = document.getElementById('deptChart').getContext('2d');
  if (deptChart) deptChart.destroy();
  const ink3 = '#8a8175', bd = 'rgba(42,38,34,0.10)';
  deptChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: data.map(d => d.department_name),
      datasets: [{
        data: data.map(d => d.total),
        backgroundColor: '#18bc9c',
        hoverBackgroundColor: '#0f8a73',
        borderRadius: 2,
        barThickness: 14,
      }]
    },
    options: {
      indexAxis: 'y',
      maintainAspectRatio: false,
      plugins: { legend: { display: false }, tooltip: { backgroundColor: '#2a2622' } },
      scales: {
        x: { grid: { color: bd, drawBorder: false }, ticks: { color: ink3, font: { family: "'IBM Plex Mono', monospace", size: 11 } } },
        y: { grid: { display: false, drawBorder: false }, ticks: { color: '#5c554c', font: { family: "'IBM Plex Sans', sans-serif", size: 12 } } }
      }
    }
  });
}

let _t;
document.getElementById('searchInput').addEventListener('input', () => {
  clearTimeout(_t); _t = setTimeout(() => loadData(1), 300);
});
</script>

</body>
</html>

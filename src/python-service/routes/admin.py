from fastapi import APIRouter, Query
from fastapi.responses import HTMLResponse
from database import collection

router = APIRouter(prefix="/admin", tags=["Admin"])

_HTML = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>MongoDB Index Viewer</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; min-height: 100vh; }
  header { background: #1e293b; border-bottom: 1px solid #334155; padding: 16px 24px; display: flex; align-items: center; gap: 16px; }
  header h1 { font-size: 1.1rem; font-weight: 600; color: #f8fafc; }
  #stats { display: flex; gap: 12px; margin-left: auto; flex-wrap: wrap; }
  .stat { background: #0f172a; border: 1px solid #334155; border-radius: 8px; padding: 8px 16px; text-align: center; }
  .stat-num { font-size: 1.4rem; font-weight: 700; color: #38bdf8; }
  .stat-lbl { font-size: 0.7rem; color: #94a3b8; text-transform: uppercase; letter-spacing: .05em; }
  .toolbar { padding: 16px 24px; display: flex; gap: 12px; flex-wrap: wrap; align-items: center; background: #1e293b; border-bottom: 1px solid #334155; }
  input, select { background: #0f172a; border: 1px solid #334155; color: #e2e8f0; border-radius: 6px; padding: 8px 12px; font-size: 0.85rem; outline: none; }
  input:focus, select:focus { border-color: #38bdf8; }
  input[type=text] { width: 280px; }
  button { background: #0284c7; color: #fff; border: none; border-radius: 6px; padding: 8px 18px; font-size: 0.85rem; cursor: pointer; }
  button:hover { background: #0369a1; }
  button.sec { background: #334155; }
  button.sec:hover { background: #475569; }
  #content { padding: 20px 24px; }
  table { width: 100%; border-collapse: collapse; font-size: 0.82rem; }
  th { background: #1e293b; color: #94a3b8; text-transform: uppercase; font-size: 0.7rem; letter-spacing: .06em; padding: 10px 12px; text-align: left; position: sticky; top: 0; }
  td { padding: 10px 12px; border-bottom: 1px solid #1e293b; vertical-align: top; max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  tr:hover td { background: #1e293b; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 0.7rem; font-weight: 600; }
  .ok   { background: #064e3b; color: #34d399; }
  .fail { background: #450a0a; color: #f87171; }
  .pend { background: #1c1917; color: #a8a29e; }
  #pagination { display: flex; align-items: center; gap: 8px; padding: 16px 24px; }
  #pagination span { color: #94a3b8; font-size: 0.82rem; }
  .detail-row td { white-space: pre-wrap; word-break: break-word; background: #1e293b; font-size: 0.78rem; color: #94a3b8; max-width: none; }
  #loader { text-align: center; padding: 40px; color: #94a3b8; }
  .ext { background: #1e3a5f; color: #7dd3fc; padding: 2px 6px; border-radius: 4px; font-size: 0.7rem; font-weight: 600; }
</style>
</head>
<body>
<header>
  <h1>MongoDB Index Viewer &mdash; <span style="color:#38bdf8">dms_metadata.file_tags</span></h1>
  <div id="stats">
    <div class="stat"><div class="stat-num" id="s-total">…</div><div class="stat-lbl">Total</div></div>
    <div class="stat"><div class="stat-num" id="s-ok" style="color:#34d399">…</div><div class="stat-lbl">Extraídos</div></div>
    <div class="stat"><div class="stat-num" id="s-fail" style="color:#f87171">…</div><div class="stat-lbl">Fallidos</div></div>
    <div class="stat"><div class="stat-num" id="s-pend" style="color:#a8a29e">…</div><div class="stat-lbl">Pendientes</div></div>
  </div>
</header>
<div class="toolbar">
  <input type="text" id="q" placeholder="Buscar título, código, categoría…" oninput="debounceSearch()">
  <select id="ext-filter" onchange="load()">
    <option value="">Todas las extensiones</option>
  </select>
  <select id="extracted-filter" onchange="load()">
    <option value="">Cualquier estado</option>
    <option value="true">Contenido extraído</option>
    <option value="false">Extracción fallida</option>
    <option value="pending">Pendiente</option>
  </select>
  <select id="limit-sel" onchange="load()">
    <option value="20">20 por página</option>
    <option value="50">50 por página</option>
    <option value="100">100 por página</option>
  </select>
  <button class="sec" onclick="triggerBulkSync()">⟳ Bulk Sync</button>
  <button class="sec" onclick="load()">↻ Refrescar</button>
</div>
<div id="content"><div id="loader">Cargando…</div></div>
<div id="pagination"></div>

<script>
let page = 1, total = 0, _debounce;

// Works whether accessed directly (port 8001) or via Nginx (/api/)
const BASE = window.location.pathname.replace(/\/admin\/viewer.*/, '');

function debounceSearch() { clearTimeout(_debounce); _debounce = setTimeout(() => { page=1; load(); }, 350); }

async function load() {
  const q     = document.getElementById('q').value.trim();
  const ext   = document.getElementById('ext-filter').value;
  const extr  = document.getElementById('extracted-filter').value;
  const limit = parseInt(document.getElementById('limit-sel').value);
  const skip  = (page - 1) * limit;

  let url = `${BASE}/admin/docs?limit=${limit}&skip=${skip}`;
  if (q)    url += `&q=${encodeURIComponent(q)}`;
  if (ext)  url += `&ext=${encodeURIComponent(ext)}`;
  if (extr) url += `&extracted=${encodeURIComponent(extr)}`;

  document.getElementById('loader') && (document.getElementById('content').innerHTML = '<div id="loader">Cargando…</div>');
  const res  = await fetch(url);
  const data = await res.json();
  total = data.total;
  renderTable(data.docs);
  renderPagination(total, limit);
  loadStats();
  populateExtFilter(data.extensions || []);
}

async function loadStats() {
  const r = await fetch(`${BASE}/admin/stats`);
  const s = await r.json();
  document.getElementById('s-total').textContent = s.total;
  document.getElementById('s-ok').textContent    = s.extracted;
  document.getElementById('s-fail').textContent  = s.failed;
  document.getElementById('s-pend').textContent  = s.pending;
}

function populateExtFilter(exts) {
  const sel = document.getElementById('ext-filter');
  const cur = sel.value;
  sel.innerHTML = '<option value="">Todas las extensiones</option>';
  exts.forEach(e => { const o = document.createElement('option'); o.value=e; o.textContent=e||'(sin ext)'; if(e===cur) o.selected=true; sel.appendChild(o); });
}

function renderTable(docs) {
  if (!docs.length) { document.getElementById('content').innerHTML = '<div id="loader">Sin resultados.</div>'; return; }
  let html = `<table><thead><tr>
    <th>ID</th><th>Código</th><th>Título</th><th>Categoría</th><th>Dpto.</th>
    <th>Archivo</th><th>Ext</th><th>Tamaño</th><th>Contenido</th><th>Sync</th>
  </tr></thead><tbody>`;
  docs.forEach((d, i) => {
    const extr = d.content_extraction_error === 'pending'
      ? '<span class="badge pend">pendiente</span>'
      : d.content_extracted
        ? '<span class="badge ok">✓ OK</span>'
        : `<span class="badge fail" title="${d.content_extraction_error||''}">✗ error</span>`;
    const size = d.size ? (d.size > 1048576 ? (d.size/1048576).toFixed(1)+' MB' : (d.size/1024).toFixed(0)+' KB') : '—';
    const sync = d.sync_date ? d.sync_date.replace('T',' ').substring(0,19) : '—';
    html += `<tr onclick="toggleDetail(${i})" style="cursor:pointer">
      <td style="color:#94a3b8">${d.postgres_id||'—'}</td>
      <td style="font-family:monospace;color:#7dd3fc">${d.code||'—'}</td>
      <td title="${d.title||''}">${d.title||'—'}</td>
      <td>${d.category_name||'—'}</td>
      <td>${d.department_name||'—'}</td>
      <td title="${d.file_name||''}" style="max-width:160px">${d.file_name||'—'}</td>
      <td><span class="ext">${d.extension||'—'}</span></td>
      <td>${size}</td>
      <td>${extr}</td>
      <td style="color:#94a3b8;font-size:0.75rem">${sync}</td>
    </tr>
    <tr id="detail-${i}" style="display:none"><td colspan="10" class="detail-row">${formatDetail(d)}</td></tr>`;
  });
  html += '</tbody></table>';
  document.getElementById('content').innerHTML = html;
}

function formatDetail(d) {
  const preview = (d.content||'').substring(0,500).replace(/</g,'&lt;');
  return `<b>postgres_id:</b> ${d.postgres_id}  <b>document_id:</b> ${d.document_id}  <b>version:</b> ${d.version}  <b>is_active:</b> ${d.is_active}
<b>file_url:</b> ${d.file_url||'—'}  <b>mime_type:</b> ${d.mime_type||'—'}
<b>extraction_error:</b> ${d.content_extraction_error||'none'}
<b>content preview (500 chars):</b>
${preview||'(vacío)'}`;
}

function toggleDetail(i) {
  const row = document.getElementById('detail-'+i);
  row.style.display = row.style.display === 'none' ? 'table-row' : 'none';
}

function renderPagination(total, limit) {
  const pages = Math.ceil(total / limit);
  let html = `<span>${total} documentos — página ${page}/${pages||1}</span>`;
  if (page > 1)     html += `<button class="sec" onclick="page--;load()">‹ Anterior</button>`;
  if (page < pages) html += `<button class="sec" onclick="page++;load()">Siguiente ›</button>`;
  document.getElementById('pagination').innerHTML = html;
}

async function triggerBulkSync() {
  const r = await fetch(`${BASE}/sync/start`, {method:'POST'});
  const d = await r.json();
  alert(d.message || 'Sync iniciado');
  setTimeout(load, 2000);
}

load();
</script>
</body>
</html>"""


@router.get("/viewer", response_class=HTMLResponse, include_in_schema=False)
async def viewer():
    return _HTML


@router.get("/stats")
async def stats():
    total     = await collection.count_documents({})
    extracted = await collection.count_documents({"content_extracted": True})
    failed    = await collection.count_documents({"content_extracted": False,
                                                   "content_extraction_error": {"$ne": "pending"}})
    pending   = await collection.count_documents({"content_extraction_error": "pending"})
    return {"total": total, "extracted": extracted, "failed": failed, "pending": pending}


@router.get("/docs")
async def list_docs(
    q:         str  = Query(default="", description="Filter by title/code/category"),
    ext:       str  = Query(default="", description="Filter by file extension"),
    extracted: str  = Query(default="", description="true | false | pending"),
    limit:     int  = Query(default=20, le=200),
    skip:      int  = Query(default=0, ge=0),
):
    filt: dict = {}

    if q:
        filt["$or"] = [
            {"title":           {"$regex": q, "$options": "i"}},
            {"code":            {"$regex": q, "$options": "i"}},
            {"category_name":   {"$regex": q, "$options": "i"}},
            {"department_name": {"$regex": q, "$options": "i"}},
            {"file_name":       {"$regex": q, "$options": "i"}},
        ]
    if ext:
        filt["extension"] = ext
    if extracted == "true":
        filt["content_extracted"] = True
    elif extracted == "false":
        filt["content_extracted"] = False
        filt["content_extraction_error"] = {"$ne": "pending"}
    elif extracted == "pending":
        filt["content_extraction_error"] = "pending"

    projection = {
        "_id": 0, "postgres_id": 1, "document_id": 1, "code": 1, "title": 1,
        "category_name": 1, "department_name": 1, "version": 1, "is_active": 1,
        "file_name": 1, "extension": 1, "mime_type": 1, "size": 1, "file_url": 1,
        "content_extracted": 1, "content_extraction_error": 1, "sync_date": 1,
        "content": {"$substr": ["$content", 0, 500]},
    }

    total = await collection.count_documents(filt)
    cursor = collection.find(filt, projection).sort("sync_date", -1).skip(skip).limit(limit)
    docs   = await cursor.to_list(length=limit)

    extensions = await collection.distinct("extension")

    return {"total": total, "docs": docs, "extensions": sorted(e for e in extensions if e)}

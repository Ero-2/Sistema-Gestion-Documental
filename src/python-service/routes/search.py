import os
import re
import jwt
import logging
from typing import Optional

from fastapi import APIRouter, Query, Header, HTTPException, Request
from fastapi.responses import HTMLResponse

from database import collection

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Search"])

JWT_SECRET = os.getenv("JWT_SECRET", "")
JWT_ALGORITHM = "HS256"
API_KEY = os.getenv("FASTAPI_API_KEY", "")

# Campos expuestos al registro público (lectura). El contenido extraído NO se
# devuelve completo — solo la bandera de si se indexó.
_PROJECTION = {
    "_id": 0,
    "postgres_id": 1,
    "company_id": 1,
    "company_name": 1,
    "code": 1,
    "title": 1,
    "category_name": 1,
    "department_name": 1,
    "version": 1,
    "is_active": 1,
    "file_url": 1,
    "file_name": 1,
    "extension": 1,
    "mime_type": 1,
    "size": 1,
    "content_extracted": 1,
    "is_simulated": 1,
    "sync_date": 1,
    "file_meta": 1,
    "version_history": 1,
}


def _authorize(authorization: Optional[str], x_api_key: Optional[str]) -> dict:
    """
    API de búsqueda reutilizable: la consumen tanto usuarios (JWT Bearer emitido
    por /auth/login) como módulos servidor (.NET / PHP) vía X-API-Key. Acepta
    cualquiera de los dos. 401 si ninguno es válido.
    """
    if API_KEY and x_api_key and x_api_key == API_KEY:
        return {"svc": True}
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")
    token = authorization.replace("Bearer ", "", 1)
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


@router.get("/search/documents")
async def list_documents(
    q: Optional[str] = Query(default=None, description="Término de búsqueda (opcional)"),
    company_id: Optional[int] = Query(default=None, description="Filtrar por empresa (multiempresa)"),
    status: Optional[str] = Query(default="active", description="'active' | 'obsolete' | 'all'"),
    limit: int = Query(default=100, ge=1, le=500, description="Documentos por página"),
    offset: int = Query(default=0, ge=0, description="Desplazamiento para paginación"),
    authorization: Optional[str] = Header(default=None),
    x_api_key: Optional[str] = Header(default=None),
):
    """
    API de búsqueda reutilizable (Mongo full-text), consumible por .NET y PHP.
    Sin `q`: devuelve todos los documentos (orden por sync_date desc).
    Con `q` (>=2): búsqueda full-text (título, código, categoría, depto y contenido).
    `company_id`: acota a una empresa (aislamiento multiempresa).
    `status`: 'active' (default) solo vigentes, 'obsolete' solo retirados, 'all' sin filtro.
    Paginación: `limit` (tamaño de página) + `offset` (salto). `total` es el conteo
    completo del filtro (independiente de la página) para que el cliente pueda paginar.
    """
    _authorize(authorization, x_api_key)

    # Filtro base: empresa + estado activo/obsoleto
    base: dict = {}
    if company_id is not None:
        base["company_id"] = company_id
    if status == "obsolete":
        base["is_active"] = False
    elif status != "all":
        base["is_active"] = {"$ne": False}  # vigentes (True o sin campo)

    term = (q or "").strip()
    if term:
        # Substring case-insensitive (type-ahead): "proc" matchea "Procedimiento".
        # $text de Mongo solo matchea palabras completas → usamos regex sobre los
        # campos clave (incluye contenido extraído para buscar dentro de PDF/Word/Excel).
        rx = {"$regex": re.escape(term), "$options": "i"}
        flt = {
            **base,
            "$or": [
                {"title": rx},
                {"code": rx},
                {"category_name": rx},
                {"department_name": rx},
                {"content": rx},
            ],
        }
    else:
        flt = base

    total = await collection.count_documents(flt)
    cursor = collection.find(flt, _PROJECTION).sort("sync_date", -1).skip(offset).limit(limit)
    docs = await cursor.to_list(length=limit)
    for d in docs:
        d.pop("score", None)

    return {
        "documents": docs,
        "count": len(docs),
        "total": total,
        "offset": offset,
        "limit": limit,
    }


@router.get("/search", response_class=HTMLResponse)
async def search_page(request: Request):
    # Prefijo público cuando se sirve detrás de Nginx por path (/fastapi).
    base = request.headers.get("x-forwarded-prefix", "").rstrip("/")
    return _PAGE.replace("__BASE__", base)


_PAGE = """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>dms://index</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root {
  /* surfaces — cool slate, whisper-quiet elevation */
  --bg:        #0e1217;
  --surface-1: #141a21;
  --surface-2: #19212a;
  --hover:     #161d26;
  /* text hierarchy */
  --tx-1: #d7dee5;
  --tx-2: #9aa7b2;
  --tx-3: #6b7682;
  --tx-4: #4a535c;
  /* single accent — the live index signal */
  --accent: #4fd1c5;
  --accent-dim: rgba(79,209,197,0.14);
  /* semantic */
  --vigente: #5fb89a;
  --inactivo: #c79a55;
  --danger: #e0727a;
  /* borders — low-opacity cool, disappear until needed */
  --bd-1: rgba(200,215,225,0.08);
  --bd-2: rgba(200,215,225,0.14);
  --bd-3: rgba(200,215,225,0.22);
  --mono: 'IBM Plex Mono', ui-monospace, monospace;
  --sans: 'IBM Plex Sans', system-ui, sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; }
body {
  background: var(--bg);
  color: var(--tx-1);
  font-family: var(--sans);
  font-size: 14px;
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
}
::selection { background: var(--accent-dim); }

/* ── Status tabs ──────────────────────────────────────── */
.status-tabs {
  display: flex; gap: 6px; padding: 14px 24px 0;
  border-bottom: 1px solid var(--bd-1);
}
.stab {
  font-family: var(--mono); font-size: 12px; padding: 6px 16px;
  border-radius: 4px 4px 0 0; border: 1px solid transparent;
  background: transparent; color: var(--tx-3); cursor: pointer;
  transition: all .12s ease; border-bottom: none;
}
.stab:hover { color: var(--tx-1); }
.stab.on { background: var(--surface-1); border-color: var(--bd-2); color: var(--tx-1); }
.stab.obs.on { color: var(--danger); border-color: rgba(224,114,122,0.35); }

/* ── Header ───────────────────────────────────────────── */
.topbar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 14px 24px;
  border-bottom: 1px solid var(--bd-2);
  background: var(--bg);
}
.brand { font-family: var(--mono); font-size: 14px; font-weight: 600; letter-spacing: -0.01em; }
.brand .scheme { color: var(--accent); }
.brand .path { color: var(--tx-3); }
.session { display: flex; align-items: center; gap: 16px; font-family: var(--mono); font-size: 12px; }
.session .who { color: var(--tx-2); }
.session .who b { color: var(--tx-1); font-weight: 500; }
.btn-out {
  font-family: var(--mono); font-size: 12px; color: var(--tx-2);
  background: transparent; border: 1px solid var(--bd-2);
  border-radius: 4px; padding: 5px 12px; cursor: pointer;
  transition: border-color .12s ease, color .12s ease;
}
.btn-out:hover { border-color: var(--bd-3); color: var(--tx-1); }

/* ── Toolbar ──────────────────────────────────────────── */
.toolbar { padding: 18px 24px 14px; border-bottom: 1px solid var(--bd-1); }
.prompt {
  display: flex; align-items: center; gap: 10px;
  background: var(--surface-1); border: 1px solid var(--bd-2);
  border-radius: 5px; padding: 0 14px; height: 44px;
  transition: border-color .12s ease;
}
.prompt:focus-within { border-color: var(--accent); }
.prompt .caret { font-family: var(--mono); color: var(--accent); font-size: 15px; font-weight: 600; }
.prompt input {
  flex: 1; background: transparent; border: none; outline: none;
  color: var(--tx-1); font-family: var(--mono); font-size: 14px;
}
.prompt input::placeholder { color: var(--tx-4); }
.prompt .clear {
  font-family: var(--mono); font-size: 12px; color: var(--tx-3);
  background: transparent; border: none; cursor: pointer; display: none;
}
.prompt .clear:hover { color: var(--tx-1); }

.meta-line {
  display: flex; align-items: center; gap: 16px; flex-wrap: wrap;
  margin-top: 12px; font-family: var(--mono); font-size: 12px; color: var(--tx-3);
}
.meta-line .count b { color: var(--accent); font-weight: 600; }
.meta-line .range { color: var(--tx-3); font-variant-numeric: tabular-nums; }
.meta-line .range::before { content: '['; color: var(--tx-4); margin-right: 2px; }
.meta-line .range::after { content: ']'; color: var(--tx-4); margin-left: 2px; }
.meta-line .src { color: var(--tx-4); }
.meta-line .stat { color: var(--tx-3); }
.meta-line .stat b { color: var(--vigente); font-weight: 500; }

.chips { display: flex; gap: 8px; flex-wrap: wrap; margin-left: auto; }
.chip {
  font-family: var(--mono); font-size: 11px; color: var(--tx-2);
  background: transparent; border: 1px solid var(--bd-2);
  border-radius: 999px; padding: 4px 11px; cursor: pointer;
  transition: all .12s ease; white-space: nowrap;
}
.chip:hover { border-color: var(--bd-3); color: var(--tx-1); }
.chip.active { background: var(--accent-dim); border-color: var(--accent); color: var(--accent); }

/* ── Register (table) ─────────────────────────────────── */
.register { padding: 8px 24px 48px; }
.reg-head, .reg-row {
  display: grid;
  grid-template-columns: 110px 1fr 200px 70px 96px 148px;
  align-items: center; gap: 16px;
}
.reg-head {
  padding: 12px 14px; font-family: var(--mono); font-size: 11px;
  text-transform: uppercase; letter-spacing: 0.08em; color: var(--tx-3);
  border-bottom: 1px solid var(--bd-2); position: sticky; top: 0;
  background: var(--bg); z-index: 1;
}
.reg-row {
  padding: 13px 14px; border-bottom: 1px solid var(--bd-1);
  transition: background .1s ease;
  border-left: 2px solid transparent;
}
.reg-row:hover { background: var(--hover); border-left-color: var(--accent); }
/* ── Metadata expand panel ────────────────────────────────── */
.meta-panel {
  display: none; flex-direction: column; gap: 12px;
  background: var(--surface-2);
  border-bottom: 1px solid var(--bd-2); border-left: 2px solid var(--accent);
  padding: 14px 20px 16px;
}
.meta-panel.open { display: flex; }
/* fila superior: botones de acción */
.mp-actions { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.mp-btn-view {
  font-family: var(--mono); font-size: 12px; color: #fff;
  background: #0284c7; border: none; border-radius: 4px;
  padding: 7px 16px; cursor: pointer;
}
.mp-btn-view:hover { background: #0369a1; }
.mp-btn-dl {
  font-family: var(--mono); font-size: 12px; color: var(--tx-1);
  background: transparent; border: 1px solid var(--bd-2);
  border-radius: 4px; padding: 7px 16px; cursor: pointer;
}
.mp-btn-dl:hover { border-color: var(--bd-3); color: var(--tx-1); }
.sim-badge {
  font-family: var(--mono); font-size: 10px; color: #7dd3fc;
  background: #1c3045; border: 1px solid #1e4060;
  border-radius: 4px; padding: 4px 10px;
}
/* fila de summary de campos clave */
.mp-summary {
  display: flex; gap: 20px; flex-wrap: wrap;
  font-family: var(--mono); font-size: 11px; color: var(--tx-3);
}
.mp-summary .kv { display: flex; flex-direction: column; gap: 2px; }
.mp-summary .k { font-size: 10px; text-transform: uppercase; letter-spacing: .04em; color: var(--tx-4); }
.mp-summary .v { color: var(--tx-2); }
/* bloque metadatos internos del archivo */
.mp-filemeta { margin-top: 4px; }
.mp-filemeta-title {
  font-family: var(--mono); font-size: 10px; text-transform: uppercase;
  letter-spacing: .06em; color: var(--tx-4); margin-bottom: 8px;
}
/* JSON pre */
.meta-json {
  font-family: var(--mono); font-size: 11px; color: var(--tx-2);
  background: var(--surface-1); border: 1px solid var(--bd-1);
  border-radius: 4px; padding: 10px 14px;
  max-height: 220px; overflow: auto; white-space: pre-wrap; word-break: break-word;
}

.c-code { font-family: var(--mono); font-size: 13px; font-weight: 600; color: var(--accent); letter-spacing: -0.01em; }
.c-title { min-width: 0; }
.c-title .t { color: var(--tx-1); font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.c-title .sub { font-family: var(--mono); font-size: 11px; color: var(--tx-4); margin-top: 2px; }
.c-taxo { font-size: 12px; color: var(--tx-2); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.c-taxo .dot { color: var(--tx-4); margin: 0 6px; }
.c-ver { font-family: var(--mono); font-size: 12px; color: var(--tx-2); font-variant-numeric: tabular-nums; }
.c-ver::before { content: 'v'; color: var(--tx-4); }
.c-status { display: flex; align-items: center; gap: 6px; font-family: var(--mono); font-size: 10px; text-transform: uppercase; letter-spacing: 0.06em; }
.c-status .led { width: 6px; height: 6px; border-radius: 50%; }
.s-on  .led { background: var(--vigente); box-shadow: 0 0 6px rgba(95,184,154,0.6); }
.s-on  { color: var(--vigente); }
.s-off .led { background: var(--inactivo); }
.s-off { color: var(--inactivo); }
.c-actions { display: flex; gap: 5px; align-items: center; justify-content: flex-end; }
/* botones de acción por fila */
.ab { font-family: var(--mono); font-size: 11px; border-radius: 4px; padding: 5px 8px; cursor: pointer; border: 1px solid var(--bd-2); background: transparent; color: var(--tx-2); transition: all .12s; white-space: nowrap; }
.ab:hover { border-color: var(--bd-3); color: var(--tx-1); }
.ab-view { background: rgba(2,132,199,0.12); border-color: rgba(2,132,199,0.5); color: #7dd3fc; }
.ab-view:hover { background: rgba(2,132,199,0.25); border-color: #0284c7; }
.ab-dl:hover { border-color: var(--accent); color: var(--accent); }
.ab-meta { font-size: 10px; letter-spacing: 0.04em; }
.ab-meta.open { background: var(--accent-dim); border-color: var(--accent); color: var(--accent); }
.idx-flag { font-family: var(--mono); font-size: 10px; color: var(--tx-4); }
.idx-flag.on { color: var(--accent); }
.idx-flag.sim { color: #7dd3fc; }

/* ── States ───────────────────────────────────────────── */
.state { padding: 64px 24px; text-align: center; font-family: var(--mono); font-size: 13px; color: var(--tx-3); }
.state .big { font-size: 13px; letter-spacing: 0.04em; text-transform: uppercase; color: var(--tx-2); }
.state .hint { margin-top: 8px; color: var(--tx-4); font-size: 12px; }
.state.err .big { color: var(--danger); }
.cursor { display: inline-block; width: 8px; height: 15px; background: var(--accent); vertical-align: -2px; animation: blink 1s step-end infinite; }
@keyframes blink { 50% { opacity: 0; } }

/* ── Pager ────────────────────────────────────────────── */
.pager {
  display: flex; align-items: center; justify-content: center; gap: 8px;
  padding: 28px 24px 8px; font-family: var(--mono); font-size: 12px;
}
.pager:empty { display: none; }
.pg-btn {
  font-family: var(--mono); font-size: 12px; color: var(--tx-2);
  background: transparent; border: 1px solid var(--bd-2);
  border-radius: 4px; padding: 6px 13px; cursor: pointer;
  transition: border-color .12s ease, color .12s ease;
}
.pg-btn:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
.pg-btn:disabled { color: var(--tx-4); border-color: var(--bd-1); cursor: not-allowed; }
.pg-info { color: var(--tx-3); padding: 0 14px; font-variant-numeric: tabular-nums; }
.pg-info b { color: var(--accent); font-weight: 600; }
.pg-info .of { color: var(--tx-4); }

/* ── Responsive ───────────────────────────────────────── */
@media (max-width: 720px) {
  .reg-head { display: none; }
  .reg-row {
    grid-template-columns: 1fr auto; gap: 6px 12px; padding: 14px;
  }
  .c-code { grid-column: 1; }
  .c-status { grid-column: 2; grid-row: 1; justify-self: end; }
  .c-title { grid-column: 1 / -1; }
  .c-taxo { grid-column: 1 / -1; }
  .c-ver { grid-column: 1; }
  .c-actions { grid-column: 2; }
  .chips { width: 100%; margin: 10px 0 0; }
  .meta-panel { flex-direction: column; }
  .meta-actions { flex-direction: row; flex-wrap: wrap; }
}
</style>
</head>
<body>

<header class="topbar">
  <div class="brand"><span class="scheme">dms://</span><span class="path">index</span></div>
  <div class="session">
    <span class="who" id="who">···</span>
    <button class="btn-out" onclick="logout()">exit</button>
  </div>
</header>

<div class="status-tabs">
  <span class="stab on"      id="stab-active"   onclick="switchStatus('active')">vigentes</span>
  <span class="stab obs"     id="stab-obsolete" onclick="switchStatus('obsolete')">obsoletos</span>
</div>

<div class="toolbar">
  <div class="prompt">
    <span class="caret">&gt;</span>
    <input id="q" type="text" autocomplete="off" spellcheck="false"
           placeholder="filtrar registro — código, título, categoría o contenido…">
    <button class="clear" id="clear" onclick="clearQ()">esc</button>
  </div>
  <div class="meta-line">
    <span class="count"><b id="total">0</b> documentos</span>
    <span class="range" id="range">—</span>
    <span class="stat"><b id="vig">0</b> vigentes en página</span>
    <span class="src">idx:mongo · full-text</span>
    <div class="chips" id="chips"></div>
  </div>
</div>

<main class="register">
  <div class="reg-head">
    <div>código</div><div>documento</div><div>clasificación</div>
    <div>ver.</div><div>estado</div><div style="text-align:right">acciones</div>
  </div>
  <div id="rows"></div>
  <nav class="pager" id="pager"></nav>
</main>

<script>
const BASE = '__BASE__';
const token = localStorage.getItem('access_token');
if (!token) location.href = BASE + '/auth/login';
const uname = localStorage.getItem('user_name') || 'sesión';
document.getElementById('who').innerHTML = '<b>' + uname.toLowerCase().replace(/\\s+/g,'.') + '</b>@qualitydms';

const PAGE = 100;          // documentos por página (servidor)
let pageDocs = [];         // página actual recibida del servidor
let total = 0;             // total de documentos que matchean el filtro
let offset = 0;            // desplazamiento de la página actual
let activeDept = null;
let currentStatus = 'active';
let _t;

function switchStatus(s) {
  currentStatus = s;
  document.getElementById('stab-active').classList.toggle('on', s === 'active');
  document.getElementById('stab-obsolete').classList.toggle('on', s === 'obsolete');
  fetchDocs(true);
}

const rows  = document.getElementById('rows');
const qIn   = document.getElementById('q');
const clrBtn= document.getElementById('clear');

qIn.addEventListener('input', () => {
  clrBtn.style.display = qIn.value ? 'block' : 'none';
  clearTimeout(_t);
  _t = setTimeout(() => fetchDocs(true), 320);
});
qIn.addEventListener('keydown', e => { if (e.key === 'Escape') clearQ(); });

function clearQ() { qIn.value = ''; clrBtn.style.display = 'none'; fetchDocs(true); }

function showState(html, cls) {
  rows.innerHTML = '<div class="state ' + (cls||'') + '">' + html + '</div>';
}

// resetPage=true: nueva consulta (vuelve a la primera página).
// resetPage=false: navegación entre páginas (conserva offset).
async function fetchDocs(resetPage) {
  if (resetPage) offset = 0;
  const q = qIn.value.trim();
  showState('consultando índice <span class="cursor"></span>');
  document.getElementById('pager').innerHTML = '';
  try {
    let url = BASE + '/search/documents?limit=' + PAGE + '&offset=' + offset + '&status=' + currentStatus;
    if (q.length >= 2) url += '&q=' + encodeURIComponent(q);
    const res = await fetch(url, { headers: { 'Authorization': 'Bearer ' + token } });
    if (res.status === 401) { logout(); return; }
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    pageDocs = data.documents || [];
    total = data.total || 0;
    activeDept = null;
    buildChips();
    render();
  } catch (e) {
    showState('error de conexión<div class="hint">' + e.message + '</div>', 'err');
  }
}

function gotoPage(newOffset) {
  offset = Math.max(0, newOffset);
  fetchDocs(false);
  window.scrollTo({ top: 0, behavior: 'smooth' });
}

function renderPager() {
  const pager = document.getElementById('pager');
  if (total <= PAGE) { pager.innerHTML = ''; return; }
  const page    = Math.floor(offset / PAGE) + 1;
  const pages   = Math.ceil(total / PAGE);
  const canPrev = offset > 0;
  const canNext = offset + PAGE < total;
  pager.innerHTML =
    '<button class="pg-btn" ' + (canPrev ? '' : 'disabled') +
      ' onclick="gotoPage(' + (offset - PAGE) + ')">&lsaquo; anterior</button>' +
    '<span class="pg-info">pág <b>' + page + '</b> <span class="of">de</span> ' + pages + '</span>' +
    '<button class="pg-btn" ' + (canNext ? '' : 'disabled') +
      ' onclick="gotoPage(' + (offset + PAGE) + ')">siguiente &rsaquo;</button>';
}

function buildChips() {
  const depts = [...new Set(pageDocs.map(d => d.department_name).filter(Boolean))].sort();
  const chips = document.getElementById('chips');
  if (depts.length <= 1) { chips.innerHTML = ''; return; }
  chips.innerHTML =
    '<span class="chip active" data-d="" onclick="filterDept(this,null)">todas</span>' +
    depts.map(d => '<span class="chip" data-d="'+esc(d)+'" onclick="filterDept(this,\\''+esc(d)+'\\')">'+esc(d)+'</span>').join('');
}

function filterDept(el, dept) {
  activeDept = dept;
  document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
  el.classList.add('active');
  render();
}

let _expandedIdx = null;
let _files = [];   // _files[i] = file_name del doc i en la página actual

function render() {
  const docs = activeDept ? pageDocs.filter(d => d.department_name === activeDept) : pageDocs;
  const start = total ? offset + 1 : 0;
  const end   = offset + pageDocs.length;
  document.getElementById('total').textContent = total.toLocaleString('es');
  document.getElementById('range').textContent = total ? (start + '–' + end) : 'vacío';
  document.getElementById('vig').textContent = docs.filter(d => d.is_active !== false).length;
  _expandedIdx = null;
  _files = docs.map(d => d.file_name || '');

  if (!docs.length) {
    const q = qIn.value.trim();
    renderPager();
    showState(
      '<div class="big">sin registros</div><div class="hint">' +
      (q ? 'ningún documento coincide con «' + esc(q) + '»' : (currentStatus === 'obsolete' ? 'no hay documentos obsoletos' : 'no hay documentos indexados todavía')) +
      '</div>');
    return;
  }

  rows.innerHTML = docs.map((d, i) => {
    const active = d.is_active !== false;
    const file   = d.file_name || '';
    const isSim  = d.is_simulated;

    let idxFlag;
    if (isSim)                   idxFlag = '<span class="idx-flag sim" title="documento simulado">◆ sim</span>';
    else if (d.content_extracted) idxFlag = '<span class="idx-flag on"  title="texto indexado">◆ txt</span>';
    else                          idxFlag = '<span class="idx-flag"      title="solo metadatos">◇ meta</span>';

    // Botones de fila — usan índice numérico, sin strings embebidos
    const btnVer = file
      ? '<button class="ab ab-view" onclick="event.stopPropagation();openFile('+i+')" title="Abrir visor">👁 Ver</button>'
      : '';
    const btnDl = (file && !isSim)
      ? '<button class="ab ab-dl"   onclick="event.stopPropagation();dlFile('+i+')"   title="Descargar">↓ DL</button>'
      : '';
    const btnMeta =
      '<button class="ab ab-meta" id="mb-'+i+'" onclick="event.stopPropagation();toggleMeta('+i+')" title="Metadatos JSON">{ }</button>';

    return ''
      + '<div class="reg-row">'
      +   '<div class="c-code">' + esc(d.code || '—') + '</div>'
      +   '<div class="c-title"><div class="t">' + esc(d.title || 'Sin título') + '</div>'
      +     '<div class="sub">' + idxFlag + (file ? ' · ' + esc(file) : '') + '</div></div>'
      +   '<div class="c-taxo">' + esc(d.category_name || '—')
      +     '<span class="dot">/</span>' + esc(d.department_name || '—') + '</div>'
      +   '<div class="c-ver">' + esc(d.version || '1.0') + '</div>'
      +   '<div class="c-status ' + (active ? 's-on' : 's-off') + '"><span class="led"></span>'
      +     (active ? 'vigente' : 'inactivo') + '</div>'
      +   '<div class="c-actions">' + btnVer + btnDl + btnMeta + '</div>'
      + '</div>'
      + buildMetaPanel(d, i, file, isSim);
  }).join('');

  renderPager();
}

function buildMetaPanel(d, i, file, isSim) {
  // Botones dentro del panel (también por índice)
  const btnView = file
    ? '<button class="mp-btn-view" onclick="openFile('+i+')">👁 Abrir visor</button>'
    : '';
  const btnDl = (file && !isSim)
    ? '<button class="mp-btn-dl"   onclick="dlFile('+i+')">↓ Descargar</button>'
    : '';
  const simBadge = isSim ? '<span class="sim-badge">◆ Documento simulado (seed)</span>' : '';
  const noFile   = !file ? '<span style="font-family:var(--mono);font-size:11px;color:var(--tx-4)">Sin archivo físico</span>' : '';

  // Summary de campos clave
  const fmtSize = d.size
    ? (d.size > 1048576 ? (d.size/1048576).toFixed(1)+' MB' : Math.round(d.size/1024)+' KB')
    : '—';
  const fmtSync = (d.sync_date||'').replace('T',' ').substring(0,16) || '—';
  const summary = ''
    + kv('empresa',    d.company_name  || '—')
    + kv('categoría',  d.category_name || '—')
    + kv('depto.',     d.department_name || '—')
    + kv('versión',    d.version       || '—')
    + kv('extensión',  d.extension     || '—')
    + kv('tamaño',     fmtSize)
    + kv('sync',       fmtSync)
    + kv('id postgres',String(d.postgres_id || '—'));

  // Metadatos internos del archivo (autor, fechas, páginas, etc.)
  let fileMeta = '';
  if (d.file_meta && typeof d.file_meta === 'object' && Object.keys(d.file_meta).length) {
    const labels = {
      author: 'autor', title: 'título (archivo)', subject: 'asunto',
      keywords: 'palabras clave', description: 'descripción',
      last_modified_by: 'últ. modificado por', creator: 'creador',
      producer: 'productor', created: 'creado', modified: 'modificado',
      revision: 'revisión', language: 'idioma', category: 'categoría (archivo)',
      pages: 'páginas', slides: 'diapositivas', sheets: 'hojas',
      sheet_names: 'nombres de hoja', paragraphs: 'párrafos', words: 'palabras',
      chars: 'caracteres', lines: 'líneas', encoding: 'codificación',
      rows: 'filas', columns: 'columnas', headers: 'encabezados',
      dimensions: 'dimensiones', color_mode: 'modo color', format: 'formato img',
      dpi: 'DPI', make: 'cámara marca', model: 'cámara modelo',
      software: 'software', datetime: 'fecha foto', datetimeoriginal: 'fecha original',
      artist: 'artista', copyright: 'copyright', imagedescription: 'descripción img',
      from: 'de', to: 'para', subject_mail: 'asunto', date: 'fecha envío',
      cc: 'CC', attachments: 'adjuntos', encrypted: 'cifrado',
    };
    const fmRows = Object.entries(d.file_meta).map(([k, v]) => {
      const label = labels[k] || k.replace(/_/g, ' ');
      return kv(label, String(v));
    }).join('');
    fileMeta = '<div class="mp-filemeta"><div class="mp-filemeta-title">📎 metadatos del archivo</div>'
      + '<div class="mp-summary">' + fmRows + '</div></div>';
  }

  // Historial de versiones (version_history en MongoDB)
  let verHist = '';
  if (Array.isArray(d.version_history) && d.version_history.length) {
    const rows = d.version_history.map(v => {
      const dt = (v.obsoleted_at||'').replace('T',' ').substring(0,16) || '—';
      const vFile = v.file_url || '';
      const isSeedV = vFile.startsWith('seed/');
      const vName = v.file_name || '';
      const vLink = vFile && !isSeedV && vName
        ? '<a href="'+BASE+'/indexer/viewer/'+encodeURIComponent(vName)+'" target="_blank" style="font-size:11px;color:var(--accent);font-family:var(--mono)">ver</a>'
        : '';
      return kv('v' + (v.version||'?') + ' — obsoleta ' + dt, vLink || '(sin archivo)');
    }).join('');
    verHist = '<div class="mp-filemeta"><div class="mp-filemeta-title">📜 versiones anteriores</div>'
      + '<div class="mp-summary">' + rows + '</div></div>';
  }

  // JSON sin el campo content (puede ser enorme)
  const clone = Object.assign({}, d);
  delete clone.content;
  const json = esc(JSON.stringify(clone, null, 2));

  return '<div class="meta-panel" id="mp-'+i+'">'
    + '<div class="mp-actions">' + btnView + btnDl + simBadge + noFile + '</div>'
    + '<div class="mp-summary">' + summary + '</div>'
    + fileMeta
    + verHist
    + '<pre class="meta-json">' + json + '</pre>'
    + '</div>';
}

function kv(k, v) {
  return '<div class="kv"><span class="k">'+k+'</span><span class="v">'+esc(String(v))+'</span></div>';
}

function toggleMeta(i) {
  // Cerrar el panel anterior
  if (_expandedIdx !== null && _expandedIdx !== i) {
    document.getElementById('mp-' + _expandedIdx)?.classList.remove('open');
    document.getElementById('mb-' + _expandedIdx)?.classList.remove('open');
  }
  const panel  = document.getElementById('mp-' + i);
  const metaBtn= document.getElementById('mb-' + i);
  if (!panel) return;
  const opening = !panel.classList.contains('open');
  panel.classList.toggle('open', opening);
  metaBtn?.classList.toggle('open', opening);
  _expandedIdx = opening ? i : null;
}

function openFile(i) {
  window.open('/indexer/viewer/' + encodeURIComponent(_files[i]), '_blank');
}

function dlFile(i) {
  window.location.href = BASE + '/indexer/download/' + encodeURIComponent(_files[i]);
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function logout() {
  localStorage.clear();
  location.href = BASE + '/auth/login';
}

fetchDocs(true);
</script>
</body>
</html>"""

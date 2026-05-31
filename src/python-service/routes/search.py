import os
import jwt
import logging
from typing import Optional

from fastapi import APIRouter, Query, Header, HTTPException
from fastapi.responses import HTMLResponse

from database import collection

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Search"])

JWT_SECRET = os.getenv("JWT_SECRET", "")
JWT_ALGORITHM = "HS256"

# Campos expuestos al registro público (lectura). El contenido extraído NO se
# devuelve completo — solo la bandera de si se indexó.
_PROJECTION = {
    "_id": 0,
    "postgres_id": 1,
    "code": 1,
    "title": 1,
    "category_name": 1,
    "department_name": 1,
    "version": 1,
    "is_active": 1,
    "file_url": 1,
    "file_name": 1,
    "extension": 1,
    "content_extracted": 1,
    "sync_date": 1,
}


def _require_user(authorization: Optional[str]) -> dict:
    """Valida el JWT emitido por /auth/login. Lanza 401 si falta o es inválido."""
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
    limit: int = Query(default=200, le=500),
    authorization: Optional[str] = Header(default=None),
):
    """
    Registro de documentos indexados.
    Sin `q`: devuelve todos los documentos (orden por sync_date desc).
    Con `q` (>=2): búsqueda full-text (título, código, categoría, depto y contenido).
    """
    _require_user(authorization)

    term = (q or "").strip()
    if len(term) >= 2:
        cursor = (
            collection.find(
                {"$text": {"$search": term}},
                {**_PROJECTION, "score": {"$meta": "textScore"}},
            )
            .sort([("score", {"$meta": "textScore"})])
            .limit(limit)
        )
    else:
        cursor = collection.find({}, _PROJECTION).sort("sync_date", -1).limit(limit)

    docs = await cursor.to_list(length=limit)
    for d in docs:
        d.pop("score", None)

    return {"documents": docs, "count": len(docs)}


@router.get("/search", response_class=HTMLResponse)
async def search_page():
    return _PAGE


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
  grid-template-columns: 110px 1fr 200px 70px 96px 40px;
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
  cursor: pointer; transition: background .1s ease;
  border-left: 2px solid transparent;
}
.reg-row:hover { background: var(--hover); border-left-color: var(--accent); }

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
.c-open { font-family: var(--mono); color: var(--tx-4); text-align: right; transition: color .12s ease; }
.reg-row:hover .c-open { color: var(--accent); }
.idx-flag { font-family: var(--mono); font-size: 10px; color: var(--tx-4); }
.idx-flag.on { color: var(--accent); }

/* ── States ───────────────────────────────────────────── */
.state { padding: 64px 24px; text-align: center; font-family: var(--mono); font-size: 13px; color: var(--tx-3); }
.state .big { font-size: 13px; letter-spacing: 0.04em; text-transform: uppercase; color: var(--tx-2); }
.state .hint { margin-top: 8px; color: var(--tx-4); font-size: 12px; }
.state.err .big { color: var(--danger); }
.cursor { display: inline-block; width: 8px; height: 15px; background: var(--accent); vertical-align: -2px; animation: blink 1s step-end infinite; }
@keyframes blink { 50% { opacity: 0; } }

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
  .c-open { display: none; }
  .chips { width: 100%; margin: 10px 0 0; }
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

<div class="toolbar">
  <div class="prompt">
    <span class="caret">&gt;</span>
    <input id="q" type="text" autocomplete="off" spellcheck="false"
           placeholder="filtrar registro — código, título, categoría o contenido…">
    <button class="clear" id="clear" onclick="clearQ()">esc</button>
  </div>
  <div class="meta-line">
    <span class="count"><b id="count">0</b> documentos</span>
    <span class="stat"><b id="vig">0</b> vigentes</span>
    <span class="src">idx:mongo · full-text</span>
    <div class="chips" id="chips"></div>
  </div>
</div>

<main class="register">
  <div class="reg-head">
    <div>código</div><div>documento</div><div>clasificación</div>
    <div>ver.</div><div>estado</div><div></div>
  </div>
  <div id="rows"></div>
</main>

<script>
const token = localStorage.getItem('access_token');
if (!token) location.href = '/auth/login';
const uname = localStorage.getItem('user_name') || 'sesión';
document.getElementById('who').innerHTML = '<b>' + uname.toLowerCase().replace(/\\s+/g,'.') + '</b>@qualitydms';

let allDocs = [];
let activeDept = null;
let _t;

const rows  = document.getElementById('rows');
const qIn   = document.getElementById('q');
const clrBtn= document.getElementById('clear');

qIn.addEventListener('input', () => {
  clrBtn.style.display = qIn.value ? 'block' : 'none';
  clearTimeout(_t);
  _t = setTimeout(fetchDocs, 320);
});
qIn.addEventListener('keydown', e => { if (e.key === 'Escape') clearQ(); });

function clearQ() { qIn.value = ''; clrBtn.style.display = 'none'; fetchDocs(); }

function showState(html, cls) {
  rows.innerHTML = '<div class="state ' + (cls||'') + '">' + html + '</div>';
}

async function fetchDocs() {
  const q = qIn.value.trim();
  showState('consultando índice <span class="cursor"></span>');
  try {
    const url = '/search/documents?limit=300' + (q.length >= 2 ? '&q=' + encodeURIComponent(q) : '');
    const res = await fetch(url, { headers: { 'Authorization': 'Bearer ' + token } });
    if (res.status === 401) { logout(); return; }
    if (!res.ok) throw new Error('HTTP ' + res.status);
    const data = await res.json();
    allDocs = data.documents || [];
    activeDept = null;
    buildChips();
    render();
  } catch (e) {
    showState('error de conexión<div class="hint">' + e.message + '</div>', 'err');
  }
}

function buildChips() {
  const depts = [...new Set(allDocs.map(d => d.department_name).filter(Boolean))].sort();
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

function render() {
  const docs = activeDept ? allDocs.filter(d => d.department_name === activeDept) : allDocs;
  document.getElementById('count').textContent = docs.length;
  document.getElementById('vig').textContent = docs.filter(d => d.is_active !== false).length;

  if (!docs.length) {
    const q = qIn.value.trim();
    showState(
      '<div class="big">sin registros</div><div class="hint">' +
      (q ? 'ningún documento coincide con «' + esc(q) + '»' : 'no hay documentos indexados todavía') +
      '</div>');
    return;
  }

  rows.innerHTML = docs.map(d => {
    const active = d.is_active !== false;
    const file = d.file_name || d.file_url || '';
    const idx  = d.content_extracted ? '<span class="idx-flag on" title="contenido full-text indexado">◆ texto</span>'
                                     : '<span class="idx-flag" title="sólo metadatos">◇ meta</span>';
    return ''
      + '<div class="reg-row" ' + (file ? 'onclick="openFile(\\''+esc(file)+'\\')"' : '') + '>'
      +   '<div class="c-code">' + esc(d.code || '—') + '</div>'
      +   '<div class="c-title"><div class="t">' + esc(d.title || 'Sin título') + '</div>'
      +     '<div class="sub">' + idx + (file ? ' · ' + esc(file) : '') + '</div></div>'
      +   '<div class="c-taxo">' + esc(d.category_name || '—')
      +     '<span class="dot">/</span>' + esc(d.department_name || '—') + '</div>'
      +   '<div class="c-ver">' + esc(d.version || '1.0') + '</div>'
      +   '<div class="c-status ' + (active ? 's-on' : 's-off') + '"><span class="led"></span>'
      +     (active ? 'vigente' : 'inactivo') + '</div>'
      +   '<div class="c-open">' + (file ? '&rsaquo;' : '') + '</div>'
      + '</div>';
  }).join('');
}

function openFile(name) {
  window.open('/indexer/file/' + encodeURIComponent(name), '_blank');
}

function esc(s) {
  return String(s).replace(/[&<>"']/g, c =>
    ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function logout() {
  localStorage.clear();
  location.href = '/auth/login';
}

fetchDocs();
</script>
</body>
</html>"""

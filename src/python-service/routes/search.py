import os
import jwt
import logging
from fastapi import APIRouter, Query
from fastapi.responses import HTMLResponse, RedirectResponse

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Search"])

JWT_SECRET = os.getenv("JWT_SECRET", "")
JWT_ALGORITHM = "HS256"


@router.get("/search", response_class=HTMLResponse)
async def search_page():
    return """<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DMS Search Engine</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <style>
        :root { --primary: #667eea; --accent: #764ba2; }
        body { background: #f0f2f5; font-family: 'Segoe UI', sans-serif; }
        .navbar { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); }
        .search-card { background: white; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); padding: 24px; margin-bottom: 24px; }
        .doc-card { background: white; border-radius: 10px; border: 1px solid #e9ecef; padding: 16px; margin-bottom: 12px; transition: box-shadow 0.2s; }
        .doc-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
        .badge-dept { background: #e8f4fd; color: #0d6efd; border-radius: 6px; padding: 3px 10px; font-size: 12px; }
        .badge-cat  { background: #f0fdf4; color: #198754; border-radius: 6px; padding: 3px 10px; font-size: 12px; }
        .badge-ver  { background: #fff8e1; color: #fd7e14; border-radius: 6px; padding: 3px 10px; font-size: 12px; }
        .user-info  { font-size: 13px; color: rgba(255,255,255,0.85); }
    </style>
</head>
<body>

<nav class="navbar navbar-dark px-4 py-3 mb-4">
    <div class="d-flex align-items-center gap-3">
        <i class="bi bi-search-heart fs-4 text-white"></i>
        <span class="fw-bold text-white fs-5">DMS Search Engine</span>
    </div>
    <div class="d-flex align-items-center gap-3">
        <span class="user-info" id="userInfo"><i class="bi bi-person-circle me-1"></i>...</span>
        <button class="btn btn-sm btn-outline-light" onclick="logout()">
            <i class="bi bi-box-arrow-right"></i> Salir
        </button>
    </div>
</nav>

<div class="container">
    <div class="search-card">
        <div class="input-group input-group-lg">
            <span class="input-group-text bg-white border-end-0">
                <i class="bi bi-search text-muted"></i>
            </span>
            <input type="text" id="searchInput" class="form-control border-start-0 ps-0 fs-6"
                   placeholder="Buscar documentos por título, código, categoría o departamento...">
            <button class="btn btn-primary px-4" onclick="search()">Buscar</button>
        </div>
    </div>

    <div id="results"></div>
    <div id="noResults" class="text-center text-muted py-5" style="display:none">
        <i class="bi bi-file-earmark-x fs-1 d-block mb-2"></i>
        No se encontraron documentos
    </div>
    <div id="loading" class="text-center py-5" style="display:none">
        <div class="spinner-border text-primary"></div>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
const token = localStorage.getItem('access_token');
if (!token) window.location.href = '/auth/login';

// Mostrar usuario
const name = localStorage.getItem('user_name') || '';
if (name) document.getElementById('userInfo').innerHTML = `<i class="bi bi-person-circle me-1"></i>${name}`;

// Buscar al presionar Enter
document.getElementById('searchInput').addEventListener('keydown', e => {
    if (e.key === 'Enter') search();
});

// Buscar con debounce al escribir
let debounce;
document.getElementById('searchInput').addEventListener('input', () => {
    clearTimeout(debounce);
    debounce = setTimeout(() => search(), 400);
});

async function search() {
    const q = document.getElementById('searchInput').value.trim();
    if (!q) { document.getElementById('results').innerHTML = ''; return; }

    document.getElementById('loading').style.display = 'block';
    document.getElementById('results').innerHTML = '';
    document.getElementById('noResults').style.display = 'none';

    try {
        const res = await fetch(`/indexer/search?q=${encodeURIComponent(q)}&limit=20`, {
            headers: { 'X-API-Key': token }
        });
        const data = await res.json();
        document.getElementById('loading').style.display = 'none';

        const docs = data.results || data.data || data;
        if (!Array.isArray(docs) || docs.length === 0) {
            document.getElementById('noResults').style.display = 'block';
            return;
        }
        renderResults(docs);
    } catch (e) {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('results').innerHTML = `<div class="alert alert-danger">Error: ${e.message}</div>`;
    }
}

function renderResults(docs) {
    const container = document.getElementById('results');
    container.innerHTML = docs.map(doc => `
        <div class="doc-card">
            <div class="d-flex justify-content-between align-items-start">
                <div class="flex-grow-1">
                    <div class="fw-bold text-dark mb-1">${doc.title || doc.titulo || 'Sin título'}</div>
                    <div class="text-muted small mb-2">${doc.code || doc.codigo || ''}</div>
                    <div class="d-flex gap-2 flex-wrap">
                        ${doc.category_name ? `<span class="badge-cat">${doc.category_name}</span>` : ''}
                        ${doc.department_name ? `<span class="badge-dept">${doc.department_name}</span>` : ''}
                        ${doc.version ? `<span class="badge-ver">v${doc.version}</span>` : ''}
                    </div>
                </div>
                ${doc.file_url || doc.file_name ? `
                <a href="/indexer/file/${encodeURIComponent(doc.file_name || doc.file_url)}"
                   class="btn btn-sm btn-outline-primary ms-3" target="_blank">
                    <i class="bi bi-eye"></i> Ver
                </a>` : ''}
            </div>
        </div>
    `).join('');
}

function logout() {
    localStorage.removeItem('access_token');
    localStorage.removeItem('user_name');
    localStorage.removeItem('roles');
    window.location.href = '/auth/login';
}

// Cargar todos los docs al entrar
search();
</script>
</body>
</html>"""

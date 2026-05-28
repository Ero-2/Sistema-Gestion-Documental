<?php
// Auto-trigger removido. Eventos ahora vienen de .NET vía APIs.

session_start();

// Si autenticado, mostrar panel
if (isset($_SESSION['user_id'])) {
    // TODO: Panel de usuario
    echo "Bienvenido " . htmlspecialchars($_SESSION['user_name']) . "!";
    exit;
}

// Si no autenticado, redirigir a login
header('Location: /login.php');
exit;
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PublicDMS | Panel de Consulta Local</title>
    
    <!-- Bootstrap 5 CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Bootstrap Icons -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.10.0/font/bootstrap-icons.css">
    <!-- Chart.js -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>

    <style>
        :root { --primary-dark: #2c3e50; --accent: #18bc9c; }
        body { background-color: #f4f7f6; font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; }
        .navbar { background-color: var(--primary-dark); border-bottom: 4px solid var(--accent); }
        .stats-card { border: none; border-radius: 12px; transition: transform 0.2s; }
        .stats-card:hover { transform: translateY(-5px); }
        .search-section { background: white; border-radius: 12px; padding: 25px; box-shadow: 0 10px 30px rgba(0,0,0,0.05); margin-top: -30px; position: relative; z-index: 10; }
        .table-container { background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 5px 15px rgba(0,0,0,0.05); }
        .btn-view { border-radius: 20px; padding: 5px 15px; }
        .text-accent { color: var(--accent) !important; }

        @keyframes spin {
            from { transform: rotate(0deg); }
            to { transform: rotate(360deg); }
        }
        .bi-spin {
            display: inline-block;
            animation: spin 2s linear infinite;
        }
    </style>
</head>
<body>

<!-- Navbar -->
<nav class="navbar navbar-dark shadow-sm pb-5">
    <div class="container">
        <a class="navbar-brand fw-bold" href="#">
            <i class="bi bi-shield-check text-accent me-2"></i> PUBLIC <span class="text-accent">DMS</span>
        </a>
        
        <div class="d-flex align-items-center">
            <button id="btnSync" class="btn btn-sm btn-outline-light me-3 shadow-sm">
                <i class="bi bi-arrow-repeat" id="syncIcon"></i> Sincronizar Ahora
            </button>

            <div class="text-white-50 small">
                <i class="bi bi-clock-history me-1"></i> 
                Último Sync: <span id="lastSyncTime"><?php echo file_exists($archivo_sync_log) ? date('H:i', (int)file_get_contents($archivo_sync_log)) : 'Pendiente'; ?></span>
            </div>
        </div>
    </div>
</nav>

<div class="container pb-5">
    
    <!-- Dashboards -->
    <div class="row g-4 mb-4 mt-2">
        <div class="col-lg-8">
            <div class="card stats-card shadow-sm h-100">
                <div class="card-body">
                    <h6 class="text-muted mb-3 fw-bold">DISTRIBUCIÓN POR DEPARTAMENTO</h6>
                    <div style="height: 200px;">
                        <canvas id="deptChart"></canvas>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-lg-4">
            <div class="card stats-card shadow-sm h-100 bg-primary text-white">
                <div class="card-body text-center d-flex flex-column justify-content-center">
                    <h6 class="text-white-50 fw-bold">POR VENCER (30 DÍAS)</h6>
                    <h1 id="expiryCount" class="display-2 fw-bold my-2">0</h1>
                    <i class="bi bi-exclamation-triangle-fill text-warning fs-3"></i>
                </div>
            </div>
        </div>
    </div>

    <!-- Buscador -->
    <div class="search-section mb-4">
        <form id="searchForm" class="row g-3">
            <div class="col-md-12">
                <div class="input-group input-group-lg">
                    <span class="input-group-text bg-transparent border-end-0"><i class="bi bi-search text-muted"></i></span>
                    <input type="text" id="searchInput" class="form-control border-start-0 ps-0" placeholder="Buscar por nombre de documento o código...">
                </div>
            </div>
        </form>
    </div>

    <!-- Tabla de Resultados -->
    <div class="table-container shadow-sm">
        <div class="table-responsive">
            <table class="table table-hover align-middle mb-0">
                <thead class="table-light">
                    <tr>
                        <th class="ps-4">Código</th>
                        <th>Documento</th>
                        <th>Categoría</th>
                        <th>Departamento</th>
                        <th class="text-center">Versión</th>
                        <th>Acción</th>
                    </tr>
                </thead>
                <tbody id="resultsTable">
                    <!-- Contenido dinámico mediante JS -->
                </tbody>
            </table>
        </div>
        
        <div class="card-footer bg-white border-top-0 p-4">
            <div class="d-flex justify-content-between align-items-center">
                <span id="pageInfo" class="small text-muted">Cargando...</span>
                <nav>
                    <ul class="pagination mb-0" id="paginationControls"></ul>
                </nav>
            </div>
        </div>
    </div>
</div>

<script>
    let currentPage = 1;
    const recordsPerPage = 10;
    let deptChart = null;

    document.addEventListener('DOMContentLoaded', () => {
        loadData(1);
        loadReports();
    });

    // Botón Sincronizar — llama sync directo (incremental = segundos)
    document.getElementById('btnSync').addEventListener('click', async function() {
        const btn  = this;
        const icon = document.getElementById('syncIcon');
        btn.disabled = true;
        icon.classList.add('bi-spin');

        try {
            await fetch('sync/sync_main.php');
            location.reload();
        } catch (error) {
            btn.disabled = false;
            icon.classList.remove('bi-spin');
            alert('Error en la sincronización');
        }
    });

    async function loadData(page = 1) {
        currentPage = page;
        const search = document.getElementById('searchInput').value;
        try {
            const response = await fetch(`api/documents/documents.php?page=${page}&limit=${recordsPerPage}&search=${encodeURIComponent(search)}`);
            const result = await response.json();

            if (result.status === "success") {
                renderTable(result.data);
                renderPagination(result.pagination);
            }
        } catch (error) {
            console.error("Error al cargar datos", error);
        }
    }

    function renderTable(data) {
        const tableBody = document.getElementById('resultsTable');
        if (data.length === 0) {
            tableBody.innerHTML = `<tr><td colspan="6" class="text-center p-5 text-muted">No se encontraron documentos</td></tr>`;
            return;
        }

        tableBody.innerHTML = data.map(doc => {
            const hasFile   = doc.file_url && doc.file_url !== '';
            const viewUrl   = hasFile ? 'viewer.php?file='        + encodeURIComponent(doc.file_url) : '#';
            const dlUrl     = hasFile ? 'view_pdf.php?file='     + encodeURIComponent(doc.file_url) + '&download=1' : '#';
            const disabled  = hasFile ? '' : 'disabled';

            return `
                <tr>
                    <td class="ps-4 fw-bold text-secondary">${doc.code}</td>
                    <td>
                        <div class="fw-bold text-dark">${doc.title}</div>
                        <small class="text-muted">Sync: ${doc.last_sync || 'N/A'}</small>
                    </td>
                    <td><span class="badge bg-light text-dark border">${doc.category_name}</span></td>
                    <td>${doc.department_name}</td>
                    <td class="text-center"><span class="badge bg-info text-dark">v.${doc.version}</span></td>
                    <td class="d-flex gap-1">
                        <a href="${viewUrl}" target="_blank" class="btn btn-sm btn-outline-primary btn-view ${disabled}">
                            <i class="bi bi-eye"></i> Ver
                        </a>
                        <a href="${dlUrl}" class="btn btn-sm btn-outline-secondary ${disabled}" title="Descargar">
                            <i class="bi bi-download"></i>
                        </a>
                    </td>
                </tr>
            `;
        }).join('');
    }

    function renderPagination(meta) {
        const container = document.getElementById('paginationControls');
        document.getElementById('pageInfo').innerText = `Página ${meta.page} de ${meta.pages} (${meta.total} totales)`;
        
        let html = `<li class="page-item ${meta.page === 1 ? 'disabled' : ''}"><a class="page-link" href="#" onclick="loadData(${meta.page - 1})">Anterior</a></li>`;
        
        for (let i = 1; i <= meta.pages; i++) {
            if (i === 1 || i === meta.pages || (i >= meta.page - 1 && i <= meta.page + 1)) {
                html += `<li class="page-item ${i === meta.page ? 'active' : ''}"><a class="page-link" href="#" onclick="loadData(${i})">${i}</a></li>`;
            } else if (i === meta.page - 2 || i === meta.page + 2) {
                html += `<li class="page-item disabled"><span class="page-link">...</span></li>`;
            }
        }

        html += `<li class="page-item ${meta.page === meta.pages ? 'disabled' : ''}"><a class="page-link" href="#" onclick="loadData(${meta.page + 1})">Siguiente</a></li>`;
        container.innerHTML = html;
    }

    async function loadReports() {
        try {
            const res = await fetch('api/reports/compliance.php');
            const result = await res.json();
            if (result.status === "success") {
                document.getElementById('expiryCount').innerText = result.reports.near_expiry.length;
                updateChart(result.reports.by_department);
            }
        } catch (e) { console.error(e); }
    }

    function updateChart(data) {
        const ctx = document.getElementById('deptChart').getContext('2d');
        if (deptChart) deptChart.destroy();
        deptChart = new Chart(ctx, {
            type: 'bar',
            data: {
                labels: data.map(d => d.department_name),
                datasets: [{
                    label: 'Documentos',
                    data: data.map(d => d.total),
                    backgroundColor: '#18bc9c',
                    borderRadius: 5
                }]
            },
            options: { maintainAspectRatio: false, plugins: { legend: { display: false } } }
        });
    }

    document.getElementById('searchInput').addEventListener('input', () => loadData(1));
    document.getElementById('searchForm').addEventListener('submit', (e) => { e.preventDefault(); loadData(1); });

</script>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
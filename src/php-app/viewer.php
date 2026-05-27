<?php
if (!isset($_GET['file']) || trim($_GET['file']) === '') {
    http_response_code(400);
    exit('Parámetro file requerido.');
}

$relativePath = ltrim(str_replace('\\', '/', $_GET['file']), '/');
if (strpos($relativePath, '..') !== false) {
    http_response_code(403);
    exit('Ruta no permitida.');
}

$filename = basename($relativePath);
$ext      = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
$fileUrl  = 'view_pdf.php?file=' . urlencode($_GET['file']);
$dlUrl    = $fileUrl . '&download=1';

$imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'];
$textExts  = ['txt', 'csv', 'log', 'json', 'xml', 'yaml', 'yml', 'ini', 'md'];
?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= htmlspecialchars($filename) ?></title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap-icons@1.11.3/font/bootstrap-icons.min.css">
    <style>
        body { background: #1a1a2e; color: #e0e0e0; font-family: 'Segoe UI', sans-serif; }
        .topbar { background: #16213e; border-bottom: 1px solid #0f3460; padding: .6rem 1.2rem; }
        .topbar .filename { font-size: 1rem; font-weight: 600; color: #e0e0e0; }
        .topbar .badge-ext { background: #0f3460; color: #e0e0e0; font-size: .75rem; }
        #viewer-container { height: calc(100vh - 54px); overflow: auto; }
        iframe { width: 100%; height: 100%; border: none; }
        #sheet-container { padding: 1rem; overflow: auto; height: 100%; }
        #sheet-container table { border-collapse: collapse; font-size: .85rem; }
        #sheet-container th { background: #0f3460; color: #e0e0e0; padding: 6px 10px; }
        #sheet-container td { border: 1px solid #2a2a4a; padding: 5px 10px; color: #d0d0d0; }
        #sheet-tabs { background: #16213e; border-bottom: 1px solid #0f3460; padding: .3rem .8rem; display: flex; gap: .4rem; flex-wrap: wrap; }
        #sheet-tabs button { background: #0f3460; border: none; color: #a0a0c0; padding: .2rem .7rem; border-radius: 4px; font-size: .8rem; cursor: pointer; }
        #sheet-tabs button.active { background: #e94560; color: #fff; }
        #docx-container { padding: 2rem; max-width: 860px; margin: 0 auto; background: #fff; color: #111; min-height: 100%; }
        #text-container { padding: 1.5rem; }
        #text-container pre { background: #12122a; color: #c8f0c8; padding: 1rem; border-radius: 6px; font-size: .85rem; white-space: pre-wrap; word-break: break-word; }
        #image-container { display: flex; justify-content: center; align-items: flex-start; padding: 2rem; }
        #image-container img { max-width: 100%; border-radius: 6px; box-shadow: 0 4px 20px rgba(0,0,0,.5); }
        #unsupported { display: flex; flex-direction: column; align-items: center; justify-content: center; height: 80%; gap: 1rem; }
        .spinner-border { color: #e94560; }
        #error-msg { color: #ff6b6b; font-size: .9rem; }
    </style>
</head>
<body>

<div class="topbar d-flex align-items-center gap-2">
    <button onclick="history.back()" class="btn btn-sm btn-outline-secondary me-2">
        <i class="bi bi-arrow-left"></i>
    </button>
    <span class="filename"><?= htmlspecialchars($filename) ?></span>
    <span class="badge badge-ext"><?= strtoupper(htmlspecialchars($ext)) ?></span>
    <a href="<?= htmlspecialchars($dlUrl) ?>" class="btn btn-sm btn-outline-light ms-auto">
        <i class="bi bi-download"></i> Descargar
    </a>
</div>

<div id="viewer-container">

<?php if ($ext === 'pdf'): ?>
    <iframe src="<?= htmlspecialchars($fileUrl) ?>" title="<?= htmlspecialchars($filename) ?>"></iframe>

<?php elseif (in_array($ext, $imageExts)): ?>
    <div id="image-container">
        <img src="<?= htmlspecialchars($fileUrl) ?>" alt="<?= htmlspecialchars($filename) ?>">
    </div>

<?php elseif ($ext === 'docx'): ?>
    <div id="viewer-container">
        <div id="docx-container"><div class="d-flex justify-content-center p-5"><div class="spinner-border"></div></div></div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/mammoth@1.8.0/mammoth.browser.min.js"></script>
    <script>
    fetch(<?= json_encode($fileUrl) ?>)
        .then(r => r.arrayBuffer())
        .then(buf => mammoth.convertToHtml({ arrayBuffer: buf }))
        .then(result => {
            document.getElementById('docx-container').innerHTML = result.value;
        })
        .catch(err => {
            document.getElementById('docx-container').innerHTML =
                '<p style="color:red">Error al procesar DOCX: ' + err.message + '</p>';
        });
    </script>

<?php elseif (in_array($ext, ['xlsx', 'xls'])): ?>
    <div id="sheet-tabs"></div>
    <div id="viewer-container" style="height:calc(100vh - 90px)">
        <div id="sheet-container"><div class="d-flex justify-content-center p-5"><div class="spinner-border"></div></div></div>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/xlsx@0.18.5/dist/xlsx.full.min.js"></script>
    <script>
    let workbook;
    fetch(<?= json_encode($fileUrl) ?>)
        .then(r => r.arrayBuffer())
        .then(buf => {
            workbook = XLSX.read(buf, { type: 'array' });
            const tabs = document.getElementById('sheet-tabs');
            workbook.SheetNames.forEach((name, i) => {
                const btn = document.createElement('button');
                btn.textContent = name;
                if (i === 0) btn.classList.add('active');
                btn.onclick = () => {
                    document.querySelectorAll('#sheet-tabs button').forEach(b => b.classList.remove('active'));
                    btn.classList.add('active');
                    renderSheet(name);
                };
                tabs.appendChild(btn);
            });
            renderSheet(workbook.SheetNames[0]);
        })
        .catch(err => {
            document.getElementById('sheet-container').innerHTML =
                '<p style="color:red">Error al procesar Excel: ' + err.message + '</p>';
        });

    function renderSheet(name) {
        const ws  = workbook.Sheets[name];
        const html = XLSX.utils.sheet_to_html(ws, { editable: false });
        document.getElementById('sheet-container').innerHTML = html;
    }
    </script>

<?php elseif (in_array($ext, $textExts)): ?>
    <div id="text-container">
        <pre id="text-content"><span class="text-muted">Cargando...</span></pre>
    </div>
    <script>
    fetch(<?= json_encode($fileUrl) ?>)
        .then(r => r.text())
        .then(t => { document.getElementById('text-content').textContent = t; })
        .catch(err => { document.getElementById('text-content').textContent = 'Error: ' + err.message; });
    </script>

<?php else: ?>
    <div id="unsupported">
        <i class="bi bi-file-earmark-x" style="font-size:4rem;color:#555"></i>
        <p class="text-muted">Vista previa no disponible para <strong>.<?= htmlspecialchars($ext) ?></strong></p>
        <a href="<?= htmlspecialchars($dlUrl) ?>" class="btn btn-outline-light">
            <i class="bi bi-download"></i> Descargar archivo
        </a>
    </div>
<?php endif; ?>

</div>
</body>
</html>

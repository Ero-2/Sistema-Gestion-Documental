<?php
require_once __DIR__ . '/config/storage.php';

if (!isset($_GET['file']) || trim($_GET['file']) === '') {
    http_response_code(400);
    exit('Parámetro file requerido.');
}

// Normalizar: solo forward slashes, sin slash inicial
$relativePath = ltrim(str_replace('\\', '/', $_GET['file']), '/');

// Bloquear path traversal antes de realpath
if (strpos($relativePath, '..') !== false) {
    http_response_code(403);
    exit('Ruta no permitida.');
}

// Documentos simulados (seed/Faker) — sin archivo físico
if (str_starts_with($relativePath, 'seed/')) {
    http_response_code(422);
    header('Content-Type: text/html; charset=UTF-8');
    $simName = htmlspecialchars(basename($relativePath));
    echo <<<HTML
    <!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
    <title>Documento simulado</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css">
    </head>
    <body class="bg-dark text-light d-flex align-items-center justify-content-center" style="min-height:100vh">
    <div class="text-center p-4">
      <div style="font-size:3rem">📄</div>
      <h5 class="mt-3">Documento simulado</h5>
      <p class="text-muted small">No existe archivo físico asociado a <code>{$simName}</code>.<br>
         Fue generado mediante datos de prueba (Faker).</p>
      <button onclick="history.back()" class="btn btn-sm btn-outline-secondary mt-2">Volver</button>
    </div>
    </body></html>
    HTML;
    exit;
}

$fullPath = DMS_STORAGE_ROOT . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $relativePath);

$realStorage = realpath(DMS_STORAGE_ROOT);
$realFile    = realpath($fullPath);

if ($realStorage === false) {
    http_response_code(500);
    exit('Storage no configurado. Verificar DMS_STORAGE_PATH.');
}

if ($realFile === false || strpos($realFile, $realStorage . DIRECTORY_SEPARATOR) !== 0) {
    http_response_code(403);
    exit('Acceso denegado.');
}

if (!file_exists($realFile)) {
    http_response_code(404);
    exit('Archivo no encontrado en storage.');
}

$download = isset($_GET['download']) && $_GET['download'] === '1';
$filename = basename($realFile);

$mimeMap = [
    'pdf'  => 'application/pdf',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'doc'  => 'application/msword',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'xls'  => 'application/vnd.ms-excel',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'ppt'  => 'application/vnd.ms-powerpoint',
    'png'  => 'image/png',
    'jpg'  => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'gif'  => 'image/gif',
    'webp' => 'image/webp',
    'txt'  => 'text/plain',
    'csv'  => 'text/csv',
    'html' => 'text/html',
    'htm'  => 'text/html',
];
$ext  = strtolower(pathinfo($filename, PATHINFO_EXTENSION));
$mime = $mimeMap[$ext] ?? 'application/octet-stream';

header('Content-Type: ' . $mime);
header('Content-Length: ' . filesize($realFile));
header('Content-Disposition: ' . ($download ? 'attachment' : 'inline') . '; filename="' . rawurlencode($filename) . '"');
header('X-Content-Type-Options: nosniff');
readfile($realFile);
exit;

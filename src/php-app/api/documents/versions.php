<?php
// api/documents/versions.php
// Historial de versiones APROBADAS de un documento (vigente + obsoletas).
// Lectura pública desacoplada (read model PostgreSQL). GET ?document_id=NN
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/db.php';

$documentId = isset($_GET['document_id']) ? (int)$_GET['document_id'] : 0;
if ($documentId <= 0) {
    http_response_code(400);
    echo json_encode(['status' => 'error', 'message' => 'document_id requerido']);
    exit;
}

try {
    $sql = "
        SELECT
            version,
            file_url,
            is_current,
            TO_CHAR(approved_at,  'DD/MM/YYYY HH24:MI') AS approved_at,
            TO_CHAR(obsoleted_at, 'DD/MM/YYYY HH24:MI') AS obsoleted_at,
            TO_CHAR(effective_date,  'DD/MM/YYYY') AS effective_date,
            TO_CHAR(expiration_date, 'DD/MM/YYYY') AS expiration_date
        FROM publicdms.document_versions
        WHERE document_id = :id
        ORDER BY approved_at DESC NULLS LAST, id DESC
    ";
    $stmt = $pdo->prepare($sql);
    $stmt->execute([':id' => $documentId]);
    $versions = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Anota estado legible para la UI.
    foreach ($versions as &$v) {
        $v['status'] = $v['is_current'] ? 'vigente' : 'obsoleta';
    }
    unset($v);

    echo json_encode([
        'status'      => 'success',
        'document_id' => $documentId,
        'versions'    => $versions,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => 'Error en el servidor: ' . $e->getMessage()]);
}

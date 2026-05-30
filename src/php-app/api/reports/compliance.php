<?php
// api/reports/compliance.php
header("Content-Type: application/json");
require_once __DIR__ . '/../../config/db.php';

try {
    // Reporte 1: Conteo de documentos por departamento
    $statsQuery = "
        SELECT department_name, COUNT(*) as total
        FROM documents
        WHERE is_active = TRUE
        GROUP BY department_name";
    
    $stats = $pdo->query($statsQuery)->fetchAll(PDO::FETCH_ASSOC);

    // Reporte 2: Documentos próximos a vencer (en los próximos 30 días)
    $expiryQuery = "
        SELECT code, title, expiration_date 
        FROM documents 
        WHERE expiration_date <= CURRENT_DATE + INTERVAL '30 days'
        AND is_active = TRUE";
    
    $expiring = $pdo->query($expiryQuery)->fetchAll(PDO::FETCH_ASSOC);

    
    echo json_encode([
        "status" => "success",
        "reports" => [
            "by_department" => $stats,
            "near_expiry"   => $expiring
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => $e->getMessage()]);
}
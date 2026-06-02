<?php
// api/reports/compliance.php
header("Content-Type: application/json");
require_once __DIR__ . '/../../config/db.php';

try {
    // Reporte 1: Conteo de documentos por departamento
    $statsQuery = "
        SELECT department_name, COUNT(*) as total
        FROM publicdms.documents
        WHERE is_active = TRUE
        GROUP BY department_name";
    
    $stats = $pdo->query($statsQuery)->fetchAll(PDO::FETCH_ASSOC);

    // Reporte 2: Documentos próximos a vencer o a revisar (en los próximos 30 días)
    $expiryQuery = "
        SELECT code, title, expiration_date, next_review_date
        FROM publicdms.documents
        WHERE is_active = TRUE
          AND (
            (expiration_date IS NOT NULL AND expiration_date <= CURRENT_DATE + INTERVAL '30 days')
            OR
            (next_review_date IS NOT NULL AND next_review_date <= CURRENT_DATE + INTERVAL '30 days')
          )";
    
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
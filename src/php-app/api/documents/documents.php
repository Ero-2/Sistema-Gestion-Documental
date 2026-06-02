<?php
// api/documents/documents.php
header('Content-Type: application/json');
require_once __DIR__ . '/../../config/db.php';
require_once __DIR__ . '/../../includes/MongoSearchClient.php';

$page   = isset($_GET['page'])  && (int)$_GET['page']  > 0 ? (int)$_GET['page']  : 1;
$limit  = isset($_GET['limit']) && (int)$_GET['limit'] > 0 ? (int)$_GET['limit'] : 10;
$search = isset($_GET['search']) ? trim($_GET['search']) : '';
$status = ($_GET['status'] ?? 'active') === 'obsolete' ? 'obsolete' : 'active';
$offset = ($page - 1) * $limit;

try {
    $whereClause  = $status === 'obsolete' ? "WHERE is_active = FALSE" : "WHERE is_active = TRUE";
    $countParams  = [];
    $dataParams   = [];
    $mongoIds     = [];
    $useMongoOrder = false;

    if (!empty($search)) {
        try {
            $mongo    = new MongoSearchClient();
            $mongoIds = $mongo->searchDocumentIds($search);

            if (!empty($mongoIds)) {
                $placeholders = implode(',', array_fill(0, count($mongoIds), '?'));
                $whereClause  = "WHERE id IN ($placeholders) AND is_active = TRUE";
                $countParams  = $mongoIds;
                $useMongoOrder = true;
            } else {
                // Mongo responded but found nothing — skip SQL entirely
                echo json_encode([
                    "status"     => "success",
                    "data"       => [],
                    "pagination" => ["total" => 0, "page" => $page, "pages" => 1, "limit" => $limit]
                ]);
                exit;
            }
        } catch (Exception $e) {
            // Fallback: ILIKE when FastAPI / Mongo unreachable
            error_log("[MongoSearch] Fallback ILIKE: " . $e->getMessage());
            $whereClause = "WHERE (title ILIKE ? OR code ILIKE ?) AND is_active = TRUE";
            $searchParam = '%' . $search . '%';
            $countParams = [$searchParam, $searchParam];
        }
    }

    // COUNT for pagination
    $stmtCount = $pdo->prepare("SELECT COUNT(*) FROM documents $whereClause");
    $stmtCount->execute($countParams);
    $totalRecords = (int)$stmtCount->fetchColumn();

    // ORDER BY: preserve Mongo relevance rank when available
    if ($useMongoOrder && !empty($mongoIds)) {
        $cases = '';
        foreach ($mongoIds as $i => $id) {
            $cases .= "WHEN id = $id THEN $i ";
        }
        $orderBy = "ORDER BY CASE $cases ELSE 999 END";
    } else {
        $orderBy = "ORDER BY last_sync DESC, id ASC";
    }

    $dataSql = "
        SELECT
            id,
            code,
            title,
            category_name,
            department_name,
            version,
            file_url,
            local_file_name,
            TO_CHAR(last_sync, 'DD/MM/YYYY HH24:MI') AS last_sync
        FROM documents
        $whereClause
        $orderBy
        LIMIT ? OFFSET ?
    ";

    $dataParams = array_merge($countParams, [$limit, $offset]);
    $stmtData   = $pdo->prepare($dataSql);
    $stmtData->execute($dataParams);
    $documents = $stmtData->fetchAll(PDO::FETCH_ASSOC);

    $totalPages = ($totalRecords > 0) ? (int)ceil($totalRecords / $limit) : 1;

    echo json_encode([
        "status"     => "success",
        "data"       => $documents,
        "pagination" => [
            "total" => $totalRecords,
            "page"  => $page,
            "pages" => $totalPages,
            "limit" => $limit
        ]
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        "status"  => "error",
        "message" => "Error en el servidor: " . $e->getMessage()
    ]);
}

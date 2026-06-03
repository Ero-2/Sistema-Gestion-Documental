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

// ── Obsoletos: delega en FastAPI para incluir version_history como entradas separadas ──
if ($status === 'obsolete') {
    $fastapiBase = defined('FASTAPI_URL') ? FASTAPI_URL : (getenv('FASTAPI_URL') ?: 'http://dms_fastapi:8000');
    $apiKey      = defined('FASTAPI_API_KEY') ? FASTAPI_API_KEY : (getenv('FASTAPI_API_KEY') ?: '');

    $url = rtrim($fastapiBase, '/') . '/search/documents?status=obsolete'
         . '&limit=' . $limit . '&offset=' . $offset;
    if (!empty($search)) {
        $url .= '&q=' . urlencode($search);
    }

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 5,
        CURLOPT_HTTPHEADER     => ['X-API-Key: ' . $apiKey],
    ]);
    $res  = curl_exec($ch);
    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($res === false || $code !== 200) {
        http_response_code(500);
        echo json_encode(['status' => 'error', 'message' => "FastAPI no disponible (HTTP $code)"]);
        exit;
    }

    $data         = json_decode($res, true);
    $totalRecords = (int)($data['total'] ?? 0);
    $totalPages   = $totalRecords > 0 ? (int)ceil($totalRecords / $limit) : 1;

    $documents = array_map(function ($doc) {
        $sync = $doc['sync_date'] ?? '';
        if ($sync) {
            try { $sync = (new DateTime($sync))->format('d/m/Y H:i'); }
            catch (Exception $e) { $sync = substr($sync, 0, 16); }
        }
        return [
            'id'              => (int)($doc['postgres_id'] ?? 0),
            'code'            => $doc['code']            ?? '',
            'title'           => $doc['title']           ?? '',
            'category_name'   => $doc['category_name']   ?? '',
            'department_name' => $doc['department_name'] ?? '',
            'version'         => $doc['version']         ?? '',
            'file_url'        => $doc['file_url']        ?? '',
            'local_file_name' => $doc['file_name']       ?? '',
            'last_sync'       => $sync,
        ];
    }, $data['documents'] ?? []);

    echo json_encode([
        'status'     => 'success',
        'data'       => $documents,
        'pagination' => ['total' => $totalRecords, 'page' => $page, 'pages' => $totalPages, 'limit' => $limit],
    ]);
    exit;
}

try {
    $whereClause  = "WHERE is_active = TRUE";
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

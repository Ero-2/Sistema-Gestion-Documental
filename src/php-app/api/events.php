<?php
/**
 * API de Eventos — Recibe cambios desde .NET
 * POST /api/events.php?action=approve
 * POST /api/events.php?action=update
 * POST /api/events.php?action=version
 * POST /api/events.php?action=obsolete
 */

header('Content-Type: application/json; charset=utf-8');

// Validar método
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// Validar API Key
$apiKey = $_ENV['FASTAPI_API_KEY'] ?? '';
$headerKey = $_SERVER['HTTP_X_API_KEY'] ?? '';

if (empty($apiKey) || $headerKey !== $apiKey) {
    http_response_code(401);
    echo json_encode(['error' => 'Unauthorized']);
    exit;
}

// Parsear JSON
$input = json_decode(file_get_contents('php://input'), true);
if (!is_array($input)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON']);
    exit;
}

// Obtener acción
$action = $_GET['action'] ?? null;

// Conectar a DB
require_once __DIR__ . '/../config/db.php';

// Cargar handler
require_once __DIR__ . '/handlers/DocumentEventHandler.php';

try {
    $handler = new DocumentEventHandler();

    switch ($action) {
        case 'approve':
            $result = $handler->handleApprove($input);
            break;
        case 'update':
            $result = $handler->handleUpdate($input);
            break;
        case 'version':
            $result = $handler->handleVersion($input);
            break;
        case 'obsolete':
            $result = $handler->handleObsolete($input);
            break;
        default:
            http_response_code(400);
            echo json_encode(['error' => 'Invalid action']);
            exit;
    }

    http_response_code(200);
    echo json_encode($result);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage()]);
    error_log("[API Event Error] $action: " . $e->getMessage());
}

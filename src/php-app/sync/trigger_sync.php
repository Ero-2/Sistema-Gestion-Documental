<?php
header('Content-Type: application/json');

$logFile = __DIR__ . '/ultimo_sync.txt';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $phpBin = PHP_BINARY;

    // If CalidadSYS sends a document_id, do a fast targeted upsert inline.
    // Otherwise fall back to full incremental sync in background.
    $body       = json_decode(file_get_contents('php://input'), true);
    $documentId = isset($body['document_id']) ? (int)$body['document_id'] : 0;

    if ($documentId > 0) {
        // Targeted single-doc sync — runs inline, returns in ~200ms
        $SINGLE_DOC_ID = $documentId;
        require __DIR__ . '/sync_single_doc.php';
    } else {
        // Full incremental sync — spawn background process
        $script = __DIR__ . '/sync_main.php';
        if (stristr(PHP_OS, 'WIN')) {
            pclose(popen("start /B \"\" \"$phpBin\" \"$script\"", "r"));
        } else {
            shell_exec("\"$phpBin\" \"$script\" > /dev/null 2>&1 &");
        }
    }
}

echo json_encode([
    'status'    => 'ok',
    'last_sync' => file_exists($logFile) ? (int)file_get_contents($logFile) : 0
]);

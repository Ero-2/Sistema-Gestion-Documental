<?php
// sync/sync_single_doc.php
// Targeted upsert of one document into PostgreSQL — called by trigger_sync.php
// when CalidadSYS sends a document_id in the webhook body.

require_once __DIR__ . '/../config/sqlserver.php';
require_once __DIR__ . '/../config/db.php';

if (empty($SINGLE_DOC_ID) || !is_int($SINGLE_DOC_ID)) {
    echo "ERROR: \$SINGLE_DOC_ID not set\n";
    return;
}

$id = $SINGLE_DOC_ID;

$querySQL = "
    SELECT
        d.DocumentId     AS doc_id,
        d.Code           AS doc_code,
        d.Title          AS doc_title,
        d.CategoryId     AS cat_id,
        c.Name           AS cat_name,
        d.DepartmentId   AS dep_id,
        dep.Name         AS dep_name,
        d.IsActive       AS doc_is_active,
        dv.VersionNumber AS doc_version,
        dv.FilePath      AS doc_url,
        d.EffectiveDate,
        d.ExpirationDate
    FROM Documents d
    INNER JOIN DocumentCategories c   ON d.CategoryId   = c.CategoryId
    INNER JOIN Departments dep        ON d.DepartmentId = dep.DepartmentId
    INNER JOIN DocumentVersions dv    ON dv.DocumentId  = d.DocumentId
    WHERE d.DocumentId = ? AND d.CurrentStatus = 3 AND dv.IsCurrent = 1
";

$stmtSQL = $connSQL->prepare($querySQL);
$stmtSQL->execute([$id]);
$doc = $stmtSQL->fetch(PDO::FETCH_ASSOC);

if (!$doc) {
    echo "Document $id not found or not approved — skipping\n";
    return;
}

$queryPG = "
    INSERT INTO publicdms.documents (
        id, code, title, category_id, category_name,
        department_id, department_name, version,
        file_url, is_active, effective_date, expiration_date, last_sync
    ) VALUES (
        :id, :code, :title, :cat_id, :cat_name,
        :dep_id, :dep_name, :version,
        :url, :is_active, :eff, :exp, NOW()
    )
    ON CONFLICT (id) DO UPDATE SET
        code            = EXCLUDED.code,
        title           = EXCLUDED.title,
        category_name   = EXCLUDED.category_name,
        department_name = EXCLUDED.department_name,
        version         = EXCLUDED.version,
        file_url        = EXCLUDED.file_url,
        is_active       = EXCLUDED.is_active,
        last_sync       = NOW();
";

$stmtPG = $pdo->prepare($queryPG);
$stmtPG->execute([
    ':id'        => $doc['doc_id'],
    ':code'      => $doc['doc_code'],
    ':title'     => $doc['doc_title'],
    ':cat_id'    => $doc['cat_id'],
    ':cat_name'  => $doc['cat_name'],
    ':dep_id'    => $doc['dep_id'],
    ':dep_name'  => $doc['dep_name'],
    ':version'   => (string)$doc['doc_version'],
    ':url'       => ltrim(str_replace('\\', '/', (string)$doc['doc_url']), '/'),
    ':is_active' => (bool)$doc['doc_is_active'] ? 'true' : 'false',
    ':eff'       => $doc['EffectiveDate'],
    ':exp'       => $doc['ExpirationDate'],
]);

echo "Document $id upserted into PostgreSQL\n";

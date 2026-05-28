<?php
/**
 * Maneja eventos de .NET.
 * Inserta/actualiza en PostgreSQL (publicdms schema).
 */

class DocumentEventHandler
{
    private $pdo;

    public function __construct($pdo = null)
    {
        if ($pdo) {
            $this->pdo = $pdo;
        } else {
            require_once __DIR__ . '/../../config/db.php';
            global $pdo;
            $this->pdo = $pdo;
        }

        if (!$this->pdo) {
            throw new Exception('PostgreSQL connection failed');
        }
    }

    /**
     * Evento: Documento aprobado (estado 3 en SQL Server).
     * Inserta en publicdms.documents.
     */
    public function handleApprove(array $data)
    {
        $this->validateApproveData($data);

        $query = <<<SQL
            INSERT INTO publicdms.documents (
                id, code, title, category_id, category_name,
                department_id, department_name, version,
                file_url, is_active, effective_date, expiration_date, last_sync
            ) VALUES (
                :id, :code, :title, :cat_id, :cat_name,
                :dep_id, :dep_name, :version,
                :url, :is_active, :eff_date, :exp_date, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                code = EXCLUDED.code,
                title = EXCLUDED.title,
                category_name = EXCLUDED.category_name,
                department_name = EXCLUDED.department_name,
                version = EXCLUDED.version,
                file_url = EXCLUDED.file_url,
                effective_date = EXCLUDED.effective_date,
                expiration_date = EXCLUDED.expiration_date,
                last_sync = NOW();
        SQL;

        $stmt = $this->pdo->prepare($query);
        $stmt->execute([
            ':id'       => $data['document_id'],
            ':code'     => $data['code'],
            ':title'    => $data['title'],
            ':cat_id'   => $data['category_id'],
            ':cat_name' => $data['category_name'],
            ':dep_id'   => $data['department_id'],
            ':dep_name' => $data['department_name'],
            ':version'  => $data['version'],
            ':url'      => $data['file_url'] ?? null,
            ':is_active' => true,
            ':eff_date' => $data['effective_date'] ?? null,
            ':exp_date' => $data['expiration_date'] ?? null,
        ]);

        $this->logEvent($data['document_id'], 'approved');

        return [
            'status'      => 'success',
            'document_id' => $data['document_id'],
            'action'      => 'approved',
        ];
    }

    /**
     * Evento: Actualizar estado/vigencia.
     */
    public function handleUpdate(array $data)
    {
        $this->validateUpdateData($data);

        $updates = [];
        $params = [':id' => $data['document_id']];

        if (isset($data['is_active'])) {
            $updates[] = 'is_active = :is_active';
            $params[':is_active'] = (bool)$data['is_active'];
        }

        if (isset($data['effective_date']) && $data['effective_date']) {
            $updates[] = 'effective_date = :eff_date';
            $params[':eff_date'] = $data['effective_date'];
        }

        if (isset($data['expiration_date']) && $data['expiration_date']) {
            $updates[] = 'expiration_date = :exp_date';
            $params[':exp_date'] = $data['expiration_date'];
        }

        $updates[] = 'last_sync = NOW()';

        if (empty($updates)) {
            return ['status' => 'no_changes'];
        }

        $query = 'UPDATE publicdms.documents SET ' . implode(', ', $updates) . ' WHERE id = :id;';
        $stmt = $this->pdo->prepare($query);
        $stmt->execute($params);

        $this->logEvent($data['document_id'], 'updated');

        return [
            'status'      => 'success',
            'document_id' => $data['document_id'],
            'action'      => 'updated',
        ];
    }

    /**
     * Evento: Nueva versión.
     */
    public function handleVersion(array $data)
    {
        $this->validateVersionData($data);

        $query = <<<SQL
            UPDATE publicdms.documents
            SET version = :version, file_url = :url, last_sync = NOW()
            WHERE id = :id;
        SQL;

        $stmt = $this->pdo->prepare($query);
        $stmt->execute([
            ':id'      => $data['document_id'],
            ':version' => $data['version'],
            ':url'     => $data['file_url'],
        ]);

        $this->logEvent($data['document_id'], "versioned_{$data['version']}");

        return [
            'status'      => 'success',
            'document_id' => $data['document_id'],
            'version'     => $data['version'],
            'action'      => 'versioned',
        ];
    }

    /**
     * Evento: Marcar como obsoleto.
     */
    public function handleObsolete(array $data)
    {
        $this->validateObsoleteData($data);

        $query = <<<SQL
            UPDATE publicdms.documents
            SET is_active = FALSE, last_sync = NOW()
            WHERE id = :id;
        SQL;

        $stmt = $this->pdo->prepare($query);
        $stmt->execute([':id' => $data['document_id']]);

        $this->logEvent($data['document_id'], 'obsoleted');

        return [
            'status'      => 'success',
            'document_id' => $data['document_id'],
            'action'      => 'obsoleted',
            'reason'      => $data['obsolete_reason'] ?? null,
        ];
    }

    // ── Validaciones ───────────────────────────────────────────────

    private function validateApproveData(array $data)
    {
        $required = ['document_id', 'code', 'title', 'category_id', 'category_name',
                     'department_id', 'department_name', 'version'];

        foreach ($required as $field) {
            if (!isset($data[$field]) || (is_string($data[$field]) && empty($data[$field]))) {
                throw new Exception("Missing required field: $field");
            }
        }
    }

    private function validateUpdateData(array $data)
    {
        if (!isset($data['document_id'])) {
            throw new Exception("Missing required field: document_id");
        }
    }

    private function validateVersionData(array $data)
    {
        $required = ['document_id', 'version', 'file_url'];

        foreach ($required as $field) {
            if (!isset($data[$field]) || (is_string($data[$field]) && empty($data[$field]))) {
                throw new Exception("Missing required field: $field");
            }
        }
    }

    private function validateObsoleteData(array $data)
    {
        if (!isset($data['document_id'])) {
            throw new Exception("Missing required field: document_id");
        }
    }

    // ── Logging ────────────────────────────────────────────────────

    private function logEvent(int $documentId, string $action)
    {
        try {
            $query = <<<SQL
                INSERT INTO publicdms.sync_log (entity, action, processed_at)
                VALUES (:entity, :action, NOW());
            SQL;

            $stmt = $this->pdo->prepare($query);
            $stmt->execute([
                ':entity' => "document_$documentId",
                ':action' => $action,
            ]);
        } catch (Exception $e) {
            error_log("Failed to log event: " . $e->getMessage());
        }
    }
}

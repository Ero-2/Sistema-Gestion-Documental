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

        // Toda la aprobación es atómica: puntero vigente + historial + obsolescencia
        // de la versión anterior viajan juntos. Así el índice único filtrado
        // ux_docver_one_current nunca ve dos vigentes a la vez.
        $this->pdo->beginTransaction();
        try {
            // Sembrar categoría y departamento referenciados (vienen del evento .NET).
            // Postgres es un modelo de lectura desacoplado: no consulta SQL Server, así que
            // las tablas de catálogo se pueblan vía el mismo push de aprobación (upsert por id).
            $this->upsertCatalog('categories', $data['category_id'], $data['category_name']);
            $this->upsertCatalog('departments', $data['department_id'], $data['department_name']);

            // 1) Puntero a la versión vigente (lo que ve el público). 1 fila por documento.
            $query = <<<SQL
                INSERT INTO publicdms.documents (
                    id, company_id, company_name, code, title, category_id, category_name,
                    department_id, department_name, version,
                    file_url, is_active, effective_date, expiration_date, last_sync
                ) VALUES (
                    :id, :company_id, :company_name, :code, :title, :cat_id, :cat_name,
                    :dep_id, :dep_name, :version,
                    :url, :is_active, :eff_date, :exp_date, NOW()
                )
                ON CONFLICT (id) DO UPDATE SET
                    company_id = EXCLUDED.company_id,
                    company_name = EXCLUDED.company_name,
                    code = EXCLUDED.code,
                    title = EXCLUDED.title,
                    category_name = EXCLUDED.category_name,
                    department_name = EXCLUDED.department_name,
                    version = EXCLUDED.version,
                    file_url = EXCLUDED.file_url,
                    is_active = TRUE,
                    effective_date = EXCLUDED.effective_date,
                    expiration_date = EXCLUDED.expiration_date,
                    last_sync = NOW();
            SQL;

            $stmt = $this->pdo->prepare($query);
            $stmt->execute([
                ':id'          => $data['document_id'],
                ':company_id'  => $data['company_id'] ?? null,
                ':company_name'=> $data['company_name'] ?? null,
                ':code'        => $data['code'],
                ':title'       => $data['title'],
                ':cat_id'      => $data['category_id'],
                ':cat_name'    => $data['category_name'],
                ':dep_id'      => $data['department_id'],
                ':dep_name'    => $data['department_name'],
                ':version'     => $data['version'],
                ':url'         => $data['file_url'] ?? null,
                ':is_active'   => true,
                ':eff_date'    => $data['effective_date'] ?? null,
                ':exp_date'    => $data['expiration_date'] ?? null,
            ]);

            // 2) Obsoletar la vigente anterior (toda versión distinta a la entrante).
            //    Debe ir ANTES del insert de la nueva para no chocar con el índice filtrado.
            $obs = $this->pdo->prepare(<<<SQL
                UPDATE publicdms.document_versions
                SET is_current = FALSE, obsoleted_at = NOW()
                WHERE document_id = :id AND is_current = TRUE AND version <> :version;
            SQL);
            $obs->execute([':id' => $data['document_id'], ':version' => $data['version']]);

            // 3) Registrar la nueva versión aprobada como vigente (append-only; idempotente).
            $ver = $this->pdo->prepare(<<<SQL
                INSERT INTO publicdms.document_versions (
                    document_id, version, file_url, is_current,
                    approved_at, obsoleted_at, effective_date, expiration_date
                ) VALUES (
                    :id, :version, :url, TRUE,
                    COALESCE(:approved_at, NOW()), NULL, :eff_date, :exp_date
                )
                ON CONFLICT (document_id, version) DO UPDATE SET
                    file_url        = EXCLUDED.file_url,
                    is_current      = TRUE,
                    obsoleted_at    = NULL,
                    approved_at     = EXCLUDED.approved_at,
                    effective_date  = EXCLUDED.effective_date,
                    expiration_date = EXCLUDED.expiration_date;
            SQL);
            $ver->execute([
                ':id'          => $data['document_id'],
                ':version'     => $data['version'],
                ':url'         => $data['file_url'] ?? null,
                ':approved_at' => $data['approved_at'] ?? null,
                ':eff_date'    => $data['effective_date'] ?? null,
                ':exp_date'    => $data['expiration_date'] ?? null,
            ]);

            $this->logEvent($data['document_id'], "approved_{$data['version']}");

            $this->pdo->commit();
        } catch (Exception $e) {
            $this->pdo->rollBack();
            throw $e;
        }

        return [
            'status'      => 'success',
            'document_id' => $data['document_id'],
            'version'     => $data['version'],
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

        // Retiro total del documento (sin reemplazo): el puntero deja de ser vigente
        // y la versión aprobada actual queda obsoleta. El historial se conserva.
        $this->pdo->beginTransaction();
        try {
            $stmt = $this->pdo->prepare(<<<SQL
                UPDATE publicdms.documents
                SET is_active = FALSE, last_sync = NOW()
                WHERE id = :id;
            SQL);
            $stmt->execute([':id' => $data['document_id']]);

            $verObs = $this->pdo->prepare(<<<SQL
                UPDATE publicdms.document_versions
                SET is_current = FALSE, obsoleted_at = NOW()
                WHERE document_id = :id AND is_current = TRUE;
            SQL);
            $verObs->execute([':id' => $data['document_id']]);

            $this->logEvent($data['document_id'], 'obsoleted');

            $this->pdo->commit();
        } catch (Exception $e) {
            $this->pdo->rollBack();
            throw $e;
        }

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

    // ── Catálogos (categorías / departamentos) ─────────────────────

    /**
     * Upsert idempotente de un catálogo referenciado por el documento.
     * Mantiene la integridad referencial sin que Postgres consulte SQL Server:
     * el id+nombre llegan en el propio evento de aprobación desde .NET.
     */
    private function upsertCatalog(string $table, $id, $name)
    {
        if (empty($id) || empty($name)) {
            return;
        }

        $query = "INSERT INTO publicdms.$table (id, name) VALUES (:id, :name)
                  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;";
        $stmt = $this->pdo->prepare($query);
        $stmt->execute([':id' => $id, ':name' => $name]);
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

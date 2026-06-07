# Integración APIs — Sistema de Gestión Documental

## Descripción General

Las APIs reemplazan el sistema de sincronización basado en cron jobs. En lugar de polling cada 5 minutos, los eventos se disparan **inmediatamente** desde SQL Server (.NET) hacia las APIs FastAPI.

**Arquitectura desacoplada:**
- **API 1**: Documents Sync → PostgreSQL (publicdms)
- **API 2**: Metadata Sync → MongoDB (dms_metadata)

Ambas APIs son **independientes**. Un error en una no bloquea la otra.

---

## Autenticación

Todas las peticiones requieren header `X-API-Key`:

```bash
curl -X POST http://dms_fastapi:8000/documents/approve \
  -H "X-API-Key: ${FASTAPI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"document_id": 123, ...}'
```

La clave se define en `docker-compose.yml`:
```yaml
environment:
  FASTAPI_API_KEY: your-secret-key-here
```

---

## API 1: Documents Sync

**Base URL:** `http://dms_fastapi:8000/documents`

### POST `/approve`

Inserta documento aprobado en PostgreSQL cuando estado cambia a 3 en SQL Server.

**Payload:**
```json
{
  "document_id": 123,
  "code": "DOC-2024-001",
  "title": "Política de Calidad",
  "category_id": 1,
  "category_name": "Políticas",
  "department_id": 2,
  "department_name": "Calidad",
  "version": "1.0",
  "file_url": "/uploads/2024/doc-123-v1.pdf",
  "effective_date": "2024-01-15T10:00:00Z",
  "expiration_date": "2025-01-15T10:00:00Z"
}
```

**Respuesta (200):**
```json
{
  "status": "success",
  "document_id": 123,
  "action": "approved"
}
```

---

### POST `/update`

Actualiza estado, vigencia o información documental.

**Payload:**
```json
{
  "document_id": 123,
  "is_active": true,
  "effective_date": "2024-02-01T10:00:00Z",
  "expiration_date": "2026-02-01T10:00:00Z",
  "reason": "Renovación anual"
}
```

**Campos opcionales:** todos excepto `document_id`.

---

### POST `/version`

Registra nueva versión de documento.

**Payload:**
```json
{
  "document_id": 123,
  "version": "2.0",
  "file_url": "/uploads/2024/doc-123-v2.pdf",
  "created_at": "2024-06-15T14:30:00Z"
}
```

---

### POST `/obsolete`

Marca documento como obsoleto (inactivo).

**Payload:**
```json
{
  "document_id": 123,
  "obsolete_reason": "Reemplazado por versión 3.0",
  "effective_at": "2024-06-20T00:00:00Z"
}
```

---

## API 2: Metadata Sync

**Base URL:** `http://dms_fastapi:8000/metadata`

### POST `/register`

Registra metadatos nuevos en MongoDB cuando documento es aprobado.

**Payload:**
```json
{
  "postgres_id": 123,
  "code": "DOC-2024-001",
  "title": "Política de Calidad",
  "category_name": "Políticas",
  "department_name": "Calidad",
  "file_url": "/uploads/2024/doc-123-v1.pdf",
  "version": "1.0"
}
```

---

### POST `/update`

Actualiza metadatos en MongoDB.

**Payload:**
```json
{
  "postgres_id": 123,
  "updates": {
    "is_active": true,
    "version": "2.0",
    "tags": ["política", "calidad", "2024"]
  },
  "updated_at": "2024-06-15T14:30:00Z"
}
```

**Campo `updates`:** diccionario con campos a actualizar.

---

### POST `/history`

Registra evento en historial de metadatos.

**Payload:**
```json
{
  "postgres_id": 123,
  "action": "updated",
  "details": {
    "version": "2.0",
    "updated_by": "admin@example.com"
  },
  "timestamp": "2024-06-15T14:30:00Z"
}
```

**Acciones recomendadas:** `created`, `updated`, `versioned`, `obsoleted`, `approved`.

---

### GET `/history/{postgres_id}`

Obtiene historial completo de cambios.

**Respuesta (200):**
```json
{
  "status": "success",
  "postgres_id": 123,
  "history": [
    {
      "_id": "...",
      "postgres_id": 123,
      "action": "created",
      "details": {...},
      "timestamp": "2024-01-15T10:00:00Z"
    }
  ],
  "total": 5
}
```

---

## Flujo esperado desde .NET

1. **Documento aprobado** (estado 3 en SQL Server)
   ```
   .NET trigger DocumentApprovedEvent
     ↓
   POST /documents/approve
   POST /metadata/register
   ```

2. **Documento actualizado** (cambio de vigencia/estado)
   ```
   .NET trigger DocumentUpdatedEvent
     ↓
   POST /documents/update
   POST /metadata/update
   ```

3. **Nueva versión** (DocumentVersionCreated)
   ```
   .NET trigger DocumentVersionEvent
     ↓
   POST /documents/version
   POST /metadata/update
   ```

4. **Documento obsoletado**
   ```
   .NET trigger DocumentObsoletedEvent
     ↓
   POST /documents/obsolete
   POST /metadata/history
   ```

---

## Manejo de errores

### Códigos de respuesta

| Código | Significado | Acción |
|--------|------------|--------|
| 200 | Éxito | Continuar |
| 401 | API Key inválido | Revisar credenciales |
| 404 | Recurso no encontrado | Puede ignorarse (idempotente) |
| 500 | Error servidor | Reintentar con backoff |

### Reintentos recomendados

```csharp
// Pseudocódigo
for (int attempt = 1; attempt <= 3; attempt++) {
    try {
        response = await httpClient.PostAsync(apiUrl, content);
        if (response.IsSuccessStatusCode) break;
        if (response.StatusCode != HttpStatusCode.InternalServerError) throw;
    } catch (Exception ex) {
        if (attempt == 3) throw;
        await Task.Delay(Math.Pow(2, attempt) * 1000);
    }
}
```

---

## Ejemplo .NET

```csharp
using System.Net.Http;
using System.Text;
using System.Text.Json;

public class DmsApiClient {
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly string _baseUrl = "http://dms_fastapi:8000";

    public DmsApiClient(HttpClient http, string apiKey) {
        _http = http;
        _apiKey = apiKey;
    }

    public async Task ApproveDocumentAsync(int docId, string code, string title, 
        int catId, string catName, int deptId, string deptName, string version, 
        string fileUrl, DateTime? effDate, DateTime? expDate) {
        
        var payload = new {
            document_id = docId,
            code = code,
            title = title,
            category_id = catId,
            category_name = catName,
            department_id = deptId,
            department_name = deptName,
            version = version,
            file_url = fileUrl,
            effective_date = effDate,
            expiration_date = expDate
        };

        var json = JsonSerializer.Serialize(payload);
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        
        var request = new HttpRequestMessage(HttpMethod.Post, 
            $"{_baseUrl}/documents/approve") {
            Content = content,
            Headers = { {"X-API-Key", _apiKey} }
        };

        var response = await _http.SendAsync(request);
        response.EnsureSuccessStatusCode();
    }
}
```

---

## Testing

### curl — Approve

```bash
curl -X POST http://localhost:8001/documents/approve \
  -H "X-API-Key: test-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "document_id": 1,
    "code": "TEST-001",
    "title": "Test Doc",
    "category_id": 1,
    "category_name": "Test",
    "department_id": 1,
    "department_name": "Test Dept",
    "version": "1.0",
    "file_url": "/uploads/test.pdf"
  }'
```

### curl — Update

```bash
curl -X POST http://localhost:8001/documents/update \
  -H "X-API-Key: test-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "document_id": 1,
    "is_active": true,
    "expiration_date": "2025-12-31T23:59:59Z"
  }'
```

### curl — Register Metadata

```bash
curl -X POST http://localhost:8001/metadata/register \
  -H "X-API-Key: test-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "postgres_id": 1,
    "code": "TEST-001",
    "title": "Test Doc",
    "category_name": "Test",
    "department_name": "Test Dept",
    "file_url": "/uploads/test.pdf",
    "version": "1.0"
  }'
```

---

## Logging y Auditoría

Todos los eventos se registran en:

- **PostgreSQL**: tabla `publicdms.sync_log` (documento ID, acción, timestamp)
- **MongoDB**: colección `metadata_history` (detalles completos)

Revisar logs de FastAPI:
```bash
docker logs dms_fastapi | grep "✓\|✗"
```

---

## Migración desde Cron

Cambios realizados:

✓ Eliminado cron job cada 5 minutos (`docker/php-app/crontab`)  
✓ Removido `sync_main.php`, `sync_docs.php`, etc. (mantener para referencia)  
✓ Endpoints PHP de sync (`/sync/start`) ahora solo para admin manual  
✓ .NET debe disparar webhooks a FastAPI para cada evento

**Orden de implementación .NET:**
1. Inyectar `DmsApiClient` en controladores relevantes
2. En handler de `DocumentApprovedEvent`, llamar `/documents/approve` + `/metadata/register`
3. En handler de `DocumentUpdatedEvent`, llamar `/documents/update` + `/metadata/update`
4. Etc.

---

## Contacto

Para cambios en formato de eventos o problemas de integración, documentar cambios aquí.

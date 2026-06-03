# Arquitectura Docker — Sistema de Gestión Documental

> Documento de la refactorización a **3 stacks Docker independientes** (2026-06-02).

## 1. Arquitectura anterior

- **Un solo proyecto** Docker (`compose-all.yml`, proyecto `sistema-gestion-documental`) con 7 contenedores.
- Existían además `compose-net.yml` / `compose-php.yml` / `compose-indexer.yml`, pero:
  - Nombres no estándar y solapados con el monolito.
  - **Nginx vivía en el stack PHP**.
  - Archivos físicos compartidos por **bind-mount** `./data/uploads` (o el volumen `uploads_data`).
- Resolución de servicios por **nombre de servicio compose** (`php`, `dotnet`, `fastapi`) — válido solo dentro de un mismo proyecto.
- PHP ya migrado a **PHP-FPM** (sin Apache), pero `.NET` apuntaba a `http://php` (FPM no sirve HTTP).

```
┌─ proyecto único: sistema-gestion-documental ────────────────┐
│ nginx ─ php(FPM) ─ postgres                                  │
│ dotnet ─ sqlserver     fastapi ─ mongodb                     │
│ red: dms_net      volumen archivos: uploads_data (bind)      │
└──────────────────────────────────────────────────────────────┘
```

## 2. Arquitectura nueva (3 stacks)

3 `docker-compose` independientes, cada uno su propio proyecto (`-p`), unidos por una **red externa compartida** y un **volumen externo de documentos**.

| Stack | Archivo | Proyecto | Servicios |
|-------|---------|----------|-----------|
| 1 .NET | `docker-compose.dotnet.yml` | `dms-dotnet` | `dms_sqlserver` + `dms_dotnet` |
| 2 PHP | `docker-compose.php.yml` | `dms-php` | `dms_postgres` + `dms_php` |
| 3 FastAPI | `docker-compose.fastapi.yml` | `dms-fastapi` | `dms_mongodb` + `dms_fastapi` + `dms_nginx` |

```
            ┌──────── dms_backbone (red externa compartida) ────────┐
            │                                                        │
 [dms-dotnet]                [dms-php]                 [dms-fastapi] │
  sqlserver(int)──dotnet─────────────────php(FPM)──postgres(int)     │
                    │            ▲          │                        │
                    │            │          │      mongodb(int)──fastapi──nginx
                    └─ HTTP ─────┘          └─ FastCGI :9000 ─────────────┘ ▲
              (.NET→dms_nginx→events.php)        (nginx :80→dms_php:9000)   │
                                                                  entrada única
   Volumen externo 'documentos': dotnet(rw) · php(ro) · fastapi(ro) · nginx(ro)
```

### Red y resolución de nombres
- **`dms_backbone`** (bridge externa): única red por la que cruzan los stacks.
- Cada stack tiene además un bridge **interno** (`net_internal` / `php_internal` / `indexer_internal`) que aísla su BD (no expuesta a otros stacks).
- Cross-stack se resuelve por **container_name** (`dms_php`, `dms_dotnet`, `dms_fastapi`, `dms_nginx`), no por nombre de servicio (que no cruza proyectos).

### Nginx — punto de entrada único (stack FastAPI), ROUTING POR PATH
Puerto `80`, un solo host, distinguido por prefijo de ruta:
| Ruta | Destino | Mecanismo |
|------|---------|-----------|
| `/` | → `302 /php/` | redirect |
| `/php/` | `dms_php:9000` (FastCGI) | strip prefix + `X-Forwarded-Prefix: /php` |
| `/fastapi/` | `dms_fastapi:8000` | strip + `X-Forwarded-Prefix: /fastapi` |
| `/dotnet/` | `dms_dotnet:8080` (+ SignalR) | strip + `X-Forwarded-Prefix: /dotnet` |

Cada app reconstruye sus enlaces con el prefijo recibido (`X-Forwarded-Prefix`):
- **.NET**: middleware `Request.PathBase` (Program.cs) → tag helpers, cookies y static auto-prefijan (`/dotnet/...`).
- **FastAPI**: `BASE` inyectado en las páginas HTML (search/auth/viewer) + redirect raíz.
- **PHP**: `config/bootstrap.php` define `DMS_BASE` (auto_prepend) → redirects/links usan el prefijo.

Sin header (acceso directo) → prefijo vacío → la app sirve en la raíz. Por eso se mantienen también los puertos directos **`8443`** (FastAPI HTTPS) y **`8084`** (.NET) para debug/compatibilidad.

### Volúmenes
| Volumen | Tipo | Uso |
|---------|------|-----|
| `sqlserver_data` | nombrado | datos SQL Server (stack dotnet) |
| `postgres_data` | nombrado | datos PostgreSQL (stack php) |
| `mongodb_data` | nombrado | datos MongoDB (stack fastapi) |
| `indices_busqueda` | nombrado | artefactos/cache de búsqueda FastAPI (`/app/indices`) |
| `documentos` | **externo compartido** | archivos físicos: `dotnet` r/w, `php`/`fastapi`/`nginx` r/o |

> Decisión: los `documentos_dotnet/php/fastapi` de la spec se **unifican** en un único volumen externo `documentos`, porque FastAPI y PHP **leen** el archivo físico (no reciben los bytes por evento). Así se preserva visor/descarga sin duplicar archivos ni cambiar el mecanismo de sincronización.

## 3. Cambios realizados

### Archivos creados
- `docker-compose.dotnet.yml`, `docker-compose.php.yml`, `docker-compose.fastapi.yml`
- `ARQUITECTURA_DOCKER.md` (este documento)

### Archivos renombrados / eliminados
- `compose-all.yml` → **`compose-all.legacy.yml`** (respaldo, no se ejecuta con el split).
- Eliminados: `compose-net.yml`, `compose-php.yml`, `compose-indexer.yml`.
- Backup: `setup.ps1.bak`.

### Wiring (URLs por container name)
- `.NET` `PublicDms__PhpSyncUrl` = **`http://dms_nginx`** (antes `http://php`; FPM no sirve HTTP → vía nginx).
- `.NET` `PublicDms__WebhookUrl` = `http://dms_fastapi:8000`.
- `php` `FASTAPI_URL` = `http://dms_fastapi:8000`, `DOTNET_API_URL` = `http://dms_dotnet:8080`.
- `fastapi` `DOTNET_API_URL` = `http://dms_dotnet:8080`, `POSTGRES_HOST` = `dms_postgres`.
- `nginx.conf`: upstreams `dms_php:9000` / `dms_fastapi:8000` / `dms_dotnet:8080`.
- Fallbacks de código actualizados: `DependencyInjection.cs`, `PhpSyncService.cs`, `DbSeeder.cs`, `routes/auth.py`, `viewer.php`, `api/auth.php`. Env: `.env`, `.env.php`, `.env.net`, `.env.indexer`.

### setup.ps1
- Subcomandos no interactivos: **`status` · `ports` · `logs` · `validate`** (+ `-Diagnose` menú).
- Stacks: `-Stack dotnet|php|fastapi` (alias legacy `net`→dotnet, `indexer`→fastapi).
- `Initialize-SharedInfra`: crea `dms_backbone` + `documentos` idempotente.
- `up` itera los stacks por proyecto (`-p`); `.env` raíz único.

## 4. Riesgos encontrados

| Riesgo | Estado / Mitigación |
|--------|---------------------|
| DNS cross-proyecto (servicio vs container) | Resuelto usando **container_name** sobre `dms_backbone`. |
| `.NET → PHP` 401 (events.php exige `X-API-Key`) | `DependencyInjection.cs` ya inyecta `X-API-Key` + `BaseAddress`. Solo requiere `FASTAPI_API_KEY` en `.env`. |
| FPM no sirve HTTP | `.NET` apunta a `dms_nginx`, que hace `fastcgi_pass` a `dms_php:9000`. |
| Volumen `documentos` r/o en php/fastapi | Solo `.NET` escribe (fuente maestra). Coherente con arquitectura unidireccional. |
| Orden de arranque (nginx proxya a dotnet/php) | nginx usa `resolver` dinámico; reintenta. Orden de boot: dotnet→php→fastapi. |
| Datos sandbox | Volúmenes de BD regenerables (`DMS_SEED_MODE=sandbox`). `documentos` migrado del volumen anterior. |
| compose-all simultáneo con split | Mismos `container_name` → **no** ejecutar a la vez. Legacy queda como respaldo. |

## 5. Checklist de pruebas

- [ ] `docker ps` → 7 contenedores, BDs healthy.
- [ ] Smoke HTTP: `:80`→302, `https://localhost:8443`→307, `:8084`→302.
- [ ] Login en .NET (`:8084`).
- [ ] Aprobar documento en .NET → aparece en portal PHP (`:80`) y búsqueda FastAPI (`:8443`) [valida .NET→nginx→events.php + .NET→fastapi metadata].
- [ ] Ver/Descargar documento real desde **.NET**, **PHP** y **FastAPI** (volumen `documentos` compartido).
- [ ] Documento **obsoleto** visible+descargable en los 3 stacks.
- [ ] `events.php` POST approve → 200 (sin 401).
- [ ] Bajar 1 stack y verificar que los otros 2 siguen vivos (despliegue independiente).
- [ ] `setup.ps1 status | ports | logs | validate` devuelven info correcta.

## 6. Comandos

```powershell
# Infra compartida (una vez)
docker network create dms_backbone
docker volume create documentos

# Levantar (independiente por stack)
docker compose -p dms-dotnet  -f docker-compose.dotnet.yml  --env-file .env up -d --build
docker compose -p dms-php     -f docker-compose.php.yml     --env-file .env up -d --build
docker compose -p dms-fastapi -f docker-compose.fastapi.yml --env-file .env up -d --build

# O todo vía setup
.\setup.ps1                 # los 3 stacks
.\setup.ps1 -Stack php      # solo uno
.\setup.ps1 status|ports|logs|validate

# Detener un stack
docker compose -p dms-php -f docker-compose.php.yml down
```

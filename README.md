# Sistema Integral de Gestión Documental (DMS)

[![Repo](https://img.shields.io/badge/GitHub-Ero--2%2FSistema--Gestion--Documental-blue?logo=github)](https://github.com/Ero-2/Sistema-Gestion-Documental)

Sistema multi-stack para gestión, aprobación y consulta pública de documentos normativos.

## Cómo funciona la arquitectura hoy (2026-05)

Tres servicios independientes, cada uno con su base de datos, comunicados **solo por API + eventos push unidireccionales** desde .NET. Solo .NET accede a SQL Server (fuente de verdad); PHP y FastAPI reciben los datos por sus propios endpoints. **Sin polling, sin cron de sincronización, sin accesos cruzados a BD.**

```
                         ┌──────────────────────────────────────────┐
                         │  .NET (CalidadSYS) + SQL Server           │
                         │  Fuente de verdad · auth · workflows ·    │
                         │  versionado · multiempresa                │
                         └───────────────┬───────────────┬──────────┘
        push HTTPS + X-API-Key (evento)  │               │  push HTTPS + X-API-Key
        (documento aprobado X.0)         ▼               ▼  (metadatos + archivo)
              ┌──────────────────────────────┐   ┌──────────────────────────────┐
              │  PHP + PostgreSQL             │   │  FastAPI + MongoDB            │
              │  Portal público · historial   │   │  Indexación full-text ·       │
              │  de versiones · obsolescencia │   │  API de búsqueda reutilizable │
              └──────────────────────────────┘   └───────────────▲──────────────┘
                         │  ambos consumen la misma API de búsqueda │
                         └──────────────────────────────────────────┘
```

### Núcleo documental: versionado, vigencia y obsolescencia
- **Numeración:** borradores `0.1, 0.2…` → primera aprobación `1.0` → borradores de revisión `1.1, 1.2…` → nueva aprobación `2.0` (la `1.0` pasa a **obsoleta**) → `2.1…` → `3.0`, y así.
- **El estado vive por versión** (`DocumentVersion.Status`: Draft / PendingApproval / Approved / Obsolete / Rejected). `Document.Status` es solo un caché derivado.
- **Una sola versión vigente por documento**, garantizado por la BD con un **índice único filtrado** (`WHERE IsCurrent = 1`) tanto en SQL Server como en PostgreSQL.
- **Solo las versiones aprobadas `X.0` se publican** a PHP/Mongo. Los borradores nunca salen de .NET.
- **El historial se conserva**: las versiones anteriores se marcan obsoletas, no se borran. PostgreSQL guarda el historial en `publicdms.document_versions`.

### Multiempresa (multi-tenant)
- Entidad `Company`; `CompanyId` en documentos, departamentos, categorías, flujos y usuarios.
- **Aislamiento automático** por *global query filters* de EF Core: cada usuario solo ve los datos de su empresa.
- Roles **SuperAdmin** (global, ve y administra todas las empresas vía panel **Empresas**) y **AdminEmpresa** (solo la suya).
- La empresa viaja en el evento de aprobación → PostgreSQL y MongoDB guardan `company_id`/`company_name`.
- Códigos únicos **por empresa** (`Code + CompanyId`): dos empresas pueden tener el mismo `POL-001`.

### API de búsqueda reutilizable (FastAPI + MongoDB)
- Un único endpoint `GET /search/documents` (full-text sobre título, código, categoría, departamento y **contenido** de PDF/Word/Excel) **consumido por .NET y PHP por HTTP**, sin que ninguno toque Mongo directamente.
- Autenticación dual: **JWT** (usuarios) o **X-API-Key** (módulos servidor).
- **Búsqueda en vivo** (type-ahead, coincidencia por substring: «proc» encuentra «Procedimiento») y **filtro por empresa**.

## Cambios recientes — Refactor a arquitectura desacoplada por eventos (2026-05)

Migración a comunicación **unidireccional orientada a eventos**. Solo **.NET (CalidadSYS)** conecta a SQL Server; PHP y FastAPI nunca lo consultan: reciben los datos por API y leen los archivos del volumen compartido. **Sin polling, cron ni auto-sync.**

- **Eliminado polling/cron:** borrado `_auto_sync_loop`, `SYNC_INTERVAL_SECONDS`, `bulk_sync.py`, endpoint `/sync/start` y botón "Bulk Sync" del admin.
- **SQL Server fuera de los servicios secundarios:** FastAPI sin `pyodbc`; PHP sin driver ODBC/`sqlsrv`. Borrados `config/sqlserver.php` y `config/test_sql.php`. Quitados drivers `msodbcsql17`/ODBC de los 4 Dockerfiles y las vars `SQL_*`/`SQLSERVER_*` + `depends_on: sqlserver` de `docker-compose`.
- **Aprobación = push completo de evento:** al aprobar, .NET hace `POST /indexer/upsert` a FastAPI con metadatos completos (FastAPI extrae texto del archivo, no consulta SQL) y `POST api/events.php` a PHP para PostgreSQL. Reemplaza al antiguo `/indexer/notify` que disparaba un SELECT a SQL.
- **Seeder de datos de prueba:** `DbSeeder` precarga roles, usuarios (hash PBKDF2 vía `UserManager`), departamentos, categorías, flujo de aprobación y documentos de ejemplo en `Development` (idempotente). Ver `db/sqlserver/README.md`.
- **Extracción `.doc` legado:** añadido `antiword`/`catdoc` al contenedor FastAPI.

## Arquitectura

```
┌─────────────────────┐     webhook      ┌──────────────────────┐
│   CalidadSYS        │ ───────────────▶ │   python-service      │
│   ASP.NET Core 10   │                  │   FastAPI + MongoDB   │
│   + SQL Server 2022 │ ───────────────▶ │   Indexación +        │
└─────────────────────┘     webhook      │   Extracción texto    │
         │                               └──────────────────────┘
         │ webhook                                ▲
         ▼                                        │ búsqueda
┌─────────────────────┐                           │
│   PublicDMS         │ ──────────────────────────┘
│   PHP 8 + PostgreSQL│
│   Consulta Pública  │
└─────────────────────┘
         │
         └─────────────── uploads_data (volumen compartido, solo lectura) ───────┐
                                                                                  │
                                                              CalidadSYS (escribe)┘
```

| Servicio       | Tecnología              | Puerto (host) | Rol                                        |
|----------------|-------------------------|---------------|--------------------------------------------|
| CalidadSYS     | ASP.NET Core 10 MVC     | 5080          | Gestión de documentos, workflows, uploads  |
| python-service | FastAPI + Python 3.12   | 8001          | Indexación MongoDB, extracción texto, búsqueda full-text |
| PublicDMS      | PHP 8.3 + Apache        | 80 / 8443     | Portal de consulta pública                 |
| SQL Server     | SQL Server 2022         | 1434          | Base de datos maestra                      |
| PostgreSQL     | PostgreSQL 16           | 5433          | Metadatos sincronizados (PublicDMS)        |
| MongoDB        | MongoDB 7               | 27018         | Índice full-text de documentos             |
| Nginx          | Nginx                   | 80 / 8443     | Reverse proxy + HTTPS                      |

## Estructura del repositorio

```
/
├── src/
│   ├── dotnet-core/        ← Código fuente CalidadSYS (ASP.NET Core)
│   ├── php-app/            ← Módulo PHP PublicDMS
│   └── python-service/     ← Código fuente moduloDMS (FastAPI)
├── db/
│   ├── postgres/           ← Schema PostgreSQL (auto-ejecutado en primer arranque)
│   ├── mongo/              ← Init MongoDB (auto-ejecutado en primer arranque)
│   └── sqlserver/          ← Instrucciones para exportar schema SQL Server
├── docker/
│   ├── php-app/            ← Dockerfile + config Apache + crontab
│   ├── python-service/     ← Dockerfile FastAPI
│   └── dotnet-core/        ← Dockerfile .NET 10 multi-stage
├── docker-compose.yml
├── .env.example
├── install.sh              ← Installer Linux/macOS/WSL (recomendado)
├── setup.ps1               ← Installer Windows PowerShell
├── scripts/                ← Módulos del installer (colors, spinner, ui, deps…)
└── README.md
```

## Requisitos

- Docker Desktop 4.x o superior (con Docker Compose V2)
- Git
- curl, openssl
- 8 GB RAM disponibles para los contenedores

## Configuración inicial

### Opción A — Installer Linux / macOS / WSL (recomendado)

```bash
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental
bash install.sh
```

El installer:
1. Verifica dependencias (Docker, Compose, Git, curl, openssl)
2. Pide una **contraseña maestra** que se aplica a PostgreSQL, MongoDB y SQL Server
3. Genera `.env` automáticamente (API key y JWT secret aleatorios)
4. Construye y levanta todos los contenedores
5. Espera que cada servicio esté healthy
6. Muestra dashboard con URLs y comandos

**Requisito de la contraseña maestra** (política SQL Server):
- Mínimo 8 caracteres
- Al menos una mayúscula, una minúscula, un dígito y un carácter especial
- Ejemplo válido: `MiPass1!`

**Opciones del installer:**

```bash
bash install.sh --verbose    # muestra output completo de docker build
bash install.sh --force      # sobreescribe .env existente sin preguntar
bash install.sh --no-build   # usa imágenes cacheadas (sin rebuild)
bash install.sh --skip-env   # usa .env existente sin modificarlo
```

### Opción B — Installer Windows (PowerShell)

```powershell
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental
.\setup.ps1
```

### Opción C — Setup manual

```bash
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental

cp .env.example .env
# Editar .env con tus contraseñas

docker compose up -d --build
```

Variables requeridas en `.env`:

| Variable            | Descripción                             | Ejemplo             |
|---------------------|-----------------------------------------|---------------------|
| `MSSQL_SA_PASSWORD` | Contraseña SA de SQL Server (política)  | `MiPass1!`          |
| `MSSQL_DB`          | Nombre BD SQL Server                    | `QualityDMS`        |
| `POSTGRES_PASSWORD` | Contraseña PostgreSQL                   | `MiPass1!`          |
| `MONGO_PASSWORD`    | Contraseña MongoDB                      | `MiPass1!`          |
| `FASTAPI_API_KEY`   | API key interna FastAPI (hex 64 chars)  | `openssl rand -hex 32` |
| `JWT_SECRET`        | JWT secret interno                      | `openssl rand -base64 64` |

## URLs del sistema

| Servicio              | URL                            |
|-----------------------|--------------------------------|
| Portal PublicDMS      | http://localhost               |
| Portal PublicDMS HTTPS| https://localhost:8443         |
| CalidadSYS            | http://localhost:5080          |
| CalidadSYS Swagger    | http://localhost:5080/swagger  |
| FastAPI Docs          | http://localhost:8001/docs     |

## Verificar que todo está correcto

```powershell
# Estado de contenedores
docker compose ps

# Logs en tiempo real
docker compose logs -f

# Health checks individuales
curl http://localhost/
curl http://localhost:8001/health
curl http://localhost:5080/
```

## Flujo de datos

```
Arquitectura orientada a eventos, comunicación unidireccional (.NET → PHP, .NET → FastAPI).
Solo .NET conecta a SQL Server. PHP y FastAPI nunca consultan SQL Server: reciben todos
los datos por API y leen los archivos del volumen compartido. Sin polling, cron ni auto-sync.

1. Upload y aprobación
   CalidadSYS sube PDF/DOCX/etc → uploads_data (volumen compartido)
   CalidadSYS registra en SQL Server (DocumentVersions.FilePath)
   Documento aprobado → CalidadSYS dispara eventos (push HTTP inmediato):
     → POST http://fastapi:8000/indexer/upsert        (metadatos + contenido → MongoDB)
     → POST http://php/api/events.php?action=approve  (documento → PostgreSQL)

2. Indexación (FastAPI — inmediata tras el evento)
   Recibe metadatos en el payload (no consulta SQL Server)
   Lee el archivo del volumen y extrae texto (PDF→PyMuPDF, DOCX→python-docx, XLSX→openpyxl, .doc→antiword)
   Guarda metadatos + contenido en MongoDB

3. Recepción PostgreSQL (PHP — inmediata tras el evento)
   api/events.php recibe el documento aprobado e inserta/actualiza en PostgreSQL
   (no consulta SQL Server)

4. Consulta pública
   Usuario busca → PHP llama FastAPI /indexer/search?q=...
   MongoDB full-text search → devuelve postgres_ids
   PHP consulta PostgreSQL con esos ids → muestra resultados
   Ver documento → viewer.php (renderizado en browser por tipo)
   Descargar → view_pdf.php?download=1 → uploads_data (solo lectura)
```

## Visor de documentos

`viewer.php` renderiza cualquier archivo directamente en el navegador sin plugins adicionales:

| Formato        | Extensión                        | Método                          |
|----------------|----------------------------------|---------------------------------|
| PDF            | .pdf                             | Embed nativo del navegador      |
| Word           | .docx                            | mammoth.js (CDN) → HTML         |
| Excel          | .xlsx / .xls                     | SheetJS (CDN) → tabla con tabs  |
| Imágenes       | .png / .jpg / .jpeg / .gif / .webp | `<img>` directo               |
| Texto plano    | .txt / .csv / .json / .xml / .md | `<pre>` con fetch               |
| Sin soporte    | cualquier otro                   | Botón de descarga               |

> Requiere acceso a internet (CDN). En entornos air-gapped, alojar las librerías localmente.

## Formatos soportados para indexación de contenido

| Formato | Extensión       | Librería            |
|---------|-----------------|---------------------|
| PDF     | .pdf            | PyMuPDF             |
| Word    | .docx           | python-docx         |
| Word    | .doc            | antiword (sistema)  |
| Excel   | .xlsx           | openpyxl            |
| Excel   | .xls            | xlrd                |
| PowerPoint | .pptx        | python-pptx         |
| PowerPoint | .ppt         | catppt (sistema)    |
| Texto   | .txt / .md      | nativo + chardet    |
| RTF     | .rtf            | striprtf            |
| OpenDoc | .odt / .ods / .odp | odfpy            |
| CSV     | .csv            | nativo              |
| Web     | .html / .htm    | beautifulsoup4      |
| XML     | .xml            | lxml                |
| Email   | .eml            | nativo email lib    |
| Outlook | .msg            | extract-msg         |

Archivos con formato no soportado se indexan con solo metadatos (sin contenido).

## Desarrollo local (sin Docker)

### FastAPI (python-service)
```powershell
cd src/python-service
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### PHP (PublicDMS)
Requiere PHP 8.3 con extensión `pdo_pgsql` (solo PostgreSQL; no usa SQL Server).
Ajustar `config/storage.php` con la ruta local a los uploads de CalidadSYS.

### CalidadSYS
Abrir `src/dotnet-core/CalidadSYS/CalidadSYS.csproj` en Visual Studio 2022 y ejecutar con F5.

## Gestión de contenedores

```powershell
# Detener (conserva datos)
docker compose down

# Detener y BORRAR todos los datos (irreversible)
docker compose down -v

# Reconstruir un servicio específico
docker compose up -d --build fastapi

# Ver logs de un servicio
docker compose logs -f fastapi
```

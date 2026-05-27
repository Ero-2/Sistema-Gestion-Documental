# Sistema Integral de Gestión Documental (DMS)

Sistema multi-stack para gestión, aprobación y consulta pública de documentos normativos.

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
├── install.sh              ← CLI installer (Linux / macOS / WSL) ✨
├── setup.ps1               ← Script de setup automatizado (Windows PowerShell)
└── README.md
```

## Requisitos

- Docker Desktop 4.x o superior
- Git
- 8 GB RAM disponibles para los contenedores

## Instalación

### ⚡ Un solo comando (Linux / macOS / WSL)

```bash
curl -fsSL https://raw.githubusercontent.com/Ero-2/Sistema-Gestion-Documental/mAIN/install.sh | bash
```

> El script descarga el repo, pide una contraseña maestra, genera el `.env` y levanta todos los contenedores automáticamente.

---

### Opción A — CLI installer interactivo (recomendado)

Descarga el script y ejecútalo — te guía paso a paso:

```bash
# Linux / macOS / WSL
curl -fsSL https://raw.githubusercontent.com/Ero-2/Sistema-Gestion-Documental/mAIN/install.sh -o install.sh
bash install.sh
```

```powershell
# Windows (PowerShell)
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental
.\setup.ps1
```

El installer interactivo:
- ✅ Verifica dependencias (git, Docker, docker compose)
- 📁 Clona el repositorio en el directorio que elijas
- 🔐 Pide contraseña maestra con confirmación (entrada oculta, mín. 6 chars)
- 🔑 Genera una API key aleatoria de 64 hex chars
- 🐳 Construye e inicia todos los contenedores (`docker compose up -d --build`)
- ⏳ Espera a que SQL Server esté listo (healthcheck automático)
- 🗺️ Muestra la tabla de URLs y puertos al finalizar

---

### Opción B — Setup manual

```bash
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental

cp .env.example .env
# Editar .env con tus contraseñas

docker compose up -d --build
```

Variables requeridas en `.env`:

| Variable            | Descripción                  | Ejemplo               |
|---------------------|------------------------------|-----------------------|
| `MSSQL_SA_PASSWORD` | Contraseña SA de SQL Server  | `MiPass1@`            |
| `MSSQL_DB`          | Nombre BD SQL Server         | `QualityDMS`          |
| `POSTGRES_PASSWORD` | Contraseña PostgreSQL        | `mipassword`          |
| `MONGO_PASSWORD`    | Contraseña MongoDB           | `mipassword`          |
| `FASTAPI_API_KEY`   | API key para FastAPI         | `clave-secreta-hex`   |

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
1. Upload y aprobación
   CalidadSYS sube PDF/DOCX/etc → uploads_data (volumen compartido)
   CalidadSYS registra en SQL Server (DocumentVersions.FilePath)
   Documento aprobado → CalidadSYS dispara dos webhooks en paralelo:
     → POST http://fastapi:8000/indexer/notify  (indexación inmediata MongoDB)
     → POST http://php/sync/trigger_sync.php    (sync inmediato PostgreSQL)

2. Indexación (FastAPI — < 2 segundos tras aprobación)
   Lee documento de SQL Server
   Extrae texto del archivo (PDF→PyMuPDF, DOCX→python-docx, TXT, XLSX→openpyxl)
   Guarda metadatos + contenido en MongoDB
   Auto-sync cada 30s como respaldo

3. Sincronización PostgreSQL (PHP — < 3 segundos tras aprobación)
   sync_docs.php lee SQL Server → sincroniza a PostgreSQL
   Cron cada 5 min como respaldo

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
Requiere XAMPP con PHP 8.3, extensiones `pdo_pgsql` y `pdo_sqlsrv`.
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

# Sistema Integral de Gestión Documental

[![Repo](https://img.shields.io/badge/GitHub-Ero--2%2FSistema--Gestion--Documental-blue?logo=github)](https://github.com/Ero-2/Sistema-Gestion-Documental)

Sistema multi-stack para gestión, aprobación y consulta pública de documentos normativos, construido con arquitectura de eventos desacoplada.

---

## Arquitectura

Tres sistemas independientes comunicados únicamente por eventos HTTP desde .NET. Ningún sistema secundario accede a SQL Server directamente.

```
┌─────────────────────────────────────────┐
│  Sistema 1 — .NET Core + SQL Server      │
│  Usuarios · Roles · Flujos · Versiones   │
│  Multiempresa · Fuente de verdad         │
└──────────────┬──────────────┬───────────┘
               │ evento       │ evento
               ▼              ▼
┌──────────────────┐  ┌──────────────────────┐
│  Sistema 2        │  │  Sistema 3            │
│  PHP + PostgreSQL │  │  FastAPI + MongoDB    │
│  Portal público   │  │  Búsqueda full-text   │
│  Docs aprobados   │  │  Indexación           │
└──────────────────┘  └──────────────────────┘
```

| Servicio    | Tecnología            | Puerto |
|-------------|-----------------------|--------|
| .NET        | ASP.NET Core 10       | 5080   |
| PHP         | PHP 8.3 + Apache      | 80     |
| FastAPI     | Python 3.12           | 8001   |
| SQL Server  | SQL Server 2022       | 1434   |
| PostgreSQL  | PostgreSQL 16         | 5433   |
| MongoDB     | MongoDB 7             | 27018  |
| Nginx       | Nginx (proxy + HTTPS) | 80/8443|

---

## Requisitos

- Docker Desktop 4.x o superior (con Docker Compose V2)
- Git
- 8 GB RAM disponibles

---

## Instalación

### Windows (PowerShell)

```powershell
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental
.\setup.ps1
```

El instalador pregunta:

1. **Modo de instalación:**
   - `[1] Sandbox` — genera 10,000 documentos de prueba automáticamente
   - `[2] Development` — sistema limpio, sin documentos

2. **Contraseña maestra** para SQL Server, PostgreSQL y MongoDB
   - Mínimo 8 caracteres, mayúscula, minúscula, dígito y carácter especial
   - Ejemplo: `MiPass1!`

### Linux / macOS / WSL

```bash
git clone https://github.com/Ero-2/Sistema-Gestion-Documental.git
cd Sistema-Gestion-Documental
bash install.sh
```

Opciones adicionales:

```bash
bash install.sh --no-build    # usa imágenes cacheadas
bash install.sh --skip-env    # usa .env existente
bash install.sh --force       # sobreescribe .env sin preguntar
```

---

## Stacks independientes

Además del instalador completo, cada sistema puede levantarse por separado:

```powershell
# Solo .NET + SQL Server
.\setup.ps1 -Stack net

# Solo PHP + PostgreSQL + Nginx
.\setup.ps1 -Stack php

# Solo FastAPI + MongoDB
.\setup.ps1 -Stack indexer
```

```bash
# Linux
bash install.sh --net
bash install.sh --php
bash install.sh --indexer
```

Cada stack tiene su propia red Docker interna y volúmenes independientes. Se comunican a través de la red compartida `dms_backbone`.

---

## URLs

| Portal | URL |
|--------|-----|
| Portal público (PHP) | http://localhost |
| Portal HTTPS (FastAPI) | https://localhost:8443 |
| Admin .NET (CalidadSYS) | http://localhost:5080 |
| FastAPI Swagger | http://localhost:8001/docs |

---

## Usuarios de prueba

Todos comparten la contraseña ingresada durante la instalación (`Calidad#2026Dev` si se usó el seeder directamente).

| Rol | Email | Empresa |
|-----|-------|---------|
| SuperAdmin | super@qualitydms.local | Global |
| Admin | admin@qualitydms.local | ACME |
| AdminEmpresa | adminempresa@qualitydms.local | ACME |
| QualityManager | calidad@qualitydms.local | ACME |
| Approver | aprobador1@qualitydms.local | ACME |
| Approver | aprobador2@qualitydms.local | ACME |
| Author | autor@qualitydms.local | ACME |
| Viewer | lector@qualitydms.local | ACME |
| AdminEmpresa | admin.beta@qualitydms.local | BETA |

---

## Modo Sandbox

Al elegir modo **Sandbox** en el instalador, el sistema genera automáticamente:

- **10,000 documentos** en SQL Server con datos realistas (Bogus en español)
- **7,000 aprobados** propagados a PostgreSQL y MongoDB vía las APIs existentes
- **2,000 en revisión** y **1,000 borradores** solo en SQL Server

La propagación usa 50 llamadas concurrentes a las mismas APIs de eventos que usa el flujo real. El proceso tarda ~5 minutos en el primer arranque.

---

## Flujo de aprobación

```
Autor sube documento → borrador 0.1 en .NET
        ↓
Envía a revisión → Approver revisa → QualityManager aprueba
        ↓
.NET sella versión 1.0 y dispara eventos:
  → POST /api/events.php?action=approve   (PHP → PostgreSQL)
  → POST /indexer/upsert                  (FastAPI → MongoDB)
        ↓
Documento visible en portal público y buscable full-text
```

Nueva revisión genera `1.1, 1.2…` → nueva aprobación genera `2.0` (la `1.0` pasa a obsoleta).

---

## Gestión de contenedores

```powershell
# Ver estado
docker compose -f compose-all.yml ps

# Logs en tiempo real
docker compose -f compose-all.yml logs -f

# Detener (conserva datos)
docker compose -f compose-all.yml down

# Detener y borrar todos los datos
docker compose -f compose-all.yml down -v

# Reconstruir un servicio
docker compose -f compose-all.yml up -d --build dotnet
```

---

## Estructura del repositorio

```
/
├── compose-all.yml         ← Todos los stacks juntos
├── compose-net.yml         ← Stack 1: .NET + SQL Server
├── compose-php.yml         ← Stack 2: PHP + PostgreSQL + Nginx
├── compose-indexer.yml     ← Stack 3: FastAPI + MongoDB
├── install.sh              ← Instalador Linux/macOS/WSL
├── setup.ps1               ← Instalador Windows PowerShell
├── scripts/                ← Módulos del instalador
├── src/
│   ├── dotnet-core/        ← CalidadSYS (ASP.NET Core)
│   ├── php-app/            ← PublicDMS (PHP)
│   └── python-service/     ← Motor de búsqueda (FastAPI)
├── db/
│   ├── postgres/           ← Schema PostgreSQL
│   └── mongo/              ← Init MongoDB
└── docker/
    └── nginx/              ← Configuración Nginx
```

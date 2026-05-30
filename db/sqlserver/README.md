# SQL Server Schema

SQL Server (QualityDMS) is managed by CalidadSYS via Entity Framework Core migrations.

To export the current schema from a running instance:

```bash
# Con sqlcmd dentro del contenedor
docker exec -it dms_sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "$SA_PASSWORD" \
  -Q "SCRIPT DATABASE QualityDMS" \
  -o /tmp/schema.sql
```

Or use SQL Server Management Studio (SSMS) → Right-click DB → Tasks → Generate Scripts.

## Datos de prueba (seed automático)

Al iniciar CalidadSYS en `Development`, `DbSeeder` precarga datos de prueba para
permitir pruebas funcionales inmediatas (idempotente; cada bloque se omite si ya hay
datos). Implementación: `src/QualityDMS.Infrastructure/Persistence/DbSeeder.cs`.

- **Roles:** Admin, QualityManager, Approver, Author, Viewer
- **Usuarios** (password común `Calidad#2026Dev`):
  - `admin@qualitydms.local` — Admin
  - `calidad@qualitydms.local` — QualityManager (aprobación final)
  - `aprobador1@qualitydms.local` / `aprobador2@qualitydms.local` — Approver
  - `autor@qualitydms.local` — Author
  - `lector@qualitydms.local` — Viewer
- **Departamentos:** Calidad, Operaciones, Recursos Humanos, Tecnología
- **Categorías:** Políticas, Procedimientos (+ subcategoría Seguridad), Instructivos, Formatos
- **Flujo de aprobación:** "Flujo de Aprobación de Calidad" — 2 pasos (Revisión Técnica → Aprobación Final)
- **Documentos de ejemplo** (con versión y estado):
  - `POL-001` Política de Calidad — **Approved** (flujo completo, 2 acciones de aprobación)
  - `PRO-001` Procedimiento de Control de Documentos — **PendingApproval** (flujo en paso 1)
  - `INS-001` Instructivo de Respaldos — **Draft**

Los usuarios se crean con `UserManager` (passwords con hash PBKDF2). PHP y FastAPI
no almacenan usuarios: validan login contra `.NET POST /api/v1/auth/validate`.

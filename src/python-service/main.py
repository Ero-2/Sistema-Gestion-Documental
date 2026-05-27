import asyncio
import logging
import os

from fastapi import FastAPI, BackgroundTasks, HTTPException
from fastapi.openapi.utils import get_openapi
from fastapi.security import APIKeyHeader
from pymongo import TEXT
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from bulk_sync import run_bulk_sync_from_sql, run_incremental_sync
from database import collection
from routes.indexer import router as indexer_router
from routes.admin import router as admin_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="DMS Search Engine",
    description="Motor de búsqueda para documentos aprobados",
    version="2.0.0",
    root_path="/api",
)

# Expone el campo API Key en el botón Authorize de Swagger UI
_api_key_scheme = APIKeyHeader(name="X-API-Key", auto_error=False)


def custom_openapi():
    if app.openapi_schema:
        return app.openapi_schema
    schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )
    schema.setdefault("components", {}).setdefault("securitySchemes", {})["ApiKeyAuth"] = {
        "type": "apiKey",
        "in": "header",
        "name": "X-API-Key",
    }
    for path in schema.get("paths", {}).values():
        for op in path.values():
            op.setdefault("security", [{"ApiKeyAuth": []}])
    app.openapi_schema = schema
    return schema


app.openapi = custom_openapi

# ── API Key middleware ────────────────────────────────────────────────────────
_API_KEY    = os.getenv("FASTAPI_API_KEY", "")
_OPEN_PATHS = {"/", "/docs", "/openapi.json", "/redoc", "/health",
               "/admin/viewer", "/admin/stats", "/admin/docs",
               "/sync/start"}


class APIKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        if not _API_KEY or request.url.path in _OPEN_PATHS:
            return await call_next(request)
        if request.headers.get("X-API-Key", "") != _API_KEY:
            return JSONResponse({"detail": "Invalid or missing API key"}, status_code=401)
        return await call_next(request)


app.add_middleware(APIKeyMiddleware)
app.include_router(indexer_router)
app.include_router(admin_router)

SYNC_INTERVAL_SECONDS = int(os.getenv("SYNC_INTERVAL_SECONDS", "30"))


async def _auto_sync_loop():
    """Poller autónomo: lee SQL Server cada SYNC_INTERVAL_SECONDS e indexa en MongoDB."""
    logger.info(f"Auto-sync iniciado — intervalo: {SYNC_INTERVAL_SECONDS}s")
    await asyncio.sleep(10)  # dar tiempo al startup para terminar
    while True:
        try:
            count = await run_incremental_sync()
            if count:
                logger.info(f"Auto-sync: {count} doc(s) indexados")
        except Exception as e:
            logger.error(f"Auto-sync error: {e}", exc_info=True)
        await asyncio.sleep(SYNC_INTERVAL_SECONDS)


@app.on_event("startup")
async def on_startup():
    try:
        logger.info("Verificando índices en MongoDB...")
        existing = await collection.index_information()

        # Drop ALL text indexes — forces clean rebuild when fields change
        for name, details in existing.items():
            is_text = any("_fts" in str(v) for v in details.get("key", []))
            if is_text:
                logger.info(f"Eliminando índice de texto: {name}")
                await collection.drop_index(name)

        # Full-text index: title, code, category, department, file content
        await collection.create_index(
            [
                ("title",           TEXT),
                ("code",            TEXT),
                ("category_name",   TEXT),
                ("department_name", TEXT),
                ("content",         TEXT),
            ],
            name="dms_master_index",
            default_language="spanish",
        )

        # Supporting indexes for filtering / sorting
        await collection.create_index("file_name")
        await collection.create_index("extension")
        await collection.create_index("metadata.tags")
        await collection.create_index("created_at")
        await collection.create_index("content_extracted")

        logger.info("Índices MongoDB listos.")
    except Exception as e:
        logger.error(f"Error configurando índices: {e}")

    # Lanzar poller autónomo como background task
    asyncio.create_task(_auto_sync_loop())


@app.get("/", tags=["General"])
@app.get("/health", tags=["General"])
async def health_check():
    return {"status": "online", "engine": "FastAPI + MongoDB Text Search"}


@app.post("/sync/start", tags=["Sync"])
async def start_bulk_sync(background_tasks: BackgroundTasks):
    """Fuerza re-indexación completa de todos los docs aprobados."""
    try:
        background_tasks.add_task(run_bulk_sync_from_sql)
        return {
            "message": "Bulk sync iniciado en segundo plano",
            "source":  "SQL Server (QualityDMS)",
            "target":  "MongoDB (file_tags)",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

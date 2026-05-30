import logging
import os

from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi
from fastapi.security import APIKeyHeader
from pymongo import TEXT
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from database import collection
from routes.indexer import router as indexer_router
from routes.admin import router as admin_router
from routes.documents_sync import router as documents_sync_router
from routes.metadata_sync import router as metadata_sync_router
from routes.auth import router as auth_router
from routes.search import router as search_router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="DMS Search Engine",
    description="Motor de búsqueda para documentos aprobados",
    version="2.0.0",
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
               "/auth/login", "/auth/me", "/api/auth/login",
               "/search"}


class APIKeyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        # Check exact paths
        path = request.url.path

        # Allow open paths
        if not _API_KEY or path in _OPEN_PATHS:
            return await call_next(request)

        # Allow auth endpoints without API key (handled by individual route)
        if path.startswith("/auth/"):
            return await call_next(request)

        # Check API key for other endpoints
        if request.headers.get("X-API-Key", "") != _API_KEY:
            return JSONResponse({"detail": "Invalid or missing API key"}, status_code=401)
        return await call_next(request)


app.add_middleware(APIKeyMiddleware)
app.include_router(indexer_router)
app.include_router(admin_router)
app.include_router(documents_sync_router)
app.include_router(metadata_sync_router)
app.include_router(auth_router)
app.include_router(search_router)

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


@app.get("/", tags=["General"], response_class=None)
async def root():
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/auth/login")

@app.get("/health", tags=["General"])
async def health_check():
    return {"status": "online", "engine": "FastAPI + MongoDB Text Search"}

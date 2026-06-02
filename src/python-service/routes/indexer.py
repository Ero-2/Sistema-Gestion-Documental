import asyncio
import os
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse, HTMLResponse

from database import collection
from extractor import MAX_CONTENT_CHARS, STORAGE_ROOT, extract_text, get_file_info, resolve_path
from models import PublicDMSMetadata

router = APIRouter(prefix="/indexer", tags=["Indexer"])

# ── Helpers para documentos simulados (Faker / seed) ─────────────────────────

def _is_seed(file_url: str) -> bool:
    return (file_url or "").startswith("seed/")


def _simulated_content(code: str, title: str, category: str, department: str) -> str:
    """Genera texto fake searchable para docs seed sin archivo físico."""
    prefix = code.split("-")[0] if "-" in code else "DOC"
    blocks = {
        "POL": ["objetivo y alcance", "política general de la organización",
                "responsabilidades de los involucrados", "compromisos institucionales",
                "revisión y actualización periódica"],
        "PRO": ["descripción del procedimiento", "actividades y pasos del proceso",
                "responsables y roles asignados", "registros y evidencias requeridas",
                "frecuencia y puntos de control"],
        "INS": ["instrucciones paso a paso", "herramientas y materiales necesarios",
                "advertencias y precauciones de seguridad", "verificación del resultado",
                "criterios de aceptación"],
        "FOR": ["campos requeridos del formulario", "instrucciones de llenado",
                "datos de identificación y fecha", "firma y aprobación responsable",
                "distribución y archivo del registro"],
    }
    items = blocks.get(prefix, ["contenido general", "descripción del documento",
                                "propósito y aplicación", "vigencia y control"])
    lines = [
        f"{title}",
        f"Código: {code}  |  Categoría: {category}  |  Departamento: {department}",
        "",
        f"Este documento establece los lineamientos para {title.lower()}.",
        f"Aplica al departamento de {department} y a todas las áreas relacionadas con {category}.",
        f"La dirección de {department} es responsable de su implementación y seguimiento.",
        "",
    ]
    for item in items:
        lines.append(f"- {item.capitalize()}: conforme a los estándares de {category}.")
    lines += [
        "",
        "Documento aprobado y vigente según el proceso de gestión de calidad.",
        f"Versión generada automáticamente en el entorno de pruebas para validación de búsqueda full-text.",
    ]
    return "\n".join(lines)


def _simulated_html(doc: dict) -> str:
    title = doc.get("title", "Documento")
    code  = doc.get("code", "—")
    cat   = doc.get("category_name", "—")
    dept  = doc.get("department_name", "—")
    ver   = doc.get("version", "1.0")
    return f"""<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<title>{title}</title>
<style>
  body {{ font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0;
         display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }}
  .card {{ background: #1e293b; border: 1px solid #334155; border-radius: 12px;
           padding: 40px 48px; max-width: 520px; text-align: center; }}
  .icon {{ font-size: 3rem; margin-bottom: 16px; }}
  h1 {{ font-size: 1.1rem; color: #f8fafc; margin-bottom: 8px; }}
  p {{ color: #94a3b8; font-size: 0.88rem; line-height: 1.6; margin-bottom: 6px; }}
  .badge {{ display: inline-block; background: #1c3045; color: #7dd3fc;
            border: 1px solid #1e4060; border-radius: 6px; padding: 4px 12px;
            font-size: 0.75rem; font-family: monospace; margin: 12px 0 0; }}
  .meta {{ margin-top: 20px; text-align: left; background: #0f172a; border-radius: 8px;
           padding: 14px 18px; font-size: 0.8rem; }}
  .meta dt {{ color: #64748b; text-transform: uppercase; font-size: 0.7rem; letter-spacing: .04em; }}
  .meta dd {{ color: #cbd5e1; margin: 2px 0 10px; font-family: monospace; }}
</style>
</head>
<body>
<div class="card">
  <div class="icon">📄</div>
  <h1>Documento en entorno de pruebas</h1>
  <p>Este documento fue generado mediante datos simulados (Faker).<br>
     No existe un archivo físico asociado.</p>
  <p>El documento está correctamente indexado y participa en las búsquedas full-text.</p>
  <span class="badge">Documento simulado · sin archivo real</span>
  <dl class="meta">
    <dt>Código</dt><dd>{code}</dd>
    <dt>Título</dt><dd>{title}</dd>
    <dt>Categoría</dt><dd>{cat}</dd>
    <dt>Departamento</dt><dd>{dept}</dd>
    <dt>Versión</dt><dd>{ver}</dd>
  </dl>
</div>
</body>
</html>"""


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/upsert")
async def upsert_document(metadata: PublicDMSMetadata):
    try:
        doc_data = metadata.model_dump()
        doc_data["sync_date"] = datetime.now(timezone.utc).isoformat()

        if metadata.file_url:
            if _is_seed(metadata.file_url):
                # Doc simulado: genera contenido fake para FTS, no intenta leer archivo
                doc_data["file_name"]               = os.path.basename(metadata.file_url)
                doc_data["extension"]               = "pdf"
                doc_data["mime_type"]               = "application/pdf"
                doc_data["size"]                    = 0
                doc_data["path"]                    = metadata.file_url
                doc_data["document_id"]             = metadata.postgres_id
                doc_data["is_simulated"]            = True
                doc_data["content"]                 = _simulated_content(
                    metadata.code, metadata.title,
                    metadata.category_name, metadata.department_name,
                )
                doc_data["content_extracted"]        = True
                doc_data["content_extraction_error"] = None
                doc_data["metadata"] = {
                    "department":   metadata.department_name,
                    "company_id":   metadata.company_id,
                    "company_name": metadata.company_name,
                    "tags":         [],
                    "version":      metadata.version,
                }
            else:
                file_info = get_file_info(metadata.file_url)
                content, extraction_error = await asyncio.to_thread(extract_text, metadata.file_url)
                doc_data.update(file_info)
                doc_data["document_id"]              = metadata.postgres_id
                doc_data["is_simulated"]             = False
                doc_data["metadata"] = {
                    "department":   metadata.department_name,
                    "company_id":   metadata.company_id,
                    "company_name": metadata.company_name,
                    "tags":         [],
                    "version":      metadata.version,
                }
                doc_data["content"]                  = content[:MAX_CONTENT_CHARS]
                doc_data["content_extracted"]        = extraction_error is None
                doc_data["content_extraction_error"] = extraction_error

        result = await collection.update_one(
            {"postgres_id": metadata.postgres_id},
            {"$set": doc_data},
            upsert=True,
        )

        return {
            "status":      "success",
            "postgres_id": metadata.postgres_id,
            "action":      "updated" if result.matched_count else "indexed",
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/search")
async def search_documents(
    q:     str = Query(..., min_length=2, description="Término de búsqueda"),
    limit: int = Query(default=50, le=500),
):
    try:
        cursor = collection.find(
            {"$text": {"$search": q}},
            {"score": {"$meta": "textScore"}, "postgres_id": 1, "_id": 0},
        ).sort([("score", {"$meta": "textScore"})]).limit(limit)

        results = await cursor.to_list(length=limit)
        ids = [int(r["postgres_id"]) for r in results if r.get("postgres_id")]

        return {"ids": ids}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/file/{name}")
async def get_file(name: str):
    """
    Sirve un archivo indexado desde el volumen compartido.
    Si es un documento simulado (seed/Faker), devuelve una página HTML explicativa.
    """
    doc = await collection.find_one(
        {"file_name": name},
        {"_id": 0, "file_url": 1, "file_name": 1, "mime_type": 1,
         "is_simulated": 1, "title": 1, "code": 1,
         "category_name": 1, "department_name": 1, "version": 1},
    )
    if not doc or not doc.get("file_url"):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    if doc.get("is_simulated") or _is_seed(doc.get("file_url", "")):
        return HTMLResponse(content=_simulated_html(doc))

    real = os.path.realpath(resolve_path(doc["file_url"]))
    root = os.path.realpath(STORAGE_ROOT)
    if real != root and not real.startswith(root + os.sep):
        raise HTTPException(status_code=403, detail="Ruta inválida")
    if not os.path.isfile(real):
        raise HTTPException(status_code=404, detail="Archivo no disponible")

    return FileResponse(
        real,
        media_type=doc.get("mime_type") or "application/octet-stream",
        filename=doc.get("file_name") or name,
    )


@router.get("/download/{name}")
async def download_file(name: str):
    """
    Fuerza descarga del archivo (Content-Disposition: attachment).
    Docs simulados devuelven 422 con mensaje descriptivo.
    """
    doc = await collection.find_one(
        {"file_name": name},
        {"_id": 0, "file_url": 1, "file_name": 1, "mime_type": 1, "is_simulated": 1},
    )
    if not doc or not doc.get("file_url"):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    if doc.get("is_simulated") or _is_seed(doc.get("file_url", "")):
        raise HTTPException(
            status_code=422,
            detail="Documento simulado — no existe archivo físico para descargar. "
                   "Fue generado mediante datos de prueba (Faker).",
        )

    real = os.path.realpath(resolve_path(doc["file_url"]))
    root = os.path.realpath(STORAGE_ROOT)
    if real != root and not real.startswith(root + os.sep):
        raise HTTPException(status_code=403, detail="Ruta inválida")
    if not os.path.isfile(real):
        raise HTTPException(status_code=404, detail="Archivo no disponible")

    return FileResponse(
        real,
        media_type=doc.get("mime_type") or "application/octet-stream",
        filename=doc.get("file_name") or name,
        headers={"Content-Disposition": f'attachment; filename="{doc.get("file_name") or name}"'},
    )


@router.get("/content/{name}")
async def get_content(name: str):
    """
    Texto extraído de un documento indexado. Para docs simulados devuelve el contenido
    generado automáticamente.
    """
    doc = await collection.find_one(
        {"file_name": name},
        {"_id": 0, "title": 1, "extension": 1, "content": 1,
         "content_extracted": 1, "content_extraction_error": 1, "is_simulated": 1},
    )
    if not doc:
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    return {
        "title":       doc.get("title"),
        "extension":   doc.get("extension"),
        "extracted":   bool(doc.get("content_extracted")),
        "error":       doc.get("content_extraction_error"),
        "is_simulated": bool(doc.get("is_simulated")),
        "content":     doc.get("content") or "",
    }

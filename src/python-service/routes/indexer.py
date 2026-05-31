import asyncio
import os
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from database import collection
from extractor import MAX_CONTENT_CHARS, STORAGE_ROOT, extract_text, get_file_info, resolve_path
from models import PublicDMSMetadata

router = APIRouter(prefix="/indexer", tags=["Indexer"])


@router.post("/upsert")
async def upsert_document(metadata: PublicDMSMetadata):
    try:
        doc_data = metadata.model_dump()
        doc_data["sync_date"] = datetime.now(timezone.utc).isoformat()

        if metadata.file_url:
            file_info = get_file_info(metadata.file_url)
            content, extraction_error = await asyncio.to_thread(extract_text, metadata.file_url)
            doc_data.update(file_info)
            doc_data["document_id"] = metadata.postgres_id
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
    Sirve un archivo indexado desde el volumen compartido (sólo lectura).
    Resuelve la ruta por el `file_url` guardado en Mongo (no confía en el nombre
    recibido) y verifica que quede dentro de STORAGE_ROOT (anti path-traversal).
    """
    doc = await collection.find_one(
        {"file_name": name},
        {"_id": 0, "file_url": 1, "file_name": 1, "mime_type": 1},
    )
    if not doc or not doc.get("file_url"):
        raise HTTPException(status_code=404, detail="Documento no encontrado")

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


@router.get("/content/{name}")
async def get_content(name: str):
    """
    Texto extraído de un documento indexado (para previsualizar formatos que el
    navegador no renderiza: ppt, odt, rtf, doc, etc.). Se sirve el contenido ya
    extraído en Mongo; no vuelve a leer el archivo.
    """
    doc = await collection.find_one(
        {"file_name": name},
        {"_id": 0, "title": 1, "extension": 1, "content": 1,
         "content_extracted": 1, "content_extraction_error": 1},
    )
    if not doc:
        raise HTTPException(status_code=404, detail="Documento no encontrado")

    return {
        "title":      doc.get("title"),
        "extension":  doc.get("extension"),
        "extracted":  bool(doc.get("content_extracted")),
        "error":      doc.get("content_extraction_error"),
        "content":    doc.get("content") or "",
    }

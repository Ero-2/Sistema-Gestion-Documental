import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from database import get_collection
from models import (
    MetadataRegisterEvent,
    MetadataUpdateEvent,
    MetadataHistoryEvent,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/metadata", tags=["Metadata Sync"])

# MongoDB collections
file_tags = get_collection("file_tags")
history_log = get_collection("metadata_history")


@router.post("/register", tags=["Metadata"])
async def register_metadata(event: MetadataRegisterEvent):
    """
    Registra metadatos nuevos en MongoDB.
    Se ejecuta cuando documento es aprobado.
    """
    try:
        doc_data = {
            "postgres_id": event.postgres_id,
            "code": event.code,
            "title": event.title,
            "category_name": event.category_name,
            "department_name": event.department_name,
            "file_url": event.file_url,
            "version": event.version,
            "registered_at": datetime.now(timezone.utc),
            "updated_at": datetime.now(timezone.utc),
            "status": "active",
            "metadata": {
                "department": event.department_name,
                "tags": [],
                "version": event.version,
            },
        }

        result = await file_tags.update_one(
            {"postgres_id": event.postgres_id},
            {"$set": doc_data},
            upsert=True,
        )

        # Log en historial
        await history_log.insert_one({
            "postgres_id": event.postgres_id,
            "action": "registered",
            "details": {
                "code": event.code,
                "title": event.title,
            },
            "timestamp": datetime.now(timezone.utc),
        })

        logger.info(f"✓ Metadatos registrados para doc {event.postgres_id}")
        return {
            "status": "success",
            "postgres_id": event.postgres_id,
            "action": "registered",
            "action_type": "upserted" if result.matched_count else "inserted",
        }

    except Exception as e:
        logger.error(f"✗ Error registrando metadatos {event.postgres_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/update", tags=["Metadata"])
async def update_metadata(event: MetadataUpdateEvent):
    """
    Actualiza metadatos en MongoDB.
    """
    try:
        # Aplicar updates
        result = await file_tags.update_one(
            {"postgres_id": event.postgres_id},
            {
                "$set": {
                    **event.updates,
                    "updated_at": datetime.now(timezone.utc),
                }
            },
            upsert=False,
        )

        if result.matched_count == 0:
            logger.warning(f"⚠ Doc {event.postgres_id} no encontrado en MongoDB")
            return {
                "status": "not_found",
                "postgres_id": event.postgres_id,
            }

        # Log en historial
        await history_log.insert_one({
            "postgres_id": event.postgres_id,
            "action": "updated",
            "details": event.updates,
            "timestamp": datetime.now(timezone.utc),
        })

        logger.info(f"✓ Metadatos actualizados para doc {event.postgres_id}")
        return {
            "status": "success",
            "postgres_id": event.postgres_id,
            "action": "updated",
            "modified_count": result.modified_count,
        }

    except Exception as e:
        logger.error(f"✗ Error actualizando metadatos {event.postgres_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/history", tags=["Metadata"])
async def log_metadata_history(event: MetadataHistoryEvent):
    """
    Registra evento en historial de metadatos.
    """
    try:
        history_entry = {
            "postgres_id": event.postgres_id,
            "action": event.action,
            "details": event.details,
            "timestamp": event.timestamp,
        }

        result = await history_log.insert_one(history_entry)

        # Actualizar updated_at en file_tags
        await file_tags.update_one(
            {"postgres_id": event.postgres_id},
            {"$set": {"updated_at": event.timestamp}},
            upsert=False,
        )

        logger.info(f"✓ Evento '{event.action}' registrado para doc {event.postgres_id}")
        return {
            "status": "success",
            "postgres_id": event.postgres_id,
            "action": event.action,
            "history_id": str(result.inserted_id),
        }

    except Exception as e:
        logger.error(f"✗ Error registrando historial {event.postgres_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/history/{postgres_id}", tags=["Metadata"])
async def get_metadata_history(postgres_id: int):
    """
    Obtiene historial de cambios de un documento.
    """
    try:
        history = await history_log.find(
            {"postgres_id": postgres_id}
        ).sort("timestamp", -1).to_list(100)

        return {
            "status": "success",
            "postgres_id": postgres_id,
            "history": history,
            "total": len(history),
        }

    except Exception as e:
        logger.error(f"✗ Error obteniendo historial {postgres_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))

import logging
import os
from datetime import datetime

import asyncpg
from fastapi import APIRouter, HTTPException

from models import (
    DocumentApproveEvent,
    DocumentUpdateEvent,
    DocumentVersionEvent,
    DocumentObsoleteEvent,
)

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/documents", tags=["Documents Sync"])

# PostgreSQL async
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_DB = os.getenv("POSTGRES_DB", "PublicDMS")
POSTGRES_USER = os.getenv("POSTGRES_USER", "postgres")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5432"))


async def get_db_connection():
    """Pool connection to PostgreSQL."""
    return await asyncpg.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
        database=POSTGRES_DB,
    )


@router.post("/approve", tags=["Documents"])
async def approve_document(event: DocumentApproveEvent):
    """
    Inserta documento aprobado en PostgreSQL.
    Se ejecuta cuando doc cambia a estado 3 en SQL Server.
    """
    conn = None
    try:
        conn = await get_db_connection()

        # Upsert: inserta o actualiza
        query = """
            INSERT INTO publicdms.documents (
                id, code, title, category_id, category_name,
                department_id, department_name, version,
                file_url, is_active, effective_date, expiration_date, last_sync
            ) VALUES (
                $1, $2, $3, $4, $5,
                $6, $7, $8,
                $9, $10, $11, $12, NOW()
            )
            ON CONFLICT (id) DO UPDATE SET
                code = EXCLUDED.code,
                title = EXCLUDED.title,
                category_name = EXCLUDED.category_name,
                department_name = EXCLUDED.department_name,
                version = EXCLUDED.version,
                file_url = EXCLUDED.file_url,
                effective_date = EXCLUDED.effective_date,
                expiration_date = EXCLUDED.expiration_date,
                last_sync = NOW();
        """

        await conn.execute(query,
            event.document_id,
            event.code,
            event.title,
            event.category_id,
            event.category_name,
            event.department_id,
            event.department_name,
            event.version,
            event.file_url,
            True,
            event.effective_date,
            event.expiration_date,
        )

        # Log sync
        log_query = """
            INSERT INTO publicdms.sync_log (entity, action, processed_at)
            VALUES ($1, $2, NOW());
        """
        await conn.execute(log_query, f"document_{event.document_id}", "approved")

        logger.info(f"✓ Doc {event.document_id} aprobado en PostgreSQL")
        return {
            "status": "success",
            "document_id": event.document_id,
            "action": "approved",
        }

    except Exception as e:
        logger.error(f"✗ Error aprobando doc {event.document_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            await conn.close()


@router.post("/update", tags=["Documents"])
async def update_document(event: DocumentUpdateEvent):
    """
    Actualiza estado/vigencia de documento.
    """
    conn = None
    try:
        conn = await get_db_connection()

        updates = []
        params = [event.document_id]
        param_idx = 2

        if hasattr(event, "is_active"):
            updates.append(f"is_active = ${param_idx}")
            params.append(event.is_active)
            param_idx += 1

        if event.effective_date:
            updates.append(f"effective_date = ${param_idx}")
            params.append(event.effective_date)
            param_idx += 1

        if event.expiration_date:
            updates.append(f"expiration_date = ${param_idx}")
            params.append(event.expiration_date)
            param_idx += 1

        updates.append("last_sync = NOW()")

        if not updates:
            return {"status": "no_changes"}

        query = f"""
            UPDATE publicdms.documents
            SET {', '.join(updates)}
            WHERE id = $1;
        """

        result = await conn.execute(query, *params)

        # Log
        log_query = """
            INSERT INTO publicdms.sync_log (entity, action, processed_at)
            VALUES ($1, $2, NOW());
        """
        await conn.execute(log_query, f"document_{event.document_id}", "updated")

        logger.info(f"✓ Doc {event.document_id} actualizado")
        return {
            "status": "success",
            "document_id": event.document_id,
            "action": "updated",
        }

    except Exception as e:
        logger.error(f"✗ Error actualizando doc {event.document_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            await conn.close()


@router.post("/version", tags=["Documents"])
async def add_document_version(event: DocumentVersionEvent):
    """
    Registra nueva versión de documento.
    """
    conn = None
    try:
        conn = await get_db_connection()

        query = """
            UPDATE publicdms.documents
            SET version = $1, file_url = $2, last_sync = NOW()
            WHERE id = $3;
        """

        await conn.execute(query,
            event.version,
            event.file_url,
            event.document_id,
        )

        # Log
        log_query = """
            INSERT INTO publicdms.sync_log (entity, action, processed_at)
            VALUES ($1, $2, NOW());
        """
        await conn.execute(log_query,
            f"document_{event.document_id}",
            f"versioned_{event.version}",
        )

        logger.info(f"✓ Doc {event.document_id} versión {event.version} registrada")
        return {
            "status": "success",
            "document_id": event.document_id,
            "version": event.version,
            "action": "versioned",
        }

    except Exception as e:
        logger.error(f"✗ Error versionando doc {event.document_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            await conn.close()


@router.post("/obsolete", tags=["Documents"])
async def obsolete_document(event: DocumentObsoleteEvent):
    """
    Marca documento como obsoleto.
    """
    conn = None
    try:
        conn = await get_db_connection()

        query = """
            UPDATE publicdms.documents
            SET is_active = FALSE, last_sync = NOW()
            WHERE id = $1;
        """

        await conn.execute(query, event.document_id)

        # Log
        log_query = """
            INSERT INTO publicdms.sync_log (entity, action, processed_at)
            VALUES ($1, $2, NOW());
        """
        await conn.execute(log_query, f"document_{event.document_id}", "obsoleted")

        logger.info(f"✓ Doc {event.document_id} marcado como obsoleto")
        return {
            "status": "success",
            "document_id": event.document_id,
            "action": "obsoleted",
            "reason": event.obsolete_reason,
        }

    except Exception as e:
        logger.error(f"✗ Error obsoletando doc {event.document_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if conn:
            await conn.close()

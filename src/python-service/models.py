from pydantic import BaseModel, Field
from typing import Optional, Dict, Any
from datetime import datetime


class DocumentMetadata(BaseModel):
    doc_id: int
    code: str
    title: str
    category_name: str
    department_name: str
    version: str
    file_url: Optional[str] = None
    is_active: bool = True
    indexed_at: datetime = Field(default_factory=datetime.utcnow)
    extra_info: Dict[str, Any] = Field(default_factory=dict)


class PublicDMSMetadata(BaseModel):
    postgres_id: str
    code: str
    title: str
    category_name: str
    department_name: str
    version: str = "1.0"
    is_active: bool = True
    file_url: str = ""


# ── API 1: Documents Events (SQL Server → PostgreSQL) ────────────────────────

class DocumentApproveEvent(BaseModel):
    """Evento: documento aprobado (estado 3)"""
    document_id: int
    code: str
    title: str
    category_id: int
    category_name: str
    department_id: int
    department_name: str
    version: str
    file_url: Optional[str] = None
    effective_date: Optional[datetime] = None
    expiration_date: Optional[datetime] = None


class DocumentUpdateEvent(BaseModel):
    """Evento: cambio de estado/vigencia"""
    document_id: int
    is_active: bool = True
    effective_date: Optional[datetime] = None
    expiration_date: Optional[datetime] = None
    reason: Optional[str] = None


class DocumentVersionEvent(BaseModel):
    """Evento: nueva versión"""
    document_id: int
    version: str
    file_url: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class DocumentObsoleteEvent(BaseModel):
    """Evento: marcar como obsoleto"""
    document_id: int
    obsolete_reason: Optional[str] = None
    effective_at: datetime = Field(default_factory=datetime.utcnow)


# ── API 2: Metadata Events (SQL Server → MongoDB) ────────────────────────────

class MetadataRegisterEvent(BaseModel):
    """Evento: registrar metadatos nuevos"""
    postgres_id: int
    code: str
    title: str
    category_name: str
    department_name: str
    file_url: str
    version: str = "1.0"


class MetadataUpdateEvent(BaseModel):
    """Evento: actualizar metadatos"""
    postgres_id: int
    updates: Dict[str, Any]
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class MetadataHistoryEvent(BaseModel):
    """Evento: registrar en historial"""
    postgres_id: int
    action: str  # "created", "updated", "obsoleted", etc.
    details: Dict[str, Any] = Field(default_factory=dict)
    timestamp: datetime = Field(default_factory=datetime.utcnow)

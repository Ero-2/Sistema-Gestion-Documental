-- PostgreSQL — PublicDMS schema
CREATE SCHEMA IF NOT EXISTS publicdms;

CREATE TABLE IF NOT EXISTS publicdms.categories (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS publicdms.departments (
    id   SERIAL PRIMARY KEY,
    name VARCHAR(150) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS publicdms.documents (
    id              INTEGER PRIMARY KEY,
    company_id      INTEGER,
    company_name    VARCHAR(200),
    code            VARCHAR(50)  NOT NULL,
    title           VARCHAR(500) NOT NULL,
    category_id     INTEGER REFERENCES publicdms.categories(id),
    category_name   VARCHAR(150),
    department_id   INTEGER REFERENCES publicdms.departments(id),
    department_name VARCHAR(150),
    version         VARCHAR(50),
    file_url        TEXT,
    local_file_name VARCHAR(255),
    is_active        BOOLEAN DEFAULT TRUE,
    effective_date   TIMESTAMP,
    expiration_date  TIMESTAMP,
    next_review_date TIMESTAMP,
    last_sync        TIMESTAMPTZ DEFAULT NOW()
);

-- Historial append-only de versiones APROBADAS (X.0). Espejo de DocumentVersion
-- en SQL Server, pero sólo las aprobadas se publican aquí. La vigente es is_current=TRUE;
-- al entrar una nueva X.0 la anterior se marca obsoleta (is_current=FALSE, obsoleted_at).
-- Los borradores X.Y nunca llegan a este read model.
CREATE TABLE IF NOT EXISTS publicdms.document_versions (
    id              SERIAL PRIMARY KEY,
    document_id     INTEGER NOT NULL REFERENCES publicdms.documents(id) ON DELETE CASCADE,
    version         VARCHAR(50)  NOT NULL,
    file_url        TEXT,
    is_current      BOOLEAN NOT NULL DEFAULT TRUE,
    approved_at     TIMESTAMP,
    obsoleted_at    TIMESTAMP,
    effective_date  TIMESTAMP,
    expiration_date TIMESTAMP,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (document_id, version)
);

-- Una sola versión vigente por documento (espejo de UX_DocumentVersions_OneCurrent en SQL).
CREATE UNIQUE INDEX IF NOT EXISTS ux_docver_one_current
    ON publicdms.document_versions (document_id) WHERE is_current = TRUE;

CREATE INDEX IF NOT EXISTS idx_docver_document ON publicdms.document_versions(document_id);

CREATE TABLE IF NOT EXISTS publicdms.sync_log (
    id           SERIAL PRIMARY KEY,
    entity       VARCHAR(100),
    action       VARCHAR(100),
    processed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_docs_company   ON publicdms.documents(company_id);
CREATE INDEX IF NOT EXISTS idx_docs_active    ON publicdms.documents(is_active);
CREATE INDEX IF NOT EXISTS idx_docs_category  ON publicdms.documents(category_id);
CREATE INDEX IF NOT EXISTS idx_docs_dept      ON publicdms.documents(department_id);
CREATE INDEX IF NOT EXISTS idx_docs_last_sync ON publicdms.documents(last_sync);

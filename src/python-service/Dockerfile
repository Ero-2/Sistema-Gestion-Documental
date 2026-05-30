# ── FastAPI + MongoDB ──
# FastAPI no conecta a SQL Server (arquitectura desacoplada por eventos).
# Sin pyodbc / ODBC driver. Solo MongoDB + extracción de archivos del volumen.
FROM python:3.12-slim-bookworm

# antiword/catdoc: extracción de texto de .doc binario antiguo
RUN apt-get update && apt-get install -y \
    antiword catdoc \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

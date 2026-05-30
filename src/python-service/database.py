import os
from urllib.parse import quote_plus

from dotenv import load_dotenv
from motor.motor_asyncio import AsyncIOMotorClient

load_dotenv()

# --- MongoDB (Motor de Búsqueda / Metadatos) ---
# Comunicación desacoplada: FastAPI NO conecta a SQL Server.
# Recibe eventos vía API REST (push desde .NET) y lee archivos del volumen compartido.
_raw_mongo_url = os.getenv("MONGO_URL", "mongodb://localhost:27017/")

def _escape_mongo_url(url: str) -> str:
    """URL-encode credentials in mongodb:// URI (RFC 3986)."""
    if "://" not in url or "@" not in url:
        return url
    scheme, rest = url.split("://", 1)
    userinfo, hostpart = rest.rsplit("@", 1)
    if ":" in userinfo:
        user, passwd = userinfo.split(":", 1)
        userinfo = f"{quote_plus(user)}:{quote_plus(passwd)}"
    return f"{scheme}://{userinfo}@{hostpart}"

MONGO_URL    = _escape_mongo_url(_raw_mongo_url)
mongo_client = AsyncIOMotorClient(MONGO_URL)
db         = mongo_client["dms_metadata"]
collection = db["file_tags"]


def get_collection(name: str):
    return db[name]

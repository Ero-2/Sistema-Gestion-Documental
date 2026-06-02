import csv as _csv
import email as _email
import logging
import mimetypes
import os
import subprocess
from pathlib import Path

logger = logging.getLogger(__name__)

STORAGE_ROOT = os.getenv("DMS_STORAGE_PATH", "/app/uploads")
MAX_CONTENT_CHARS = 500_000

_MIME_MAP = {
    ".pdf":  "application/pdf",
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".doc":  "application/msword",
    ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    ".xls":  "application/vnd.ms-excel",
    ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    ".ppt":  "application/vnd.ms-powerpoint",
    ".txt":  "text/plain",
    ".rtf":  "application/rtf",
    ".odt":  "application/vnd.oasis.opendocument.text",
    ".ods":  "application/vnd.oasis.opendocument.spreadsheet",
    ".odp":  "application/vnd.oasis.opendocument.presentation",
    ".csv":  "text/csv",
    ".html": "text/html",
    ".htm":  "text/html",
    ".xml":  "application/xml",
    ".md":   "text/markdown",
    ".eml":  "message/rfc822",
    ".msg":  "application/vnd.ms-outlook",
}


def resolve_path(file_url: str) -> str:
    return os.path.join(STORAGE_ROOT, file_url.lstrip("/").replace("\\", "/"))


def get_file_info(file_url: str) -> dict:
    if not file_url:
        return {}
    full_path = resolve_path(file_url)
    p = Path(full_path)
    ext_with_dot = p.suffix.lower()          # ".docx"
    ext = ext_with_dot.lstrip(".")           # "docx"
    size = 0
    try:
        size = p.stat().st_size
    except OSError:
        pass
    return {
        "file_name": p.name,
        "extension": ext,
        "mime_type": _MIME_MAP.get(ext_with_dot) or mimetypes.guess_type(str(p))[0] or "application/octet-stream",
        "size":      size,
        "path":      file_url,
    }


def extract_text(file_url: str) -> tuple[str, str | None]:
    """Returns (text, error_or_None). Never raises."""
    if not file_url:
        return "", "no file_url provided"
    full_path = resolve_path(file_url)
    if not os.path.isfile(full_path):
        return "", f"file not found: {full_path}"
    ext = Path(full_path).suffix.lower()
    try:
        fn = _EXTRACTORS.get(ext)
        if fn is None:
            return "", f"unsupported extension: {ext}"
        return fn(full_path), None
    except Exception as exc:
        logger.warning("Text extraction failed [%s]: %s", file_url, exc)
        return "", str(exc)


# ── Extractors ────────────────────────────────────────────────

def _pdf(path: str) -> str:
    import fitz
    with fitz.open(path) as doc:
        return "\n".join(page.get_text() for page in doc)


def _docx(path: str) -> str:
    from docx import Document
    doc = Document(path)
    return "\n".join(p.text for p in doc.paragraphs if p.text.strip())


def _doc(path: str) -> str:
    result = subprocess.run(
        ["antiword", path], capture_output=True, timeout=30)
    return result.stdout.decode("utf-8", errors="ignore")


def _xlsx(path: str) -> str:
    from openpyxl import load_workbook
    wb = load_workbook(path, read_only=True, data_only=True)
    parts = []
    for ws in wb.worksheets:
        for row in ws.iter_rows(values_only=True):
            line = " ".join(str(c) for c in row if c is not None)
            if line.strip():
                parts.append(line)
    return "\n".join(parts)


def _xls(path: str) -> str:
    import xlrd
    wb = xlrd.open_workbook(path)
    parts = []
    for sheet in wb.sheets():
        for row in range(sheet.nrows):
            line = " ".join(str(sheet.cell_value(row, col)) for col in range(sheet.ncols))
            if line.strip():
                parts.append(line)
    return "\n".join(parts)


def _pptx(path: str) -> str:
    from pptx import Presentation
    prs = Presentation(path)
    parts = []
    for slide in prs.slides:
        for shape in slide.shapes:
            if hasattr(shape, "text") and shape.text.strip():
                parts.append(shape.text)
    return "\n".join(parts)


def _ppt(path: str) -> str:
    result = subprocess.run(
        ["catppt", path], capture_output=True, timeout=30)
    return result.stdout.decode("utf-8", errors="ignore")


def _txt(path: str) -> str:
    import chardet
    with open(path, "rb") as f:
        raw = f.read()
    enc = chardet.detect(raw).get("encoding") or "utf-8"
    return raw.decode(enc, errors="ignore")


def _rtf(path: str) -> str:
    from striprtf.striprtf import rtf_to_text
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        return rtf_to_text(f.read())


def _odf(path: str) -> str:
    from odf.opendocument import load
    from odf import teletype
    from odf.text import P
    doc = load(path)
    parts = []
    for para in doc.body.getElementsByType(P):
        t = teletype.extractText(para)
        if t.strip():
            parts.append(t)
    return "\n".join(parts)


def _csv(path: str) -> str:
    parts = []
    with open(path, "r", encoding="utf-8", errors="ignore", newline="") as f:
        for row in _csv.reader(f):
            line = " ".join(row)
            if line.strip():
                parts.append(line)
    return "\n".join(parts)


def _html(path: str) -> str:
    from bs4 import BeautifulSoup
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        soup = BeautifulSoup(f.read(), "lxml")
    return soup.get_text(separator="\n", strip=True)


def _xml(path: str) -> str:
    from lxml import etree
    tree = etree.parse(path)
    return " ".join(tree.getroot().itertext()).strip()


def _md(path: str) -> str:
    return _txt(path)


def _eml(path: str) -> str:
    with open(path, "rb") as f:
        msg = _email.message_from_binary_file(f, policy=_email.policy.default)
    parts = [msg.get("subject", ""), msg.get("from", "")]
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain":
                try:
                    parts.append(part.get_content())
                except Exception:
                    pass
    else:
        try:
            parts.append(msg.get_content())
        except Exception:
            pass
    return "\n".join(p for p in parts if p)


def _msg(path: str) -> str:
    import extract_msg
    with extract_msg.Message(path) as msg:
        parts = [msg.subject or "", msg.sender or "", msg.body or ""]
    return "\n".join(p for p in parts if p)


# ── Metadata extraction ───────────────────────────────────────

def _clean(d: dict) -> dict:
    """Elimina None, strings vacíos y 0 del dict de metadatos."""
    return {k: v for k, v in d.items() if v not in (None, "", 0, "0")}


def _meta_pdf(path: str) -> dict:
    import fitz
    with fitz.open(path) as doc:
        m = doc.metadata or {}
        return _clean({
            "author":    m.get("author"),
            "title":     m.get("title"),
            "subject":   m.get("subject"),
            "keywords":  m.get("keywords"),
            "creator":   m.get("creator"),
            "producer":  m.get("producer"),
            "created":   m.get("creationDate"),
            "modified":  m.get("modDate"),
            "pages":     doc.page_count,
            "encrypted": doc.is_encrypted or None,
        })


def _cp_str(cp, attr: str):
    v = getattr(cp, attr, None)
    return str(v).strip() if v else None

def _cp_dt(cp, attr: str):
    v = getattr(cp, attr, None)
    return v.isoformat() if v else None

def _meta_docx(path: str) -> dict:
    from docx import Document
    doc = Document(path)
    cp = doc.core_properties
    text = " ".join(p.text for p in doc.paragraphs if p.text.strip())
    words = len(text.split()) if text else None
    return _clean({
        "author":           _cp_str(cp, "author"),
        "title":            _cp_str(cp, "title"),
        "subject":          _cp_str(cp, "subject"),
        "keywords":         _cp_str(cp, "keywords"),
        "description":      _cp_str(cp, "description"),
        "last_modified_by": _cp_str(cp, "last_modified_by"),
        "created":          _cp_dt(cp,  "created"),
        "modified":         _cp_dt(cp,  "modified"),
        "revision":         getattr(cp, "revision", None),
        "language":         _cp_str(cp, "language"),
        "category":         _cp_str(cp, "category"),
        "paragraphs":       len(doc.paragraphs) if doc.paragraphs else None,
        "words":            words,
    })


def _meta_xlsx_xlsm(path: str) -> dict:
    from openpyxl import load_workbook
    wb = load_workbook(path, read_only=True, data_only=True)
    cp = wb.properties
    names = wb.sheetnames
    return _clean({
        "creator":          _cp_str(cp, "creator"),
        "title":            _cp_str(cp, "title"),
        "subject":          _cp_str(cp, "subject"),
        "keywords":         _cp_str(cp, "keywords"),
        "description":      _cp_str(cp, "description"),
        "last_modified_by": _cp_str(cp, "lastModifiedBy"),
        "created":          _cp_dt(cp,  "created"),
        "modified":         _cp_dt(cp,  "modified"),
        "category":         _cp_str(cp, "category"),
        "sheets":           len(names),
        "sheet_names":      ", ".join(names) if names else None,
    })


def _meta_xls(path: str) -> dict:
    import xlrd
    wb = xlrd.open_workbook(path)
    return _clean({
        "sheets":      wb.nsheets,
        "sheet_names": ", ".join(wb.sheet_names()),
    })


def _meta_pptx(path: str) -> dict:
    from pptx import Presentation
    prs = Presentation(path)
    cp = prs.core_properties
    return _clean({
        "author":           _cp_str(cp, "author"),
        "title":            _cp_str(cp, "title"),
        "subject":          _cp_str(cp, "subject"),
        "keywords":         _cp_str(cp, "keywords"),
        "description":      _cp_str(cp, "description"),
        "last_modified_by": _cp_str(cp, "last_modified_by"),
        "created":          _cp_dt(cp,  "created"),
        "modified":         _cp_dt(cp,  "modified"),
        "language":         _cp_str(cp, "language"),
        "slides":           len(prs.slides),
    })


def _meta_image(path: str) -> dict:
    from PIL import Image
    from PIL.ExifTags import TAGS
    _WANT = {"DateTime", "DateTimeOriginal", "DateTimeDigitized",
             "Make", "Model", "Software", "Artist", "Copyright",
             "ImageDescription", "XResolution", "YResolution"}
    with Image.open(path) as img:
        result: dict = {
            "dimensions": f"{img.width}x{img.height}",
            "color_mode": img.mode,
            "format":     img.format,
        }
        try:
            dpi = img.info.get("dpi")
            if dpi:
                result["dpi"] = f"{round(dpi[0])}x{round(dpi[1])}"
        except Exception:
            pass
        try:
            exif_raw = img._getexif()
            if exif_raw:
                for tag_id, value in exif_raw.items():
                    tag = TAGS.get(tag_id, "")
                    if tag in _WANT and isinstance(value, (str, int, float)):
                        result[tag.lower()] = str(value).strip()
        except Exception:
            pass
    return _clean(result)


def _meta_txt(path: str) -> dict:
    with open(path, "rb") as f:
        raw = f.read(65536)  # muestra para detección
    import chardet
    enc = chardet.detect(raw).get("encoding") or "utf-8"
    full = raw.decode(enc, errors="ignore")
    return _clean({
        "encoding": enc,
        "lines":    full.count("\n") + 1,
        "words":    len(full.split()),
        "chars":    len(full),
    })


def _meta_csv(path: str) -> dict:
    import csv as _csv_mod
    with open(path, "r", encoding="utf-8", errors="ignore", newline="") as f:
        rows = list(_csv_mod.reader(f))
    cols = max((len(r) for r in rows), default=0)
    return _clean({
        "rows":    len(rows),
        "columns": cols,
        "headers": ", ".join(rows[0]) if rows else None,
    })


def _meta_odf(path: str) -> dict:
    from odf.opendocument import load
    from odf.namespaces import METANS
    doc = load(path)
    result: dict = {}
    try:
        meta_el = doc.meta
        for child in meta_el.childNodes:
            tag = getattr(child, "qname", (None, ""))[1]
            text = getattr(child, "firstChild", None)
            if tag and text:
                val = str(text).strip()
                if val:
                    result[tag.replace("-", "_")] = val
    except Exception:
        pass
    return _clean(result)


def _meta_eml(path: str) -> dict:
    import email as _email_mod
    with open(path, "rb") as f:
        msg = _email_mod.message_from_binary_file(f, policy=_email_mod.policy.default)
    attachments = sum(
        1 for part in msg.walk()
        if part.get_content_disposition() == "attachment"
    )
    return _clean({
        "from":        str(msg.get("from",    "") or ""),
        "to":          str(msg.get("to",      "") or ""),
        "subject":     str(msg.get("subject", "") or ""),
        "date":        str(msg.get("date",    "") or ""),
        "cc":          str(msg.get("cc",      "") or ""),
        "attachments": attachments or None,
    })


def _meta_msg(path: str) -> dict:
    import extract_msg
    with extract_msg.Message(path) as msg:
        return _clean({
            "from":    str(msg.sender  or ""),
            "to":      str(msg.to      or ""),
            "subject": str(msg.subject or ""),
            "date":    str(msg.date    or ""),
        })


_META_EXTRACTORS: dict = {
    ".pdf":  _meta_pdf,
    ".docx": _meta_docx,
    ".doc":  _meta_docx,   # python-docx también lee .doc moderno
    ".xlsx": _meta_xlsx_xlsm,
    ".xlsm": _meta_xlsx_xlsm,
    ".xls":  _meta_xls,
    ".pptx": _meta_pptx,
    ".ppt":  _meta_pptx,   # python-pptx puede leer algunos .ppt
    ".odt":  _meta_odf,
    ".ods":  _meta_odf,
    ".odp":  _meta_odf,
    ".png":  _meta_image,
    ".jpg":  _meta_image,
    ".jpeg": _meta_image,
    ".gif":  _meta_image,
    ".webp": _meta_image,
    ".bmp":  _meta_image,
    ".tiff": _meta_image,
    ".tif":  _meta_image,
    ".txt":  _meta_txt,
    ".md":   _meta_txt,
    ".csv":  _meta_csv,
    ".log":  _meta_txt,
    ".xml":  _meta_txt,
    ".json": _meta_txt,
    ".eml":  _meta_eml,
    ".msg":  _meta_msg,
}


def extract_file_metadata(file_url: str) -> dict:
    """
    Extrae metadatos internos del archivo (autor, fechas, páginas, etc.).
    Retorna dict vacío si el formato no es soportado o hay error. Nunca lanza.
    """
    if not file_url:
        return {}
    full_path = resolve_path(file_url)
    if not os.path.isfile(full_path):
        return {}
    ext = Path(full_path).suffix.lower()
    try:
        fn = _META_EXTRACTORS.get(ext)
        if fn is None:
            return {}
        return fn(full_path) or {}
    except Exception as exc:
        logger.warning("File metadata extraction failed [%s]: %s", file_url, exc)
        return {}


# ── Dispatch table ────────────────────────────────────────────
_EXTRACTORS = {
    ".pdf":  _pdf,
    ".docx": _docx,
    ".doc":  _doc,
    ".xlsx": _xlsx,
    ".xls":  _xls,
    ".pptx": _pptx,
    ".ppt":  _ppt,
    ".txt":  _txt,
    ".rtf":  _rtf,
    ".odt":  _odf,
    ".ods":  _odf,
    ".odp":  _odf,
    ".csv":  _csv,
    ".html": _html,
    ".htm":  _html,
    ".xml":  _xml,
    ".md":   _md,
    ".eml":  _eml,
    ".msg":  _msg,
}

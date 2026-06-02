import os
import httpx
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Header
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
import jwt

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/auth", tags=["Auth"])

# Config
DOTNET_API_URL = os.getenv("DOTNET_API_URL", "http://dotnet:8080")
JWT_SECRET = os.getenv("JWT_SECRET", "")
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 8


class LoginRequest(BaseModel):
    email: str
    password: str


class LoginResponse(BaseModel):
    access_token: str
    token_type: str
    user_id: str
    user_name: str
    email: str
    roles: list[str]
    expires_in: int


@router.post("/login", response_model=LoginResponse)
async def login(req: LoginRequest):
    """
    Validar credenciales contra .NET (SQL Server).
    Retorna JWT token para acceso a FastAPI.
    """
    if not JWT_SECRET:
        logger.error("JWT_SECRET not configured")
        raise HTTPException(status_code=500, detail="Auth service misconfigured")

    try:
        # Llamar a .NET para validar credenciales
        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.post(
                f"{DOTNET_API_URL}/api/v1/auth/validate",
                json={"email": req.email, "password": req.password}
            )

        if response.status_code == 401:
            logger.warning(f"Login failed for {req.email}")
            raise HTTPException(status_code=401, detail="Invalid credentials")

        if response.status_code != 200:
            logger.error(f"Auth service returned {response.status_code}")
            raise HTTPException(status_code=500, detail="Authentication service error")

        user_data = response.json()

        # Generar JWT
        now = datetime.now(timezone.utc)
        expires_at = now + timedelta(hours=JWT_EXPIRATION_HOURS)
        expires_in = int(JWT_EXPIRATION_HOURS * 3600)

        payload = {
            "sub": user_data["userId"],
            "email": req.email,
            "name": user_data["userName"],
            "roles": user_data.get("roles", []),
            "iat": now,
            "exp": expires_at
        }

        token = jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

        logger.info(f"Login successful for {req.email}")

        return LoginResponse(
            access_token=token,
            token_type="bearer",
            user_id=user_data["userId"],
            user_name=user_data["userName"],
            email=req.email,
            roles=user_data.get("roles", []),
            expires_in=expires_in
        )

    except httpx.TimeoutException:
        logger.error("Auth service timeout")
        raise HTTPException(status_code=503, detail="Auth service unavailable")
    except Exception as e:
        logger.error(f"Login error: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")


@router.get("/me")
async def get_current_user(authorization: Optional[str] = Header(default=None)):
    """
    Obtener información del usuario actual desde token JWT.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing or invalid token")

    token = authorization.replace("Bearer ", "")

    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return {
            "user_id": payload.get("sub"),
            "email": payload.get("email"),
            "user_name": payload.get("name"),
            "roles": payload.get("roles", [])
        }
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")


@router.get("/login", response_class=HTMLResponse)
async def login_page():
    """Página de login para FastAPI — consola dms://auth."""
    return """<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>dms://auth</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600&display=swap" rel="stylesheet">
<style>
:root {
  /* surfaces — cool slate, whisper-quiet elevation (idéntico a /search) */
  --bg:        #0e1217;
  --surface-1: #141a21;
  --surface-2: #19212a;
  /* inputs — inset, un punto más oscuros que su contenedor */
  --field:     #10151b;
  /* text hierarchy */
  --tx-1: #d7dee5;
  --tx-2: #9aa7b2;
  --tx-3: #6b7682;
  --tx-4: #4a535c;
  /* single accent — the live index signal */
  --accent: #4fd1c5;
  --accent-dim: rgba(79,209,197,0.14);
  /* semantic */
  --vigente: #5fb89a;
  --inactivo: #c79a55;
  --danger: #e0727a;
  --danger-dim: rgba(224,114,122,0.12);
  /* borders — low-opacity cool, disappear until needed */
  --bd-1: rgba(200,215,225,0.08);
  --bd-2: rgba(200,215,225,0.14);
  --bd-3: rgba(200,215,225,0.22);
  --mono: 'IBM Plex Mono', ui-monospace, monospace;
  --sans: 'IBM Plex Sans', system-ui, sans-serif;
}
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { height: 100%; }
body {
  background: var(--bg);
  color: var(--tx-1);
  font-family: var(--sans);
  font-size: 14px;
  line-height: 1.5;
  -webkit-font-smoothing: antialiased;
  display: flex; align-items: center; justify-content: center;
  /* retícula técnica casi imperceptible — textura de consola */
  background-image:
    linear-gradient(var(--bd-1) 1px, transparent 1px),
    linear-gradient(90deg, var(--bd-1) 1px, transparent 1px);
  background-size: 44px 44px;
  background-position: center;
}
::selection { background: var(--accent-dim); }

.panel {
  width: 100%; max-width: 380px; margin: 24px;
  background: var(--surface-1);
  border: 1px solid var(--bd-2);
  border-radius: 6px;
  overflow: hidden;
}

/* ── Cabecera de la consola ───────────────────────────── */
.panel-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 13px 18px;
  border-bottom: 1px solid var(--bd-2);
  background: var(--bg);
}
.brand { font-family: var(--mono); font-size: 14px; font-weight: 600; letter-spacing: -0.01em; }
.brand .scheme { color: var(--accent); }
.brand .path { color: var(--tx-3); }
.led-line { display: flex; align-items: center; gap: 7px; font-family: var(--mono); font-size: 11px; color: var(--tx-3); }
.led { width: 6px; height: 6px; border-radius: 50%; background: var(--inactivo); transition: background .2s, box-shadow .2s; }
.led.on { background: var(--vigente); box-shadow: 0 0 6px rgba(95,184,154,0.6); }

/* ── Cuerpo ───────────────────────────────────────────── */
.panel-body { padding: 26px 22px 22px; }
.intro { font-family: var(--mono); font-size: 11px; color: var(--tx-4); margin-bottom: 22px; }
.intro .caret { color: var(--accent); }

.field { margin-bottom: 16px; }
.field label {
  display: block; font-family: var(--mono); font-size: 10px;
  text-transform: uppercase; letter-spacing: 0.1em; color: var(--tx-3);
  margin-bottom: 7px;
}
.field input {
  width: 100%; height: 42px; padding: 0 13px;
  background: var(--field); color: var(--tx-1);
  font-family: var(--mono); font-size: 13px;
  border: 1px solid var(--bd-2); border-radius: 5px;
  outline: none; transition: border-color .12s ease;
}
.field input::placeholder { color: var(--tx-4); }
.field input:focus { border-color: var(--accent); }

.btn-auth {
  width: 100%; height: 44px; margin-top: 6px;
  display: flex; align-items: center; justify-content: center; gap: 8px;
  font-family: var(--mono); font-size: 13px; font-weight: 500; letter-spacing: 0.02em;
  color: var(--accent); background: var(--accent-dim);
  border: 1px solid var(--accent); border-radius: 5px;
  cursor: pointer; transition: background .12s ease, opacity .12s ease;
}
.btn-auth:hover:not(:disabled) { background: rgba(79,209,197,0.22); }
.btn-auth:disabled { opacity: 0.55; cursor: not-allowed; }
.btn-auth .arrow { transition: transform .12s ease; }
.btn-auth:hover:not(:disabled) .arrow { transform: translateX(3px); }

/* ── Línea de estado (feedback de consola) ───────────── */
.status {
  font-family: var(--mono); font-size: 11px; min-height: 18px;
  margin-top: 16px; color: var(--tx-3);
}
.status.err { color: var(--danger); }
.status.err::before { content: '! '; }
.status.run::before { content: '> '; color: var(--accent); }
.cursor { display: inline-block; width: 7px; height: 13px; background: var(--accent); vertical-align: -2px; margin-left: 2px; animation: blink 1s step-end infinite; }
@keyframes blink { 50% { opacity: 0; } }

/* ── Pie ──────────────────────────────────────────────── */
.panel-foot {
  padding: 12px 18px;
  border-top: 1px solid var(--bd-1);
  font-family: var(--mono); font-size: 10px; color: var(--tx-4);
  display: flex; align-items: center; justify-content: space-between;
}
.panel-foot .dot { color: var(--bd-3); }
</style>
</head>
<body>

<form class="panel" id="loginForm" autocomplete="on">
  <div class="panel-head">
    <div class="brand"><span class="scheme">dms://</span><span class="path">auth</span></div>
    <div class="led-line"><span class="led" id="led"></span><span id="ledTxt">en espera</span></div>
  </div>

  <div class="panel-body">
    <div class="intro"><span class="caret">&gt;</span> identifícate para acceder al índice documental</div>

    <div class="field">
      <label for="email">credencial</label>
      <input type="email" id="email" name="email" required spellcheck="false"
             autocomplete="username" placeholder="usuario@qualitydms.local">
    </div>

    <div class="field">
      <label for="password">clave</label>
      <input type="password" id="password" name="password" required
             autocomplete="current-password" placeholder="••••••••">
    </div>

    <button type="submit" class="btn-auth" id="submitBtn">
      <span id="btnTxt">autenticar</span><span class="arrow">&rsaquo;</span>
    </button>

    <div class="status" id="status"></div>
  </div>

  <div class="panel-foot">
    <span>jwt · 8h</span>
    <span class="dot">·</span>
    <span>validación: servidor central</span>
  </div>
</form>

<script>
const form   = document.getElementById('loginForm');
const btn    = document.getElementById('submitBtn');
const btnTxt = document.getElementById('btnTxt');
const status = document.getElementById('status');
const led    = document.getElementById('led');
const ledTxt = document.getElementById('ledTxt');

function setStatus(msg, cls) {
  status.className = 'status' + (cls ? ' ' + cls : '');
  status.innerHTML = msg;
}

form.addEventListener('submit', async (e) => {
  e.preventDefault();
  const email = document.getElementById('email').value.trim();
  const password = document.getElementById('password').value;

  btn.disabled = true;
  btnTxt.textContent = 'verificando';
  led.classList.remove('on'); ledTxt.textContent = 'validando';
  setStatus('validando credenciales <span class="cursor"></span>', 'run');

  try {
    const res = await fetch('/auth/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password })
    });
    const data = await res.json();

    if (res.ok) {
      localStorage.setItem('access_token', data.access_token);
      localStorage.setItem('user_name', data.user_name);
      localStorage.setItem('roles', JSON.stringify(data.roles));
      led.classList.add('on'); ledTxt.textContent = 'autenticado';
      setStatus('sesión establecida — abriendo índice <span class="cursor"></span>', 'run');
      setTimeout(() => { window.location.href = '/search'; }, 350);
    } else {
      ledTxt.textContent = 'rechazado';
      setStatus(data.detail || 'credenciales inválidas', 'err');
      btn.disabled = false; btnTxt.textContent = 'autenticar';
    }
  } catch (err) {
    ledTxt.textContent = 'sin conexión';
    setStatus('error de conexión — ' + err.message, 'err');
    btn.disabled = false; btnTxt.textContent = 'autenticar';
  }
});
</script>

</body>
</html>"""

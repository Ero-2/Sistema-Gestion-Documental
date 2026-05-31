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
    """Página de login para FastAPI."""
    return """<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login — DMS Search Engine</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
        }
        .login-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
            width: 100%;
            max-width: 400px;
            padding: 40px;
        }
        .login-header {
            text-align: center;
            margin-bottom: 30px;
        }
        .login-header h1 {
            font-size: 28px;
            font-weight: 700;
            color: #333;
            margin-bottom: 5px;
        }
        .login-header p {
            color: #999;
            font-size: 14px;
        }
        .form-control {
            border-radius: 8px;
            border: 1px solid #ddd;
            padding: 12px 15px;
            font-size: 14px;
            margin-bottom: 15px;
        }
        .form-control:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 3px rgba(102, 126, 234, 0.1);
        }
        .btn-login {
            width: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 12px;
            border-radius: 8px;
            font-weight: 600;
            font-size: 15px;
            cursor: pointer;
            transition: transform 0.2s;
        }
        .btn-login:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 20px rgba(102, 126, 234, 0.3);
            color: white;
        }
        .btn-login:disabled {
            opacity: 0.7;
            cursor: not-allowed;
            transform: none;
        }
        .alert-danger {
            border-radius: 8px;
            margin-bottom: 20px;
            border: none;
            background: #f8d7da;
            color: #721c24;
        }
        .spinner-border {
            display: none;
            width: 16px;
            height: 16px;
            margin-right: 8px;
        }
        .spinner-border.show {
            display: inline-block;
        }
    </style>
</head>
<body>

<div class="login-card">
    <div class="login-header">
        <h1>DMS Search</h1>
        <p>Motor de Búsqueda Documental</p>
    </div>

    <div id="errorAlert"></div>

    <form id="loginForm">
        <div class="mb-3">
            <label for="email" class="form-label">Email</label>
            <input type="email" class="form-control" id="email" name="email" required placeholder="usuario@example.com">
        </div>

        <div class="mb-3">
            <label for="password" class="form-label">Contraseña</label>
            <input type="password" class="form-control" id="password" name="password" required placeholder="••••••••">
        </div>

        <button type="submit" class="btn btn-login" id="submitBtn">
            <span class="spinner-border" role="status" aria-hidden="true"></span>
            Iniciar Sesión
        </button>
    </form>

    <div style="text-align: center; margin-top: 20px; color: #999; font-size: 12px;">
        <p>Autenticación centralizada.</p>
        <p>Credenciales validadas por servidor central.</p>
    </div>
</div>

<script>
document.getElementById('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault();

    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;
    const submitBtn = document.getElementById('submitBtn');
    const spinner = submitBtn.querySelector('.spinner-border');
    const errorAlert = document.getElementById('errorAlert');

    // Limpiar errores
    errorAlert.innerHTML = '';

    // Mostrar spinner
    submitBtn.disabled = true;
    spinner.classList.add('show');

    try {
        const response = await fetch('/auth/login', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ email, password })
        });

        const data = await response.json();

        if (response.ok) {
            // Login exitoso - guardar token
            localStorage.setItem('access_token', data.access_token);
            localStorage.setItem('user_name', data.user_name);
            localStorage.setItem('roles', JSON.stringify(data.roles));
            window.location.href = '/search';
        } else {
            // Error
            errorAlert.innerHTML = `<div class="alert alert-danger alert-dismissible fade show" role="alert">
                ${data.detail || 'Error en autenticación'}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>`;
            submitBtn.disabled = false;
            spinner.classList.remove('show');
        }
    } catch (error) {
        errorAlert.innerHTML = `<div class="alert alert-danger alert-dismissible fade show" role="alert">
            Error de conexión: ${error.message}
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>`;
        submitBtn.disabled = false;
        spinner.classList.remove('show');
    }
});
</script>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

</body>
</html>"""

# ============================================================
#  DMS Setup — Windows PowerShell
#  Uso: .\setup.ps1
# ============================================================

$ErrorActionPreference = "Stop"

function Write-Step  { param($msg) Write-Host "`n  $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "       $msg" -ForegroundColor Gray }

# ── Banner ────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ██████╗ ███╗   ███╗███████╗" -ForegroundColor Cyan
Write-Host "  ██╔══██╗████╗ ████║██╔════╝" -ForegroundColor Cyan
Write-Host "  ██║  ██║██╔████╔██║███████╗" -ForegroundColor Cyan
Write-Host "  ██║  ██║██║╚██╔╝██║╚════██║" -ForegroundColor Cyan
Write-Host "  ██████╔╝██║ ╚═╝ ██║███████║" -ForegroundColor Cyan
Write-Host "  ╚═════╝ ╚═╝     ╚═╝╚══════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Sistema Integral de Gestión Documental" -ForegroundColor White
Write-Host "  Enterprise Multi-Stack Platform  •  v1.0.0" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $('─' * 52)" -ForegroundColor DarkGray
Write-Host ""

# ── Verificar Docker ──────────────────────────────────────────
Write-Step "Verificando dependencias..."
Write-Host ""

try {
    $null = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Ok "Docker detectado"
} catch {
    Write-Err "Docker no está corriendo. Inicia Docker Desktop primero."
    exit 1
}

$composeCmd = $null
$null = docker compose version 2>&1
if ($LASTEXITCODE -eq 0) {
    $composeCmd = "docker compose"
    Write-Ok "Docker Compose V2"
} else {
    $null = docker-compose version 2>&1
    if ($LASTEXITCODE -eq 0) {
        $composeCmd = "docker-compose"
        Write-Ok "docker-compose (legacy)"
    } else {
        Write-Err "Docker Compose no encontrado. Actualiza Docker Desktop."
        exit 1
    }
}

Write-Ok "Git $(git --version 2>$null | Select-String -Pattern '\d[\d.]+' | ForEach-Object { $_.Matches[0].Value })"

# ── .env existente? ───────────────────────────────────────────
$generarEnv = $true

if (Test-Path ".env") {
    Write-Host ""
    Write-Warn "Ya existe un archivo .env."
    $resp = Read-Host "       Sobreescribir? (s/N)"
    if ($resp -notmatch "^[sS]$") {
        Write-Info "Usando .env existente."
        $generarEnv = $false
    }
}

# ── Contraseña maestra ────────────────────────────────────────
if ($generarEnv) {
    Write-Step "Contraseña maestra"
    Write-Host ""
    Write-Host "       Misma contraseña para SQL Server, PostgreSQL y MongoDB." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "       Requisitos (política SQL Server):" -ForegroundColor DarkGray
    Write-Host "         • Mínimo 8 caracteres" -ForegroundColor DarkGray
    Write-Host "         • Al menos una mayúscula  (A-Z)" -ForegroundColor DarkGray
    Write-Host "         • Al menos una minúscula  (a-z)" -ForegroundColor DarkGray
    Write-Host "         • Al menos un dígito      (0-9)" -ForegroundColor DarkGray
    Write-Host "         • Al menos un carácter especial  (!@#`$%)" -ForegroundColor DarkGray
    Write-Host "         • Ejemplo válido: MiPass1!" -ForegroundColor DarkGray
    Write-Host ""

    $MASTER_PASS = ""
    do {
        $pass1 = Read-Host "  Contraseña" -AsSecureString
        $pass2 = Read-Host "  Confirmar " -AsSecureString

        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

        if ($p1 -ne $p2) {
            Write-Warn "Las contraseñas no coinciden. Intenta de nuevo."
            Write-Host ""
            continue
        }

        $valid = $p1.Length -ge 8 `
            -and $p1 -cmatch '[A-Z]' `
            -and $p1 -cmatch '[a-z]' `
            -and $p1 -match  '[0-9]' `
            -and $p1 -match  '[^a-zA-Z0-9]'

        if (-not $valid) {
            Write-Warn "No cumple los requisitos. Intenta de nuevo."
            Write-Host ""
            continue
        }

        $MASTER_PASS = $p1

    } while ([string]::IsNullOrEmpty($MASTER_PASS))

    # Generar secrets aleatorios
    $apiKeyBytes = New-Object byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($apiKeyBytes)
    $API_KEY = ($apiKeyBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    $jwtBytes = New-Object byte[] 48
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($jwtBytes)
    $JWT_SECRET = [Convert]::ToBase64String($jwtBytes)

    $envContent = @"
# Generado por setup.ps1 — $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# NO commitear este archivo.

# ── SQL Server ──────────────────────────────
MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS

# ── PostgreSQL ───────────────────────────────
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS

# ── MongoDB ──────────────────────────────────
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS

# ── FastAPI ───────────────────────────────────
FASTAPI_API_KEY=$API_KEY
FASTAPI_URL=http://fastapi:8000

# ── JWT ───────────────────────────────────────
JWT_SECRET=$JWT_SECRET

# ── Sync ──────────────────────────────────────
SYNC_INTERVAL_SECONDS=30
"@

    Set-Content -Path ".env" -Value $envContent -Encoding UTF8
    Write-Host ""
    Write-Ok ".env generado"
    Write-Ok "SQL Server / PostgreSQL / MongoDB  → misma contraseña maestra"
    Write-Ok "FastAPI API key  (256-bit random)"
    Write-Ok "JWT secret       (384-bit random)"
}

# ── Levantar contenedores ─────────────────────────────────────
Write-Step "Construyendo e iniciando contenedores..."
Write-Host ""
Write-Info "La primera vez puede tardar 5–15 minutos."
Write-Host ""

Invoke-Expression "$composeCmd up -d --build"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Err "Falló al levantar contenedores."
    Write-Info "Revisa los logs: $composeCmd logs"
    exit 1
}

Write-Host ""
Write-Ok "Contenedores iniciados"

# ── Healthchecks ──────────────────────────────────────────────
function Wait-Container {
    param(
        [string]$Name,
        [string]$Container,
        [int]$TimeoutSecs = 120,
        [bool]$NeedsHealth = $true
    )

    Write-Host "  [~] Esperando $Name..." -NoNewline -ForegroundColor Yellow
    $elapsed = 0
    $interval = 5

    while ($elapsed -lt $TimeoutSecs) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        if ($NeedsHealth) {
            $status = docker inspect --format="{{.State.Health.Status}}" $Container 2>$null
            if ($status -eq "healthy") {
                Write-Host "`r  [OK] $Name healthy ($($elapsed)s)          " -ForegroundColor Green
                return $true
            }
            if ($status -eq "unhealthy") {
                Write-Host "`r  [X]  $Name unhealthy — revisa: docker logs $Container" -ForegroundColor Red
                return $false
            }
        } else {
            $state = docker inspect --format="{{.State.Status}}" $Container 2>$null
            if ($state -eq "running") {
                Write-Host "`r  [OK] $Name running ($($elapsed)s)          " -ForegroundColor Green
                return $true
            }
            if ($state -eq "exited" -or $state -eq "dead") {
                Write-Host "`r  [X]  $Name crashed — revisa: docker logs $Container" -ForegroundColor Red
                return $false
            }
        }
    }

    Write-Host "`r  [!]  $Name timeout ($($TimeoutSecs)s) — revisa: docker logs $Container" -ForegroundColor Yellow
    return $false
}

Write-Step "Esperando que los servicios estén listos..."
Write-Info "SQL Server puede tardar hasta 90s en el primer arranque."
Write-Host ""

Wait-Container -Name "SQL Server"  -Container "dms_sqlserver" -TimeoutSecs 120 -NeedsHealth $true
Wait-Container -Name "PostgreSQL"  -Container "dms_postgres"  -TimeoutSecs 60  -NeedsHealth $true
Wait-Container -Name "MongoDB"     -Container "dms_mongodb"   -TimeoutSecs 60  -NeedsHealth $true
Wait-Container -Name "FastAPI"     -Container "dms_fastapi"   -TimeoutSecs 60  -NeedsHealth $false
Wait-Container -Name "PHP/Apache"  -Container "dms_php"       -TimeoutSecs 60  -NeedsHealth $false
Wait-Container -Name ".NET Core"   -Container "dms_dotnet"    -TimeoutSecs 90  -NeedsHealth $false
Wait-Container -Name "Nginx"       -Container "dms_nginx"     -TimeoutSecs 30  -NeedsHealth $false

# ── Dashboard final ───────────────────────────────────────────
Write-Host ""
Write-Host "  $('═' * 54)" -ForegroundColor Cyan
Write-Host "        INSTALLATION COMPLETE" -ForegroundColor White
Write-Host "  $('═' * 54)" -ForegroundColor Cyan
Write-Host ""
Write-Host "  → Portal Público      http://localhost" -ForegroundColor White
Write-Host "  → Portal HTTPS        https://localhost:8443" -ForegroundColor White
Write-Host "  → Admin (CalidadSYS)  http://localhost:5080" -ForegroundColor White
Write-Host "  → FastAPI Docs        http://localhost:8001/docs" -ForegroundColor White
Write-Host ""
Write-Host "  $('─' * 54)" -ForegroundColor DarkGray
Write-Host "  → PostgreSQL          localhost:5433" -ForegroundColor DarkGray
Write-Host "  → MongoDB             localhost:27018" -ForegroundColor DarkGray
Write-Host "  → SQL Server          localhost:1434" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $('─' * 54)" -ForegroundColor DarkGray
Write-Host "  $composeCmd ps" -ForegroundColor DarkGray
Write-Host "  $composeCmd logs -f" -ForegroundColor DarkGray
Write-Host "  $composeCmd down" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  $('═' * 54)" -ForegroundColor Cyan
Write-Host ""

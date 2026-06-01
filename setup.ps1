# ============================================================
#  DMS Setup -- Windows PowerShell
#
#  Instalación completa:   .\setup.ps1
#  Solo .NET + SQL Server: .\setup.ps1 -Stack net
#  Solo PHP + PostgreSQL:  .\setup.ps1 -Stack php
#  Solo FastAPI + MongoDB: .\setup.ps1 -Stack indexer
# ============================================================

param(
    [ValidateSet("all","net","php","indexer")]
    [string]$Stack = "all"
)

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "" ; Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "       $msg" -ForegroundColor Gray }

# -- Banner ---------------------------------------------------
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$b  = [char]0x2588
$dr = [char]0x2557
$dl = [char]0x2554
$v  = [char]0x2551
$h  = [char]0x2550
$ur = [char]0x255D
$ul = [char]0x255A

Clear-Host
Write-Host ""
Write-Host "  $b$b$b$b$b$b$dr $b$b$b$dr   $b$b$b$dr$b$b$b$b$b$b$b$dr" -ForegroundColor Cyan
Write-Host "  $b$b$dl$h$h$b$b$dr$b$b$b$b$dr $b$b$b$b$v$b$b$dl$h$h$h$h$ur" -ForegroundColor Cyan
Write-Host "  $b$b$v  $b$b$v$b$b$dl$b$b$b$b$dl$b$b$v$b$b$b$b$b$b$b$dr" -ForegroundColor Cyan
Write-Host "  $b$b$v  $b$b$v$b$b$v$ul$b$b$dl$ur$b$b$v$ul$h$h$h$h$b$b$v" -ForegroundColor Cyan
Write-Host "  $b$b$b$b$b$b$dl$ur$b$b$v $ul$h$ur $b$b$v$b$b$b$b$b$b$b$v" -ForegroundColor Cyan
Write-Host "  $ul$h$h$h$h$h$ur $ul$h$ur     $ul$h$ur$ul$h$h$h$h$h$h$ur" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Sistema Integral de Gestion Documental" -ForegroundColor White
Write-Host "  Enterprise Multi-Stack Platform  v2.0.0" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Stack seleccionado: $Stack" -ForegroundColor Yellow
Write-Host ""

# -- Seleccion de modo ----------------------------------------
Write-Host ("  " + "-" * 54) -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Selecciona el modo de instalacion:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1]  Sandbox     - 10000 documentos de prueba generados" -ForegroundColor White
Write-Host "       automaticamente. Sistema listo para demo desde el" -ForegroundColor DarkGray
Write-Host "       primer arranque." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [2]  Development - Sistema limpio, sin documentos." -ForegroundColor White
Write-Host "       Solo usuarios, roles y configuracion base." -ForegroundColor DarkGray
Write-Host ""

$modeInput = ""
do {
    $modeInput = Read-Host "  Opcion [1/2]"
} while ($modeInput -notin @("1", "2"))

$seedMode = if ($modeInput -eq "1") { "sandbox" } else { "dev" }
$seedModeLabel = if ($modeInput -eq "1") { "Sandbox (10000 docs)" } else { "Development (limpio)" }

Write-Host ""
Write-Ok "Modo: $seedModeLabel"
Write-Host ""

# -- Configurar archivos según stack --------------------------
$composeFile = switch ($Stack) {
    "net"     { "compose-net.yml" }
    "php"     { "compose-php.yml" }
    "indexer" { "compose-indexer.yml" }
    default   { "compose-all.yml" }
}

$envFile = switch ($Stack) {
    "net"     { ".env.net" }
    "php"     { ".env.php" }
    "indexer" { ".env.indexer" }
    default   { ".env" }
}

Write-Info "Compose file: $composeFile"
Write-Info "Env file:     $envFile"

# -- Verificar Docker -----------------------------------------
Write-Step "Checking dependencies..."
Write-Host ""

try {
    $null = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw }
    Write-Ok "Docker running"
} catch {
    Write-Err "Docker is not running. Start Docker Desktop first."
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
        Write-Err "Docker Compose not found. Update Docker Desktop."
        exit 1
    }
}

# -- Crear red dms_backbone (solo para stacks separados) ------
if ($Stack -ne "all") {
    Write-Step "Ensuring shared network dms_backbone..."
    $netExists = docker network inspect dms_backbone 2>&1
    if ($LASTEXITCODE -ne 0) {
        docker network create dms_backbone | Out-Null
        Write-Ok "Network dms_backbone created"
    } else {
        Write-Info "Network dms_backbone already exists"
    }

    # Crear directorio de uploads compartido
    if (-not (Test-Path ".\data\uploads")) {
        New-Item -ItemType Directory -Path ".\data\uploads" -Force | Out-Null
        Write-Ok "Created .\data\uploads  (shared bind mount for PDFs)"
    } else {
        Write-Info ".\data\uploads already exists"
    }
}

# -- .env existente? ------------------------------------------
$generarEnv = $true

if (Test-Path $envFile) {
    Write-Host ""
    Write-Warn "$envFile already exists."
    $resp = Read-Host "       Overwrite? (y/N)"
    if ($resp -notmatch "^[yY]$") {
        Write-Info "Using existing $envFile."
        $generarEnv = $false
    }
}

# -- Contraseña maestra ---------------------------------------
if ($generarEnv) {
    Write-Step "Master password"
    Write-Host ""
    Write-Info "Same password for SQL Server, PostgreSQL and MongoDB."
    Write-Host ""
    Write-Info "Requirements (SQL Server policy):"
    Write-Info "  - Minimum 8 characters"
    Write-Info "  - At least one uppercase letter  (A-Z)"
    Write-Info "  - At least one lowercase letter  (a-z)"
    Write-Info "  - At least one digit             (0-9)"
    Write-Info "  - At least one special character (example: MiPass1!)"
    Write-Host ""

    $MASTER_PASS = ""
    do {
        $pass1 = Read-Host "  Password" -AsSecureString
        $pass2 = Read-Host "  Confirm " -AsSecureString

        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

        if ($p1 -ne $p2) {
            Write-Warn "Passwords do not match. Try again."
            Write-Host ""
            continue
        }

        $valid = $p1.Length -ge 8 `
            -and $p1 -cmatch '[A-Z]' `
            -and $p1 -cmatch '[a-z]' `
            -and $p1 -match  '[0-9]' `
            -and $p1 -match  '[^a-zA-Z0-9]'

        if (-not $valid) {
            Write-Warn "Password does not meet requirements. Try again."
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

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # Función auxiliar para escribir env files
    function Write-EnvFile {
        param([string]$Path, [string]$Content)
        Set-Content -Path $Path -Value $Content -Encoding UTF8
        Write-Ok "$Path generated"
    }

    $envNet = @"
# Stack 1 - .NET + SQL Server
# Generated by setup.ps1 -- $timestamp
# DO NOT commit this file.

# -- SQL Server
MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS

# -- Shared secrets
FASTAPI_API_KEY=$API_KEY
JWT_SECRET=$JWT_SECRET

# -- Cross-stack URLs
PHP_WEBHOOK_URL=http://php
FASTAPI_WEBHOOK_URL=http://fastapi:8000

# -- Seed mode: sandbox | dev | none
DMS_SEED_MODE=$seedMode
"@

    $envPhp = @"
# Stack 2 - PHP + PostgreSQL + Nginx
# Generated by setup.ps1 -- $timestamp
# DO NOT commit this file.

# -- PostgreSQL
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS

# -- Shared secrets
FASTAPI_API_KEY=$API_KEY

# -- Cross-stack URLs
FASTAPI_URL=http://fastapi:8000
DOTNET_API_URL=http://dotnet:8080
"@

    $envIndexer = @"
# Stack 3 - FastAPI + MongoDB
# Generated by setup.ps1 -- $timestamp
# DO NOT commit this file.

# -- MongoDB
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS

# -- Shared secrets
FASTAPI_API_KEY=$API_KEY
JWT_SECRET=$JWT_SECRET

# -- PostgreSQL cross-stack (documents_sync.py)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS

# -- Cross-stack URLs
DOTNET_API_URL=http://dotnet:8080
"@

    $envAll = @"
# Generated by setup.ps1 -- $timestamp
# DO NOT commit this file.

# -- SQL Server
MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS

# -- PostgreSQL
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS

# -- MongoDB
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS

# -- FastAPI
FASTAPI_API_KEY=$API_KEY
FASTAPI_URL=http://fastapi:8000

# -- JWT
JWT_SECRET=$JWT_SECRET

# -- Seed mode: sandbox | dev | none
DMS_SEED_MODE=$seedMode
"@

    switch ($Stack) {
        "net"     { Write-EnvFile -Path ".env.net"     -Content $envNet }
        "php"     { Write-EnvFile -Path ".env.php"     -Content $envPhp }
        "indexer" { Write-EnvFile -Path ".env.indexer" -Content $envIndexer }
        default   {
            Write-EnvFile -Path ".env"         -Content $envAll
            Write-EnvFile -Path ".env.net"     -Content $envNet
            Write-EnvFile -Path ".env.php"     -Content $envPhp
            Write-EnvFile -Path ".env.indexer" -Content $envIndexer
            Write-Warn "IMPORTANT: FASTAPI_API_KEY and JWT_SECRET are identical in all env files."
            Write-Info "If deploying on separate servers, copy those values manually."
        }
    }
}

# -- Levantar contenedores ------------------------------------
Write-Step "Building and starting containers..."
Write-Host ""
Write-Info "First run may take 5-15 minutes."
Write-Host ""

$upCmd = "$composeCmd --env-file $envFile -f $composeFile up -d --build"
Write-Info "Running: $upCmd"
Write-Host ""

Invoke-Expression $upCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Err "Failed to start containers."
    Write-Info "Check logs: $composeCmd -f $composeFile logs"
    exit 1
}

Write-Host ""
Write-Ok "All containers started"

# -- Healthchecks ---------------------------------------------
function Wait-Container {
    param(
        [string]$DisplayName,
        [string]$Container,
        [int]$TimeoutSecs = 120,
        [bool]$NeedsHealth = $true
    )

    Write-Host ("  [~] Waiting for " + $DisplayName + "...") -NoNewline -ForegroundColor Yellow

    $elapsed  = 0
    $interval = 5

    while ($elapsed -lt $TimeoutSecs) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval

        if ($NeedsHealth) {
            $status = docker inspect --format="{{.State.Health.Status}}" $Container 2>$null
            if ($status -eq "healthy") {
                Write-Host ("`r  [OK] " + $DisplayName + " healthy (" + $elapsed + "s)          ") -ForegroundColor Green
                return $true
            }
            if ($status -eq "unhealthy") {
                Write-Host ("`r  [X]  " + $DisplayName + " unhealthy -- check: docker logs " + $Container) -ForegroundColor Red
                return $false
            }
        } else {
            $state = docker inspect --format="{{.State.Status}}" $Container 2>$null
            if ($state -eq "running") {
                Write-Host ("`r  [OK] " + $DisplayName + " running (" + $elapsed + "s)          ") -ForegroundColor Green
                return $true
            }
            if ($state -eq "exited" -or $state -eq "dead") {
                Write-Host ("`r  [X]  " + $DisplayName + " crashed -- check: docker logs " + $Container) -ForegroundColor Red
                return $false
            }
        }
    }

    Write-Host ("`r  [!]  " + $DisplayName + " timeout (" + $TimeoutSecs + "s)") -ForegroundColor Yellow
    return $false
}

Write-Step "Waiting for services..."
Write-Host ""

switch ($Stack) {
    "net" {
        Write-Info "SQL Server may take up to 90s on first boot."
        $null = Wait-Container -DisplayName "SQL Server" -Container "dms_sqlserver" -TimeoutSecs 120 -NeedsHealth $true
        $null = Wait-Container -DisplayName ".NET Core"  -Container "dms_dotnet"    -TimeoutSecs 90  -NeedsHealth $false
    }
    "php" {
        $null = Wait-Container -DisplayName "PostgreSQL"  -Container "dms_postgres"  -TimeoutSecs 60  -NeedsHealth $true
        $null = Wait-Container -DisplayName "PHP/Apache"  -Container "dms_php"       -TimeoutSecs 60  -NeedsHealth $false
        $null = Wait-Container -DisplayName "Nginx"       -Container "dms_nginx"     -TimeoutSecs 30  -NeedsHealth $false
    }
    "indexer" {
        $null = Wait-Container -DisplayName "MongoDB"     -Container "dms_mongodb"   -TimeoutSecs 60  -NeedsHealth $true
        $null = Wait-Container -DisplayName "FastAPI"     -Container "dms_fastapi"   -TimeoutSecs 60  -NeedsHealth $false
    }
    default {
        Write-Info "SQL Server may take up to 90s on first boot."
        $null = Wait-Container -DisplayName "SQL Server"  -Container "dms_sqlserver" -TimeoutSecs 120 -NeedsHealth $true
        $null = Wait-Container -DisplayName "PostgreSQL"  -Container "dms_postgres"  -TimeoutSecs 60  -NeedsHealth $true
        $null = Wait-Container -DisplayName "MongoDB"     -Container "dms_mongodb"   -TimeoutSecs 60  -NeedsHealth $true
        $null = Wait-Container -DisplayName "FastAPI"     -Container "dms_fastapi"   -TimeoutSecs 60  -NeedsHealth $false
        $null = Wait-Container -DisplayName "PHP/Apache"  -Container "dms_php"       -TimeoutSecs 90  -NeedsHealth $false
        $null = Wait-Container -DisplayName ".NET Core"   -Container "dms_dotnet"    -TimeoutSecs 90  -NeedsHealth $false
        $null = Wait-Container -DisplayName "Nginx"       -Container "dms_nginx"     -TimeoutSecs 30  -NeedsHealth $false
    }
}

# -- Dashboard final ------------------------------------------
Write-Host ""
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host ("        INSTALLATION COMPLETE  [stack: $Stack]") -ForegroundColor White
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host ""

switch ($Stack) {
    "net" {
        Write-Host "  -> Admin (CalidadSYS)  http://localhost:5080" -ForegroundColor White
        Write-Host ""
        Write-Host "  -> SQL Server          localhost:1434" -ForegroundColor DarkGray
    }
    "php" {
        Write-Host "  -> Portal Publico      http://localhost"       -ForegroundColor White
        Write-Host "  -> Portal HTTPS        https://localhost:8443" -ForegroundColor White
        Write-Host ""
        Write-Host "  -> PostgreSQL          localhost:5433" -ForegroundColor DarkGray
    }
    "indexer" {
        Write-Host "  -> FastAPI Docs        http://localhost:8001/docs" -ForegroundColor White
        Write-Host ""
        Write-Host "  -> MongoDB             localhost:27018" -ForegroundColor DarkGray
    }
    default {
        Write-Host "  -> Portal Publico      http://localhost"            -ForegroundColor White
        Write-Host "  -> Portal HTTPS        https://localhost:8443"      -ForegroundColor White
        Write-Host "  -> Admin (CalidadSYS)  http://localhost:5080"       -ForegroundColor White
        Write-Host "  -> FastAPI Docs        http://localhost:8001/docs"  -ForegroundColor White
        Write-Host ""
        Write-Host ("  " + "-" * 54) -ForegroundColor DarkGray
        Write-Host "  -> PostgreSQL          localhost:5433"  -ForegroundColor DarkGray
        Write-Host "  -> MongoDB             localhost:27018" -ForegroundColor DarkGray
        Write-Host "  -> SQL Server          localhost:1434"  -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host ("  " + "-" * 54) -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " -f " + $composeFile + " ps")      -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " -f " + $composeFile + " logs -f") -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " -f " + $composeFile + " down")    -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host ""

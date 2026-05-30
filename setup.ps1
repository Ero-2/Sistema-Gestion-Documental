# ============================================================
#  DMS Setup -- Windows PowerShell
#  Uso: .\setup.ps1
# ============================================================

$ErrorActionPreference = "Stop"

function Write-Step { param($msg) Write-Host "" ; Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "       $msg" -ForegroundColor Gray }

# -- Banner ---------------------------------------------------
# Unicode chars defined via code points -- source stays ASCII, PS builds them at runtime
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$b  = [char]0x2588  # full block
$dr = [char]0x2557  # corner down-right
$dl = [char]0x2554  # corner down-left
$v  = [char]0x2551  # vertical
$h  = [char]0x2550  # horizontal
$ur = [char]0x255D  # corner up-right
$ul = [char]0x255A  # corner up-left

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
Write-Host "  Enterprise Multi-Stack Platform  v1.0.0" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Stack: .NET 10 | PHP 8.3 | FastAPI | MongoDB | PostgreSQL | SQL Server | Nginx" -ForegroundColor DarkGray
Write-Host ""

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

# -- .env existente? ------------------------------------------
$generarEnv = $true

if (Test-Path ".env") {
    Write-Host ""
    Write-Warn ".env already exists."
    $resp = Read-Host "       Overwrite? (y/N)"
    if ($resp -notmatch "^[yY]$") {
        Write-Info "Using existing .env."
        $generarEnv = $false
    }
}

# -- Contrasena maestra ---------------------------------------
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
    $envContent = "# Generated by setup.ps1 -- " + $timestamp + "`r`n"
    $envContent += "# DO NOT commit this file.`r`n"
    $envContent += "`r`n"
    $envContent += "# -- SQL Server`r`n"
    $envContent += "MSSQL_SA_PASSWORD=" + $MASTER_PASS + "`r`n"
    $envContent += "MSSQL_DB=QualityDMS`r`n"
    $envContent += "`r`n"
    $envContent += "# -- PostgreSQL`r`n"
    $envContent += "POSTGRES_DB=PublicDMS`r`n"
    $envContent += "POSTGRES_USER=postgres`r`n"
    $envContent += "POSTGRES_PASSWORD=" + $MASTER_PASS + "`r`n"
    $envContent += "`r`n"
    $envContent += "# -- MongoDB`r`n"
    $envContent += "MONGO_USER=mongoadmin`r`n"
    $envContent += "MONGO_PASSWORD=" + $MASTER_PASS + "`r`n"
    $envContent += "`r`n"
    $envContent += "# -- FastAPI`r`n"
    $envContent += "FASTAPI_API_KEY=" + $API_KEY + "`r`n"
    $envContent += "FASTAPI_URL=http://fastapi:8000`r`n"
    $envContent += "`r`n"
    $envContent += "# -- JWT`r`n"
    $envContent += "JWT_SECRET=" + $JWT_SECRET + "`r`n"

    Set-Content -Path ".env" -Value $envContent -Encoding UTF8
    Write-Host ""
    Write-Ok ".env generated"
    Write-Ok "SQL Server / PostgreSQL / MongoDB -- master password"
    Write-Ok "FastAPI API key  (256-bit random)"
    Write-Ok "JWT secret       (384-bit random)"
}

# -- Levantar contenedores ------------------------------------
Write-Step "Building and starting containers..."
Write-Host ""
Write-Info "First run may take 5-15 minutes."
Write-Host ""

Invoke-Expression "$composeCmd up -d --build"

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Err "Failed to start containers."
    Write-Info ("Check logs: " + $composeCmd + " logs")
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

    Write-Host ("`r  [!]  " + $DisplayName + " timeout (" + $TimeoutSecs + "s) -- check: docker logs " + $Container) -ForegroundColor Yellow
    return $false
}

Write-Step "Waiting for services..."
Write-Info "SQL Server may take up to 90s on first boot."
Write-Host ""

$null = Wait-Container -DisplayName "SQL Server" -Container "dms_sqlserver" -TimeoutSecs 120 -NeedsHealth $true
$null = Wait-Container -DisplayName "PostgreSQL"  -Container "dms_postgres"  -TimeoutSecs 60  -NeedsHealth $true
$null = Wait-Container -DisplayName "MongoDB"     -Container "dms_mongodb"   -TimeoutSecs 60  -NeedsHealth $true
$null = Wait-Container -DisplayName "FastAPI"     -Container "dms_fastapi"   -TimeoutSecs 60  -NeedsHealth $false
$null = Wait-Container -DisplayName "PHP/Apache"  -Container "dms_php"       -TimeoutSecs 90  -NeedsHealth $false
$null = Wait-Container -DisplayName ".NET Core"   -Container "dms_dotnet"    -TimeoutSecs 90  -NeedsHealth $false
$null = Wait-Container -DisplayName "Nginx"       -Container "dms_nginx"     -TimeoutSecs 30  -NeedsHealth $false

# -- Dashboard final ------------------------------------------
Write-Host ""
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host "        INSTALLATION COMPLETE" -ForegroundColor White
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host ""
Write-Host "  -> Portal Publico      http://localhost"           -ForegroundColor White
Write-Host "  -> Portal HTTPS        https://localhost:8443"     -ForegroundColor White
Write-Host "  -> Admin (CalidadSYS)  http://localhost:5080"      -ForegroundColor White
Write-Host "  -> FastAPI Docs        http://localhost:8001/docs"  -ForegroundColor White
Write-Host ""
Write-Host ("  " + "-" * 54) -ForegroundColor DarkGray
Write-Host "  -> PostgreSQL          localhost:5433"  -ForegroundColor DarkGray
Write-Host "  -> MongoDB             localhost:27018" -ForegroundColor DarkGray
Write-Host "  -> SQL Server          localhost:1434"  -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  " + "-" * 54) -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " ps")      -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " logs -f") -ForegroundColor DarkGray
Write-Host ("  " + $composeCmd + " down")    -ForegroundColor DarkGray
Write-Host ""
Write-Host ("  " + "=" * 54) -ForegroundColor Cyan
Write-Host ""

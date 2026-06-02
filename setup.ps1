# ============================================================
#  DMS Setup -- Windows PowerShell
#
#  Instalacion completa:    .\setup.ps1
#  Solo .NET + SQL Server:  .\setup.ps1 -Stack net
#  Solo PHP + PostgreSQL:   .\setup.ps1 -Stack php
#  Solo FastAPI + MongoDB:  .\setup.ps1 -Stack indexer
#  Diagnostico del sistema: .\setup.ps1 -Diagnose
# ============================================================

param(
    [ValidateSet("all","net","php","indexer")]
    [string]$Stack = "all",
    [switch]$Diagnose
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── Helpers de output ─────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host ""; Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "       $msg" -ForegroundColor Gray }
function Write-Sep  { param([char]$c='─',[int]$n=60) Write-Host ("  " + ($c * $n)) -ForegroundColor DarkGray }

# ── Puertos del sistema ───────────────────────────────────────────────────────
$PORT_MAP = [ordered]@{
    80    = "Nginx → PHP (portal publico)"
    8443  = "Nginx → FastAPI (busqueda HTTPS)"
    8084  = "Nginx → .NET  (gestion interna)"
    5080  = ".NET directo (CalidadSYS)"
    8001  = "FastAPI directo (Swagger)"
    1435  = "SQL Server"
    5433  = "PostgreSQL"
    27018 = "MongoDB"
}

# ── Contenedores del sistema ──────────────────────────────────────────────────
$DMS_CONTAINERS = @(
    "dms_nginx","dms_dotnet","dms_sqlserver",
    "dms_postgres","dms_php","dms_fastapi","dms_mongodb"
)

# ── Detectar proceso que ocupa un puerto ──────────────────────────────────────
function Get-PortOwner {
    param([int]$Port)
    $lines = netstat -ano 2>$null | Select-String "[\s:]$Port\s"
    foreach ($line in $lines) {
        if ($line -match "LISTENING|LISTEN") {
            $parts = $line.Line.Trim() -split '\s+'
            $pid   = $parts[-1]
            try {
                $proc = Get-Process -Id ([int]$pid) -ErrorAction Stop
                return "$($proc.ProcessName) (PID $pid)"
            } catch { return "PID $pid" }
        }
    }
    return $null
}

function Test-PortFree { param([int]$Port); return ($null -eq (Get-PortOwner -Port $Port)) }

# ── Detectar compose + env segun stack ───────────────────────────────────────
function Get-StackFiles {
    param([string]$s)
    switch ($s) {
        "net"     { return @{ Compose = "compose-net.yml";     Env = ".env.net"     } }
        "php"     { return @{ Compose = "compose-php.yml";     Env = ".env.php"     } }
        "indexer" { return @{ Compose = "compose-indexer.yml"; Env = ".env.indexer" } }
        default   { return @{ Compose = "compose-all.yml";     Env = ".env"         } }
    }
}

# ── Detectar docker compose CLI ───────────────────────────────────────────────
function Get-ComposeCmd {
    $null = docker compose version 2>&1
    if ($LASTEXITCODE -eq 0) { return "docker compose" }
    $null = docker-compose version 2>&1
    if ($LASTEXITCODE -eq 0) { return "docker-compose" }
    return $null
}

# ── Banner ────────────────────────────────────────────────────────────────────
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ██████╗ ███╗   ███╗███████╗" -ForegroundColor Cyan
    Write-Host "  ██╔══██╗████╗ ████║██╔════╝" -ForegroundColor Cyan
    Write-Host "  ██║  ██║██╔████╔██║███████╗" -ForegroundColor Cyan
    Write-Host "  ██║  ██║██║╚██╔╝██║╚════██║" -ForegroundColor Cyan
    Write-Host "  ██████╔╝██║ ╚═╝ ██║███████║" -ForegroundColor Cyan
    Write-Host "  ╚═════╝ ╚═╝     ╚═╝╚══════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Sistema Integral de Gestion Documental" -ForegroundColor White
    Write-Host "  Enterprise Multi-Stack Platform  v2.1.0" -ForegroundColor DarkGray
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  DIAGNOSTICO
# ══════════════════════════════════════════════════════════════════════════════
function Show-ContainerStatus {
    Write-Host ""
    Write-Host "  ESTADO DE CONTENEDORES" -ForegroundColor Cyan
    Write-Sep
    $cols = @{Expression={$_.Names};Label="Contenedor";Width=22},
            @{Expression={$_.Status};Label="Estado";Width=30},
            @{Expression={$_.Ports};Label="Puertos";Width=30}
    $rows = docker ps -a --filter "name=dms_" --format "{{.Names}}|{{.Status}}|{{.Ports}}" 2>$null
    if (-not $rows) {
        Write-Warn "No se encontraron contenedores DMS."
        return
    }
    foreach ($r in $rows) {
        $p = $r -split '\|'
        $color = if ($p[1] -match "Up") { "Green" } elseif ($p[1] -match "Exit") { "Red" } else { "Yellow" }
        Write-Host ("  {0,-24} {1,-28} {2}" -f $p[0], $p[1], $p[2]) -ForegroundColor $color
    }
    Write-Host ""
}

function Show-PortStatus {
    Write-Host ""
    Write-Host "  ESTADO DE PUERTOS" -ForegroundColor Cyan
    Write-Sep
    Write-Host ("  {0,-6} {1,-38} {2}" -f "PUERTO","SERVICIO","ESTADO") -ForegroundColor DarkGray
    Write-Sep
    foreach ($kv in $PORT_MAP.GetEnumerator()) {
        $owner = Get-PortOwner -Port $kv.Key
        if ($null -eq $owner) {
            Write-Host ("  {0,-6} {1,-38} {2}" -f $kv.Key, $kv.Value, "libre") -ForegroundColor DarkGray
        } else {
            $color = if ($owner -match "docker|vpnkit|com.docker") { "Green" } else { "Yellow" }
            Write-Host ("  {0,-6} {1,-38} {2}" -f $kv.Key, $kv.Value, "OCUPADO por $owner") -ForegroundColor $color
        }
    }
    Write-Host ""
}

function Show-Logs {
    param([string]$composeCmd, [string]$composeFile, [string]$envFile)
    Write-Host ""
    Write-Host "  SERVICIO para ver logs:" -ForegroundColor Cyan
    Write-Host "  [1] nginx   [2] dotnet   [3] sqlserver"
    Write-Host "  [4] php     [5] fastapi  [6] postgres   [7] mongodb"
    Write-Host "  [0] Todos"
    $svc = Read-Host "  Opcion"
    $map = @{"1"="nginx";"2"="dotnet";"3"="sqlserver";"4"="php";"5"="fastapi";"6"="postgres";"7"="mongodb";"0"=""}
    if ($map.ContainsKey($svc)) {
        $args2 = if ($map[$svc]) { "logs --tail=80 $($map[$svc])" } else { "logs --tail=40" }
        Invoke-Expression "$composeCmd --env-file `"$envFile`" -f `"$composeFile`" $args2"
    }
}

function Restart-Services {
    param([string]$composeCmd, [string]$composeFile, [string]$envFile)
    Write-Host ""
    Write-Warn "Reiniciando todos los servicios del stack $Stack..."
    Invoke-Expression "$composeCmd --env-file `"$envFile`" -f `"$composeFile`" restart"
    Write-Ok "Reinicio completado."
}

function Test-HttpConnectivity {
    Write-Host ""
    Write-Host "  VALIDACION DE CONECTIVIDAD HTTP" -ForegroundColor Cyan
    Write-Sep
    $endpoints = @(
        @{ Url = "http://localhost";          Label = "PHP  portal publico       :80"   }
        @{ Url = "https://localhost:8443";    Label = "FastAPI busqueda         :8443"  }
        @{ Url = "http://localhost:8084";     Label = ".NET gestion            :8084"   }
        @{ Url = "http://localhost:8001/health"; Label = "FastAPI health         :8001" }
        @{ Url = "http://localhost:5080";     Label = ".NET directo             :5080"  }
    )
    foreach ($ep in $endpoints) {
        try {
            $resp = Invoke-WebRequest -Uri $ep.Url -UseBasicParsing -TimeoutSec 5 `
                    -SkipCertificateCheck -ErrorAction Stop 2>$null
            Write-Ok "$($ep.Label)  →  $($resp.StatusCode)"
        } catch {
            $code = $_.Exception.Response?.StatusCode
            if ($code) { Write-Warn "$($ep.Label)  →  HTTP $([int]$code)" }
            else        { Write-Err  "$($ep.Label)  →  Sin respuesta" }
        }
    }
    Write-Host ""
}

function Test-Databases {
    Write-Host ""
    Write-Host "  VALIDACION DE BASES DE DATOS" -ForegroundColor Cyan
    Write-Sep

    # SQL Server
    try {
        $r = docker exec dms_sqlserver /opt/mssql-tools18/bin/sqlcmd `
             -S localhost -U sa -P "$env:MSSQL_SA_PASSWORD" `
             -Q "SELECT COUNT(*) FROM QualityDMS.dbo.Documents" -No 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok "SQL Server  - Documents: $($r[1].Trim())" }
        else { throw }
    } catch { Write-Err "SQL Server  - No accesible (contenedor parado o error)" }

    # PostgreSQL
    try {
        $r = docker exec dms_postgres psql -U postgres -d PublicDMS `
             -c "SELECT COUNT(*) FROM publicdms.documents;" -t 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok "PostgreSQL  - publicdms.documents: $($r.Trim())" }
        else { throw }
    } catch { Write-Err "PostgreSQL  - No accesible" }

    # MongoDB
    try {
        $r = docker exec dms_mongodb mongosh dms_metadata --quiet `
             --eval "db.file_tags.countDocuments({})" 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok "MongoDB     - file_tags: $($r.Trim())" }
        else { throw }
    } catch { Write-Err "MongoDB     - No accesible" }

    Write-Host ""
}

function Test-Storage {
    Write-Host ""
    Write-Host "  VALIDACION DE ALMACENAMIENTO DOCUMENTAL" -ForegroundColor Cyan
    Write-Sep
    $paths = @(".\data\uploads", "/app/uploads")
    foreach ($p in $paths) {
        if (Test-Path $p) {
            $files = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-Ok "${p}  →  $files archivos"
        } else {
            Write-Warn "${p}  →  no existe localmente"
        }
    }
    # Verificar dentro del contenedor dotnet
    try {
        $r = docker exec dms_dotnet sh -c "find /app/uploads -type f | wc -l" 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Ok ".NET /app/uploads →  $($r.Trim()) archivos en contenedor" }
    } catch { Write-Warn "Contenedor dotnet no accesible" }
    Write-Host ""
}

function Test-SearchEngine {
    Write-Host ""
    Write-Host "  VALIDACION DEL MOTOR DE BUSQUEDA (FastAPI + MongoDB)" -ForegroundColor Cyan
    Write-Sep
    try {
        $h = Invoke-WebRequest -Uri "http://localhost:8001/health" -UseBasicParsing `
             -TimeoutSec 5 -ErrorAction Stop
        Write-Ok "FastAPI /health  →  $($h.StatusCode)"
    } catch { Write-Err "FastAPI no responde en :8001" }

    try {
        $r = docker exec dms_mongodb mongosh dms_metadata --quiet `
             --eval "db.file_tags.countDocuments({is_simulated: true})" 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Info "Docs simulados en MongoDB: $($r.Trim())" }
        $r2 = docker exec dms_mongodb mongosh dms_metadata --quiet `
              --eval "db.file_tags.countDocuments({content_extracted: true})" 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Info "Docs con texto indexado:   $($r2.Trim())" }
    } catch {}
    Write-Host ""
}

function Show-DiagnosticMenu {
    param([string]$composeCmd, [string]$composeFile, [string]$envFile)
    do {
        Write-Host ""
        Write-Sep '═'
        Write-Host "  DIAGNOSTICO DEL SISTEMA  [stack: $Stack]" -ForegroundColor Cyan
        Write-Sep '═'
        Write-Host "  [1]  Estado de contenedores"       -ForegroundColor White
        Write-Host "  [2]  Puertos utilizados"            -ForegroundColor White
        Write-Host "  [3]  Ver logs de servicio"          -ForegroundColor White
        Write-Host "  [4]  Reiniciar servicios"           -ForegroundColor White
        Write-Host "  [5]  Validar conectividad HTTP"     -ForegroundColor White
        Write-Host "  [6]  Validar bases de datos"        -ForegroundColor White
        Write-Host "  [7]  Validar almacenamiento"        -ForegroundColor White
        Write-Host "  [8]  Validar motor de busqueda"     -ForegroundColor White
        Write-Host "  [0]  Salir"                         -ForegroundColor DarkGray
        Write-Sep '═'
        $opt = Read-Host "  Opcion"
        switch ($opt) {
            "1" { Show-ContainerStatus }
            "2" { Show-PortStatus }
            "3" { Show-Logs -composeCmd $composeCmd -composeFile $composeFile -envFile $envFile }
            "4" { Restart-Services -composeCmd $composeCmd -composeFile $composeFile -envFile $envFile }
            "5" { Test-HttpConnectivity }
            "6" { Test-Databases }
            "7" { Test-Storage }
            "8" { Test-SearchEngine }
            "0" { return }
            default { Write-Warn "Opcion invalida." }
        }
    } while ($true)
}

# ══════════════════════════════════════════════════════════════════════════════
#  INICIO
# ══════════════════════════════════════════════════════════════════════════════
Show-Banner

$files       = Get-StackFiles -s $Stack
$composeFile = $files.Compose
$envFile     = $files.Env

# ── Modo diagnostico puro ─────────────────────────────────────────────────────
if ($Diagnose) {
    $composeCmd = Get-ComposeCmd
    if (-not $composeCmd) { Write-Err "Docker Compose no encontrado."; exit 1 }
    Show-DiagnosticMenu -composeCmd $composeCmd -composeFile $composeFile -envFile $envFile
    exit 0
}

# ── Verificar Docker ──────────────────────────────────────────────────────────
Write-Step "Verificando Docker..."
Write-Host ""

try {
    $null = docker info 2>&1
    if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE" }
    Write-Ok "Docker en ejecucion"
} catch {
    Write-Err "Docker no esta corriendo. Abre Docker Desktop primero."
    Write-Info "Tip: una vez abierto, ejecuta de nuevo: .\setup.ps1"
    exit 1
}

$composeCmd = Get-ComposeCmd
if (-not $composeCmd) {
    Write-Err "Docker Compose no encontrado. Actualiza Docker Desktop."
    exit 1
}
Write-Ok "Docker Compose disponible ($composeCmd)"

# ── Detectar instalacion existente ────────────────────────────────────────────
$existingContainers = docker ps -a --filter "name=dms_" --format "{{.Names}}" 2>$null
$systemExists = ($existingContainers | Measure-Object).Count -gt 0

if ($systemExists) {
    Write-Host ""
    Write-Sep '═'
    Write-Host "  SISTEMA YA INICIALIZADO" -ForegroundColor Yellow
    Write-Sep '═'
    Write-Host ""
    Write-Host "  Se encontraron contenedores DMS existentes:" -ForegroundColor White
    $existingContainers | ForEach-Object {
        $st = docker inspect --format="{{.State.Status}}" $_ 2>$null
        $color = if ($st -eq "running") { "Green" } else { "Red" }
        Write-Host ("    {0,-28} [{1}]" -f $_, $st) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "  Que deseas hacer?" -ForegroundColor Cyan
    Write-Host "  [R]  Reutilizar (solo restart, conserva datos)" -ForegroundColor White
    Write-Host "  [L]  Reinicializar limpio (elimina volumenes, rebuilds)"  -ForegroundColor White
    Write-Host "  [D]  Ir al menu de diagnostico" -ForegroundColor White
    Write-Host "  [S]  Salir" -ForegroundColor DarkGray
    Write-Host ""

    $choice = ""
    do { $choice = (Read-Host "  Opcion [R/L/D/S]").ToUpper() } while ($choice -notin @("R","L","D","S"))

    switch ($choice) {
        "S" { Write-Info "Saliendo."; exit 0 }
        "D" {
            Show-DiagnosticMenu -composeCmd $composeCmd -composeFile $composeFile -envFile $envFile
            exit 0
        }
        "R" {
            Write-Step "Reiniciando servicios existentes..."
            Invoke-Expression "$composeCmd --env-file `"$envFile`" -f `"$composeFile`" restart" 2>&1 | Out-Null
            Write-Ok "Servicios reiniciados."
            Write-Host ""
            # Mostrar dashboard y salir
            $skip = $true
        }
        "L" {
            Write-Host ""
            Write-Warn "ADVERTENCIA: Se eliminaran todos los volumenes de datos."
            Write-Warn "SQL Server, PostgreSQL y MongoDB perderan todos sus datos."
            Write-Host ""
            $confirm = Read-Host "  Escribe CONFIRMAR para continuar"
            if ($confirm -ne "CONFIRMAR") {
                Write-Info "Cancelado."; exit 0
            }
            Write-Step "Eliminando contenedores y volumenes..."
            Invoke-Expression "$composeCmd --env-file `"$envFile`" -f `"$composeFile`" down -v" 2>&1 | Out-Null
            Write-Ok "Limpieza completa. Procediendo con instalacion limpia..."
            $systemExists = $false
            $skip = $false
        }
    }
}

# ── Validacion de puertos ─────────────────────────────────────────────────────
if (-not $skip) {

Write-Step "Validando puertos..."
Write-Host ""

# Puertos criticos segun el stack seleccionado
$portsToCheck = switch ($Stack) {
    "net"     { @(5080, 1435) }
    "php"     { @(80, 8443, 8084, 5433) }
    "indexer" { @(8001, 27018) }
    default   { @(80, 8443, 8084, 5080, 8001, 1435, 5433, 27018) }
}

$conflicts = @()
foreach ($port in $portsToCheck) {
    $owner = Get-PortOwner -Port $port
    if ($null -ne $owner) {
        $isDocker = $owner -match "docker|vpnkit|com\.docker|vmmem"
        if (-not $isDocker) {
            $conflicts += @{ Port = $port; Owner = $owner; Service = $PORT_MAP[$port] }
            Write-Warn "Puerto $port ocupado por: $owner"
            Write-Info "  Servicio afectado: $($PORT_MAP[$port])"
        } else {
            Write-Info "Puerto $port  —  en uso por Docker (OK)"
        }
    } else {
        Write-Ok "Puerto $port libre"
    }
}

if ($conflicts.Count -gt 0) {
    Write-Host ""
    Write-Warn "$($conflicts.Count) conflicto(s) de puerto detectado(s)."
    Write-Host ""
    Write-Host "  Opciones:" -ForegroundColor Cyan
    Write-Host "  [C]  Continuar de todas formas (los puertos del conflicto no funcionaran)" -ForegroundColor White
    Write-Host "  [S]  Salir y resolver los conflictos manualmente" -ForegroundColor White
    Write-Host ""
    Write-Info "Para liberar un puerto en Windows:"
    Write-Info "  netstat -ano | findstr :<puerto>"
    Write-Info "  Stop-Process -Id <PID> -Force"
    Write-Host ""

    $pChoice = ""
    do { $pChoice = (Read-Host "  Opcion [C/S]").ToUpper() } while ($pChoice -notin @("C","S"))
    if ($pChoice -eq "S") { Write-Info "Saliendo. Libera los puertos e intenta de nuevo."; exit 0 }
}

# ── Seleccion de modo ─────────────────────────────────────────────────────────
Write-Host ""
Write-Sep '─'
Write-Host ""
Write-Host "  Modo de instalacion:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  [1]  Sandbox     - 10,000 documentos de prueba generados"  -ForegroundColor White
Write-Host "       automaticamente. Sistema listo para demo."              -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [2]  Development - Sistema limpio."                          -ForegroundColor White
Write-Host "       Solo usuarios, roles y configuracion base."             -ForegroundColor DarkGray
Write-Host ""

$modeInput = ""
do { $modeInput = Read-Host "  Opcion [1/2]" } while ($modeInput -notin @("1","2"))

$seedMode      = if ($modeInput -eq "1") { "sandbox" } else { "dev" }
$seedModeLabel = if ($modeInput -eq "1") { "Sandbox (10,000 docs)" } else { "Development (limpio)" }
Write-Host ""
Write-Ok "Modo: $seedModeLabel"

# ── Red compartida (stacks separados) ─────────────────────────────────────────
if ($Stack -ne "all") {
    Write-Step "Verificando red compartida dms_backbone..."
    $netExists = docker network inspect dms_backbone 2>&1
    if ($LASTEXITCODE -ne 0) {
        docker network create dms_backbone | Out-Null
        Write-Ok "Red dms_backbone creada"
    } else {
        Write-Info "Red dms_backbone ya existe"
    }
    if (-not (Test-Path ".\data\uploads")) {
        New-Item -ItemType Directory -Path ".\data\uploads" -Force | Out-Null
        Write-Ok "Directorio .\data\uploads creado"
    } else {
        Write-Info ".\data\uploads ya existe"
    }
}

# ── Generar archivos .env ─────────────────────────────────────────────────────
$generarEnv = $true
if (Test-Path $envFile) {
    Write-Host ""
    Write-Warn "$envFile ya existe."
    $resp = Read-Host "  Sobreescribir? (y/N)"
    if ($resp -notmatch "^[yY]$") {
        Write-Info "Usando $envFile existente."
        $generarEnv = $false
    }
}

if ($generarEnv) {
    Write-Step "Configurando credenciales..."
    Write-Host ""
    Write-Info "Misma contrasena para SQL Server, PostgreSQL y MongoDB."
    Write-Host ""
    Write-Info "Requisitos (politica SQL Server):"
    Write-Info "  - Minimo 8 caracteres"
    Write-Info "  - Al menos una mayuscula  (A-Z)"
    Write-Info "  - Al menos una minuscula  (a-z)"
    Write-Info "  - Al menos un digito      (0-9)"
    Write-Info "  - Al menos un caracter especial  (Ej: MiPass1!)"
    Write-Host ""

    $MASTER_PASS = ""
    do {
        $pass1 = Read-Host "  Password" -AsSecureString
        $pass2 = Read-Host "  Confirmar" -AsSecureString

        $p1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1))
        $p2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2))

        if ($p1 -ne $p2) { Write-Warn "Las contrasenas no coinciden."; Write-Host ""; continue }

        $valid = $p1.Length -ge 8 -and $p1 -cmatch '[A-Z]' -and $p1 -cmatch '[a-z]' `
              -and $p1 -match '[0-9]' -and $p1 -match '[^a-zA-Z0-9]'

        if (-not $valid) { Write-Warn "La contrasena no cumple los requisitos."; Write-Host ""; continue }

        $MASTER_PASS = $p1
    } while ([string]::IsNullOrEmpty($MASTER_PASS))

    $apiKeyBytes = New-Object byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($apiKeyBytes)
    $API_KEY = ($apiKeyBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    $jwtBytes = New-Object byte[] 48
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($jwtBytes)
    $JWT_SECRET = [Convert]::ToBase64String($jwtBytes)

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    function Write-EnvFile { param([string]$Path,[string]$Content)
        Set-Content -Path $Path -Value $Content -Encoding UTF8; Write-Ok "$Path generado" }

    $envAll = @"
# Generado por setup.ps1 -- $ts
# NO commitear este archivo.

MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS
FASTAPI_API_KEY=$API_KEY
FASTAPI_URL=http://fastapi:8000
JWT_SECRET=$JWT_SECRET
DMS_SEED_MODE=$seedMode
"@
    $envNet = @"
# Stack 1 — .NET + SQL Server — $ts
MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS
FASTAPI_API_KEY=$API_KEY
JWT_SECRET=$JWT_SECRET
PHP_WEBHOOK_URL=http://php
FASTAPI_WEBHOOK_URL=http://fastapi:8000
DMS_SEED_MODE=$seedMode
"@
    $envPhp = @"
# Stack 2 — PHP + PostgreSQL + Nginx — $ts
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS
FASTAPI_API_KEY=$API_KEY
FASTAPI_URL=http://fastapi:8000
DOTNET_API_URL=http://dotnet:8080
"@
    $envIndexer = @"
# Stack 3 — FastAPI + MongoDB — $ts
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS
FASTAPI_API_KEY=$API_KEY
JWT_SECRET=$JWT_SECRET
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS
DOTNET_API_URL=http://dotnet:8080
"@

    switch ($Stack) {
        "net"     { Write-EnvFile ".env.net"     $envNet }
        "php"     { Write-EnvFile ".env.php"     $envPhp }
        "indexer" { Write-EnvFile ".env.indexer" $envIndexer }
        default   {
            Write-EnvFile ".env"         $envAll
            Write-EnvFile ".env.net"     $envNet
            Write-EnvFile ".env.php"     $envPhp
            Write-EnvFile ".env.indexer" $envIndexer
        }
    }
}

# ── Levantar contenedores ─────────────────────────────────────────────────────
Write-Step "Construyendo e iniciando contenedores..."
Write-Host ""
Write-Info "Primera ejecucion puede tomar 5-15 minutos (pull de imagenes + healthchecks)."
Write-Host ""
Write-Info "Comando: $composeCmd --env-file $envFile -f $composeFile up -d --build"
Write-Host ""

$workDir = (Get-Location).Path
$job = Start-Job -ScriptBlock {
    param($cc,$ef,$cf,$wd)
    Set-Location $wd
    Invoke-Expression "$cc --env-file `"$ef`" -f `"$cf`" up -d --build" | Out-String
    $LASTEXITCODE
} -ArgumentList $composeCmd,$envFile,$composeFile,$workDir

$elapsed = 0; $si = 0; $sp = @('|','/','-','\')
Write-Host "  [~] Iniciando... (0s)  " -NoNewline -ForegroundColor Yellow
while ($job.State -eq 'Running') {
    Start-Sleep 1; $elapsed++
    Write-Host ("`r  $($sp[$si % 4])  Iniciando... ($elapsed`s)  ") -NoNewline -ForegroundColor Yellow
    $si++
}

$res      = Receive-Job $job -Wait -AutoRemoveJob
$arr      = @($res)
$exitCode = if ($arr.Count -gt 0 -and $arr[-1] -is [int]) { [int]$arr[-1] } else { 0 }
$dockerOut = if ($arr.Count -gt 1) { $arr[0].ToString().Trim() } else { "" }
Write-Host ""

if ($dockerOut) { $dockerOut -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" }; Write-Host "" }

if ($exitCode -ne 0) {
    Write-Err "Error al iniciar contenedores."
    Write-Host ""
    Write-Host "  Causas comunes:" -ForegroundColor Yellow
    Write-Info "  - Puerto ocupado: revisa con  .\setup.ps1 -Diagnose  opcion [2]"
    Write-Info "  - Imagen corrupta: docker system prune -f  (borra cache)"
    Write-Info "  - Sin espacio:    docker system df"
    Write-Info "  - Logs:           $composeCmd -f $composeFile logs"
    exit 1
}
Write-Ok "Contenedores iniciados"

# ── Healthchecks ──────────────────────────────────────────────────────────────
function Wait-Container {
    param([string]$DisplayName,[string]$Container,[int]$TimeoutSecs=120,[bool]$NeedsHealth=$true)
    Write-Host ("  [~] Esperando " + $DisplayName + "... (0s)") -NoNewline -ForegroundColor Yellow
    $elapsed = 0; $interval = 5
    while ($elapsed -lt $TimeoutSecs) {
        Start-Sleep $interval; $elapsed += $interval
        Write-Host ("`r  [~] Esperando $DisplayName... ($elapsed`s)   ") -NoNewline -ForegroundColor Yellow
        if ($NeedsHealth) {
            $st = docker inspect --format="{{.State.Health.Status}}" $Container 2>$null
            if ($st -eq "healthy") { Write-Host ("`r  [OK] $DisplayName - healthy ($elapsed`s)              ") -ForegroundColor Green; return $true }
            if ($st -eq "unhealthy") { Write-Host ("`r  [X]  $DisplayName - unhealthy -- docker logs $Container") -ForegroundColor Red; return $false }
        } else {
            $st = docker inspect --format="{{.State.Status}}" $Container 2>$null
            if ($st -eq "running") { Write-Host ("`r  [OK] $DisplayName - running ($elapsed`s)              ") -ForegroundColor Green; return $true }
            if ($st -in @("exited","dead")) { Write-Host ("`r  [X]  $DisplayName - crashed -- docker logs $Container") -ForegroundColor Red; return $false }
        }
    }
    Write-Host ("`r  [!]  $DisplayName - timeout ($TimeoutSecs`s)") -ForegroundColor Yellow; return $false
}

Write-Step "Esperando servicios..."
Write-Host ""
switch ($Stack) {
    "net" {
        Write-Info "SQL Server puede tardar hasta 90s en primer arranque."
        $null = Wait-Container "SQL Server" "dms_sqlserver" 120 $true
        $null = Wait-Container ".NET Core"  "dms_dotnet"    90  $false
    }
    "php" {
        $null = Wait-Container "PostgreSQL" "dms_postgres" 60 $true
        $null = Wait-Container "PHP-FPM"    "dms_php"      60 $false
        $null = Wait-Container "Nginx"      "dms_nginx"    30 $false
    }
    "indexer" {
        $null = Wait-Container "MongoDB"  "dms_mongodb" 60 $true
        $null = Wait-Container "FastAPI"  "dms_fastapi" 60 $false
    }
    default {
        Write-Info "SQL Server puede tardar hasta 90s en primer arranque."
        $null = Wait-Container "SQL Server"  "dms_sqlserver" 120 $true
        $null = Wait-Container "PostgreSQL"  "dms_postgres"  60  $true
        $null = Wait-Container "MongoDB"     "dms_mongodb"   60  $true
        $null = Wait-Container "FastAPI"     "dms_fastapi"   60  $false
        $null = Wait-Container "PHP-FPM"     "dms_php"       90  $false
        $null = Wait-Container ".NET Core"   "dms_dotnet"    90  $false
        $null = Wait-Container "Nginx"       "dms_nginx"     30  $false
    }
}

} # fin bloque if (-not $skip)

# ── Dashboard final ───────────────────────────────────────────────────────────
Write-Host ""
Write-Sep '═'
Write-Host "  INSTALACION COMPLETA  [stack: $Stack]" -ForegroundColor White
Write-Sep '═'
Write-Host ""

Write-Host "  PORTALES" -ForegroundColor Cyan
switch ($Stack) {
    "net" {
        Write-Host "  -> .NET Gestion Documental     http://localhost:8084"      -ForegroundColor White
        Write-Host "  -> .NET Acceso directo         http://localhost:5080"      -ForegroundColor DarkGray
    }
    "php" {
        Write-Host "  -> Portal Publico  (PHP)       http://localhost"           -ForegroundColor White
        Write-Host "  -> Motor Busqueda  (FastAPI)   https://localhost:8443"     -ForegroundColor White
        Write-Host "  -> Gestion interna (.NET)      http://localhost:8084"      -ForegroundColor White
    }
    "indexer" {
        Write-Host "  -> FastAPI Swagger              http://localhost:8001/docs" -ForegroundColor White
        Write-Host "  -> Admin Viewer                 http://localhost:8001/admin/viewer" -ForegroundColor White
    }
    default {
        Write-Host "  -> Portal Publico  (PHP)       http://localhost"            -ForegroundColor White
        Write-Host "  -> Gestion interna (.NET)      http://localhost:8084"       -ForegroundColor White
        Write-Host "  -> Motor Busqueda  (FastAPI)   https://localhost:8443"      -ForegroundColor White
        Write-Host "  -> FastAPI Swagger             http://localhost:8001/docs"  -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  BASES DE DATOS" -ForegroundColor Cyan
switch ($Stack) {
    "net"     { Write-Host "  -> SQL Server    localhost:1435"  -ForegroundColor DarkGray }
    "php"     { Write-Host "  -> PostgreSQL    localhost:5433"  -ForegroundColor DarkGray }
    "indexer" { Write-Host "  -> MongoDB       localhost:27018" -ForegroundColor DarkGray }
    default   {
        Write-Host "  -> SQL Server    localhost:1435"  -ForegroundColor DarkGray
        Write-Host "  -> PostgreSQL    localhost:5433"  -ForegroundColor DarkGray
        Write-Host "  -> MongoDB       localhost:27018" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Sep '─'
Write-Host "  USUARIOS  (password: Calidad#2026Dev)" -ForegroundColor Cyan
Write-Sep '─'
Write-Host ("  {0,-16} {1,-38} {2}" -f "ROL","EMAIL","EMPRESA") -ForegroundColor DarkGray
Write-Sep '─'
@(
    @("SuperAdmin",     "super@qualitydms.local",        "Global"),
    @("Admin",          "admin@qualitydms.local",        "ACME"),
    @("AdminEmpresa",   "adminempresa@qualitydms.local", "ACME"),
    @("QualityManager", "calidad@qualitydms.local",      "ACME"),
    @("Approver",       "aprobador1@qualitydms.local",   "ACME"),
    @("Approver",       "aprobador2@qualitydms.local",   "ACME"),
    @("Author",         "autor@qualitydms.local",        "ACME"),
    @("Viewer",         "lector@qualitydms.local",       "ACME"),
    @("AdminEmpresa",   "admin.beta@qualitydms.local",   "BETA")
) | ForEach-Object { Write-Host ("  {0,-16} {1,-38} {2}" -f $_[0],$_[1],$_[2]) -ForegroundColor White }

if ($seedMode -eq "sandbox") {
    Write-Host ""
    Write-Sep '─'
    Write-Host "  DATOS SANDBOX" -ForegroundColor Cyan
    Write-Sep '─'
    Write-Host "  [OK] 10,000 documentos en SQL Server"                   -ForegroundColor Green
    Write-Host "  [OK]  7,000 aprobados → PostgreSQL + MongoDB (FTS)"     -ForegroundColor Green
    Write-Host "  [OK]  2,000 en revision  |  1,000 borradores"           -ForegroundColor Green
}

Write-Host ""
Write-Sep '─'
Write-Host "  COMANDOS UTILES" -ForegroundColor Cyan
Write-Sep '─'
Write-Host "  Estado:      $composeCmd -f $composeFile ps"            -ForegroundColor DarkGray
Write-Host "  Logs:        $composeCmd -f $composeFile logs -f"       -ForegroundColor DarkGray
Write-Host "  Detener:     $composeCmd -f $composeFile down"          -ForegroundColor DarkGray
Write-Host "  Diagnostico: .\setup.ps1 -Diagnose [-Stack $Stack]"     -ForegroundColor DarkGray
Write-Host ""
Write-Sep '═'
Write-Host ""

# ============================================================
#  DMS Setup -- Windows PowerShell
#
#  Instalacion completa:    .\setup.ps1            (3 stacks)
#  Solo .NET + SQL Server:  .\setup.ps1 -Stack dotnet
#  Solo PHP + PostgreSQL:   .\setup.ps1 -Stack php
#  Solo FastAPI + Mongo+Nginx: .\setup.ps1 -Stack fastapi
#
#  Subcomandos de diagnostico (no interactivos):
#    .\setup.ps1 status     estado de contenedores
#    .\setup.ps1 ports      puertos del sistema
#    .\setup.ps1 logs       logs (todos / -Stack <s>)
#    .\setup.ps1 validate   HTTP + BD + storage + busqueda
#  Menu interactivo:        .\setup.ps1 -Diagnose
# ============================================================

param(
    [Parameter(Position=0)]
    [string]$Command = "all",
    [ValidateSet("all","dotnet","php","fastapi","net","indexer")]
    [string]$Stack = "all",
    [switch]$Diagnose
)

# ── Normalizar comando/stack ──────────────────────────────────────────────────
# Subcomandos posicionales: .\setup.ps1 status|ports|logs|validate
$Subcommand = $null
switch ($Command.ToLower()) {
    "status"   { $Subcommand = "status" }
    "ports"    { $Subcommand = "ports" }
    "logs"     { $Subcommand = "logs" }
    "validate" { $Subcommand = "validate" }
    "all"      { }                                  # default: instalacion
    default    { $Stack = $Command }                # trata el posicional como stack
}
# Alias legacy de nombres de stack
switch ($Stack.ToLower()) {
    "net"     { $Stack = "dotnet" }
    "indexer" { $Stack = "fastapi" }
}

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ── Helpers de output ─────────────────────────────────────────────────────────
function Write-Step { param($msg) Write-Host ""; Write-Host "  $msg" -ForegroundColor Cyan }
function Write-Ok   { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "       $msg" -ForegroundColor Gray }
function Write-Sep  { param([string]$c='-',[int]$n=60) Write-Host ("  " + ($c * $n)) -ForegroundColor DarkGray }

# ── Puertos del sistema ───────────────────────────────────────────────────────
# Hashtables normales (acceso por clave int). Orden de display en $PORT_ORDER.
$PORT_ORDER = @(80, 8443, 8084, 5080, 8001, 1435, 5433, 27018)
$PORT_MAP = @{
    80    = "Nginx -> PHP (portal publico)"
    8443  = "Nginx -> FastAPI (busqueda HTTPS)"
    8084  = "Nginx -> .NET  (gestion interna)"
    5080  = ".NET directo (CalidadSYS)"
    8001  = "FastAPI directo (Swagger)"
    1435  = "SQL Server"
    5433  = "PostgreSQL"
    27018 = "MongoDB"
}

# ── Mapa puerto host -> variable de entorno (.env) para reasignacion ──────────
$PORT_ENV = @{
    80    = "NGINX_HTTP_PORT"
    8443  = "NGINX_HTTPS_PORT"
    8084  = "NGINX_DOTNET_PORT"
    5080  = "DOTNET_PORT"
    8001  = "FASTAPI_PORT"
    1435  = "SQLSERVER_PORT"
    5433  = "POSTGRES_HOST_PORT"
    27018 = "MONGO_HOST_PORT"
}
# Puertos host efectivos (se actualizan si el usuario reasigna)
$PortNow = @{}
foreach ($k in $PORT_ORDER) { $PortNow[$k] = $k }

# ── Contenedores del sistema ──────────────────────────────────────────────────
$DMS_CONTAINERS = @(
    "dms_nginx","dms_dotnet","dms_sqlserver",
    "dms_postgres","dms_php","dms_fastapi","dms_mongodb"
)

# ── Upsert KEY=VALUE en un archivo .env ───────────────────────────────────────
function Set-EnvVar {
    param([string]$File, [string]$Key, [string]$Value)
    $line = "$Key=$Value"
    if (Test-Path $File) {
        $content = Get-Content $File
        if ($content -match "^$Key=") {
            ($content -replace "^$Key=.*", $line) | Set-Content $File -Encoding UTF8
        } else {
            Add-Content $File -Value $line -Encoding UTF8
        }
    } else {
        Set-Content $File -Value $line -Encoding UTF8
    }
}

# ── Buscar el siguiente puerto libre a partir de uno dado ─────────────────────
function Get-NextFreePort {
    param([int]$Start)
    for ($p = $Start; $p -lt $Start + 200; $p++) {
        if ($null -eq (Get-PortOwner -Port $p)) { return $p }
    }
    return $Start
}

# ── Detectar proceso que ocupa un puerto ──────────────────────────────────────
function Get-PortOwner {
    param([int]$Port)
    $lines = netstat -ano 2>$null | Select-String "[\s:]$Port\s"
    foreach ($line in $lines) {
        if ($line -match "LISTENING|LISTEN") {
            $parts  = $line.Line.Trim() -split '\s+'
            $procId = $parts[-1]
            try {
                $proc = Get-Process -Id ([int]$procId) -ErrorAction Stop
                return "$($proc.ProcessName) (PID $procId)"
            } catch { return "PID $procId" }
        }
    }
    return $null
}

function Test-PortFree { param([int]$Port); return ($null -eq (Get-PortOwner -Port $Port)) }

# ── Cargar variables de .env al entorno del proceso (para diagnosticos) ───────
function Import-DotEnv {
    param([string]$File = ".env")
    if (-not (Test-Path $File)) { return }
    foreach ($line in Get-Content $File) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $k, $v = $line -split '=', 2
        $k = $k.Trim(); $v = $v.Trim()
        if ($k) { Set-Item -Path "Env:$k" -Value $v -ErrorAction SilentlyContinue }
    }
}

# ── Tabla de stacks (3 docker-compose independientes) ────────────────────────
# Todos comparten el mismo .env raiz, la red 'dms_backbone' y el volumen 'documentos'.
$STACK_TABLE = [ordered]@{
    dotnet  = @{ Project = "dms-dotnet";  Compose = "docker-compose.dotnet.yml"  }
    php     = @{ Project = "dms-php";      Compose = "docker-compose.php.yml"     }
    fastapi = @{ Project = "dms-fastapi";  Compose = "docker-compose.fastapi.yml" }
}
$SHARED_ENV = ".env"

# Devuelve la lista de claves de stack a operar segun seleccion ("all" = los 3).
function Get-StackList {
    param([string]$s)
    if ($s -eq "all" -or [string]::IsNullOrEmpty($s)) { return @($STACK_TABLE.Keys) }
    return @($s)
}

# Asegura red compartida + volumen externo de documentos (idempotente).
function Initialize-SharedInfra {
    $null = docker network inspect dms_backbone 2>&1
    if ($LASTEXITCODE -ne 0) { docker network create dms_backbone | Out-Null; Write-Ok "Red dms_backbone creada" }
    else { Write-Info "Red dms_backbone ya existe" }
    $null = docker volume inspect documentos 2>&1
    if ($LASTEXITCODE -ne 0) { docker volume create documentos | Out-Null; Write-Ok "Volumen 'documentos' creado" }
    else { Write-Info "Volumen 'documentos' ya existe" }
}

# Levanta un stack (build + up -d) con su nombre de proyecto.
function Invoke-StackUp {
    param([string]$composeCmd, [string]$stackKey)
    $s = $STACK_TABLE[$stackKey]
    Invoke-Expression "$composeCmd -p $($s.Project) --env-file `"$SHARED_ENV`" -f `"$($s.Compose)`" up -d --build" | Out-String
}

# Ejecuta un comando compose (down/restart/ps/logs...) sobre uno o todos los stacks.
function Invoke-StackCompose {
    param([string]$composeCmd, [string]$stackSel, [string]$action)
    foreach ($k in (Get-StackList $stackSel)) {
        $s = $STACK_TABLE[$k]
        Write-Info "[$($s.Project)] $action"
        Invoke-Expression "$composeCmd -p $($s.Project) --env-file `"$SHARED_ENV`" -f `"$($s.Compose)`" $action"
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
    foreach ($port in $PORT_ORDER) {
        $owner = Get-PortOwner -Port $port
        if ($null -eq $owner) {
            Write-Host ("  {0,-6} {1,-38} {2}" -f $port, $PORT_MAP[$port], "libre") -ForegroundColor DarkGray
        } else {
            $color = if ($owner -match "docker|vpnkit|com.docker") { "Green" } else { "Yellow" }
            Write-Host ("  {0,-6} {1,-38} {2}" -f $port, $PORT_MAP[$port], "OCUPADO por $owner") -ForegroundColor $color
        }
    }
    Write-Host ""
}

function Show-Logs {
    param([int]$Tail = 60)
    Write-Host ""
    Write-Host "  LOGS (ultimas $Tail lineas por contenedor)" -ForegroundColor Cyan
    Write-Sep
    foreach ($c in $DMS_CONTAINERS) {
        $exists = docker ps -a --filter "name=^$c$" --format "{{.Names}}" 2>$null
        if (-not $exists) { Write-Warn "$c  —  no existe"; continue }
        Write-Host ""
        Write-Host "  ===== $c =====" -ForegroundColor DarkCyan
        docker logs --tail $Tail $c 2>&1 | ForEach-Object { Write-Host "  $_" }
    }
    Write-Host ""
}

function Restart-Services {
    param([string]$composeCmd, [string]$stackSel)
    Write-Host ""
    Write-Warn "Reiniciando servicios [stack: $stackSel]..."
    Invoke-StackCompose -composeCmd $composeCmd -stackSel $stackSel -action "restart"
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
    # Ignorar certificados self-signed + TLS 1.2 (compatible 5.1 y 7).
    try {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
    } catch {}
    foreach ($ep in $endpoints) {
        try {
            $resp = Invoke-WebRequest -Uri $ep.Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            Write-Ok "$($ep.Label)  ->  $($resp.StatusCode)"
        } catch {
            $code = $null
            try { $code = $_.Exception.Response.StatusCode } catch {}
            if ($code) { Write-Warn "$($ep.Label)  ->  HTTP $([int]$code)" }
            else       { Write-Err  "$($ep.Label)  ->  Sin respuesta" }
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
    # Volumen externo compartido
    $null = docker volume inspect documentos 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Ok "Volumen 'documentos' existe (compartido por los 3 stacks)" }
    else { Write-Warn "Volumen 'documentos' NO existe (crear con: docker volume create documentos)" }

    # Conteo de archivos por contenedor (cada uno monta 'documentos')
    foreach ($pair in @(@("dms_dotnet","/app/uploads"), @("dms_php","/var/dms/uploads"), @("dms_fastapi","/app/uploads"))) {
        try {
            $r = docker exec $pair[0] sh -c "find $($pair[1]) -type f 2>/dev/null | wc -l" 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok "$($pair[0]) $($pair[1]) →  $($r.Trim()) archivos" }
            else { Write-Warn "$($pair[0]) no accesible" }
        } catch { Write-Warn "$($pair[0]) no accesible" }
    }
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
    param([string]$composeCmd, [string]$stackSel)
    do {
        Write-Host ""
        Write-Sep '═'
        Write-Host "  DIAGNOSTICO DEL SISTEMA  [stack: $stackSel]" -ForegroundColor Cyan
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
            "3" { Show-Logs }
            "4" { Restart-Services -composeCmd $composeCmd -stackSel $stackSel }
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

$envFile = $SHARED_ENV

# ── Subcomandos de diagnostico (no interactivos) ──────────────────────────────
if ($Subcommand) {
    Import-DotEnv -File $SHARED_ENV
    switch ($Subcommand) {
        "status"   { Show-ContainerStatus }
        "ports"    { Show-PortStatus }
        "logs"     { Show-Logs }
        "validate" {
            Test-HttpConnectivity
            Test-Databases
            Test-Storage
            Test-SearchEngine
        }
    }
    exit 0
}

# ── Modo diagnostico puro (menu interactivo) ──────────────────────────────────
if ($Diagnose) {
    Import-DotEnv -File $SHARED_ENV
    $composeCmd = Get-ComposeCmd
    if (-not $composeCmd) { Write-Err "Docker Compose no encontrado."; exit 1 }
    Show-DiagnosticMenu -composeCmd $composeCmd -stackSel $Stack
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
            Show-DiagnosticMenu -composeCmd $composeCmd -stackSel $Stack
            exit 0
        }
        "R" {
            Write-Step "Reiniciando servicios existentes..."
            Invoke-StackCompose -composeCmd $composeCmd -stackSel $Stack -action "restart" 2>&1 | Out-Null
            Write-Ok "Servicios reiniciados."
            Write-Host ""
            # Mostrar dashboard y salir
            $skip = $true
        }
        "L" {
            Write-Host ""
            Write-Warn "ADVERTENCIA: Se eliminaran los volumenes de datos de los stacks."
            Write-Warn "SQL Server, PostgreSQL y MongoDB perderan sus datos."
            Write-Warn "El volumen externo 'documentos' NO se elimina (compartido)."
            Write-Host ""
            $confirm = Read-Host "  Escribe CONFIRMAR para continuar"
            if ($confirm -ne "CONFIRMAR") {
                Write-Info "Cancelado."; exit 0
            }
            Write-Step "Eliminando contenedores y volumenes..."
            Invoke-StackCompose -composeCmd $composeCmd -stackSel $Stack -action "down -v" 2>&1 | Out-Null
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
    "dotnet"  { @(5080, 1435) }
    "php"     { @(5433) }
    "fastapi" { @(80, 8443, 8084, 8001, 27018) }
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

$PortOverride = @{}
if ($conflicts.Count -gt 0) {
    Write-Host ""
    Write-Warn "$($conflicts.Count) conflicto(s) de puerto detectado(s)."
    Write-Host ""
    Write-Host "  Opciones:" -ForegroundColor Cyan
    Write-Host "  [R]  Reasignar los puertos en conflicto (cambia el puerto host)" -ForegroundColor White
    Write-Host "  [C]  Continuar de todas formas (los puertos en conflicto no funcionaran)" -ForegroundColor White
    Write-Host "  [S]  Salir y resolver los conflictos manualmente" -ForegroundColor White
    Write-Host ""
    Write-Info "Para liberar un puerto en Windows:"
    Write-Info "  netstat -ano | findstr :<puerto>"
    Write-Info "  Stop-Process -Id <PID> -Force"
    Write-Host ""

    $pChoice = ""
    do { $pChoice = (Read-Host "  Opcion [R/C/S]").ToUpper() } while ($pChoice -notin @("R","C","S"))
    if ($pChoice -eq "S") { Write-Info "Saliendo. Libera los puertos e intenta de nuevo."; exit 0 }

    if ($pChoice -eq "R") {
        Write-Host ""
        foreach ($c in $conflicts) {
            $port = [int]$c.Port
            $envVar = $PORT_ENV[$port]
            if (-not $envVar) { Write-Warn "Puerto $port no es reasignable (interno)."; continue }
            $suggest = Get-NextFreePort -Start ($port + 1)
            Write-Host "  Puerto $port ($($PORT_MAP[$port]))" -ForegroundColor Cyan
            $inp = Read-Host "    Nuevo puerto [Enter = $suggest]"
            $newPort = if ([string]::IsNullOrWhiteSpace($inp)) { $suggest } else { [int]$inp }
            # Validar que el nuevo puerto este libre
            if ($null -ne (Get-PortOwner -Port $newPort)) {
                Write-Warn "    Puerto $newPort tambien ocupado. Usando $suggest."
                $newPort = $suggest
            }
            $PortOverride[$port] = $newPort
            $PortNow[$port]      = $newPort
            Write-Ok "    $port → $newPort  ($envVar)"
        }
        Write-Host ""
        Write-Info "Los nuevos puertos se guardaran en .env antes de levantar."
    }
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

# ── Infraestructura compartida: red dms_backbone + volumen documentos ─────────
Write-Step "Verificando infraestructura compartida..."
Initialize-SharedInfra

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

    # .env raiz unico — consumido por los 3 docker-compose (--env-file .env).
    # Las URLs cross-stack van inline en los compose (dms_php/dms_dotnet/dms_fastapi/dms_nginx).
    $envAll = @"
# Generado por setup.ps1 -- $ts
# NO commitear este archivo.

# -- SQL Server
MSSQL_SA_PASSWORD=$MASTER_PASS
MSSQL_DB=QualityDMS

# -- PostgreSQL (cross-stack: fastapi/documents_sync apunta a dms_postgres)
POSTGRES_HOST=dms_postgres
POSTGRES_PORT=5432
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$MASTER_PASS

# -- MongoDB
MONGO_USER=mongoadmin
MONGO_PASSWORD=$MASTER_PASS

# -- Secretos compartidos
FASTAPI_API_KEY=$API_KEY
JWT_SECRET=$JWT_SECRET

# -- URLs cross-stack (container names sobre dms_backbone)
FASTAPI_URL=http://dms_fastapi:8000

# -- Seed: sandbox | dev | none
DMS_SEED_MODE=$seedMode
"@

    Write-EnvFile $SHARED_ENV $envAll
}

# ── Persistir puertos reasignados (sobre el .env ya generado) ─────────────────
if ($PortOverride.Count -gt 0) {
    Write-Step "Aplicando puertos reasignados a .env..."
    foreach ($p in $PortOverride.Keys) {
        Set-EnvVar -File $SHARED_ENV -Key $PORT_ENV[$p] -Value ([string]$PortOverride[$p])
        Write-Ok "$($PORT_ENV[$p])=$($PortOverride[$p])  (era $p)"
    }
}

# ── Levantar contenedores (1 o varios stacks independientes) ──────────────────
Write-Step "Construyendo e iniciando contenedores..."
Write-Host ""
Write-Info "Primera ejecucion puede tomar 5-15 minutos (pull de imagenes + builds)."
Write-Host ""

# Orden: dotnet (SQL) y php (Postgres) primero; fastapi+nginx al final
# (nginx hace proxy a dms_dotnet/dms_php, que deben existir en la red).
$bootOrder = @("dotnet","php","fastapi") | Where-Object { $_ -in (Get-StackList $Stack) }

$failed = $false
foreach ($k in $bootOrder) {
    $s = $STACK_TABLE[$k]
    Write-Host ""
    Write-Info "[$($s.Project)]  $composeCmd -p $($s.Project) -f $($s.Compose) up -d --build"
    $out = Invoke-StackUp -composeCmd $composeCmd -stackKey $k
    if ($LASTEXITCODE -ne 0) {
        Write-Err "[$($s.Project)] fallo (exit $LASTEXITCODE)"
        if ($out) { $out -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "  $_" } }
        $failed = $true
        break
    }
    Write-Ok "[$($s.Project)] iniciado"
}

if ($failed) {
    Write-Host ""
    Write-Host "  Causas comunes:" -ForegroundColor Yellow
    Write-Info "  - Puerto ocupado: .\setup.ps1 ports"
    Write-Info "  - Imagen corrupta: docker system prune -f"
    Write-Info "  - Sin espacio:    docker system df"
    Write-Info "  - Logs:           .\setup.ps1 logs"
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
    "dotnet" {
        Write-Info "SQL Server puede tardar hasta 90s en primer arranque."
        $null = Wait-Container "SQL Server" "dms_sqlserver" 120 $true
        $null = Wait-Container ".NET Core"  "dms_dotnet"    90  $false
    }
    "php" {
        $null = Wait-Container "PostgreSQL" "dms_postgres" 60 $true
        $null = Wait-Container "PHP-FPM"    "dms_php"      60 $false
    }
    "fastapi" {
        $null = Wait-Container "MongoDB"  "dms_mongodb" 60 $true
        $null = Wait-Container "FastAPI"  "dms_fastapi" 60 $false
        $null = Wait-Container "Nginx"    "dms_nginx"   30 $false
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

# Puertos host efectivos (reflejan reasignaciones)
$hp    = $PortNow[80]
$root  = if ($hp -eq 80) { "http://localhost" } else { "http://localhost:$hp" }
$pHttps = $PortNow[8443]; $pDnet = $PortNow[8084]; $pFa = $PortNow[8001]; $pNet5080 = $PortNow[5080]

Write-Host "  PORTALES  (routing por path via Nginx)" -ForegroundColor Cyan
Write-Host "  -> Portal Publico  (PHP)       $root/php/"      -ForegroundColor White
Write-Host "  -> Gestion interna (.NET)      $root/dotnet/"   -ForegroundColor White
Write-Host "  -> Motor Busqueda  (FastAPI)   $root/fastapi/"  -ForegroundColor White
Write-Host ""
Write-Host "  ACCESO DIRECTO (debug)" -ForegroundColor DarkGray
Write-Host "  -> .NET directo                http://localhost:$pNet5080"   -ForegroundColor DarkGray
Write-Host "  -> .NET via Nginx              http://localhost:$pDnet"      -ForegroundColor DarkGray
Write-Host "  -> FastAPI Swagger             http://localhost:$pFa/docs"   -ForegroundColor DarkGray
Write-Host "  -> FastAPI HTTPS               https://localhost:$pHttps"    -ForegroundColor DarkGray

Write-Host ""
Write-Host "  BASES DE DATOS" -ForegroundColor Cyan
switch ($Stack) {
    "dotnet"  { Write-Host "  -> SQL Server    localhost:$($PortNow[1435])"  -ForegroundColor DarkGray }
    "php"     { Write-Host "  -> PostgreSQL    localhost:$($PortNow[5433])"  -ForegroundColor DarkGray }
    "fastapi" { Write-Host "  -> MongoDB       localhost:$($PortNow[27018])" -ForegroundColor DarkGray }
    default   {
        Write-Host "  -> SQL Server    localhost:$($PortNow[1435])"  -ForegroundColor DarkGray
        Write-Host "  -> PostgreSQL    localhost:$($PortNow[5433])"  -ForegroundColor DarkGray
        Write-Host "  -> MongoDB       localhost:$($PortNow[27018])" -ForegroundColor DarkGray
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
Write-Host "  Estado:      .\setup.ps1 status"                        -ForegroundColor DarkGray
Write-Host "  Puertos:     .\setup.ps1 ports"                         -ForegroundColor DarkGray
Write-Host "  Logs:        .\setup.ps1 logs"                          -ForegroundColor DarkGray
Write-Host "  Validar:     .\setup.ps1 validate"                      -ForegroundColor DarkGray
Write-Host "  Detener:     docker compose -p dms-fastapi -f docker-compose.fastapi.yml down" -ForegroundColor DarkGray
Write-Host "  Diagnostico: .\setup.ps1 -Diagnose"                     -ForegroundColor DarkGray
Write-Host ""
Write-Sep '═'
Write-Host ""

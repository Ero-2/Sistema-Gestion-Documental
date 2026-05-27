#!/usr/bin/env bash
# ============================================================
#  install.sh — CLI Installer
#  Sistema Integral de Gestión Documental (DMS)
#
#  Uso:
#    bash install.sh
#  O descarga y ejecuta en un paso:
#    curl -fsSL https://raw.githubusercontent.com/Ero-2/Sistema-Gestion-Documental/mAIN/install.sh | bash
# ============================================================

set -euo pipefail

# ── Colores ANSI ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# ── Helpers ───────────────────────────────────────────────────
line()  { echo -e "${CYAN}$(printf '═%.0s' {1..58})${NC}"; }
ok()    { echo -e "  ${GREEN}[✓]${NC}  $1"; }
warn()  { echo -e "  ${YELLOW}[!]${NC}  $1"; }
err()   { echo -e "  ${RED}[✗]${NC}  $1"; }
info()  { echo -e "  ${GRAY}→${NC}   $1"; }
step()  { echo -e "\n${BOLD}${WHITE}$1${NC}"; }

# ── Banner ────────────────────────────────────────────────────
clear
echo ""
line
echo -e "${CYAN}${BOLD}"
echo "  ██████╗ ███╗   ███╗███████╗"
echo "  ██╔══██╗████╗ ████║██╔════╝"
echo "  ██║  ██║██╔████╔██║███████╗"
echo "  ██║  ██║██║╚██╔╝██║╚════██║"
echo "  ██████╔╝██║ ╚═╝ ██║███████║"
echo "  ╚═════╝ ╚═╝     ╚═╝╚══════╝"
echo -e "${NC}"
echo -e "${WHITE}${BOLD}  Sistema Integral de Gestión Documental${NC}"
echo -e "${GRAY}  Installer v1.0 · Multi-Stack · Docker${NC}"
line
echo ""

# ══════════════════════════════════════════════════════════════
#  PASO 1 — Verificar dependencias
# ══════════════════════════════════════════════════════════════
step "  [1/5]  Verificando dependencias..."
echo ""

# git
if ! command -v git &>/dev/null; then
  err "git no encontrado."
  info "Instálalo desde: https://git-scm.com"
  exit 1
fi
ok "git $(git --version | awk '{print $3}')"

# Docker daemon
if ! docker info &>/dev/null 2>&1; then
  err "Docker no está corriendo."
  info "Inicia Docker Desktop y vuelve a ejecutar este script."
  exit 1
fi
ok "Docker $(docker --version | awk '{print $3}' | tr -d ',')"

# docker compose (v2 preferido, v1 como fallback)
if docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  COMPOSE_VER=$(docker compose version --short 2>/dev/null || echo "v2")
  ok "docker compose ${COMPOSE_VER}"
elif command -v docker-compose &>/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
  ok "docker-compose (legacy v1)"
else
  err "docker compose no encontrado."
  info "Actualiza Docker Desktop o instala el plugin Compose."
  exit 1
fi

# openssl para generar API key
if command -v openssl &>/dev/null; then
  HAS_OPENSSL=true
  ok "openssl $(openssl version | awk '{print $2}')"
else
  HAS_OPENSSL=false
  warn "openssl no encontrado — se usará /dev/urandom como fallback."
fi

# ══════════════════════════════════════════════════════════════
#  PASO 2 — Clonar repositorio
# ══════════════════════════════════════════════════════════════
step "  [2/5]  Clonar repositorio..."

REPO_URL="https://github.com/Ero-2/Sistema-Gestion-Documental.git"
DEFAULT_DIR="Sistema-Gestion-Documental"

echo ""
echo -e "  Repositorio  : ${CYAN}${REPO_URL}${NC}"
echo -ne "  Directorio   ${GRAY}[${DEFAULT_DIR}]${NC}: "
read -r INPUT_DIR
INSTALL_DIR="${INPUT_DIR:-$DEFAULT_DIR}"

echo ""

if [ -d "$INSTALL_DIR/.git" ]; then
  warn "El directorio '${INSTALL_DIR}' ya es un repositorio Git."
  echo -ne "  ¿Continuar con ese directorio? (s/N): "
  read -r RESP_DIR
  if [[ ! "$RESP_DIR" =~ ^[sS]$ ]]; then
    err "Instalación cancelada."
    exit 1
  fi
  ok "Usando directorio existente."
elif [ -d "$INSTALL_DIR" ]; then
  err "El directorio '${INSTALL_DIR}' ya existe pero no es un repo Git."
  info "Bórralo manualmente o elige otro nombre."
  exit 1
else
  info "Clonando repositorio..."
  git clone "$REPO_URL" "$INSTALL_DIR"
  ok "Repositorio clonado en ./${INSTALL_DIR}"
fi

cd "$INSTALL_DIR"

# ══════════════════════════════════════════════════════════════
#  PASO 3 — Contraseña maestra y generación de .env
# ══════════════════════════════════════════════════════════════
step "  [3/5]  Configuración de credenciales..."

GENERATE_ENV=true

if [ -f ".env" ]; then
  echo ""
  warn "Ya existe un archivo .env."
  echo -ne "  ¿Sobreescribir? (s/N): "
  read -r RESP_ENV
  if [[ ! "$RESP_ENV" =~ ^[sS]$ ]]; then
    ok "Usando .env existente."
    GENERATE_ENV=false
  fi
fi

if [ "$GENERATE_ENV" = true ]; then
  echo ""
  echo -e "  ${YELLOW}Crea una contraseña maestra para todos los servicios.${NC}"
  echo -e "  ${GRAY}  · Mínimo 6 caracteres${NC}"
  echo -e "  ${GRAY}  · Se usará para SQL Server, PostgreSQL y MongoDB${NC}"
  echo ""

  while true; do
    # Leer contraseña oculta (sin eco)
    echo -ne "  ${BOLD}🔐 Contraseña :${NC} "
    read -rs PASS1
    echo ""
    echo -ne "  ${BOLD}🔐 Confirmar  :${NC} "
    read -rs PASS2
    echo ""

    if [ "$PASS1" != "$PASS2" ]; then
      err "Las contraseñas no coinciden. Intenta de nuevo."
      echo ""
      continue
    fi
    if [ "${#PASS1}" -lt 6 ]; then
      err "Mínimo 6 caracteres. Intenta de nuevo."
      echo ""
      continue
    fi
    break
  done

  MASTER_PASS="$PASS1"

  # SQL Server exige al menos un símbolo especial
  if [[ "$MASTER_PASS" =~ [^a-zA-Z0-9] ]]; then
    MSSQL_PASS="$MASTER_PASS"
  else
    MSSQL_PASS="${MASTER_PASS}@Dm5"
  fi

  # Generar API key de 64 hex chars
  if [ "$HAS_OPENSSL" = true ]; then
    API_KEY=$(openssl rand -hex 32)
  else
    API_KEY=$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 64 | head -n 1)
  fi

  # Escribir .env
  cat > .env <<EOF
# Generado por install.sh — $(date '+%Y-%m-%d %H:%M:%S')

# ── SQL Server ──────────────────────────────
MSSQL_SA_PASSWORD=${MSSQL_PASS}
MSSQL_DB=QualityDMS

# ── PostgreSQL ───────────────────────────────
POSTGRES_DB=PublicDMS
POSTGRES_USER=postgres
POSTGRES_PASSWORD=${MASTER_PASS}

# ── MongoDB ──────────────────────────────────
MONGO_USER=mongoadmin
MONGO_PASSWORD=${MASTER_PASS}

# ── FastAPI ───────────────────────────────────
FASTAPI_API_KEY=${API_KEY}
FASTAPI_URL=http://fastapi:8000

# ── Sync ──────────────────────────────────────
SYNC_INTERVAL_SECONDS=30
EOF

  ok ".env generado correctamente."
  info "API Key generada automáticamente (64 hex chars)."
fi

# ══════════════════════════════════════════════════════════════
#  PASO 4 — Build y arranque de contenedores
# ══════════════════════════════════════════════════════════════
step "  [4/5]  Construyendo e iniciando contenedores..."
echo ""
echo -e "  ${GRAY}La primera vez puede tardar entre 5 y 15 minutos${NC}"
echo -e "  ${GRAY}según tu conexión y hardware.${NC}"
echo ""

if ! $COMPOSE_CMD up -d --build; then
  echo ""
  err "Falló al levantar los contenedores."
  info "Revisa los logs con: ${COMPOSE_CMD} logs"
  exit 1
fi

ok "Todos los contenedores iniciados."

# ══════════════════════════════════════════════════════════════
#  PASO 5 — Esperar SQL Server (healthcheck)
# ══════════════════════════════════════════════════════════════
step "  [5/5]  Esperando que SQL Server esté listo..."
echo ""
echo -e "  ${GRAY}(Puede tardar hasta 60 s mientras inicializa la BD)${NC}"
echo ""

MAX_ATTEMPTS=24   # 24 × 5s = 120s máximo
ATTEMPT=0
SQL_STATUS=""

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  sleep 5
  ATTEMPT=$((ATTEMPT + 1))
  SQL_STATUS=$(docker inspect --format="{{.State.Health.Status}}" dms_sqlserver 2>/dev/null || echo "starting")

  if [ "$SQL_STATUS" = "healthy" ]; then
    echo -e "\r  ${GREEN}[✓]${NC}  SQL Server: ${GREEN}healthy${NC} (${ATTEMPT}/${MAX_ATTEMPTS})          "
    break
  else
    echo -ne "\r  ${YELLOW}[~]${NC}  SQL Server: ${YELLOW}${SQL_STATUS}${NC} (${ATTEMPT}/${MAX_ATTEMPTS})...   "
  fi
done

echo ""
if [ "$SQL_STATUS" != "healthy" ]; then
  warn "SQL Server tardó más de lo esperado."
  info "Verifica con: docker logs dms_sqlserver"
  info "El sistema puede continuar iniciando en segundo plano."
fi

# ══════════════════════════════════════════════════════════════
#  TABLA FINAL DE SERVICIOS Y PUERTOS
# ══════════════════════════════════════════════════════════════
echo ""
line
echo -e "${GREEN}${BOLD}  🚀  ¡Sistema levantado correctamente!${NC}"
line
echo ""
echo -e "  ${BOLD}${WHITE}APLICACIONES WEB${NC}"
echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
echo -e "  ${WHITE}Portal Público  (HTTP) ${NC} ▶  ${CYAN}http://localhost${NC}"
echo -e "  ${WHITE}Portal Público  (HTTPS)${NC} ▶  ${CYAN}https://localhost:8443${NC}"
echo -e "  ${WHITE}CalidadSYS (Admin)     ${NC} ▶  ${CYAN}http://localhost:5080${NC}"
echo -e "  ${WHITE}CalidadSYS Swagger API ${NC} ▶  ${CYAN}http://localhost:5080/swagger${NC}"
echo -e "  ${WHITE}FastAPI Docs           ${NC} ▶  ${CYAN}http://localhost:8001/docs${NC}"
echo ""
echo -e "  ${BOLD}${WHITE}BASES DE DATOS (solo acceso local)${NC}"
echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
echo -e "  ${WHITE}SQL Server 2022        ${NC} ▶  ${GRAY}localhost:1434${NC}"
echo -e "  ${WHITE}PostgreSQL 16          ${NC} ▶  ${GRAY}localhost:5433${NC}"
echo -e "  ${WHITE}MongoDB 7              ${NC} ▶  ${GRAY}localhost:27018${NC}"
echo ""
echo -e "  ${BOLD}${WHITE}COMANDOS ÚTILES${NC}"
echo -e "  ${GRAY}──────────────────────────────────────────────────────${NC}"
echo -e "  ${GRAY}Ver logs en vivo  :${NC}  ${COMPOSE_CMD} logs -f"
echo -e "  ${GRAY}Estado contenedor :${NC}  ${COMPOSE_CMD} ps"
echo -e "  ${GRAY}Detener (conserva datos)  :${NC}  ${COMPOSE_CMD} down"
echo -e "  ${GRAY}Detener (borra BD) :${NC}  ${COMPOSE_CMD} down -v"
echo -e "  ${GRAY}Reconstruir uno   :${NC}  ${COMPOSE_CMD} up -d --build fastapi"
echo ""
line
echo ""

#!/usr/bin/env bash
# ============================================================
#  DMS Installer — Sistema Integral de Gestión Documental
#
#  Instalación completa (todos los stacks):
#    bash install.sh
#
#  Instalación parcial:
#    bash install.sh --dotnet     → .NET + SQL Server   (alias: --net)
#    bash install.sh --php        → PHP + PostgreSQL
#    bash install.sh --fastapi    → FastAPI + MongoDB + Nginx  (alias: --indexer)
#
#  Gestión de servicios (no interactivos):
#    bash install.sh up           → encender contenedores (start)
#    bash install.sh down         → apagar contenedores (stop -- los conserva)
#    bash install.sh restart      → reiniciar
#    bash install.sh reinstall    → rebuild + recrea (conserva datos)
#    bash install.sh status       → estado de contenedores
#    bash install.sh logs         → ultimas lineas por contenedor
#       (todos o con --dotnet|--php|--fastapi)
#
#  Opciones adicionales:
#    -v, --verbose    Mostrar output completo de Docker
#    -f, --force      Sobrescribir .env sin preguntar
#        --no-build   Usar imágenes en caché (sin rebuild)
#        --skip-env   Usar .env existente
#    -h, --help       Mostrar esta ayuda
# ============================================================
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$INSTALL_DIR/scripts"

# ── Globals ──────────────────────────────────────────────────
VERBOSE=false
FORCE=false
NO_BUILD=false
SKIP_ENV=false
STACK="all"       # all | dotnet | php | fastapi
SUBCMD=""         # "" = instalar | up | down | restart | reinstall | status | logs
MASTER_PASSWORD=""
COMPOSE_CMD="docker compose"
SHARED_ENV=".env"
ROLLBACK_TRIGGERED=false

export LOG_DIR="$INSTALL_DIR/logs"
export LOG_FILE="$LOG_DIR/install-$(date +%Y%m%d-%H%M%S).log"

# ── Source helpers ────────────────────────────────────────────
for _lib in colors logger spinner ui deps env_gen docker_ops healthcheck; do
    # shellcheck source=/dev/null
    source "$SCRIPTS_DIR/${_lib}.sh"
done

# ── Argument parsing ──────────────────────────────────────────
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # Subcomandos de ciclo de vida (posicionales, no interactivos)
            up|start)        SUBCMD="up" ;;
            down|stop)       SUBCMD="down" ;;
            restart)         SUBCMD="restart" ;;
            reinstall|rebuild) SUBCMD="reinstall" ;;
            status|ps)       SUBCMD="status" ;;
            logs)            SUBCMD="logs" ;;
            install|all)     SUBCMD="" ;;          # instalacion completa (default)
            # Selección de stack (acepta nombres nuevos y alias legacy)
            --dotnet|--net)     STACK="dotnet" ;;
            --php)              STACK="php" ;;
            --fastapi|--indexer) STACK="fastapi" ;;
            # Opciones
            -v|--verbose)   VERBOSE=true ;;
            -f|--force)     FORCE=true ;;
            --no-build)     NO_BUILD=true ;;
            --skip-env)     SKIP_ENV=true ;;
            -h|--help)      _show_help; exit 0 ;;
            *) printf "  Unknown option: %s\n" "$1" >&2; exit 1 ;;
        esac
        shift
    done

    # Normalizar alias legacy de stack -> claves nuevas
    case "$STACK" in
        net)     STACK="dotnet" ;;
        indexer) STACK="fastapi" ;;
    esac
}

_show_help() {
    cat <<EOF

Usage: bash install.sh [COMANDO] [STACK] [OPTIONS]

Comando (opcional — sin comando = instalación completa):
      up | start     Encender contenedores
      down | stop    Apagar contenedores (los conserva)
      restart        Reiniciar
      reinstall      Rebuild + recrea (conserva datos)
      status | ps    Estado de contenedores
      logs           Últimas líneas por contenedor

Stack (opcional — sin flag aplica a todo):
      --dotnet     .NET Core + SQL Server   (alias: --net)
      --php        PHP + PostgreSQL
      --fastapi    FastAPI + MongoDB + Nginx  (alias: --indexer)

Options:
  -v, --verbose    Show full docker build output
  -f, --force      Overwrite existing .env without asking
      --no-build   Skip image build (use cached images)
      --skip-env   Skip .env generation (use existing)
  -h, --help       Show this help

Ejemplos:
  bash install.sh                   # Instala y levanta los 3 stacks
  bash install.sh --dotnet          # Solo .NET + SQL Server
  bash install.sh up                # Encender todo
  bash install.sh down --php        # Apagar solo el stack PHP
  bash install.sh reinstall         # Rebuild conservando datos

Nota: Los stacks comparten la red dms_backbone y el volumen externo
'documentos'. El instalador los crea automáticamente si no existen.

EOF
}

# ── Create required directories ───────────────────────────────
create_dirs() {
    log_step "Creating directory structure"
    local dirs=(logs backups temp)
    for d in "${dirs[@]}"; do
        mkdir -p "$INSTALL_DIR/$d"
        log_ok "$d/"
    done
}

# ── Dashboard final ───────────────────────────────────────────
show_dashboard() {
    echo
    local line
    line="$(printf '═%.0s' {1..58})"
    printf "  %s\n" "$line"
    printf "        INSTALLATION COMPLETE  ${GRAY}[stack: ${STACK}]${RESET}\n"
    printf "  %s\n" "$line"
    echo

    # ── URLs por stack ────────────────────────────────────────
    case "$STACK" in
        dotnet)
            printf "  ${CYAN}PORTALES${RESET}\n"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Admin (CalidadSYS)" "http://localhost:5080"
            echo
            printf "  ${CYAN}BASES DE DATOS${RESET}\n"
            printf "  ${GRAY}%-28s %s${RESET}\n" "SQL Server" "localhost:1435"
            ;;
        php)
            printf "  ${CYAN}PORTALES${RESET}\n"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Portal Publico (PHP)" "http://localhost/php/"
            echo
            printf "  ${CYAN}BASES DE DATOS${RESET}\n"
            printf "  ${GRAY}%-28s %s${RESET}\n" "PostgreSQL" "localhost:5433"
            ;;
        fastapi)
            printf "  ${CYAN}PORTALES${RESET}\n"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Busqueda (FastAPI)" "http://localhost/fastapi/"
            printf "  ${WHITE}%-28s${RESET} %s\n" "FastAPI Swagger" "http://localhost:8001/docs"
            printf "  ${WHITE}%-28s${RESET} %s\n" "FastAPI HTTPS" "https://localhost:8443"
            echo
            printf "  ${CYAN}BASES DE DATOS${RESET}\n"
            printf "  ${GRAY}%-28s %s${RESET}\n" "MongoDB" "localhost:27018"
            ;;
        all|*)
            printf "  ${CYAN}PORTALES${RESET}  ${GRAY}(routing por path via Nginx :80)${RESET}\n"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Portal Publico (PHP)" "http://localhost/php/"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Gestion interna (.NET)" "http://localhost/dotnet/"
            printf "  ${WHITE}%-28s${RESET} %s\n" "Busqueda (FastAPI)" "http://localhost/fastapi/"
            echo
            printf "  ${CYAN}ACCESO DIRECTO${RESET}\n"
            printf "  ${GRAY}%-28s %s${RESET}\n" ".NET directo" "http://localhost:5080"
            printf "  ${GRAY}%-28s %s${RESET}\n" "FastAPI Swagger" "http://localhost:8001/docs"
            printf "  ${GRAY}%-28s %s${RESET}\n" "FastAPI HTTPS" "https://localhost:8443"
            echo
            printf "  ${CYAN}BASES DE DATOS${RESET}\n"
            printf "  ${GRAY}%-28s %s${RESET}\n" "SQL Server" "localhost:1435"
            printf "  ${GRAY}%-28s %s${RESET}\n" "PostgreSQL" "localhost:5433"
            printf "  ${GRAY}%-28s %s${RESET}\n" "MongoDB" "localhost:27018"
            ;;
    esac

    # ── Usuarios sembrados (solo si se ejecutó el seeder) ─────
    if [ "${SKIP_ENV:-false}" = false ] && [ "${SEED_MODE:-dev}" != "none" ]; then
        echo
        printf "  %s\n" "$(printf '─%.0s' {1..58})"
        printf "  ${CYAN}USUARIOS REGISTRADOS${RESET}  ${GRAY}(password: Calidad#2026Dev)${RESET}\n"
        printf "  %s\n" "$(printf '─%.0s' {1..58})"
        printf "  ${GRAY}%-14s %-38s %s${RESET}\n" "ROL" "EMAIL" "EMPRESA"
        printf "  %s\n" "$(printf '─%.0s' {1..58})"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "SuperAdmin"      "super@qualitydms.local"       "Global"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "Admin"           "admin@qualitydms.local"       "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "AdminEmpresa"    "adminempresa@qualitydms.local" "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "QualityManager"  "calidad@qualitydms.local"     "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "Approver"        "aprobador1@qualitydms.local"  "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "Approver"        "aprobador2@qualitydms.local"  "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "Author"          "autor@qualitydms.local"       "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "Viewer"          "lector@qualitydms.local"      "ACME"
        printf "  ${WHITE}%-14s${RESET} %-38s %s\n" "AdminEmpresa"    "admin.beta@qualitydms.local"  "BETA"

        if [ "${SEED_MODE:-dev}" = "sandbox" ]; then
            echo
            printf "  ${CYAN}DATOS SANDBOX${RESET}\n"
            printf "  ${GREEN}✓${RESET} 10,000 documentos generados en SQL Server\n"
            printf "  ${GREEN}✓${RESET}  7,000 aprobados propagados a PostgreSQL y MongoDB\n"
            printf "  ${GREEN}✓${RESET}  2,000 en revision  |  1,000 borradores\n"
        fi
    fi

    echo
    printf "  %s\n" "$line"
    echo
}

# ── Cleanup / rollback on unexpected exit ─────────────────────
_cleanup() {
    local code=$?
    spinner_stop 2>/dev/null || true
    show_cursor
    # Solo en instalacion completa (no en subcomandos up/down/status/...).
    if [ "$code" -ne 0 ] && [ "$ROLLBACK_TRIGGERED" = false ] && [ -z "${SUBCMD:-}" ]; then
        ROLLBACK_TRIGGERED=true
        echo
        log_error "Installation failed (exit code: $code)"
        echo
        printf "  ${YELLOW}Diagnose:${RESET}\n"
        printf "    cat %s\n" "$LOG_FILE"
        printf "    bash install.sh logs\n"
        echo
        printf "  ${YELLOW}Clean up (elimina volumenes del stack):${RESET}\n"
        printf "    docker compose -p dms-%s -f docker-compose.%s.yml down -v\n" "$STACK" "$STACK"
        echo
    fi
}
trap '_cleanup' EXIT
trap 'echo; log_error "Interrupted (SIGINT)"; exit 130' INT
trap 'echo; log_error "Interrupted (SIGTERM)"; exit 143' TERM

# ── Main ──────────────────────────────────────────────────────
main() {
    parse_args "$@"

    mkdir -p "$LOG_DIR"

    {
        echo "============================================"
        echo "  DMS Install — $(date)"
        echo "  Stack: $STACK | Verbose: $VERBOSE | Force: $FORCE | No-build: $NO_BUILD"
        echo "============================================"
    } >> "$LOG_FILE"

    show_banner

    # ── Subcomandos de ciclo de vida (no interactivos) ────────
    if [ -n "$SUBCMD" ]; then
        case "$SUBCMD" in
            up)        docker_up ;;          # build + up -d (incluye infra compartida)
            down)      docker_stop ;;        # stop: apaga, conserva contenedores
            restart)   docker_restart ;;
            reinstall) docker_reinstall ;;
            status)    docker_ps ;;
            logs)      docker_logs ;;
        esac
        echo
        exit 0
    fi

    log_info "Stack:    ${WHITE}${STACK}${RESET}"
    log_info "Log file: ${GRAY}$LOG_FILE${RESET}"
    echo

    check_deps
    handle_existing_env

    if [ "${SKIP_ENV:-false}" = false ]; then
        prompt_seed_mode
        prompt_master_password
        generate_env
    fi

    create_dirs
    docker_up
    wait_all_services
    show_dashboard

    echo
    log_ok "Done. Full log: ${GRAY}$LOG_FILE${RESET}"
    echo
}

main "$@"

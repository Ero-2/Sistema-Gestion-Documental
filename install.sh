#!/usr/bin/env bash
# ============================================================
#  DMS Installer — Sistema Integral de Gestión Documental
#
#  Instalación completa (todos los stacks):
#    bash install.sh
#
#  Instalación parcial:
#    bash install.sh --net        → .NET + SQL Server
#    bash install.sh --php        → PHP + PostgreSQL + Nginx
#    bash install.sh --indexer    → FastAPI + MongoDB
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
STACK="all"       # all | net | php | indexer
MASTER_PASSWORD=""
COMPOSE_CMD="docker compose"
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
            -v|--verbose)   VERBOSE=true ;;
            -f|--force)     FORCE=true ;;
            --no-build)     NO_BUILD=true ;;
            --skip-env)     SKIP_ENV=true ;;
            --net)          STACK="net" ;;
            --php)          STACK="php" ;;
            --indexer)      STACK="indexer" ;;
            -h|--help)      _show_help; exit 0 ;;
            *) printf "  Unknown option: %s\n" "$1" >&2; exit 1 ;;
        esac
        shift
    done
}

_show_help() {
    cat <<EOF

Usage: bash install.sh [STACK] [OPTIONS]

Stack (opcional — sin flag levanta todo):
      --net        .NET Core + SQL Server
      --php        PHP + PostgreSQL + Nginx
      --indexer    FastAPI + MongoDB

Options:
  -v, --verbose    Show full docker build output
  -f, --force      Overwrite existing .env without asking
      --no-build   Skip image build (use cached images)
      --skip-env   Skip .env generation (use existing)
  -h, --help       Show this help

Ejemplos:
  bash install.sh                   # Levanta los 3 stacks
  bash install.sh --net             # Solo .NET + SQL Server
  bash install.sh --php --no-build  # PHP stack sin rebuild

Nota: Los stacks separados requieren la red compartida dms_backbone.
El instalador la crea automáticamente si no existe.

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
    _section_line() { printf "  %s\n" "$(printf '═%.0s' {1..54})"; }
    _section_line
    printf "        INSTALLATION COMPLETE  ${GRAY}[stack: ${STACK}]${RESET}\n"
    _section_line
    echo

    case "$STACK" in
        net)
            printf "  ${WHITE}→ Admin (CalidadSYS)${RESET}  http://localhost:5080\n"
            printf "  ${GRAY}→ SQL Server          localhost:1434${RESET}\n"
            ;;
        php)
            printf "  ${WHITE}→ Portal Público      http://localhost${RESET}\n"
            printf "  ${WHITE}→ Portal HTTPS        https://localhost:8443${RESET}\n"
            printf "  ${GRAY}→ PostgreSQL          localhost:5433${RESET}\n"
            ;;
        indexer)
            printf "  ${WHITE}→ FastAPI Docs        http://localhost:8001/docs${RESET}\n"
            printf "  ${GRAY}→ MongoDB             localhost:27018${RESET}\n"
            ;;
        all|*)
            printf "  ${WHITE}→ Portal Público      http://localhost${RESET}\n"
            printf "  ${WHITE}→ Portal HTTPS        https://localhost:8443${RESET}\n"
            printf "  ${WHITE}→ Admin (CalidadSYS)  http://localhost:5080${RESET}\n"
            printf "  ${WHITE}→ FastAPI Docs        http://localhost:8001/docs${RESET}\n"
            echo
            printf "  ${GRAY}→ PostgreSQL          localhost:5433${RESET}\n"
            printf "  ${GRAY}→ MongoDB             localhost:27018${RESET}\n"
            printf "  ${GRAY}→ SQL Server          localhost:1434${RESET}\n"
            ;;
    esac

    echo
    _section_line
    echo
}

# ── Cleanup / rollback on unexpected exit ─────────────────────
_cleanup() {
    local code=$?
    spinner_stop 2>/dev/null || true
    show_cursor
    if [ "$code" -ne 0 ] && [ "$ROLLBACK_TRIGGERED" = false ]; then
        ROLLBACK_TRIGGERED=true
        echo
        log_error "Installation failed (exit code: $code)"
        echo
        printf "  ${YELLOW}Diagnose:${RESET}\n"
        printf "    cat %s\n" "$LOG_FILE"
        echo
        printf "  ${YELLOW}Clean up:${RESET}\n"
        printf "    docker compose -f compose-%s.yml down -v\n" "$STACK"
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

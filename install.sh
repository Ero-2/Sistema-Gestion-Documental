#!/usr/bin/env bash
# ============================================================
#  DMS Installer — Sistema Integral de Gestión Documental
#  Usage: bash install.sh [--verbose] [--force] [--no-build]
#                         [--skip-env] [--help]
# ============================================================
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$INSTALL_DIR/scripts"

# ── Globals ──────────────────────────────────────────────────
VERBOSE=false
FORCE=false
NO_BUILD=false
SKIP_ENV=false
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
            -h|--help)      _show_help; exit 0 ;;
            *) printf "  Unknown option: %s\n" "$1" >&2; exit 1 ;;
        esac
        shift
    done
}

_show_help() {
    cat <<EOF

Usage: bash install.sh [OPTIONS]

Options:
  -v, --verbose    Show full docker build output
  -f, --force      Overwrite existing .env without asking
      --no-build   Skip image build (use cached images)
      --skip-env   Skip .env generation (use existing)
  -h, --help       Show this help

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
        printf "    docker compose logs\n"
        printf "    cat %s\n" "$LOG_FILE"
        echo
        printf "  ${YELLOW}Clean up:${RESET}\n"
        printf "    docker compose down -v\n"
        echo
    fi
}
trap '_cleanup' EXIT
trap 'echo; log_error "Interrupted (SIGINT)"; exit 130' INT
trap 'echo; log_error "Interrupted (SIGTERM)"; exit 143' TERM

# ── Main ──────────────────────────────────────────────────────
main() {
    parse_args "$@"

    # Log dir must exist before any log call
    mkdir -p "$LOG_DIR"

    {
        echo "============================================"
        echo "  DMS Install — $(date)"
        echo "  Verbose: $VERBOSE | Force: $FORCE | No-build: $NO_BUILD"
        echo "============================================"
    } >> "$LOG_FILE"

    show_banner

    log_info "Log file: ${GRAY}$LOG_FILE${RESET}"

    check_deps
    handle_existing_env

    if [ "${SKIP_ENV:-false}" = false ]; then
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

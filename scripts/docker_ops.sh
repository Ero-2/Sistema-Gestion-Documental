#!/usr/bin/env bash
# Docker Compose operations — multi-stack aware

COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

# Selecciona el compose file y el env file según STACK
_compose_args() {
    case "${STACK:-all}" in
        net)
            echo "--env-file .env.net -f compose-net.yml"
            ;;
        php)
            echo "--env-file .env.php -f compose-php.yml"
            ;;
        indexer)
            echo "--env-file .env.indexer -f compose-indexer.yml"
            ;;
        all|*)
            echo "-f compose-all.yml"
            ;;
    esac
}

# Crea la red compartida dms_backbone si no existe.
# No se usa en el modo "all" porque compose-all.yml tiene su propia red.
ensure_backbone_network() {
    [ "${STACK:-all}" = "all" ] && return 0

    if docker network inspect dms_backbone > /dev/null 2>&1; then
        log_info "Network dms_backbone already exists"
    else
        spinner_start "Creating shared network dms_backbone..."
        docker network create dms_backbone >> "$LOG_FILE" 2>&1
        spinner_stop
        log_ok "Network dms_backbone created"
    fi
}

# Crea el directorio de uploads compartido en el host.
# Reemplaza el volumen nombrado uploads_data en los stacks separados.
ensure_uploads_dir() {
    [ "${STACK:-all}" = "all" ] && return 0

    if [ ! -d "./data/uploads" ]; then
        mkdir -p ./data/uploads
        log_ok "Created ./data/uploads  ${GRAY}(shared bind mount for PDFs)${RESET}"
    else
        log_info "./data/uploads already exists"
    fi
}

docker_up() {
    log_step "Starting containers  ${GRAY}[stack: ${STACK:-all}]${RESET}"

    ensure_backbone_network
    ensure_uploads_dir

    local build_flag="--build"
    [ "${NO_BUILD:-false}" = true ] && build_flag=""

    local args
    args=$(_compose_args)

    if [ "${VERBOSE:-false}" = true ]; then
        log_info "Running: $COMPOSE_CMD $args up -d $build_flag"
        echo
        # shellcheck disable=SC2086
        $COMPOSE_CMD $args up -d $build_flag 2>&1 | tee -a "$LOG_FILE"
        local rc=${PIPESTATUS[0]}
    else
        spinner_start "Building images and starting services..."
        # shellcheck disable=SC2086
        $COMPOSE_CMD $args up -d $build_flag >> "$LOG_FILE" 2>&1
        local rc=$?
        spinner_stop
    fi

    if [ "$rc" -ne 0 ]; then
        log_error "docker compose up failed (exit $rc)"
        log_warn "Full output: $LOG_FILE"
        log_warn "Diagnose:   $COMPOSE_CMD $args logs"
        exit 1
    fi

    log_ok "All containers started"
}

docker_ps() {
    local args
    args=$(_compose_args)
    echo
    # shellcheck disable=SC2086
    $COMPOSE_CMD $args ps 2>/dev/null || true
}

docker_down_volumes() {
    local args
    args=$(_compose_args)
    log_warn "Rolling back — stopping and removing containers + volumes"
    # shellcheck disable=SC2086
    $COMPOSE_CMD $args down -v --remove-orphans >> "$LOG_FILE" 2>&1 || true
    log_ok "Rollback complete"
}

#!/usr/bin/env bash
# Docker Compose operations

COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"

docker_up() {
    log_step "Starting containers"

    local build_flag="--build"
    [ "${NO_BUILD:-false}" = true ] && build_flag=""

    if [ "${VERBOSE:-false}" = true ]; then
        log_info "Running: $COMPOSE_CMD up -d $build_flag"
        echo
        $COMPOSE_CMD up -d $build_flag 2>&1 | tee -a "$LOG_FILE"
        local rc=${PIPESTATUS[0]}
    else
        spinner_start "Building images and starting services..."
        $COMPOSE_CMD up -d $build_flag >> "$LOG_FILE" 2>&1
        local rc=$?
        spinner_stop
    fi

    if [ "$rc" -ne 0 ]; then
        log_error "docker compose up failed (exit $rc)"
        log_warn "Full output: $LOG_FILE"
        log_warn "Diagnose:   $COMPOSE_CMD logs"
        exit 1
    fi

    log_ok "All containers started"
}

docker_ps() {
    echo
    $COMPOSE_CMD ps 2>/dev/null || true
}

docker_down_volumes() {
    log_warn "Rolling back — stopping and removing containers + volumes"
    $COMPOSE_CMD down -v --remove-orphans >> "$LOG_FILE" 2>&1 || true
    log_ok "Rollback complete"
}

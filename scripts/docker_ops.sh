#!/usr/bin/env bash
# Docker Compose operations — 3 stacks independientes (dms-dotnet / dms-php / dms-fastapi)
# Cada stack: su propio proyecto (-p), comparten .env raiz, red dms_backbone y volumen documentos.

COMPOSE_CMD="${COMPOSE_CMD:-docker compose}"
SHARED_ENV="${SHARED_ENV:-.env}"

# ── Tabla de stacks ───────────────────────────────────────────
# key -> compose file
_stack_compose() {
    case "$1" in
        dotnet)  echo "docker-compose.dotnet.yml" ;;
        php)     echo "docker-compose.php.yml" ;;
        fastapi) echo "docker-compose.fastapi.yml" ;;
    esac
}
# key -> nombre de proyecto docker
_stack_project() {
    case "$1" in
        dotnet)  echo "dms-dotnet" ;;
        php)     echo "dms-php" ;;
        fastapi) echo "dms-fastapi" ;;
    esac
}

# Lista de stacks a operar segun seleccion ("all" = los 3, en orden de arranque).
# Orden: dotnet (SQL) y php (Postgres) primero; fastapi+nginx al final (nginx proxya a los otros).
_stack_list() {
    local sel="${1:-all}"
    case "$sel" in
        all) echo "dotnet php fastapi" ;;
        *)   echo "$sel" ;;
    esac
}

# Ejecuta un comando compose sobre un stack: _compose <key> <accion...>
_compose() {
    local key="$1"; shift
    # shellcheck disable=SC2086
    $COMPOSE_CMD -p "$(_stack_project "$key")" --env-file "$SHARED_ENV" -f "$(_stack_compose "$key")" "$@"
}

# ── Infra compartida: red dms_backbone + volumen externo documentos (idempotente) ─
ensure_shared_infra() {
    if docker network inspect dms_backbone > /dev/null 2>&1; then
        log_info "Red dms_backbone ya existe"
    else
        docker network create dms_backbone >> "${LOG_FILE:-/dev/null}" 2>&1
        log_ok "Red dms_backbone creada"
    fi
    if docker volume inspect documentos > /dev/null 2>&1; then
        log_info "Volumen 'documentos' ya existe"
    else
        docker volume create documentos >> "${LOG_FILE:-/dev/null}" 2>&1
        log_ok "Volumen 'documentos' creado"
    fi
}

# ── Levantar (build + up -d) los stacks seleccionados ─────────
docker_up() {
    log_step "Starting containers  ${GRAY}[stack: ${STACK:-all}]${RESET}"

    ensure_shared_infra

    local build_flag="--build"
    [ "${NO_BUILD:-false}" = true ] && build_flag=""

    local key rc
    for key in $(_stack_list "${STACK:-all}"); do
        if [ "${VERBOSE:-false}" = true ]; then
            log_info "Running: $COMPOSE_CMD -p $(_stack_project "$key") -f $(_stack_compose "$key") up -d $build_flag"
            echo
            # shellcheck disable=SC2086
            _compose "$key" up -d $build_flag 2>&1 | tee -a "$LOG_FILE"
            rc=${PIPESTATUS[0]}
        else
            spinner_start "[$(_stack_project "$key")] building & starting..."
            # shellcheck disable=SC2086
            _compose "$key" up -d $build_flag >> "$LOG_FILE" 2>&1
            rc=$?
            spinner_stop
        fi

        if [ "$rc" -ne 0 ]; then
            log_error "[$(_stack_project "$key")] docker compose up failed (exit $rc)"
            log_warn "Full output: $LOG_FILE"
            log_warn "Diagnose:   $COMPOSE_CMD -p $(_stack_project "$key") -f $(_stack_compose "$key") logs"
            exit 1
        fi
        log_ok "[$(_stack_project "$key")] started"
    done

    log_ok "All containers started"
}

# ── Acciones de ciclo de vida (subcomandos) ───────────────────
# Apagar: stop (conserva contenedores y datos).
docker_stop() {
    log_step "Apagando servicios  ${GRAY}[stack: ${STACK:-all}]${RESET}"
    local key
    for key in $(_stack_list "${STACK:-all}"); do
        log_info "[$(_stack_project "$key")] stop"
        _compose "$key" stop
    done
    log_ok "Servicios apagados (contenedores y datos conservados)"
}

docker_restart() {
    log_step "Reiniciando servicios  ${GRAY}[stack: ${STACK:-all}]${RESET}"
    local key
    for key in $(_stack_list "${STACK:-all}"); do
        log_info "[$(_stack_project "$key")] restart"
        _compose "$key" restart
    done
    log_ok "Servicios reiniciados"
}

# Reinstalar: rebuild imagenes + recrea contenedores, conserva volumenes/datos.
docker_reinstall() {
    log_step "Reinstalando (rebuild + recrea, conserva datos)  ${GRAY}[stack: ${STACK:-all}]${RESET}"
    ensure_shared_infra
    local key
    for key in $(_stack_list "${STACK:-all}"); do
        log_info "[$(_stack_project "$key")] up -d --build --force-recreate"
        _compose "$key" up -d --build --force-recreate
    done
    log_ok "Reinstalacion completa"
}

docker_ps() {
    echo
    docker ps -a --filter "name=dms_" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || true
    echo
}

docker_logs() {
    local key
    for key in $(_stack_list "${STACK:-all}"); do
        echo
        printf "  ===== %s =====\n" "$(_stack_project "$key")"
        _compose "$key" logs --tail "${LOG_TAIL:-60}" 2>&1 || true
    done
}

# ── Rollback en fallo de instalacion (down -v de lo seleccionado) ─
docker_down_volumes() {
    log_warn "Rolling back — stopping and removing containers + volumes"
    local key
    for key in $(_stack_list "${STACK:-all}"); do
        _compose "$key" down -v --remove-orphans >> "${LOG_FILE:-/dev/null}" 2>&1 || true
    done
    log_ok "Rollback complete"
}

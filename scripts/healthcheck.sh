#!/usr/bin/env bash
# Service healthcheck framework with retry and timeout

# wait_for_service <display_name> <container_name> [timeout_secs]
wait_for_service() {
    local name="$1"
    local container="$2"
    local timeout="${3:-120}"
    local interval=4
    local elapsed=0
    local start_ts
    start_ts=$(date +%s)

    status_pending "Waiting for $name..."

    while [ $elapsed -lt $timeout ]; do
        local health state
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{end}}' \
                    "$container" 2>/dev/null || echo "")
        state=$(docker inspect --format='{{.State.Status}}' \
                    "$container" 2>/dev/null || echo "unknown")

        if [ -n "$health" ]; then
            case "$health" in
                healthy)
                    local dur=$(( $(date +%s) - start_ts ))
                    status_done "$name  ${GRAY}(healthy, ${dur}s)${RESET}"
                    echo "  [ok] $name healthy in ${dur}s" >> "$LOG_FILE"
                    return 0
                    ;;
                unhealthy)
                    status_fail "$name  ${RED}unhealthy${RESET}"
                    log_warn "Diagnose: docker logs $container"
                    return 1
                    ;;
            esac
        else
            case "$state" in
                running)
                    local dur=$(( $(date +%s) - start_ts ))
                    status_done "$name  ${GRAY}(running, ${dur}s)${RESET}"
                    echo "  [ok] $name running in ${dur}s" >> "$LOG_FILE"
                    return 0
                    ;;
                exited|dead)
                    status_fail "$name  ${RED}crashed (${state})${RESET}"
                    log_warn "Diagnose: docker logs $container"
                    return 1
                    ;;
            esac
        fi

        sleep $interval
        elapsed=$(( elapsed + interval ))
    done

    status_fail "$name  ${YELLOW}timeout after ${timeout}s${RESET}"
    log_warn "Service taking too long. Diagnose: docker logs $container"
    return 2
}

wait_all_services() {
    log_step "Waiting for services  ${GRAY}[stack: ${STACK:-all}]${RESET}"
    echo

    local failed=0

    case "${STACK:-all}" in
        net)
            log_info "SQL Server may take up to 90s on first boot."
            echo
            wait_for_service "SQL Server"  dms_sqlserver 120 || failed=1
            wait_for_service ".NET Core"   dms_dotnet     90 || failed=1
            ;;
        php)
            wait_for_service "PostgreSQL"  dms_postgres   60 || failed=1
            wait_for_service "PHP/Apache"  dms_php        60 || failed=1
            wait_for_service "Nginx"       dms_nginx      30 || failed=1
            ;;
        indexer)
            wait_for_service "MongoDB"     dms_mongodb    60 || failed=1
            wait_for_service "FastAPI"     dms_fastapi    60 || failed=1
            ;;
        all|*)
            log_info "SQL Server may take up to 90s on first boot."
            echo
            wait_for_service "SQL Server"  dms_sqlserver 120 || failed=1
            wait_for_service "PostgreSQL"  dms_postgres   60 || failed=1
            wait_for_service "MongoDB"     dms_mongodb    60 || failed=1
            wait_for_service "FastAPI"     dms_fastapi    60 || failed=1
            wait_for_service "PHP/Apache"  dms_php        60 || failed=1
            wait_for_service ".NET Core"   dms_dotnet     90 || failed=1
            wait_for_service "Nginx"       dms_nginx      30 || failed=1
            ;;
    esac

    echo

    if [ "$failed" -ne 0 ]; then
        log_warn "One or more services failed to start."
        log_warn "Run: docker compose logs -f to diagnose."
    else
        log_ok "All services healthy"
    fi
}

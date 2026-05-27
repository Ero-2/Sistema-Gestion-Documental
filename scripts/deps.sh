#!/usr/bin/env bash
# Dependency verification

REQUIRED_DEPS=(docker git curl openssl)

_check_dep() {
    local cmd="$1"
    local label="${2:-$1}"
    if command -v "$cmd" &>/dev/null; then
        local ver
        ver=$(${cmd} --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+[^ ]*' | head -1 || echo "")
        status_done "${label}${ver:+  ${GRAY}(${ver})${RESET}}"
        return 0
    else
        status_fail "$label  ${RED}not found${RESET}"
        return 1
    fi
}

_check_docker_compose() {
    if docker compose version &>/dev/null 2>&1; then
        local ver
        ver=$(docker compose version --short 2>/dev/null || echo "")
        status_done "Docker Compose${ver:+  ${GRAY}(${ver})${RESET}}"
        COMPOSE_CMD="docker compose"
        return 0
    elif command -v docker-compose &>/dev/null; then
        status_done "Docker Compose  ${GRAY}(legacy docker-compose)${RESET}"
        COMPOSE_CMD="docker-compose"
        return 0
    else
        status_fail "Docker Compose  ${RED}not found${RESET}"
        return 1
    fi
}

_check_docker_running() {
    if docker info &>/dev/null 2>&1; then
        status_done "Docker daemon   ${GRAY}(running)${RESET}"
        return 0
    else
        status_fail "Docker daemon   ${RED}not running — start Docker first${RESET}"
        return 1
    fi
}

check_deps() {
    log_step "Checking dependencies"

    local failed=0

    status_pending "Docker"
    _check_dep docker "Docker" || failed=1

    status_pending "Docker daemon"
    _check_docker_running || failed=1

    status_pending "Docker Compose"
    _check_docker_compose || failed=1

    for dep in git curl openssl; do
        status_pending "$dep"
        _check_dep "$dep" "$dep" || failed=1
    done

    if [ "$failed" -ne 0 ]; then
        echo
        log_error "Missing required dependencies. Install them and re-run."
        exit 1
    fi

    echo
    log_ok "All dependencies satisfied"
}

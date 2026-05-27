#!/usr/bin/env bash
# Logging helpers — stdout + file

LOG_FILE="${LOG_FILE:-/tmp/dms-install.log}"

_emit() {
    printf "%b\n" "$1" | tee -a "$LOG_FILE"
}

log_ok()    { _emit "  ${SYM_OK}  $1"; }
log_error() { printf "%b\n" "  ${SYM_FAIL}  ${RED}${1}${RESET}" | tee -a "$LOG_FILE" >&2; }
log_warn()  { _emit "  ${SYM_WARN}  ${YELLOW}${1}${RESET}"; }
log_info()  { _emit "  ${SYM_INFO}  $1"; }
log_debug() { [ "${VERBOSE:-false}" = true ] && _emit "  ${DIM}[dbg] ${1}${RESET}" || true; }

log_step() {
    printf "\n" | tee -a "$LOG_FILE"
    printf "%b\n" "  ${BOLD}${CYAN}▶  ${1}${RESET}" | tee -a "$LOG_FILE"
    printf "%b\n" "  ${GRAY}$(printf '%.0s─' {1..52})${RESET}" | tee -a "$LOG_FILE"
}

# status_pending / status_done / status_fail — inline update on same line
status_pending() { printf "  ${CYAN}⠿${RESET}  %-44s" "$1"; }
status_done()    { printf "\r  ${SYM_OK}  %-44s\n" "$1"; echo "  [ok] $1" >> "$LOG_FILE"; }
status_fail()    { printf "\r  ${SYM_FAIL}  %-44s\n" "$1"; echo "  [fail] $1" >> "$LOG_FILE"; }

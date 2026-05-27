#!/usr/bin/env bash
# Spinner and progress bar helpers

SPINNER_PID=""
_FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

hide_cursor() { [ -t 1 ] && printf '\033[?25l' || true; }
show_cursor() { [ -t 1 ] && printf '\033[?25h' || true; }

spinner_start() {
    local msg="${1:-Please wait...}"
    [ -t 1 ] || return 0
    hide_cursor
    (
        local i=0
        local fc=${#_FRAMES}
        while true; do
            local f="${_FRAMES:$i:1}"
            printf "\r  \033[0;36m%s\033[0m  %s" "$f" "$msg"
            i=$(( (i + 1) % fc ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    [ -z "${SPINNER_PID:-}" ] && return 0
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
    printf "\r\033[K"
    show_cursor
}

# progress_bar <label> <current> <total> [bar_width=38]
progress_bar() {
    local label="$1" cur="$2" total="$3" bw="${4:-38}"
    [ "$total" -le 0 ] && total=1
    local pct=$(( cur * 100 / total ))
    local filled=$(( cur * bw / total ))
    local empty=$(( bw - filled ))
    local bar_f bar_e
    bar_f="$(printf '%*s' "$filled" '' | tr ' ' '█')"
    bar_e="$(printf '%*s' "$empty"  '' | tr ' ' '░')"
    printf "\r  \033[1m%-20s\033[0m [\033[0;32m%s\033[0;90m%s\033[0m] \033[1m%3d%%\033[0m" \
        "$label" "$bar_f" "$bar_e" "$pct"
}

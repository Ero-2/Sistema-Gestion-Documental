#!/usr/bin/env bash
# UI components: banner, panels, dashboard

show_banner() {
    clear
    printf "\n"
    printf "\033[0;36m"
    cat <<'EOF'
   ██████╗ ███╗   ███╗███████╗
   ██╔══██╗████╗ ████║██╔════╝
   ██║  ██║██╔████╔██║███████╗
   ██║  ██║██║╚██╔╝██║╚════██║
   ██████╔╝██║ ╚═╝ ██║███████║
   ╚═════╝ ╚═╝     ╚═╝╚══════╝
EOF
    printf "\033[0m"
    printf "   \033[1;37mSistema Integral de Gestión Documental\033[0m\n"
    printf "   \033[2mEnterprise Multi-Stack Platform  •  v1.0.0\033[0m\n"
    printf "\n"
    printf "   \033[0;90m.NET 10 · PHP 8.3 · FastAPI · PostgreSQL · MongoDB · SQL Server · Nginx\033[0m\n"
    printf "\n"
    printf "   \033[0;90m"
    printf '%.0s─' {1..62}
    printf "\033[0m\n\n"
}

# Strip ANSI codes from a string to compute visual length
_visual_len() {
    local s
    s=$(printf "%b" "$1" | sed $'s/\033\[[0-9;]*[mGKHFABCDJsu]//g')
    echo ${#s}
}

# Box line: pads colored content to fixed inner width (62 chars)
_box_row() {
    local content="${1:-}"
    local inner=62
    local vis
    vis=$(_visual_len "$content")
    local pad=$(( inner - vis - 1 ))
    [ $pad -lt 0 ] && pad=0
    printf "\033[0;36m║\033[0m %b%${pad}s\033[0;36m║\033[0m\n" "$content" ""
}

_box_top() {
    printf "\033[0;36m╔"
    printf '%.0s═' {1..62}
    printf "╗\033[0m\n"
}
_box_sep() {
    printf "\033[0;36m╠"
    printf '%.0s═' {1..62}
    printf "╣\033[0m\n"
}
_box_bot() {
    printf "\033[0;36m╚"
    printf '%.0s═' {1..62}
    printf "╝\033[0m\n"
}

show_dashboard() {
    printf "\n"
    _box_top
    _box_row "$(printf '%30s\033[1;37mINSTALLATION COMPLETE\033[0m' '')"
    _box_sep

    _box_row ""
    _box_row "\033[1mACCESO AL SISTEMA\033[0m"
    _box_row ""
    _box_row "\033[0;36m→\033[0m  Portal Público        \033[0;32mhttp://localhost\033[0m"
    _box_row "\033[0;36m→\033[0m  Portal HTTPS          \033[0;32mhttps://localhost:8443\033[0m"
    _box_row "\033[0;36m→\033[0m  Admin  (CalidadSYS)   \033[0;32mhttp://localhost:5080\033[0m"
    _box_row "\033[0;36m→\033[0m  FastAPI Docs          \033[0;32mhttp://localhost:8001/docs\033[0m"
    _box_row ""

    _box_sep
    _box_row ""
    _box_row "\033[1mBASES DE DATOS\033[0m"
    _box_row ""
    _box_row "\033[0;36m→\033[0m  PostgreSQL    \033[0;90mlocalhost:5433\033[0m"
    _box_row "\033[0;36m→\033[0m  MongoDB       \033[0;90mlocalhost:27018\033[0m"
    _box_row "\033[0;36m→\033[0m  SQL Server    \033[0;90mlocalhost:1434\033[0m"
    _box_row ""

    _box_sep
    _box_row ""
    _box_row "\033[1mCOMANDOS ÚTILES\033[0m"
    _box_row ""
    _box_row "\033[2m  docker compose ps\033[0m"
    _box_row "\033[2m  docker compose logs -f\033[0m"
    _box_row "\033[2m  docker compose down\033[0m"
    _box_row "\033[2m  docker compose restart <servicio>\033[0m"
    _box_row "\033[2m  docker compose logs -f <servicio>\033[0m"
    _box_row ""

    _box_bot
    printf "\n"
}

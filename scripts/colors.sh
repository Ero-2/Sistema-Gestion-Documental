#!/usr/bin/env bash
# ANSI color definitions — sourced by all other scripts

if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA=''
    WHITE='' GRAY='' BOLD='' DIM='' RESET=''
fi

SYM_OK="${GREEN}✓${RESET}"
SYM_FAIL="${RED}✗${RESET}"
SYM_WARN="${YELLOW}⚠${RESET}"
SYM_INFO="${CYAN}ℹ${RESET}"
SYM_ARROW="${CYAN}→${RESET}"
SYM_BULLET="${GRAY}•${RESET}"

#!/usr/bin/env bash
# lib/common.sh — Common functions for mb net
# Sourced by mb and all network scripts. Do not execute directly.

set -euo pipefail

MB_NET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MB_TEMPLATES_DIR="${MB_NET_DIR}/templates"
MB_DEPLOY_DIR="${MB_DEPLOY_DIR:-/opt/mb-net}"
MB_PROXY_NETWORK="${MB_PROXY_NETWORK:-mb-proxy}"

# Colors
if [ -t 1 ]; then
    MB_RED='\033[0;31m' MB_GREEN='\033[0;32m' MB_YELLOW='\033[0;33m'
    MB_BLUE='\033[0;34m' MB_BOLD='\033[1m' MB_DIM='\033[2m' MB_RESET='\033[0m'
else
    MB_RED='' MB_GREEN='' MB_YELLOW='' MB_BLUE='' MB_BOLD='' MB_DIM='' MB_RESET=''
fi

mb_step()    { echo -e "\n${MB_BOLD}${MB_BLUE}▶ $*${MB_RESET}"; }
mb_info()    { echo -e "  ${MB_DIM}ℹ${MB_RESET} $*"; }
mb_detail()  { echo -e "  ${MB_DIM}·${MB_RESET} $*"; }
mb_success() { echo -e "  ${MB_GREEN}✓${MB_RESET} $*"; }
mb_warn()    { echo -e "  ${MB_YELLOW}⚠${MB_RESET} $*" >&2; }
mb_error()   { echo -e "  ${MB_RED}✗${MB_RESET} $*" >&2; }
mb_die()     { mb_error "$*"; exit 1; }

mb_ask() {
    local prompt="$1" default="${2:-y}"
    local yn
    if [ "$default" = "y" ]; then
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [Y/n] ")" yn </dev/tty
        [[ "$yn" =~ ^[Nn]$ ]] && return 1 || return 0
    else
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [y/N] ")" yn </dev/tty
        [[ "$yn" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

mb_ask_value() {
    local prompt="$1" default="${2:-}"
    local value
    if [ -n "$default" ]; then
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [${default}]: ")" value </dev/tty
        echo "${value:-$default}"
    else
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt}: ")" value </dev/tty
        echo "$value"
    fi
}

mb_check_command() { command -v "$1" >/dev/null 2>&1; }

mb_check_docker() {
    if ! mb_check_command docker; then
        mb_die "Docker is not installed. Run vps-bootstrap first: https://github.com/0x10debug/vps-bootstrap"
    fi
    if ! docker info >/dev/null 2>&1; then
        mb_die "Docker daemon is not running."
    fi
}

mb_template_exists() {
    local template="$1"
    [ -d "${MB_TEMPLATES_DIR}/${template}" ]
}

# Return the primary compose file for a template. Most templates use
# compose.yml; sso and load-balancing have multiple provider-specific
# compose files and no compose.yml — the caller must prompt the user to
# choose. Returns the path on stdout, or empty if none found.
mb_template_compose_file() {
    local template="$1"
    local dir="${MB_TEMPLATES_DIR}/${template}"
    if [ -f "${dir}/compose.yml" ]; then
        echo "${dir}/compose.yml"
    fi
}

mb_list_templates() {
    for dir in "$MB_TEMPLATES_DIR"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        local desc=""
        if [ -f "${dir}README.md" ]; then
            desc=$(head -1 "${dir}README.md" | sed 's/^# *//')
        fi
        echo "${name}|${desc}"
    done
}

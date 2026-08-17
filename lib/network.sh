#!/usr/bin/env bash
# lib/network.sh — Docker network management for mb net

MB_PROXY_NETWORK="${MB_PROXY_NETWORK:-mb-proxy}"

mb_network_ensure_proxy() {
    if ! docker network inspect "$MB_PROXY_NETWORK" >/dev/null 2>&1; then
        mb_info "Creating shared proxy network: $MB_PROXY_NETWORK"
        docker network create "$MB_PROXY_NETWORK" >/dev/null 2>&1
        mb_detail "Network created"
    else
        mb_detail "Proxy network exists: $MB_PROXY_NETWORK"
    fi
}

mb_network_list_containers() {
    echo "  Containers on ${MB_PROXY_NETWORK} network:"
    docker network inspect "$MB_PROXY_NETWORK" 2>/dev/null \
        | jq -r '.[0].Containers[] | "    \(.Name) — \(.IPv4Address)"' 2>/dev/null \
        || echo "    (no containers or network not found)"
}

mb_network_check_proxy() {
    docker network inspect "$MB_PROXY_NETWORK" >/dev/null 2>&1
}

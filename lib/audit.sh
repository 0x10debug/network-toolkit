#!/usr/bin/env bash
# lib/audit.sh — Port exposure audit

mb_audit_ports() {
    mb_step "Port exposure audit"
    echo ""

    # 1. Host-level listening ports
    mb_info "Host listening ports:"
    echo ""

    if mb_check_command ss; then
        ss -tulpn 2>/dev/null | awk 'NR>1 {
            split($5, a, ":")
            port=a[length(a)]
            proto=$1
            bind=$5
            sub(/:[0-9]+$/, "", bind)
            printf "  %-6s %-20s %s\n", proto, port, bind
        }' | sort -t' ' -k2 -n | uniq
    elif mb_check_command netstat; then
        netstat -tulpn 2>/dev/null | awk 'NR>2 {
            split($4, a, ":")
            port=a[length(a)]
            proto=$1
            printf "  %-6s %-20s\n", proto, port
        }' | sort | uniq
    else
        mb_warn "Neither ss nor netstat available"
    fi

    echo ""

    # 2. Docker port mappings
    mb_info "Docker port mappings:"
    echo ""

    local containers
    containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    if [ -z "$containers" ]; then
        mb_detail "No running Docker containers"
    else
        for name in $containers; do
            local ports
            ports=$(docker port "$name" 2>/dev/null)
            if [ -n "$ports" ]; then
                echo "  $name:"
                echo "$ports" | sed 's/^/    /'
            fi
        done
    fi

    echo ""

    # 3. Security analysis
    mb_info "Security analysis:"
    echo ""

    # Check for ports bound to 0.0.0.0
    local public_ports
    public_ports=$(ss -tlnp 2>/dev/null | grep "0.0.0.0" | awk '{print $4}' | rev | cut -d: -f1 | rev | sort -n | uniq || echo "")
    if [ -n "$public_ports" ]; then
        for port in $public_ports; do
            case "$port" in
                80|443)
                    mb_detail "Port $port: HTTP/HTTPS — OK (reverse proxy)"
                    ;;
                22|2222)
                    mb_warn "Port $port: SSH — exposed to public. Ensure hardened (key-only, non-root)."
                    ;;
                *)
                    mb_warn "Port $port: Exposed to 0.0.0.0 — verify this is intentional"
                    ;;
            esac
        done
    fi

    # Check firewall
    echo ""
    if mb_check_command ufw; then
        mb_info "UFW firewall status:"
        ufw status 2>/dev/null | sed 's/^/  /'
    elif [ -f /etc/nftables.nft ] || mb_check_command nft; then
        mb_info "nftables ruleset:"
        nft list ruleset 2>/dev/null | head -30 | sed 's/^/  /'
    else
        mb_warn "No firewall detected (neither UFW nor nftables)"
    fi
}

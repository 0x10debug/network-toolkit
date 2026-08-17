#!/usr/bin/env bash
# lib/ssl.sh — SSL certificate status checking

mb_ssl_list() {
    mb_info "SSL certificates managed by Caddy:"
    echo ""

    # Caddy stores certificates in its data directory
    local caddy_data="/data/caddy/data/caddy/certificates"
    if [ ! -d "$caddy_data" ]; then
        mb_warn "No Caddy certificate directory found at: $caddy_data"
        mb_detail "Is Caddy deployed? Run: mb net deploy website"
        return 1
    fi

    # Find all certificate directories
    local found=0
    for issuer_dir in "$caddy_data"/*/; do
        [ -d "$issuer_dir" ] || continue
        for cert_dir in "$issuer_dir"*/; do
            [ -d "$cert_dir" ] || continue
            local domain
            domain=$(basename "$cert_dir")
            local cert_file="${cert_dir}${domain}.crt"

            if [ -f "$cert_file" ]; then
                local expiry
                expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                local days_left
                if [ -n "$expiry" ]; then
                    days_left=$(( ( $(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %H:%M:%S %Y %Z" "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
                else
                    days_left="?"
                fi

                printf "  %-30s  expires: %-25s  days left: %s\n" "$domain" "$expiry" "$days_left"
                found=$((found + 1))
            fi
        done
    done

    if [ "$found" -eq 0 ]; then
        mb_warn "No certificates found. Caddy will obtain them on first request."
    fi
}

mb_ssl_renew() {
    mb_info "Caddy manages SSL certificates automatically."
    mb_detail "To force renewal, restart Caddy:"

    local caddy_container
    caddy_container=$(docker ps --filter "name=caddy" --format "{{.Names}}" 2>/dev/null | head -1)

    if [ -n "$caddy_container" ]; then
        mb_detail "  docker restart $caddy_container"
        if mb_ask "Restart Caddy now to trigger renewal?" "n"; then
            docker restart "$caddy_container" 2>/dev/null
            mb_success "Caddy restarted — certificates will be renewed on next request"
        fi
    else
        mb_warn "No Caddy container found. Is the reverse proxy deployed?"
    fi
}

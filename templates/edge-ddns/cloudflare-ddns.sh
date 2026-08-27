#!/usr/bin/env bash
# cloudflare-ddns.sh — update Cloudflare A/AAAA records to the current public IP
#
# Calls the Cloudflare API to keep one A (IPv4) and one AAAA (IPv6) record
# pointed at this host's current public address. Idempotent: it only writes
# when the record value differs from the current IP. Logs every run.
#
# Requires: curl, jq, and a Cloudflare API token with Zone:DNS:Edit on the
# zone. No other dependencies.
#
# Usage:
#   1. Copy this script to /usr/local/sbin/cloudflare-ddns.sh
#   2. chmod +x it
#   3. Set the CONFIG section below (or export the vars before running)
#   4. Run directly, or via cron:
#        */5 * * * * /usr/local/sbin/cloudflare-ddns.sh >> /var/log/cloudflare-ddns.log 2>&1
#
# Exit codes: 0 success (or no change needed), 1 configuration error,
# 2 transient API/network error.

set -euo pipefail

# ── Config (override via environment) ────────────────────────────────────────
CF_API_TOKEN="${CF_API_TOKEN:-}"        # Cloudflare API token (Zone:DNS:Edit)
CF_ZONE_NAME="${CF_ZONE_NAME:-}"        # e.g. example.com
CF_RECORD_NAME="${CF_RECORD_NAME:-}"    # e.g. home.example.com
# Whether to update IPv4 (A) and/or IPv6 (AAAA).
CF_UPDATE_IPV4="${CF_UPDATE_IPV4:-true}"
CF_UPDATE_IPV6="${CF_UPDATE_IPV6:-false}"
# Optional: force a specific IP instead of auto-detecting.
CF_IPV4_OVERRIDE="${CF_IPV4_OVERRIDE:-}"
CF_IPV6_OVERRIDE="${CF_IPV6_OVERRIDE:-}"

CF_API="https://api.cloudflare.com/client/v4"
LOG_TAG="cloudflare-ddns"

log()  { printf '%s [%s] %s\n' "$(date '+%F %T')" "$LOG_TAG" "$*"; }
die()  { log "ERROR: $*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
command -v curl >/dev/null || die "curl not found"
command -v jq   >/dev/null || die "jq not found"
[ -n "$CF_API_TOKEN" ]   || die "CF_API_TOKEN not set"
[ -n "$CF_ZONE_NAME" ]   || die "CF_ZONE_NAME not set"
[ -n "$CF_RECORD_NAME" ] || die "CF_RECORD_NAME not set"

# ── Helpers ──────────────────────────────────────────────────────────────────

# Resolve the zone ID for CF_ZONE_NAME.
cf_zone_id() {
    curl -fsS --max-time 15 \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${CF_API}/zones?name=${CF_ZONE_NAME}" \
        | jq -r '.result[0].id // empty'
}

# Find a DNS record ID by type and name within a zone.
cf_record_id() {
    local zone_id="$1" type="$2" name="$3"
    curl -fsS --max-time 15 \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${CF_API}/zones/${zone_id}/dns_records?type=${type}&name=${name}" \
        | jq -r '.result[0].id // empty'
}

# Get the current value of a DNS record (empty if it doesn't exist).
cf_record_value() {
    local zone_id="$1" type="$2" name="$3"
    curl -fsS --max-time 15 \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${CF_API}/zones/${zone_id}/dns_records?type=${type}&name=${name}" \
        | jq -r '.result[0].content // empty'
}

# Create or update a DNS record to the given IP. Idempotent.
cf_upsert_record() {
    local zone_id="$1" type="$2" name="$3" ip="$4"
    local record_id
    record_id=$(cf_record_id "$zone_id" "$type" "$name")

    if [ -z "$record_id" ]; then
        # Create.
        log "creating ${type} ${name} -> ${ip}"
        curl -fsS --max-time 15 \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${type}\",\"name\":\"${name}\",\"content\":\"${ip}\",\"ttl\":60,\"proxied\":false}" \
            "${CF_API}/zones/${zone_id}/dns_records" >/dev/null
    else
        # Update only if changed.
        local current
        current=$(cf_record_value "$zone_id" "$type" "$name")
        if [ "$current" = "$ip" ]; then
            log "${type} ${name} already ${ip} — no change"
            return 0
        fi
        log "updating ${type} ${name}: ${current} -> ${ip}"
        curl -fsS --max-time 15 -X PUT \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"${type}\",\"name\":\"${name}\",\"content\":\"${ip}\",\"ttl\":60,\"proxied\":false}" \
            "${CF_API}/zones/${zone_id}/dns_records/${record_id}" >/dev/null
    fi
}

# Detect the current public IPv4.
detect_ipv4() {
    if [ -n "$CF_IPV4_OVERRIDE" ]; then
        echo "$CF_IPV4_OVERRIDE"
        return
    fi
    curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true
}

# Detect the current public IPv6.
detect_ipv6() {
    if [ -n "$CF_IPV6_OVERRIDE" ]; then
        echo "$CF_IPV6_OVERRIDE"
        return
    fi
    curl -fsS --max-time 10 -6 https://api6.ipify.org 2>/dev/null || true
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    local zone_id
    zone_id=$(cf_zone_id)
    [ -n "$zone_id" ] || die "zone not found: ${CF_ZONE_NAME} (check API token scopes)"
    log "zone ${CF_ZONE_NAME} id=${zone_id}"

    local changed=false

    if [ "$CF_UPDATE_IPV4" = "true" ]; then
        local ipv4
        ipv4=$(detect_ipv4)
        if [ -n "$ipv4" ]; then
            cf_upsert_record "$zone_id" "A" "$CF_RECORD_NAME" "$ipv4"
            changed=true
        else
            log "could not detect public IPv4 — skipping A record"
        fi
    fi

    if [ "$CF_UPDATE_IPV6" = "true" ]; then
        local ipv6
        ipv6=$(detect_ipv6)
        if [ -n "$ipv6" ]; then
            cf_upsert_record "$zone_id" "AAAA" "$CF_RECORD_NAME" "$ipv6"
            changed=true
        else
            log "could not detect public IPv6 — skipping AAAA record"
        fi
    fi

    if [ "$changed" = "true" ]; then
        log "done"
    else
        log "no updates performed"
    fi
}

main

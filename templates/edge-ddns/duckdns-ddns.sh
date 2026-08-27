#!/usr/bin/env bash
# duckdns-ddns.sh — update a DuckDNS domain to the current public IP
#
# DuckDNS (https://www.duckdns.org) is a free dynamic DNS service. This script
# keeps a DuckDNS subdomain pointed at this host's current public IPv4 (and
# optionally IPv6). Idempotent: DuckDNS only updates when the IP changes, and
# the script is safe to run repeatedly. Logs every run.
#
# Requires: curl. No jq needed — DuckDNS returns a plain "OK"/"KO" response.
#
# Usage:
#   1. Copy to /usr/local/sbin/duckdns-ddns.sh and chmod +x
#   2. Set DUCKDNS_TOKEN and DUCKDNS_DOMAINS below (or export them)
#   3. Run via cron:
#        */5 * * * * /usr/local/sbin/duckdns-ddns.sh >> /var/log/duckdns-ddns.log 2>&1
#
# DUCKDNS_DOMAINS is a comma-separated list (no spaces) of your subdomains,
# e.g. "myhome,myhome2" -> updates myhome.duckdns.org and myhome2.duckdns.org.

set -euo pipefail

# ── Config (override via environment) ────────────────────────────────────────
DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-}"
DUCKDNS_DOMAINS="${DUCKDNS_DOMAINS:-}"   # e.g. myhome  (becomes myhome.duckdns.org)
DUCKDNS_UPDATE_IPV6="${DUCKDNS_UPDATE_IPV6:-false}"

LOG_TAG="duckdns-ddns"

log() { printf '%s [%s] %s\n' "$(date '+%F %T')" "$LOG_TAG" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }

command -v curl >/dev/null || die "curl not found"
[ -n "$DUCKDNS_TOKEN" ]   || die "DUCKDNS_TOKEN not set"
[ -n "$DUCKDNS_DOMAINS" ] || die "DUCKDNS_DOMAINS not set (comma-separated, no .duckdns.org suffix)"

# ── Main ─────────────────────────────────────────────────────────────────────

# DuckDNS update endpoint. Passing ip= auto-detects IPv4 server-side.
# For IPv6, pass ipv6=<addr> (or ipv6= to let DuckDNS detect it).
UPDATE_URL="https://www.duckdns.org/update?domains=${DUCKDNS_DOMAINS}&token=${DUCKDNS_TOKEN}&ip="

if [ "$DUCKDNS_UPDATE_IPV6" = "true" ]; then
    # Let DuckDNS detect the IPv6 server-side too.
    UPDATE_URL="${UPDATE_URL}&ipv6="
fi

response=$(curl -fsS --max-time 15 "$UPDATE_URL" 2>/dev/null || true)

if [ "$response" = "OK" ]; then
    log "updated ${DUCKDNS_DOMAINS} (ipv6=${DUCKDNS_UPDATE_IPV6})"
else
    log "update failed for ${DUCKDNS_DOMAINS}: response='${response:-empty}'" >&2
    exit 2
fi

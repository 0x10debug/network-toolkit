#!/usr/bin/env bash
# generate-certs.sh — generate a self-signed CA + server + client certificates
# for mutual TLS (mTLS) authentication.
#
# Produces three sets of files in --outdir (default ./certs):
#   ca.{crt,key}           — self-signed Certificate Authority
#   server.{crt,key,csr}   — server cert with SAN (used by the reverse proxy)
#   client.{crt,key,csr}   — client cert (distributed to connecting clients)
#
# Usage:
#   ./generate-certs.sh [--domain <domain>] [--days <n>] [--outdir <dir>]
#
# Examples:
#   ./generate-certs.sh                                    # default: localhost, 365 days, ./certs
#   ./generate-certs.sh --domain api.example.com --days 825
#   ./generate-certs.sh --outdir /etc/ssl/mtls --domain "*.internal.example.com"
#
# Requires: openssl. No root needed if --outdir is user-writable.

set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
DOMAIN="localhost"
DAYS=365
OUTDIR="./certs"

# ── Parse args ───────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --domain) DOMAIN="$2"; shift 2 ;;
        --days)   DAYS="$2"; shift 2 ;;
        --outdir) OUTDIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,20p' "$0"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run: $0 --help" >&2
            exit 1
            ;;
    esac
done

# ── Validate ─────────────────────────────────────────────────────────────────
command -v openssl >/dev/null 2>&1 || { echo "Error: openssl not found" >&2; exit 1; }

# Resolve outdir to an absolute path so openssl -CAfile references work
OUTDIR="$(cd "$(dirname "$OUTDIR")" 2>/dev/null && echo "$(pwd)/$(basename "$OUTDIR")")" 2>/dev/null || OUTDIR="$(pwd)/${OUTDIR#./}"

mkdir -p "$OUTDIR"
chmod 700 "$OUTDIR"

echo "==> mTLS certificate generation"
echo "    Domain : $DOMAIN"
echo "    Days   : $DAYS"
echo "    Outdir : $OUTDIR"
echo ""

# ── 1. Certificate Authority (CA) ────────────────────────────────────────────
echo "==> [1/3] Generating self-signed CA..."
openssl genrsa -out "${OUTDIR}/ca.key" 4096 2>/dev/null
openssl req -new -x509 -key "${OUTDIR}/ca.key" -out "${OUTDIR}/ca.crt" \
    -days "$DAYS" -sha256 \
    -subj "/C=US/ST=State/L=City/O=0x10debug/CN=mtls-ca" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
chmod 600 "${OUTDIR}/ca.key"
echo "    ca.crt + ca.key"

# ── 2. Server certificate (with SAN) ─────────────────────────────────────────
echo "==> [2/3] Generating server certificate..."

# Build a SAN extension config. If the domain is a wildcard, add it as a
# DNS entry; otherwise add both the domain and the bare hostname.
SAN_CONFIG="${OUTDIR}/server_san.cnf"
{
    echo "[req]"
    echo "distinguished_name = req_distinguished_name"
    echo "req_extensions = v3_req"
    echo "prompt = no"
    echo ""
    echo "[req_distinguished_name]"
    echo "C = US"
    echo "ST = State"
    echo "L = City"
    echo "O = 0x10debug"
    echo "CN = ${DOMAIN}"
    echo ""
    echo "[v3_req]"
    echo "basicConstraints = CA:FALSE"
    echo "keyUsage = critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage = serverAuth"
    echo "subjectAltName = @alt_names"
    echo ""
    echo "[alt_names]"
    echo "DNS.1 = ${DOMAIN}"
    # Add localhost and 127.0.0.1 for local testing
    if [ "$DOMAIN" != "localhost" ]; then
        echo "DNS.2 = localhost"
    fi
    echo "IP.1 = 127.0.0.1"
} > "$SAN_CONFIG"

openssl genrsa -out "${OUTDIR}/server.key" 2048 2>/dev/null
openssl req -new -key "${OUTDIR}/server.key" -out "${OUTDIR}/server.csr" \
    -config "$SAN_CONFIG" 2>/dev/null
openssl x509 -req -in "${OUTDIR}/server.csr" \
    -CA "${OUTDIR}/ca.crt" -CAkey "${OUTDIR}/ca.key" -CAcreateserial \
    -out "${OUTDIR}/server.crt" -days "$DAYS" -sha256 \
    -extensions v3_req -extfile "$SAN_CONFIG" 2>/dev/null
chmod 600 "${OUTDIR}/server.key"
echo "    server.crt + server.key (SAN: ${DOMAIN}, localhost, 127.0.0.1)"

# ── 3. Client certificate ────────────────────────────────────────────────────
echo "==> [3/3] Generating client certificate..."
CLIENT_EXT="${OUTDIR}/client_ext.cnf"
{
    echo "[v3_req]"
    echo "basicConstraints = CA:FALSE"
    echo "keyUsage = critical,digitalSignature,keyEncipherment"
    echo "extendedKeyUsage = clientAuth"
} > "$CLIENT_EXT"

openssl genrsa -out "${OUTDIR}/client.key" 2048 2>/dev/null
openssl req -new -key "${OUTDIR}/client.key" -out "${OUTDIR}/client.csr" \
    -subj "/C=US/ST=State/L=City/O=0x10debug/CN=mtls-client" 2>/dev/null
openssl x509 -req -in "${OUTDIR}/client.csr" \
    -CA "${OUTDIR}/ca.crt" -CAkey "${OUTDIR}/ca.key" -CAcreateserial \
    -out "${OUTDIR}/client.crt" -days "$DAYS" -sha256 \
    -extensions v3_req -extfile "$CLIENT_EXT" 2>/dev/null
chmod 600 "${OUTDIR}/client.key"
echo "    client.crt + client.key"

# Cleanup CSR, serial, and temp config files (keep .crt/.key only)
rm -f "${OUTDIR}/server.csr" "${OUTDIR}/client.csr" "${OUTDIR}/ca.srl" "$SAN_CONFIG" "$CLIENT_EXT"

echo ""
echo "==> Done. Files in ${OUTDIR}/:"
find "$OUTDIR" -maxdepth 1 \( -name '*.crt' -o -name '*.key' \) -type f | sort | sed 's/^/    /'
echo ""
echo "==> Next steps:"
echo "    1. Install ca.crt + server.crt + server.key on your reverse proxy"
echo "    2. Distribute ca.crt + client.crt + client.key to connecting clients"
echo "    3. Configure ssl_verify_client on (nginx) / clientAuth (traefik) / client_auth (caddy)"
echo "    4. Test: curl --cacert ${OUTDIR}/ca.crt --cert ${OUTDIR}/client.crt --key ${OUTDIR}/client.key https://${DOMAIN}"

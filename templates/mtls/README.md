# mTLS (Mutual TLS) Templates

Mutual TLS (mTLS) authentication templates for the network-toolkit. Unlike
SSO/OIDC (which authenticates at the HTTP layer), mTLS authenticates at the
**TLS layer** — every client must present a cryptographic certificate signed
by a trusted CA before the TLS handshake completes. No valid client cert =
no connection, period. This makes mTLS ideal for API-to-API, service mesh,
and zero-trust internal networks.

## What is mTLS?

Standard TLS: the **server** presents a certificate to prove its identity to
the client. The client is anonymous (or authenticates at the HTTP layer).

Mutual TLS: **both** sides present certificates. The server verifies the
client's certificate against a trusted CA, and the client verifies the
server's certificate as usual. Authentication happens during the TLS
handshake — before any HTTP traffic flows.

```
  Client                              Server (reverse proxy)
    │                                      │
    │ ── ClientHello + client cert ──────▶ │
    │ ◀── ServerHello + server cert ────── │
    │                                      │
    │   Server verifies client cert        │
    │   against trusted CA (ca.crt)        │
    │                                      │
    │ ── Encrypted HTTP traffic ─────────▶ │ ──▶ Backend
```

If the client cert is missing or invalid, the TLS handshake fails and the
connection is dropped — no HTTP 401, no redirect, just a TLS error.

## Contents

- [`generate-certs.sh`](./generate-certs.sh) — CA + server + client cert generator
  - Self-signed CA (4096-bit RSA)
  - Server cert with SAN (2048-bit, `serverAuth` EKU)
  - Client cert (2048-bit, `clientAuth` EKU)
  - `--domain`, `--days`, `--outdir` parameters
- [`nginx-mtls.conf`](./nginx-mtls.conf) — Nginx mTLS config
  - `ssl_client_certificate`, `ssl_verify_client on`, `ssl_verify_depth`
- [`traefik-mtls.yml`](./traefik-mtls.yml) — Traefik v3.6 mTLS config
  - `tls.options.mtls` with `clientAuth` (`RequireAndVerifyClientCert`)
- [`caddy-mtls.Caddyfile`](./caddy-mtls.Caddyfile) — Caddy v2.9 mTLS config
  - `client_auth` directive with `trusted_ca_cert_file`
- [`README.md`](./README.md) — this file

## Quick Start

```bash
# 1. Generate certificates (CA + server + client)
./generate-certs.sh --domain api.example.com --days 825 --outdir ./certs

# 2. Install server cert + CA on your reverse proxy
#    (mount ./certs into the proxy container)

# 3. Configure mTLS enforcement — pick your reverse proxy:
#    - Nginx:  use nginx-mtls.conf
#    - Traefik: copy traefik-mtls.yml into dynamic/
#    - Caddy:  use caddy-mtls.Caddyfile

# 4. Distribute client cert to connecting clients
#    Send: ca.crt + client.crt + client.key

# 5. Test from a client
curl --cacert ./certs/ca.crt \
     --cert ./certs/client.crt \
     --key ./certs/client.key \
     https://api.example.com
```

## Certificate Generation

`generate-certs.sh` produces three certificate pairs:

| File | Purpose | Installed on |
|---|---|---|
| `ca.crt` + `ca.key` | Certificate Authority | Server (verify clients) + Client (verify server) |
| `server.crt` + `server.key` | Server identity | Reverse proxy |
| `client.crt` + `client.key` | Client identity | Each connecting client |

### Parameters

| Flag | Default | Description |
|---|---|---|
| `--domain` | `localhost` | Domain / hostname for the server cert SAN |
| `--days` | `365` | Certificate validity period (days) |
| `--outdir` | `./certs` | Output directory for cert files |

### Examples

```bash
# Default (localhost, 365 days, ./certs)
./generate-certs.sh

# Production API with 825-day certs (Let's Encrypt-aligned)
./generate-certs.sh --domain api.example.com --days 825

# Wildcard internal domain, custom output dir
./generate-certs.sh --domain "*.internal.example.com" --outdir /etc/ssl/mtls
```

## Reverse Proxy Configuration

### Nginx

Key directives (see [`nginx-mtls.conf`](./nginx-mtls.conf) for full config):

```nginx
ssl_certificate     /certs/server.crt;
ssl_certificate_key /certs/server.key;
ssl_client_certificate /certs/ca.crt;     # CA that signed client certs
ssl_verify_client on;                      # require valid client cert
ssl_verify_depth 2;                        # chain depth (1 = direct from CA)
```

### Traefik v3.6

Define a TLS option with `clientAuth` (see [`traefik-mtls.yml`](./traefik-mtls.yml)):

```yaml
tls:
  options:
    mtls:
      clientAuth:
        caFiles: ["/certs/ca.crt"]
        clientAuthType: "RequireAndVerifyClientCert"
```

Reference it on a router: `tls: { options: mtls }`.

### Caddy v2.9

Use the `client_auth` directive (see [`caddy-mtls.Caddyfile`](./caddy-mtls.Caddyfile)):

```caddyfile
api.example.com {
    tls /certs/server.crt /certs/server.key {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /certs/ca.crt
        }
    }
    reverse_proxy backend:8080
}
```

## Client Configuration

Clients must present their certificate on every connection.

### curl

```bash
curl --cacert ca.crt --cert client.crt --key client.key https://api.example.com
```

### Python (requests)

```python
import requests
r = requests.get(
    "https://api.example.com",
    verify="ca.crt",
    cert=("client.crt", "client.key"),
)
```

### Go

```go
cert, _ := tls.LoadX509KeyPair("client.crt", "client.key")
caCert, _ := os.ReadFile("ca.crt")
pool := x509.NewCertPool()
pool.AppendCertsFromPEM(caCert)
client := &http.Client{
    Transport: &http.Transport{
        TLSClientConfig: &tls.Config{
            Certificates: []tls.Certificate{cert},
            RootCAs:      pool,
        },
    },
}
```

### Browser

Import `client.crt` + `client.key` into your browser's certificate store.
The browser will prompt you to select the client certificate when visiting
the mTLS-protected site.

## Certificate Revocation

When a client certificate is compromised or a user leaves, you must revoke
it so the reverse proxy stops accepting it.

### Option 1: CRL (Certificate Revocation List)

1. Generate a CRL from your CA:
   ```bash
   openssl ca -config openssl.cnf -revoke certs/client.crt
   openssl ca -config openssl.cnf -gencrl -out crl.pem
   ```
2. Configure the reverse proxy to check the CRL:
   - **Nginx**: `ssl_crl /certs/crl.pem;`
   - **Traefik**: not natively supported — use OCSP or rotate the CA.
   - **Caddy**: not natively supported — use OCSP or rotate the CA.

### Option 2: Rotate the CA (simplest, nuclear option)

1. Generate a new CA: `./generate-certs.sh --domain api.example.com`
2. Re-issue all **valid** client certificates with the new CA.
3. Replace `ca.crt` on the reverse proxy and reload.
4. All old client certs instantly become invalid.

This is the simplest approach for small deployments. For large fleets, use
CRL or OCSP stapling.

## mTLS vs SSO/OIDC

| | mTLS | SSO/OIDC |
|---|---|---|
| Layer | TLS handshake | HTTP (forward_auth) |
| Failure mode | TLS error (no HTTP response) | HTTP 401 → redirect to login |
| Client setup | Install client cert | Browser login flow |
| Best for | API-to-API, service mesh, zero-trust | Web apps, human users |
| Revocation | CRL / CA rotation | Disable user in IdP |
| User experience | Transparent (once cert installed) | Interactive login |

**Recommendation**: use **mTLS** for machine-to-machine communication, internal
service meshes, and zero-trust networks where every client is a known
service. Use **SSO/OIDC** (see [`templates/sso/`](../sso/)) for human-facing
web apps where users log in via browser.

## Notes

- The CA generated by `generate-certs.sh` is self-signed. This is fine for
  internal mTLS — the CA is private and only used to sign your client certs.
  Never expose `ca.key` to clients; only distribute `ca.crt`.
- `ssl_verify_depth` (Nginx) / chain depth: use `1` if client certs are
  signed directly by the CA (the default output of `generate-certs.sh`).
  Increase to `2` if you add intermediate CAs.
- For wildcard domains, pass `--domain "*.example.com"` — the SAN will
  include the wildcard entry.
- mTLS and Let's Encrypt coexist: the server cert can come from ACME while
  client certs are verified against your custom CA. They are independent
  certificate chains.

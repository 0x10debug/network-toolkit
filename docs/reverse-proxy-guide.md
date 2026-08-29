# Reverse Proxy Guide

How to use a reverse proxy to expose your self-hosted apps with HTTPS.

## What is a Reverse Proxy?

A reverse proxy sits between the internet and your applications. When someone visits `app.example.com`, the proxy routes the request to the correct container (e.g., `jellyfin:8096`). It also handles SSL certificates automatically.

## Why Caddy?

This toolkit uses [Caddy v2.9](https://caddyserver.com/) as the default reverse proxy because:

- **Automatic HTTPS** — obtains and renews Let's Encrypt certificates with zero configuration
- **HTTP/3 (QUIC)** — built-in support for the latest HTTP protocol, faster connection setup and better performance on unreliable networks
- **Simple syntax** — Caddyfile is human-readable, no complex YAML
- **Small footprint** — single binary, low memory usage
- **Production-ready** — used by major projects, battle-tested

## Quick Start

```bash
# Deploy a reverse proxy for a single site
mb net deploy website

# Enter your domain and target:
# PRIMARY_DOMAIN=app.example.com
# APP_HOST=jellyfin
# APP_PORT=8096
```

Caddy will:
1. Listen on ports 80 and 443 (TCP + UDP)
2. Obtain an SSL certificate for `app.example.com` from Let's Encrypt
3. Serve traffic over HTTP/1.1, HTTP/2, and HTTP/3 (QUIC)
4. Route all traffic to the `jellyfin` container on port 8096
5. Actively health-check the backend and mark it down if it stops responding
6. Inject security headers (HSTS, X-Content-Type-Options, etc.)

## Adding More Routes

After deploying the reverse proxy, add routes for additional apps:

```bash
mb net proxy add media.example.com jellyfin:8096
mb net proxy add music.example.com navidrome:4533
mb net proxy add photos.example.com immich:2283
```

Each route is added to the Caddyfile and Caddy is reloaded automatically. SSL certificates are obtained on first request.

## Removing Routes

```bash
mb net proxy remove media.example.com
```

## Multi-Site Setup

If you know all your domains upfront, use the multi-site template:

```bash
mb net deploy multi-site
```

This deploys Caddy with a Caddyfile pre-configured for multiple domains. Edit the Caddyfile directly to add or modify routes.

## How It Works with Docker Networks

All containers join the `mb-proxy` Docker network. The reverse proxy also joins this network. This allows the proxy to reach any container by name:

```
Internet → VPS:443 → Caddy → mb-proxy network → jellyfin:8096
```

Containers don't need to expose ports to the host — the proxy reaches them via the internal Docker network.

## Security Headers

All templates include these headers by default:

| Header | Value | Purpose |
|---|---|---|
| Strict-Transport-Security | max-age=31536000; includeSubDomains | Force HTTPS for 1 year |
| X-Content-Type-Options | nosniff | Prevent MIME type sniffing |
| X-Frame-Options | DENY | Prevent clickjacking |
| Referrer-Policy | strict-origin-when-cross-origin | Limit referrer leakage |
| Permissions-Policy | geolocation=(), microphone=(), camera=() | Disable sensitive APIs |

## Custom Caddyfile

For advanced configurations, edit the Caddyfile directly:

```bash
# Find the deployed Caddyfile
ls /opt/mb-net/*/Caddyfile

# Edit it
nano /opt/mb-net/website/Caddyfile

# Reload Caddy
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Using Traefik Instead

If you prefer Traefik over Caddy, the toolkit ships a full **Traefik v3.6**
template at [`templates/traefik/`](../templates/traefik/) with reusable
components at [`components/traefik/`](../components/traefik/).

### Why Traefik?

- **Docker-native discovery** — containers with `traefik.enable=true` labels are
  routed automatically; no manual config edits per service.
- **Dashboard** — built-in web UI for inspecting routers, services, and
  middlewares (Caddy has no equivalent).
- **Dynamic config** — file provider hot-reloads YAML without restarting.
- **Middleware library** — rate-limit, secure-headers, compress, basic-auth,
  ip-whitelist, redirect — all pre-defined in `dynamic/middlewares.yml`.

### Deploy

```bash
mb net deploy traefik
# Enter PRIMARY_DOMAIN and ACME_EMAIL
```

This starts `traefik:v3.6.0` (pinned) on ports 80/443/8080, obtains a Let's
Encrypt certificate via the TLS-ALPN-01 challenge, and routes
`https://whoami.${PRIMARY_DOMAIN}` to a demo backend.

### Add a route via Docker labels

```yaml
services:
  myapp:
    image: myapp:latest
    networks: [mb-proxy]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.example.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.routers.myapp.middlewares=secure-headers@file,compress@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
networks:
  mb-proxy:
    external: true
```

Traefik discovers the container automatically — no reload needed.

### Caddy vs Traefik

| | Caddy | Traefik |
|---|---|---|
| Config | Caddyfile (human-readable) | YAML (static + dynamic) |
| Automatic HTTPS | Built-in, zero-config | ACME resolver |
| HTTP/3 (QUIC) | Yes (`protocols h1 h2 h3`) | Not in v3.6 stable |
| Service discovery | Manual `reverse_proxy` | Docker labels (auto) |
| Dashboard | None (`admin off`) | Built-in web UI |
| Best for | Simple sites, HTTP/3 | Many Docker services, dashboard |

**Recommendation**: Caddy for single/few sites where HTTP/3 and minimal config
matter; Traefik for Docker-heavy setups with many services and a desire for
label-based auto-discovery plus a dashboard.

## Securing Docker API Access (socket-proxy)

Both Caddy and Traefik can operate without the Docker socket — Caddy uses
explicit `reverse_proxy` blocks, and even Traefik can use the file provider
instead of Docker discovery. But when a reverse proxy or monitoring tool *does*
need Docker visibility (Traefik label discovery, container metrics), never
bind-mount `/var/run/docker.sock` directly: **the Docker socket is equivalent
to root on the host.**

Deploy the [`socket-proxy`](../templates/socket-proxy/) template instead. It
runs `tecnativa/docker-socket-proxy:0.1.5` (pinned) in front of the socket and
re-exposes a **filtered** Docker API on `:2375` inside an internal Docker
network — no ports published to the host. Every endpoint defaults to denied;
you allow only what a consumer needs (`CONTAINERS=1` for listing, `POST=0` to
block mutation).

```bash
mb net deploy socket-proxy
# enable only the endpoints your consumer needs in .env
```

Then point the consumer at `tcp://socket-proxy:2375` on the `mb-socket-proxy`
network instead of mounting the raw socket. See the
[socket-proxy README](../templates/socket-proxy/README.md) for the endpoint
reference and integration snippets for Traefik and monitoring agents.

## HTTP/3 (QUIC)

All templates in this toolkit enable HTTP/3 via the `protocols h1 h2 h3` global
directive in the Caddyfile and map UDP 443 in the compose file. This allows
clients that support QUIC to benefit from faster connection setup and improved
performance on lossy networks.

### Requirements

- **Firewall**: allow inbound UDP 443 in addition to TCP 443.
- **Client support**: modern browsers (Chrome, Firefox, Edge, Safari) support
  HTTP/3 automatically. `curl` needs the `--http3` flag.
- **Fallback**: if UDP 443 is blocked, Caddy transparently falls back to
  HTTP/2 — no configuration change needed.

### Verifying HTTP/3

```bash
# Check if the server advertises HTTP/3 (look for "alt-svc: h3=...")
curl -I https://your-domain.com

# Test an actual HTTP/3 request (requires curl built with HTTP/3 support)
curl -I --http3 https://your-domain.com
```

For a dedicated HTTP/3 configuration example, see
[`templates/caddy/http3/`](../templates/caddy/http3/).

## Edge Network Hardening

A reverse proxy is only as safe as the host firewall in front of it. Two
reference templates (not Compose-based — they configure the host directly)
complete the edge:

- **[`edge-firewall`](../templates/edge-firewall/)** — a complete nftables
  ruleset: default-deny inbound, established/related + loopback allowed,
  rate-limited SSH (5/min) to defeat brute force, HTTP/HTTPS open for the
  proxy, bogon source filtering, and a dynamic IP blocklist fed by Spamhaus /
  Emerging Threats / AbuseIPDB. Use it instead of UFW when you need
  rate-limiting, blocklists, or a single version-controlled ruleset. If you
  deploy the `cloudflare` tunnel template, comment out the 80/443 rules — the
  tunnel is outbound-only.

- **[`edge-ddns`](../templates/edge-ddns/)** — Cloudflare and DuckDNS dynamic
  DNS scripts (cron, IPv4 + IPv6, idempotent). Use these when your VPS or home
  server has a dynamic public IP and you run Caddy/Traefik directly (the
  `cloudflare` tunnel template doesn't need DDNS — its domain resolves to
  Cloudflare, not your IP).

## Authentication — SSO/OIDC and mTLS

A reverse proxy can centralize authentication so your backend apps don't need
to implement their own login flows. Two complementary approaches are provided:

### SSO / OIDC (HTTP-layer auth)

The [`sso`](../templates/sso/) template deploys an SSO/OIDC gateway that
authenticates users once and injects auth headers into every request forwarded
to your backends. Two providers are included:

- **OAuth2 Proxy** (`v7.7.0`) — delegates auth to Google, GitHub, or any OIDC
  IdP. Best for "Login with Google/GitHub" flows.
- **Authelia** (`v4.38.10`) — self-hosted identity provider with local users,
  2FA (TOTP/WebAuthn), and granular per-route access policies. No external IdP
  dependency.

Both providers bind to `127.0.0.1` and are reached via the reverse proxy's
`forward_auth` directive (Traefik) or `forward_auth` block (Caddy). Protecting
a new service is a one-line config change — add the SSO middleware to the
router or site block.

```bash
# Deploy OAuth2 Proxy (choose provider at prompt)
mb net deploy sso

# Deploy Authelia (choose provider at prompt)
mb net deploy sso

# Then wire your reverse proxy — see templates/sso/traefik-middleware.yml
# or templates/sso/caddy-handler.yml for integration snippets
```

### mTLS (TLS-layer auth)

The [`mtls`](../templates/mtls/) template provides mutual TLS — every client
must present a cryptographic certificate signed by your CA before the TLS
handshake completes. No valid cert = no connection. This is ideal for
API-to-API communication, service meshes, and zero-trust internal networks.

```bash
# Generate CA + server + client certificates
cd templates/mtls && ./generate-certs.sh --domain api.example.com --days 825

# Then configure your reverse proxy — see templates/mtls/ for
# nginx-mtls.conf, traefik-mtls.yml, or caddy-mtls.Caddyfile
```

| | SSO/OIDC | mTLS |
|---|---|---|
| Layer | HTTP (forward_auth) | TLS handshake |
| Best for | Human users, web apps | Machine-to-machine, APIs |
| Failure | HTTP 401 → login redirect | TLS error (no HTTP response) |
| Template | [`templates/sso/`](../templates/sso/) | [`templates/mtls/`](../templates/mtls/) |

## Load Balancing

When a single backend instance isn't enough, the [`load-balancing`](../templates/load-balancing/)
template distributes traffic across multiple instances for high availability
and horizontal scaling. Three solutions are included:

- **HAProxy** (`3.1.0`) — dedicated L4/L7 load balancer with the highest
  throughput. Supports TCP + HTTP, SSL termination, and SNI passthrough.
  Stats page on `127.0.0.1:9999`.
- **Nginx** (`1.27.2`) — lightweight L7 load balancer using `upstream` blocks.
  Supports round_robin, ip_hash (session persistence), and least_conn.
- **Traefik** — Docker-native load balancing via WRR (weighted round robin)
  with automatic service discovery. No separate container needed — drop the
  dynamic config into your existing Traefik deployment.

```bash
# Deploy HAProxy or Nginx load balancer (choose at prompt)
mb net deploy load-balancing

# For Traefik, copy the WRR config into your dynamic config directory:
cp templates/load-balancing/traefik-lb.yml /data/traefik/dynamic/
```

| | HAProxy | Nginx | Traefik |
|---|---|---|---|
| Layer | L4 + L7 | L7 | L7 |
| Service discovery | Manual | Manual | Docker labels (auto) |
| SSL termination | Yes | Yes | Yes (ACME) |
| SNI passthrough | Yes | Yes (stream) | No |
| Best for | High-throughput, TCP | Simple HTTP LB | Docker-native |

## Troubleshooting

See [SSL Management](./ssl-management.md) for certificate issues and [Security Checklist](./security-checklist.md) for exposure auditing.

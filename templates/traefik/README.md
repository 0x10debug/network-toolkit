# Traefik v3.6 Templates

Focused **Traefik v3.6** configuration templates for the network-toolkit. These
provide a Docker-native reverse proxy alternative to the Caddy templates, with
automatic Let's Encrypt SSL, a dashboard, and a library of reusable middlewares.

## Contents

- [`traefik.yml`](./traefik.yml) — Traefik v3.6 static configuration
  - entryPoints: `web` (:80) + `websecure` (:443) + `traefik` (:8080)
  - providers: docker (`exposedByDefault=false`) + file (directory, hot-reload)
  - certificatesResolvers: `letsencrypt` (ACME + TLS-ALPN-01 challenge)
  - `api.dashboard=true`, `api.insecure=false`
  - JSON access logs + optional tracing stub
- [`compose.yml`](./compose.yml) — `traefik:v3.6.0` (pinned), ports 80/443/8080,
  docker.sock (read-only) + `acme.json` volume, healthcheck, `restart: unless-stopped`
- [`dynamic/`](./dynamic/) — hot-reloaded dynamic configuration
  - [`middlewares.yml`](./dynamic/middlewares.yml) — rate-limit, secure-headers,
    compress, redirect-to-https, basic-auth, ip-whitelist
  - [`routers.yml`](./dynamic/routers.yml) — whoami service + dashboard router + TLS
- [`.env.example`](./.env.example) — `PRIMARY_DOMAIN`, `ACME_EMAIL`, `MB_PROXY_NETWORK`
- [`traefik.example.yml`](./traefik.example.yml) — user-facing static config copy to customize

## Quick start

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set PRIMARY_DOMAIN, ACME_EMAIL
cp traefik.example.yml traefik.yml

# 3. Launch
docker compose up -d

# 4. (optional) run the whoami demo backend
docker run -d --name whoami --network mb-proxy traefik/whoami
```

Traefik will:

1. Listen on ports 80 (redirect → 443), 443 (HTTPS), and 8080 (dashboard).
2. Obtain a Let's Encrypt certificate for `${PRIMARY_DOMAIN}` via TLS-ALPN-01.
3. Route `https://whoami.${PRIMARY_DOMAIN}` → `whoami:80` with secure headers.
4. Serve the dashboard at `https://traefik.${PRIMARY_DOMAIN}/dashboard/` behind basic auth.

## Adding routes

### Via Docker labels (recommended for apps)

Label your app container and join the `mb-proxy` network — Traefik discovers it
automatically, no restart needed:

```yaml
# your app's compose.yml
services:
  myapp:
    image: myapp:latest
    networks: [mb-proxy]
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`app.${PRIMARY_DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.routers.myapp.middlewares=secure-headers@file,compress@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"
networks:
  mb-proxy:
    external: true
```

### Via the file provider

Add a router/service block to `dynamic/routers.yml` and Traefik hot-reloads it.

## Middlewares

Defined in [`dynamic/middlewares.yml`](./dynamic/middlewares.yml), referenced as
`<name>@file`:

| Middleware | Purpose |
|---|---|
| `rate-limit@file` | 100 req/s average, 200 burst per source IP |
| `secure-headers@file` | HSTS, nosniff, frame-deny, referrer policy |
| `compress@file` | gzip/brotli, excludes video/zip |
| `redirect-to-https@file` | permanent HTTP→HTTPS (fallback for per-router use) |
| `basic-auth@file` | htpasswd basic auth — **replace the placeholder hash** |
| `ip-whitelist@file` | allow RFC1918 private ranges — tighten for production |

Generate a basic-auth hash:

```bash
htpasswd -nB admin
# paste the user:hash line into middlewares.yml under basic-auth.users
```

## Traefik vs Caddy (this toolkit)

| | Caddy (`templates/caddy/`) | Traefik (`templates/traefik/`) |
|---|---|---|
| Config format | Caddyfile (human-readable) | YAML (static + dynamic) |
| Automatic HTTPS | Built-in, zero-config | ACME resolver, TLS-ALPN-01 |
| HTTP/3 (QUIC) | `protocols h1 h2 h3`, UDP 443 | Not in v3.6 stable |
| Service discovery | Manual `reverse_proxy` blocks | Docker labels (auto-discovery) |
| Dashboard | `admin off` (no UI) | Built-in web dashboard |
| Middlewares | Snippets (`import`) | Named middlewares (`@file`) |
| Image size | ~40 MB (alpine) | ~100 MB |
| Best for | Simple sites, HTTP/3 | Docker-native, many services, dashboard |

**Recommendation**: use Caddy for single/few sites where you want HTTP/3 and the
simplest possible config. Use Traefik when you have many Docker services and want
label-based auto-discovery plus a dashboard.

## Notes

- `api.insecure=false` — the dashboard is NOT exposed on :8080 publicly by
  default. It is routed via `dynamic/routers.yml` on websecure behind basic auth.
  To bind :8080 to localhost only, change the compose port mapping to
  `"127.0.0.1:8080:8080"`.
- `acme.json` must be `chmod 600`. The named volume handles persistence; if you
  bind-mount a file instead, set permissions before starting Traefik.
- The TLS-ALPN-01 challenge requires port 443 reachable from the internet. For
  DNS-01 (useful behind a firewall), swap `tlsChallenge` for `dnsChallenge`.
- `exposedByDefault=false` means only containers with `traefik.enable=true` are
  routed — this is a safety default to avoid accidentally exposing services.

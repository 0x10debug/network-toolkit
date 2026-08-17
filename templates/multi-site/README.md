# Multi-Site Template

A multi-domain reverse proxy using **Caddy** with automatic HTTPS.

One Caddy instance terminates TLS for several domains and forwards each domain
to its own backend application, all over the shared `mb-proxy` Docker network.

## What it does

- Hosts multiple domains on a single Caddy instance.
- Obtains and renews a TLS certificate for each domain automatically.
- Applies a consistent set of security headers to every site.
- Writes JSON access logs to `/data/caddy/access.log`.

## Quick start

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set SITE_1_* and SITE_2_* values
cp Caddyfile.example Caddyfile
#   edit Caddyfile: add/remove site blocks to match your domains

# 3. Launch
docker compose up -d
```

Each backend app must be on the same `mb-proxy` network so Caddy can reach it
by container name.

## Environment variables

| Variable            | Required | Default   | Description                              |
|---------------------|----------|-----------|------------------------------------------|
| `SITE_1_DOMAIN`     | yes      | —         | First domain.                            |
| `SITE_1_HOST`       | yes      | —         | First backend container hostname.        |
| `SITE_1_PORT`       | no       | `8080`    | First backend port.                      |
| `SITE_2_DOMAIN`     | yes      | —         | Second domain.                           |
| `SITE_2_HOST`       | yes      | —         | Second backend container hostname.       |
| `SITE_2_PORT`       | no       | `8080`    | Second backend port.                     |
| `MB_PROXY_NETWORK`  | no       | `mb-proxy`| Shared Docker network name.              |

## Adding more sites

Duplicate a site block in `Caddyfile`, add matching `SITE_N_*` variables to
`.env` and `compose.yml`, then `docker compose up -d` again.

## Security headers

Each site block sets:

- `Strict-Transport-Security` — enforce HTTPS for 1 year, including subdomains.
- `X-Content-Type-Options: nosniff` — prevent MIME-type sniffing.
- `X-Frame-Options: DENY` — prevent clickjacking via framing.
- `Referrer-Policy: strict-origin-when-cross-origin` — limit referrer leakage.

## Notes

- Ports `80` and `443` must be open on the host for ACME challenges.
- All domains must point (A/AAAA records) to this host's public IP.
- Certificate data persists in the `caddy-data` / `caddy-config` volumes.

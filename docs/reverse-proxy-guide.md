# Reverse Proxy Guide

How to use a reverse proxy to expose your self-hosted apps with HTTPS.

## What is a Reverse Proxy?

A reverse proxy sits between the internet and your applications. When someone visits `app.example.com`, the proxy routes the request to the correct container (e.g., `jellyfin:8096`). It also handles SSL certificates automatically.

## Why Caddy?

This toolkit uses [Caddy](https://caddyserver.com/) as the default reverse proxy because:

- **Automatic HTTPS** — obtains and renews Let's Encrypt certificates with zero configuration
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
1. Listen on ports 80 and 443
2. Obtain an SSL certificate for `app.example.com` from Let's Encrypt
3. Route all traffic to the `jellyfin` container on port 8096
4. Inject security headers (HSTS, X-Content-Type-Options, etc.)

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

If you prefer Traefik over Caddy, you can use the [Traefik components](../components/) as a starting point. However, Caddy is recommended for simplicity.

## Troubleshooting

See [SSL Management](./ssl-management.md) for certificate issues and [Security Checklist](./security-checklist.md) for exposure auditing.

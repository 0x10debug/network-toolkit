# Website Template

A single-site reverse proxy using **Caddy** with automatic HTTPS.

Caddy terminates TLS (automatic certificates via Let's Encrypt / ZeroSSL) and
forwards all traffic to a single backend application reachable on the shared
`mb-proxy` Docker network.

## What it does

- Proxies one domain to one backend app.
- Obtains and renews TLS certificates automatically (no manual cert management).
- Adds a set of sensible security headers to every response.
- Writes JSON access logs to `/data/caddy/access.log`.

## Quick start

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set PRIMARY_DOMAIN, APP_HOST, APP_PORT
cp Caddyfile.example Caddyfile
#   edit Caddyfile only if you need custom behavior

# 3. Launch
docker compose up -d
```

Make sure your backend app is on the same `mb-proxy` network so Caddy can reach
it by container name (`APP_HOST`).

## Environment variables

| Variable          | Required | Default   | Description                                  |
|-------------------|----------|-----------|----------------------------------------------|
| `PRIMARY_DOMAIN`  | yes      | —         | Domain Caddy gets a certificate for.         |
| `APP_HOST`        | yes      | —         | Backend container hostname on mb-proxy.      |
| `APP_PORT`        | no       | `8080`    | Backend container port.                      |
| `MB_PROXY_NETWORK`| no       | `mb-proxy`| Shared Docker network name.                  |

## Security headers

The Caddyfile sets the following headers on every response:

- `Strict-Transport-Security` — enforce HTTPS for 1 year, including subdomains.
- `X-Content-Type-Options: nosniff` — prevent MIME-type sniffing.
- `X-Frame-Options: DENY` — prevent clickjacking via framing.
- `Referrer-Policy: strict-origin-when-cross-origin` — limit referrer leakage.

Adjust or extend these in `Caddyfile` to match your application's needs.

## Notes

- Ports `80` and `443` must be open on the host and reachable from the internet
  for Caddy to complete the ACME HTTP-01 / TLS-ALPN challenge.
- Certificate data is persisted in the `caddy-data` and `caddy-config` named
  volumes so renewals survive container recreation.

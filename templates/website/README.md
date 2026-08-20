# Website Template

A single-site reverse proxy using **Caddy v2.9** with automatic HTTPS and
HTTP/3 (QUIC) support.

Caddy terminates TLS (automatic certificates via Let's Encrypt / ZeroSSL) and
forwards all traffic to a single backend application reachable on the shared
`mb-proxy` Docker network. HTTP/3 is enabled via the `protocols h1 h2 h3`
directive and the compose file maps UDP 443 so QUIC traffic reaches Caddy.

## What it does

- Proxies one domain to one backend app.
- Obtains and renews TLS certificates automatically (no manual cert management).
- Serves traffic over HTTP/1.1, HTTP/2, and HTTP/3 (QUIC).
- Actively health-checks the backend and marks it down if it stops responding.
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

## HTTP/3 (QUIC)

Caddy v2.9 enables HTTP/3 via the `protocols h1 h2 h3` global directive. The
compose file maps both TCP and UDP 443. Make sure your firewall allows **UDP
443** inbound — otherwise clients fall back to HTTP/2 transparently.

You can verify HTTP/3 is working with:

```bash
curl -I --http3 https://your-domain.com
```

## Notes

- Ports `80` and `443` (TCP + UDP) must be open on the host and reachable from
  the internet for Caddy to complete the ACME HTTP-01 / TLS-ALPN challenge and
  serve HTTP/3.
- Certificate data is persisted in the `caddy-data` and `caddy-config` named
  volumes so renewals survive container recreation.

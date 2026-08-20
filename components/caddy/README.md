# Caddy Components

Reusable Caddyfile snippets for the network-toolkit, targeting **Caddy v2.9**.
These snippets are meant to be imported into your site-specific Caddyfile
rather than copied, so updates propagate everywhere.

## Files

- `Caddyfile.base` — global options plus two named snippets: `(security_headers)` and `(logging)`. Includes `protocols h1 h2 h3` to enable HTTP/3 (QUIC).
- `Caddyfile.snippets` — common reverse proxy helpers: `(proxy_to)` (with active health check), `(websocket)`, and `(auth)`.

## Usage

Import the base file at the top of your site Caddyfile, then use the snippets by name:

```caddyfile
import /etc/caddy/Caddyfile.base
import /etc/caddy/Caddyfile.snippets

example.com {
    import security_headers
    import logging
    import proxy_to app:8080
}
```

The `(proxy_to)` and `(websocket)` snippets take the upstream address as their first argument, e.g. `import proxy_to caddy:80` or `import websocket app:8080`. The `(auth)` snippet takes a username and a hashed password: `import auth admin '$2a$14$...'`.

## Caddy v2.9 features used

- **`protocols h1 h2 h3`** — explicitly enables HTTP/1.1, HTTP/2, and HTTP/3 (QUIC). HTTP/3 requires UDP port 443 to be mapped in the compose file.
- **Active health checks** — the `(proxy_to)` snippet includes `health_uri`, `health_interval`, and `health_timeout` so Caddy actively probes the backend and marks it down if it stops responding, instead of waiting for a request to fail.

## Security notes

- `admin off` disables the admin API endpoint so it cannot be reached from the network.
- `auto_https disable_redirects` keeps Caddy from issuing HTTP→HTTPS redirects when a front proxy (Cloudflare, frp) already handles them.
- Set `LETSENCRYPT_EMAIL` via environment variable so the address is not committed to the repo.
- Generate basic-auth password hashes with `caddy hash-password`.

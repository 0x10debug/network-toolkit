# Caddy Components

Reusable Caddyfile snippets for the network-toolkit. These snippets are meant to be imported into your site-specific Caddyfile rather than copied, so updates propagate everywhere.

## Files

- `Caddyfile.base` — global options plus two named snippets: `(security_headers)` and `(logging)`.
- `Caddyfile.snippets` — common reverse proxy helpers: `(proxy_to)`, `(websocket)`, and `(auth)`.

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

## Security notes

- `admin off` disables the admin API endpoint so it cannot be reached from the network.
- `auto_https disable_redirects` keeps Caddy from issuing HTTP→HTTPS redirects when a front proxy (Cloudflare, frp) already handles them.
- Set `LETSENCRYPT_EMAIL` via environment variable so the address is not committed to the repo.
- Generate basic-auth password hashes with `caddy hash-password`.

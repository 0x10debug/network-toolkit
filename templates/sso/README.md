# SSO / OIDC Authentication Templates

Single sign-on (SSO) and OpenID Connect (OIDC) authentication templates for
the network-toolkit. These let you put **any** self-hosted service behind a
centralized login — users authenticate once with Google, GitHub, or any OIDC
provider, and every protected app trusts that session. No per-app auth code
required.

Two providers are included:

| Provider | Image (pinned) | Best for |
|---|---|---|
| [OAuth2 Proxy](https://oauth2-proxy.github.io/) | `quay.io/oauth2-proxy/oauth2-proxy:v7.7.0` | Delegating auth to Google / GitHub / external OIDC IdP |
| [Authelia](https://www.authelia.com/) | `authelia/authelia:4.38.10` | Self-hosted users, 2FA, granular access-control rules |

## Contents

- [`oauth2-proxy.yml`](./oauth2-proxy.yml) — OAuth2 Proxy v7.7.0 docker-compose
  - Google / GitHub / OIDC provider (selected via env)
  - Port 4180 bound to `127.0.0.1` (never public)
  - healthcheck, `restart: unless-stopped`, `mb-proxy` network
- [`authelia.yml`](./authelia.yml) — Authelia v4.38.10 docker-compose
  - SQLite (default) or MySQL storage backend
  - Port 9091 bound to `127.0.0.1` (never public)
  - healthcheck, `restart: unless-stopped`, `mb-proxy` network
- [`.env.example`](./.env.example) — all config variables for both providers
- [`traefik-middleware.yml`](./traefik-middleware.yml) — Traefik `forwardAuth`
  middleware snippets for both providers (drop into `dynamic/`)
- [`caddy-handler.yml`](./caddy-handler.yml) — Caddy `forward_auth` Caddyfile
  snippets for both providers

## How It Works

```
  Client ──HTTPS──▶ Reverse Proxy (Caddy/Traefik)
                          │
                          ├── forward_auth ──▶ SSO Provider (oauth2-proxy / authelia)
                          │                        │
                          │                   2xx → OK, inject headers
                          │                   401 → redirect to login
                          │
                          └──▶ Backend App (receives auth headers, no SSO code)
```

The reverse proxy sends a sub-request (`forward_auth`) to the SSO provider
before forwarding the original request to your backend. If the provider
returns 2xx, the request proceeds with auth headers injected (`X-Auth-Request-Email`,
`Remote-User`, etc.). If it returns 401, the user is redirected to the login
page. Your backend app only needs to read the injected headers — it never
deals with OAuth2/OIDC directly.

## OAuth2 Proxy vs Authelia

| | OAuth2 Proxy | Authelia |
|---|---|---|
| User store | External IdP (Google, GitHub, OIDC) | Built-in (file or LDAP) |
| 2FA / MFA | Depends on IdP | Built-in (TOTP, WebAuthn, Duo) |
| Access control | Email domain / group allow-list | Per-route rules, groups, policies |
| Login portal | Provider's (Google/GitHub) | Self-hosted portal |
| Setup complexity | Low (just client ID/secret) | Medium (users_database.yml, configuration.yml) |
| Best for | "Login with Google/GitHub" | Full self-hosted identity, no external IdP |

**Recommendation**: use **OAuth2 Proxy** when you want to delegate
authentication to an external provider (Google, GitHub, or your own OIDC IdP)
and only need email-domain or group-based access control. Use **Authelia**
when you want a fully self-hosted identity provider with local users, 2FA,
and granular per-route access policies — no external IdP dependency.

## Quick Start — OAuth2 Proxy

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env:
#     OAUTH2_PROXY_PROVIDER=google
#     OAUTH2_PROXY_CLIENT_ID=<from Google Cloud Console>
#     OAUTH2_PROXY_CLIENT_SECRET=<from Google Cloud Console>
#     OAUTH2_PROXY_COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)
#     PRIMARY_DOMAIN=example.com

# 3. Create a minimal oauth2-proxy.cfg (or pass all config via env)
cat > oauth2-proxy.cfg <<'CFG'
http_address = "0.0.0.0:4180"
cookie_secure = true
email_domains = ["*"]
upstreams = ["http://127.0.0.1:8080"]
CFG

# 4. Launch
docker compose -f oauth2-proxy.yml up -d

# 5. Wire your reverse proxy (see traefik-middleware.yml or caddy-handler.yml)
```

## Quick Start — Authelia

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env:
#     PRIMARY_DOMAIN=example.com
#     AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)
#     AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)
#     AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)

# 3. Create a minimal configuration.yml and users_database.yml
#    See: https://www.authelia.com/configuration/

# 4. Launch
docker compose -f authelia.yml up -d

# 5. Wire your reverse proxy (see traefik-middleware.yml or caddy-handler.yml)
```

## Protecting Any Service

Once the SSO provider is running and your reverse proxy is wired with
`forward_auth`, protecting a new service is a one-line change — add the SSO
middleware to the router (Traefik) or the `forward_auth` block to the site
(Caddy). The service itself needs no auth code.

### Traefik example

```yaml
# in dynamic/routers.yml
http:
  routers:
    jellyfin:
      rule: "Host(`media.${PRIMARY_DOMAIN}`)"
      entryPoints: [websecure]
      service: jellyfin
      middlewares:
        - sso-oauth2-proxy@file    # ← this line adds SSO
      tls:
        certResolver: letsencrypt
  services:
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://jellyfin:8096"
```

### Caddy example

```caddyfile
media.{$PRIMARY_DOMAIN} {
    forward_auth oauth2-proxy:4180 {
        uri /oauth2/auth
        copy_headers X-Auth-Request-Email X-Auth-Request-User
    }
    reverse_proxy jellyfin:8096
}
```

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PRIMARY_DOMAIN` | yes | — | Domain for redirect URL and cookie scope |
| `OAUTH2_PROXY_PROVIDER` | yes | `google` | `google` / `github` / `oidc` |
| `OAUTH2_PROXY_CLIENT_ID` | yes | — | OAuth2 client ID from your provider |
| `OAUTH2_PROXY_CLIENT_SECRET` | yes | — | OAuth2 client secret |
| `OAUTH2_PROXY_COOKIE_SECRET` | yes | — | 16/24/32-byte base64 secret |
| `OAUTH2_PROXY_EMAIL_DOMAINS` | no | `*` | Restrict to specific email domains |
| `OAUTH2_PROXY_OIDC_ISSUER_URL` | OIDC only | — | OIDC issuer URL |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | Authelia | — | DB encryption key (hex) |
| `AUTHELIA_JWT_SECRET` | Authelia | — | JWT signing secret (hex) |
| `AUTHELIA_SESSION_SECRET` | Authelia | — | Session cookie secret (hex) |
| `MB_PROXY_NETWORK` | no | `mb-proxy` | Shared Docker network name |

## Notes

- Both providers bind to `127.0.0.1` — they are **never** reachable directly
  from the public internet. All traffic must come through the reverse proxy's
  `forward_auth` sub-request over the `mb-proxy` Docker network.
- The `auth.${PRIMARY_DOMAIN}` subdomain hosts the SSO login/callback
  endpoints. Add it as a separate reverse proxy route pointing to the
  provider container.
- OAuth2 Proxy's `cookie_secret` must be exactly 16, 24, or 32 bytes
  (base64-encoded). Generate with `openssl rand -base64 32 | head -c 32`.
- Authelia requires `configuration.yml` and `users_database.yml` — see the
  [Authelia docs](https://www.authelia.com/configuration/) for reference.
  For MySQL storage, uncomment the MySQL env vars and update `configuration.yml`.
- `trustForwardHeader: true` (Traefik) / `trust_forward_header` (Caddy) is
  set so the provider trusts headers from the reverse proxy. Do NOT set this
  if the provider is directly internet-facing.

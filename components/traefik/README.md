# Traefik Components

Reusable Traefik v3.6 configuration snippets for the network-toolkit. These are
reference building blocks you can copy into your own static or dynamic config,
mirroring the role of `components/caddy/`.

## Files

- `traefik.base.yml` — minimal static configuration: three entry points, docker
  + file providers, the `letsencrypt` ACME resolver (TLS-ALPN-01), dashboard
  enabled (insecure off), JSON access logs. Use as the skeleton for a custom
  deployment.
- `dynamic.snippets.yml` — a grab-bag of the most common middlewares and a
  sample router, equivalent to `Caddyfile.snippets`: rate-limit, secure-headers,
  compress, redirect-to-https, basic-auth, ip-whitelist, plus a whoami router.

## Usage

Copy `traefik.base.yml` to your deployment as `traefik.yml`, then layer your own
dynamic config on top by merging the middleware/router blocks you need from
`dynamic.snippets.yml` into your `dynamic/` directory.

```bash
cp components/traefik/traefik.base.yml ./traefik.yml
mkdir -p dynamic
cp components/traefik/dynamic.snippets.yml dynamic/middlewares.yml
# edit traefik.yml: set PRIMARY_DOMAIN + ACME_EMAIL via .env
docker compose up -d
```

## Traefik v3.6 features used

- **Docker provider with `exposedByDefault=false`** — only containers with
  `traefik.enable=true` labels are routed, preventing accidental exposure.
- **File provider with `watch: true`** — dynamic YAML changes are hot-reloaded
  without restarting Traefik.
- **TLS-ALPN-01 challenge** — the recommended ACME challenge when port 443 is
  directly reachable (no front CDN/proxy).
- **`api.insecure=false`** — dashboard is never exposed unauthenticated; route
  it explicitly behind `basic-auth@file`.

## Security notes

- Set `ACME_EMAIL` via environment variable so the address is not committed.
- Replace the placeholder basic-auth hash before enabling the dashboard router.
- Bind the `traefik` entry point (:8080) to `127.0.0.1` in compose if you do
  not route the dashboard through websecure.
- `acme.json` must be `chmod 600`; the named volume in the templates handles
  this, but a bind-mounted file needs manual `chmod 600 acme.json`.

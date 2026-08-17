# Cloudflare Tunnel Template

Expose services on a VPS through a **Cloudflare Tunnel** — no inbound ports
required on the VPS.

`cloudflared` maintains a persistent **outbound** connection to Cloudflare's
edge. Public traffic flows: user → Cloudflare edge → cloudflared tunnel →
Caddy (internal reverse proxy) → backend app. Caddy runs only on the shared
`mb-proxy` Docker network and is **not** published on host ports `80`/`443`.

## Why this is secure

- **No inbound ports needed.** The VPS does not need `80`/`443` (or any port)
  open to the internet. `cloudflared` only makes outbound connections.
- **Cloudflare filters traffic** before it reaches your origin: DDoS
  protection, WAF, bot management, rate limiting.
- **Origin is hidden.** Your VPS's public IP never appears in DNS — the domain
  resolves to Cloudflare.
- **Caddy stays internal.** Caddy is reachable only on the `mb-proxy` network,
  so even if a host port were accidentally exposed, the proxy itself is not
  directly reachable from the internet.

## Architecture

```
  Internet users
       |
       v
  Cloudflare edge  (TLS termination, WAF, DDoS protection)
       |
       v  (outbound tunnel from VPS to Cloudflare)
  +-------------+      +-----------+
  | cloudflared |----->|  Caddy    |  (VPS, no inbound ports)
  +-------------+      |  :80      |  (internal only, mb-proxy)
                       +-----------+
                            |
                            v
                       backend app
                       (mb-proxy network)
```

## Quick start

### 1. Create the tunnel (Cloudflare dashboard or CLI)

Using the dashboard is easiest: Zero Trust → Networks → Tunnels → Create a
tunnel. You'll get a `TUNNEL_ID` and a `TUNNEL_TOKEN`.

Or via CLI:

```bash
cloudflared tunnel login
cloudflared tunnel create my-tunnel
# -> note the TUNNEL_ID and the credentials JSON file path
```

### 2. Configure the VPS

```bash
# Create the shared proxy network (once per host)
docker network create mb-proxy

# Configure
cp .env.example .env
#   edit .env: set TUNNEL_ID, TUNNEL_TOKEN, PRIMARY_DOMAIN
cp cloudflared.example.yml cloudflared.yml

# Place the tunnel credentials file so it is mounted at
# /etc/cloudflared/{$TUNNEL_ID}.json inside the cloudflared container.
# The compose file mounts ./cloudflared-creds to /etc/cloudflared.
mkdir -p cloudflared-creds
cp /path/to/${TUNNEL_ID}.json cloudflared-creds/

# Launch
docker compose up -d
```

### 3. Route the domain in Cloudflare

In the Cloudflare dashboard (or `cloudflared.yml` ingress), point
`PRIMARY_DOMAIN` at the tunnel, with the ingress service set to
`http://caddy:80`. The included `cloudflared.example.yml` already does this.

## Environment variables

| Variable            | Required | Default   | Description                                  |
|---------------------|----------|-----------|----------------------------------------------|
| `TUNNEL_ID`         | yes      | —         | Cloudflare Tunnel UUID.                      |
| `TUNNEL_TOKEN`      | yes      | —         | Tunnel token from the Cloudflare dashboard.  |
| `PRIMARY_DOMAIN`    | yes      | —         | Domain routed through the tunnel to Caddy.   |
| `MB_PROXY_NETWORK`  | no       | `mb-proxy`| Shared Docker network name.                  |

## Notes

- Caddy here does **not** obtain its own TLS certificate — Cloudflare
  terminates TLS at the edge. Caddy serves plain HTTP internally. This is fine
  because traffic between Cloudflare and cloudflared is already encrypted over
  the tunnel.
- If you want Caddy to also serve other internal backends, add site blocks to
  `Caddyfile` and corresponding ingress rules to `cloudflared.yml`.
- The `cloudflared-creds` directory holds the tunnel credentials JSON; keep it
  out of version control (add it to `.gitignore`).

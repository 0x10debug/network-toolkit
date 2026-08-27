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
  Cloudflare edge  (TLS termination, WAF, DDoS protection, Access/Zero Trust)
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

## Files

| File | Purpose |
|---|---|
| `compose.yml` | Caddy + cloudflared on the `mb-proxy` network (no host ports). |
| `cloudflared.example.yml` | Minimal single-hostname ingress config (quick start). |
| `tunnel-config.yml` | Complete ingress config: multi-hostname routing, `originRequest` tuning, warp-routing, SSH-over-tunnel. |
| `zero-trust-access.yml` | Reference for Cloudflare Zero Trust Access policies (email, IP allow list, GitHub/Google SSO). |
| `.env.example` | Environment variables (`TUNNEL_ID`, `TUNNEL_TOKEN`, `PRIMARY_DOMAIN`). |

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

## Full Cloudflare Tunnel deployment (multi-hostname)

For more than one hostname, use `tunnel-config.yml` as your starting point:

```bash
cp tunnel-config.yml cloudflared.yml
# edit cloudflared.yml:
#   - replace {$TUNNEL_ID} and {$PRIMARY_DOMAIN}
#   - adjust per-hostname service targets to match your containers
#   - enable warp-routing only if you use WARP for private-network access
docker compose restart cloudflared
```

`tunnel-config.yml` demonstrates:

- **Multi-hostname ingress** — route `app.`, `api.`, `admin.`, `grafana.`,
  and `ssh.` subdomains to different local services. The first matching rule
  wins; a final `http_status:404` catch-all is required.
- **`originRequest` tuning** — `connectTimeout`, `tlsTimeout`, keep-alive
  pooling, and `http2Origin` for h2c to plain-HTTP origins. Per-rule
  `originRequest` overrides the global block.
- **warp-routing** — lets resources behind a WARP client be reached through
  the tunnel. Disabled by default; enable only for private-network access.
- **SSH over Tunnel** — `ssh://localhost:22` exposes the host SSH through
  Cloudflare; clients use `cloudflared access ssh` to connect.

## Zero Trust Access configuration

Cloudflare Access (Zero Trust) authenticates requests at the edge **before**
they enter the tunnel, so unauthenticated users never reach your origin. It
is configured in the Cloudflare dashboard (Zero Trust → Access → Applications)
or via API / Terraform — not in `cloudflared.yml`.

`zero-trust-access.yml` is a version-controllable reference mirroring the
Access API schema. It shows:

- **Email allow list** — only listed addresses can log in.
- **IP allow list (`bypass`)** — trusted IPs skip the login challenge (CI/CD,
  office NAT, VPN ranges).
- **GitHub SSO** — restrict to an org / team.
- **Google Workspace SSO** — restrict to your domain.
- **Multi-policy combination** — policies evaluate in order; the first match
  wins. Use `requires` (all conditions) instead of `includes` (any) to layer
  conditions (e.g. SSO **and** corporate IP).

### Set up SSO

1. Zero Trust → Settings → Authentication → Add new → GitHub (or Google).
2. Create an OAuth app in GitHub / Google and paste the client ID/secret.
3. Create an Access Application for each protected hostname and attach the
   policies from `zero-trust-access.yml`.

## Integration with Caddy / Traefik

The recommended flow is **Tunnel → local reverse proxy → backend**, not
Tunnel → backend directly. The local reverse proxy (Caddy or Traefik) gives
you:

- Path-based routing and rewrites for multiple backends under one hostname.
- Consistent security headers and compression.
- Active health checks and retries.
- A single ingress hostname in the tunnel even when many backends exist.

### With Caddy (this template)

`cloudflared.example.yml` routes `{$PRIMARY_DOMAIN}` to `http://caddy:80`.
Add Caddyfile site blocks for additional paths/backends; the tunnel only
needs one ingress rule per public hostname.

### With Traefik

If you deployed the `traefik` template instead, point the tunnel at Traefik:

```yaml
ingress:
  - hostname: {$PRIMARY_DOMAIN}
    service: http://traefik:80
  - service: http_status:404
```

Traefik then routes by Docker labels as usual. The tunnel stays the single
public entry point; Traefik handles internal service discovery.

## WAF rule recommendations

Configure these in the Cloudflare dashboard (Security → WAF) for the zone
fronting your tunnel:

1. **Block known bad bots** — use the Cloudflare managed "Bot Fight Mode"
   (free) or Super Bot Fight Mode (Pro+). It challenges or blocks automated
   traffic before it reaches the tunnel.
2. **Custom block rule — block by ASN/country** — if you don't expect traffic
   from certain regions, add a WAF rule: `(ip.geoip.country in {"XX" "YY"})`
   → Block. Useful for admin panels that should only be reachable from your
   country.
3. **Rate limit on login endpoints** — Security → WAF → Rate limiting rules:
   `(http.request.uri.path contains "/login")` → when rate exceeds
   `10 requests per 1 minute per IP` → Block for 10 minutes.
4. **SQLi / XSS managed rules** — enable the Cloudflare managed ruleset
   (OWASP core) on all routes. Review false positives on API endpoints.
5. **Skip WAF for tunnel health checks** — if you run origin monitoring,
   add an exception for your monitoring source IP so WAF doesn't challenge
   health probes.

## Rate limiting configuration

Cloudflare rate limits run at the edge, before traffic enters the tunnel, so
they protect your origin from floods:

- **Dashboard**: Security → WAF → Rate limiting rules.
- **Rule example (API)**: match `(http.host eq "api.example.com")`, count
  requests per IP, threshold `100` per `10 seconds`, action `Block` for
  `60 seconds`.
- **Rule example (login)**: match
  `(http.request.uri.path eq "/login")`, threshold `5` per `1 minute`,
  action `Challenge`.
- For fine-grained per-route limits, combine Cloudflare edge rate limiting
  (coarse, DDoS-scale) with Caddy/Traefik rate-limit middleware (per-route,
  per-user) at the origin.

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
- For edge firewall hardening on the VPS itself (even with no inbound ports,
  you still want SSH protected), see the
  [`edge-firewall`](../edge-firewall/) template.
- If your VPS IP changes, keep Cloudflare DNS updated with the
  [`edge-ddns`](../edge-ddns/) Cloudflare DDNS script.

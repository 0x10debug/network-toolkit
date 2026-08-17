# Full Stack Template

All-in-one networking stack for a VPS: **reverse proxy + automatic SSL +
tunnel server + dynamic DNS**.

This template combines three services on the shared `mb-proxy` network:

- **Caddy** — multi-site reverse proxy with automatic HTTPS (Let's Encrypt /
  ZeroSSL). Serves local backends and routes one subdomain through the frp
  tunnel to a home service.
- **frps** — frp server that accepts a tunnel from an frp client on a home /
  private network, exposing a home service on the VPS without opening any
  inbound port at home.
- **ddns-go** — keeps a DNS record pointed at the VPS's (possibly dynamic)
  public IP, with a web UI on port `9876`.

## Architecture

```
  Internet users
       |
       v  (HTTPS)
  +----------+   +-----------+   +-----------+
  |  Caddy   |   |   frps    |   |  ddns-go  |  (VPS)
  |  :443    |   |  :7000    |   |  :9876    |
  +----------+   +-----------+   +-----------+
       |              ^               |
       |              | frp tunnel    | updates DNS A record
       |              | (outbound)    v
       |       +-----------+    (DNS provider)
       |       |   frpc    |  (home / private network)
       |       +-----------+
       |              |
       v              v
  local backend   home service
  (mb-proxy)      (:8080)
```

## Quick start

### On the VPS

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set PRIMARY_DOMAIN, FRP_TOKEN, DDNS_TOKEN
cp Caddyfile.example Caddyfile
cp frps.toml.example frps.toml
cp ddns-go.example.yaml ddns-go.yaml
#   edit ddns-go.yaml for your DNS provider

# 3. Launch
docker compose up -d

# 4. (Optional) Open the ddns-go web UI to finish DNS setup
#    http://YOUR_VPS_IP:9876
```

### On the home machine (frp client)

Create an `frpc.toml`:

```toml
serverAddr = "YOUR_VPS_PUBLIC_IP"
serverPort = 7000
auth.token = "SAME_FRP_TOKEN_AS_VPS"

[[proxies]]
name = "home-service"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8080        # the home service port
remotePort = 8080       # port Caddy forwards to on the VPS
```

Run frpc on the home machine.

## Environment variables

| Variable            | Required | Default   | Description                                  |
|---------------------|----------|-----------|----------------------------------------------|
| `PRIMARY_DOMAIN`    | yes      | —         | Base domain for Caddy + ddns-go.             |
| `FRP_TOKEN`         | yes      | —         | Shared frp auth secret.                      |
| `DDNS_TOKEN`        | yes      | —         | DNS provider API token for ddns-go.          |
| `MB_PROXY_NETWORK`  | no       | `mb-proxy`| Shared Docker network name.                  |

## Ports

| Port  | Service  | Purpose                                  |
|-------|----------|------------------------------------------|
| 80    | Caddy    | HTTP (redirects to HTTPS, ACME challenge)|
| 443   | Caddy    | HTTPS public entry point.                |
| 7000  | frps     | frp protocol (frpc connects here).       |
| 9876  | ddns-go  | Web UI for DDNS configuration.           |

## Security

- `FRP_TOKEN` and `DDNS_TOKEN` are secrets — keep them out of version control
  (`.env` is git-ignored).
- Caddy applies HSTS, nosniff, frame-deny, and referrer-policy headers.
- Restrict access to the ddns-go web UI (port `9876`) — e.g. via firewall rules
  or by not exposing it publicly and accessing it over SSH tunneling.

## Notes

- The frp client at home must use the same `auth.token` and `remotePort`.
- ddns-go config file format depends on your DNS provider — see the
  [ddns-go docs](https://github.com/jeessy/ddns-go).
- Certificate data persists in the `caddy-data` / `caddy-config` volumes.

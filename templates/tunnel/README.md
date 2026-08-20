# Tunnel Template

Expose a home/private-network service to the public internet with a real TLS
certificate, without opening any inbound port on the home network.

**Caddy v2.9** runs on the VPS and handles SSL for the public domain, with
HTTP/3 (QUIC) support. **frp server** (frps) runs on the VPS and accepts a
tunnel from an **frp client** (frpc) running on the home network. Caddy
forwards public traffic through the tunnel to the home service.

## Architecture

```
  Internet users
       |
       v  (HTTPS)
  +----------+      +-----------+
  |  Caddy   |----->|   frps    |  (VPS, public IP)
  |  :443    |      |  :7000    |
  +----------+      +-----------+
                          ^  frp tunnel (outbound from home)
                          |
                  +-----------+
                  |   frpc    |  (home / private network)
                  +-----------+
                          |
                          v
                    home service (:8080)
```

- The home network only makes an **outbound** connection to the VPS on port
  `7000`. No inbound port needs to be opened on the home router.
- The VPS needs ports `80`/`443` (Caddy) and `7000` (frps) open to the internet.

## Quick start

### On the VPS

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set TUNNEL_DOMAIN, TUNNEL_LOCAL_PORT, FRP_TOKEN
cp Caddyfile.example Caddyfile
cp frps.toml.example frps.toml
#   frps.toml already reads FRP_TOKEN from the environment

# 3. Launch
docker compose up -d
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
remotePort = 8080       # must equal TUNNEL_LOCAL_PORT on the VPS
```

Run frpc (binary or container) on the home machine. It will connect outbound to
the VPS and expose the home service on `remotePort`, which Caddy then proxies
to.

## Environment variables

| Variable            | Required | Default   | Description                                  |
|---------------------|----------|-----------|----------------------------------------------|
| `TUNNEL_DOMAIN`     | yes      | —         | Public domain Caddy gets a certificate for.  |
| `TUNNEL_LOCAL_PORT` | no       | `8080`    | Port on the VPS frps exposes from the tunnel.|
| `FRP_TOKEN`         | yes      | —         | Shared frp auth secret (use a long string).  |
| `MB_PROXY_NETWORK`  | no       | `mb-proxy`| Shared Docker network name.                  |

## Security

- `FRP_TOKEN` is the only thing protecting the tunnel. Use a long, random
  secret and keep it out of version control (`.env` is git-ignored).
- Caddy applies the standard security headers (HSTS, nosniff, DENY framing,
  referrer policy) to all responses.
- Consider restricting frps `bindPort` access to known home IPs if possible.

## Notes

- The frp client at home must use the **same** `auth.token` and `remotePort` as
  configured here.
- `TUNNEL_LOCAL_PORT` on the VPS must match the frpc `remotePort`.
- Ports `80` and `443` (TCP + UDP) must be open on the host. Allow **UDP 443**
  inbound for HTTP/3 (QUIC).
- Certificate data persists in the `caddy-data` / `caddy-config` volumes.

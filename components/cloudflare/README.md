# Cloudflare Components

Configuration for [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) (`cloudflared`). A Cloudflare Tunnel creates an outbound-only connection from your server to Cloudflare's edge, so you do not need to open any inbound ports on your VPS or home network.

## Why use a tunnel

- **No inbound ports** — the `cloudflared` daemon dials out to Cloudflare; no firewall rules are needed for incoming traffic.
- **No public IP required** — works behind NAT, so it is suitable for home servers as well as VPS instances.
- **Cloudflare handles TLS** — traffic between the visitor and Cloudflare's edge is encrypted; the leg from the edge to your origin can be plain HTTP on a private network.

## Creating a tunnel

1. In the Cloudflare dashboard, go to **Zero Trust → Networks → Tunnels → Create a tunnel**.
2. Choose **Cloudflared** as the connector type and name the tunnel.
3. Copy the tunnel ID shown after creation.
4. Download the credentials JSON file generated for the tunnel.

## Where to put the credentials file

Place the credentials file at the path referenced by `credentials-file` in the config. The example uses `/etc/cloudflared/YOUR_TUNNEL_ID.json`. Rename the downloaded file to match your tunnel ID and restrict its permissions:

```bash
sudo install -m 600 -o root -g root YOUR_TUNNEL_ID.json /etc/cloudflared/YOUR_TUNNEL_ID.json
```

If you run `cloudflared` in Docker, mount the file read-only into the container at the same path.

## Ingress rules

The `ingress` list maps public hostnames to internal services, evaluated top to bottom:

- Each `hostname` entry routes requests for that domain to the specified `service`.
- The example routes everything to Caddy (`http://caddy:80`), which then does its own routing to individual apps via the `(proxy_to)` snippet.
- The **last** rule must be a catch-all with no `hostname`. `service: http_status:404` returns 404 for any unmatched host so requests to unknown subdomains do not leak to a default backend.

## Running

Install `cloudflared` (package manager or the binary from the Cloudflare docs), point it at this config with `cloudflared tunnel run --config cloudflared.yml`, and run it under systemd or as a Docker container. DNS records for each `hostname` are created automatically when the tunnel is managed via the dashboard; for remotely managed tunnels add CNAME records pointing to `<tunnel-id>.cfargotunnel.com`.

## Security notes

- Keep the credentials JSON file private — anyone with it can run a connector for your tunnel.
- Prefer routing through Caddy so you still get the `(security_headers)` and access control from the Caddy component, rather than exposing services directly.
- Set `loglevel: info` (or `warn` in production) to avoid logging request bodies.

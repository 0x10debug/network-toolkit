# HTTP/3 (QUIC) Example

A focused example showing how to enable **HTTP/3 (QUIC)** with **Caddy v2.9**.

HTTP/3 is the third major version of HTTP, running over QUIC (which itself runs
over UDP). It offers faster connection setup, multiplexing without head-of-line
blocking, and better performance on unreliable networks compared to HTTP/2.

## What makes HTTP/3 work

Three things are required for HTTP/3 to function:

1. **`protocols h1 h2 h3` in the Caddyfile** — tells Caddy to serve HTTP/1.1,
   HTTP/2, and HTTP/3. Caddy v2.9 enables HTTP/3 by default when UDP 443 is
   available, but setting it explicitly makes the intent clear.

2. **UDP 443 mapped in the compose file** — the `ports` section includes both
   `"443:443"` (TCP) and `"443:443/udp"` (UDP). Without the UDP mapping, QUIC
   packets never reach Caddy.

3. **Firewall allows inbound UDP 443** — many default firewall configurations
   only allow TCP 80/443. You must explicitly allow UDP 443.

```bash
# UFW example
sudo ufw allow 443/udp

# iptables example
sudo iptables -A INPUT -p udp --dport 443 -j ACCEPT
```

## Quick start

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set PRIMARY_DOMAIN, APP_HOST, APP_PORT
cp Caddyfile.example Caddyfile

# 3. Allow UDP 443 through your firewall (see above)

# 4. Launch
docker compose up -d
```

## Verifying HTTP/3

### Check the alt-svc header

Caddy advertises HTTP/3 support via the `alt-svc` response header. Any HTTP
response (including HTTP/2) will include it:

```bash
curl -I https://your-domain.com
# Look for: alt-svc: h3=":443"; ma=2592000
```

### Make an actual HTTP/3 request

```bash
# Requires curl built with HTTP/3 support (quiche/ngtcp2)
curl -I --http3 https://your-domain.com
```

### Browser check

In Chrome/Edge, open DevTools → Network tab, right-click a column header and
enable the "Protocol" column. You should see "h3" for requests using HTTP/3.

## How it works

```
  Client (browser/curl)
       |
       +-- TCP 443 ---> Caddy --- HTTP/1.1 or HTTP/2 ---> backend
       |
       +-- UDP 443 ---> Caddy --- HTTP/3 (QUIC) -------> backend
```

Caddy listens on both TCP and UDP 443 simultaneously. Clients that support
HTTP/3 will upgrade to QUIC after seeing the `alt-svc` header; clients that
don't will continue using HTTP/2 over TCP. The fallback is automatic and
requires no extra configuration.

## Environment variables

| Variable           | Required | Default   | Description                          |
|--------------------|----------|-----------|--------------------------------------|
| `PRIMARY_DOMAIN`   | yes      | —         | Domain Caddy gets a certificate for. |
| `APP_HOST`         | yes      | —         | Backend container hostname.          |
| `APP_PORT`         | no       | `8080`    | Backend container port.              |
| `MB_PROXY_NETWORK` | no       | `mb-proxy`| Shared Docker network name.          |

## Notes

- If UDP 443 is blocked by a firewall or cloud provider, Caddy transparently
  falls back to HTTP/2. No errors are raised — clients simply use TCP.
- HTTP/3 requires TLS. Caddy handles this automatically via its built-in
  automatic HTTPS (Let's Encrypt / ZeroSSL).
- The `protocols` directive also accepts subsets, e.g. `protocols h1 h2` to
  disable HTTP/3, or `protocols h3` to serve HTTP/3 only.

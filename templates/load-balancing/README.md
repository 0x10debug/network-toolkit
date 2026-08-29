# Load Balancing Templates

Load balancer templates for the network-toolkit. Distribute traffic across
multiple backend instances for high availability, horizontal scaling, and
zero-downtime deployments. Three solutions are included — HAProxy, Nginx,
and Traefik — covering both dedicated L4/L7 load balancers and Docker-native
service discovery.

| Solution | Image (pinned) | Type | Best for |
|---|---|---|---|
| [HAProxy](https://www.haproxy.org/) | `haproxy:3.1.0` | Dedicated L4/L7 LB | High-performance, TCP + HTTP, SSL termination + SNI passthrough |
| [Nginx](https://nginx.org/) | `nginx:1.27.2` | L7 LB (reverse proxy) | Lightweight HTTP LB, already familiar to most ops |
| [Traefik](https://traefik.io/) | (existing `traefik:v3.6.0`) | Docker-native LB | Label-based auto-discovery, WRR, no separate container |

## Contents

- [`haproxy.yml`](./haproxy.yml) — HAProxy 3.1.0 docker-compose
  - Ports 80/443 on `0.0.0.0`, stats 9999 on `127.0.0.1`
  - healthcheck, `restart: unless-stopped`, `mb-proxy` network
- [`haproxy.cfg`](./haproxy.cfg) — HAProxy configuration
  - HTTP/HTTPS frontends, SSL termination + SNI passthrough alternative
  - Backend pools: roundrobin + leastconn, active health checks, backup server
  - Stats page with Prometheus metrics export
- [`nginx-upstream.yml`](./nginx-upstream.yml) — Nginx 1.27.2 docker-compose
  - Ports 80/443 on `0.0.0.0`, healthcheck, `mb-proxy` network
- [`nginx-upstream.conf`](./nginx-upstream.conf) — Nginx upstream config
  - Three methods: `round_robin`, `ip_hash`, `least_conn`
  - Health checks via `max_fails`/`fail_timeout`, failover with `backup`
  - SSL termination example (commented)
- [`traefik-lb.yml`](./traefik-lb.yml) — Traefik v3.6 WRR load balancing
  - Weighted round robin (WRR) with explicit weights
  - Active health checks, backup server (weight 0 = failover)
  - Docker label equivalent documented
- [`README.md`](./README.md) — this file

## HAProxy vs Nginx vs Traefik

| | HAProxy | Nginx | Traefik |
|---|---|---|---|
| Layer | L4 (TCP) + L7 (HTTP) | L7 (HTTP) | L7 (HTTP) |
| Performance | Highest (event-driven, C) | High | Good |
| SSL termination | Yes | Yes | Yes (via ACME) |
| SNI passthrough | Yes (mode tcp) | Yes (stream) | No |
| Service discovery | Manual (server lines) | Manual (upstream) | Docker labels (auto) |
| Health checks | Active (httpchk) | Passive (max_fails) | Active (healthCheck) |
| Session persistence | Cookie-based, source IP | ip_hash, sticky cookie | WRR, sticky cookie |
| Stats / metrics | Built-in stats page | Requires module/stub | Built-in dashboard |
| Config reload | Hot reload (seamless) | `nginx -s reload` | Hot-reload (dynamic) |
| Best for | High-throughput, TCP+HTTP | Simple HTTP LB | Docker-native, many services |

**Recommendation**: use **HAProxy** when you need maximum performance, TCP-level
load balancing, or SNI passthrough without SSL termination. Use **Nginx** for
a lightweight HTTP-only load balancer when you're already familiar with Nginx
config syntax. Use **Traefik** when your backends are Docker containers and
you want automatic service discovery via labels — no manual server list to
maintain.

## Quick Start — HAProxy

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Configure
cp .env.example .env
#   edit .env: set backend hostnames, stats password

# 3. Place your TLS cert (PEM: cert + key concatenated) in ./certs/server.pem
cat certs/server.crt certs/server.key > certs/server.pem

# 4. Edit haproxy.cfg — replace api1/api2/web1/web2 with your backend hostnames

# 5. Launch
docker compose -f haproxy.yml up -d

# 6. View stats
# SSH tunnel: ssh -L 9999:127.0.0.1:9999 user@vps
# Then open: http://127.0.0.1:9999/stats
```

## Quick Start — Nginx

```bash
# 1. Create the shared proxy network (once per host)
docker network create mb-proxy

# 2. Edit nginx-upstream.conf — replace api1/api2/web1/web2 with your backends

# 3. Launch
docker compose -f nginx-upstream.yml up -d
```

## Quick Start — Traefik

Traefik's load balancer is built into the existing `traefik:v3.6.0` deployment
(see [`templates/traefik/`](../traefik/)). No separate container needed:

```bash
# 1. Copy traefik-lb.yml into your Traefik dynamic config directory
cp traefik-lb.yml /data/traefik/dynamic/traefik-lb.yml

# 2. Traefik hot-reloads it automatically — no restart needed

# 3. Or use Docker labels on your backend containers (see traefik-lb.yml comments)
```

## Load Balancing Methods

### Round Robin (default)
Distributes requests evenly across all servers in order. Simple and
effective when all backends have similar capacity and request processing
times.

- **HAProxy**: `balance roundrobin`
- **Nginx**: (default, no directive needed)
- **Traefik**: (default for `loadBalancer`)

### Least Connections
Sends each request to the server with the fewest active connections. Better
than round robin when requests have varying processing times.

- **HAProxy**: `balance leastconn`
- **Nginx**: `least_conn;`
- **Traefik**: not built-in (use WRR as approximation)

### IP Hash (session persistence)
Same client IP always routes to the same server. Provides sticky sessions
without cookies. Use when backends store session state locally.

- **HAProxy**: `balance source` (or `balance hdr(User-Agent)`)
- **Nginx**: `ip_hash;`
- **Traefik**: `loadBalancer.sticky.cookie`

### Weighted Round Robin (WRR)
Distributes traffic with explicit weights — a server with weight 3 gets 3x
the traffic of a server with weight 1. Use when backends have different
capacities.

- **HAProxy**: `server api1 ... weight 3`
- **Nginx**: `server api1 ... weight=3;`
- **Traefik**: `weighted: { services: [{ name: ..., weight: 3 }] }`

## Health Checks

### Active health checks
The load balancer periodically sends a probe request to each backend. If the
probe fails, the backend is marked down and traffic is rerouted.

- **HAProxy**: `option httpchk GET /health` + `http-check expect status 200`
- **Nginx**: not built-in (open-source) — use passive checks or a module
- **Traefik**: `healthCheck: { path: /health, interval: 10s }`

### Passive health checks
The LB monitors real requests — if a request to a backend fails (timeout,
5xx), the LB marks it down temporarily and retries on another server.

- **HAProxy**: `default-server inter 3s fall 3 rise 2`
- **Nginx**: `max_fails=3 fail_timeout=30s` + `proxy_next_upstream`
- **Traefik**: automatic (retries via `retry` middleware)

## Session Persistence

| Method | HAProxy | Nginx | Traefik |
|---|---|---|---|
| Source IP | `balance source` | `ip_hash;` | — |
| Cookie-based | `cookie SRV_ID insert` | `sticky cookie` | `sticky.cookie` |
| Header-based | `balance hdr(X-Header)` | `hash $http_x_header` | — |

## SSL Offloading (Termination)

The load balancer terminates TLS (decrypts HTTPS) and forwards plain HTTP to
backends. This centralizes certificate management and offloads crypto from
backends.

- **HAProxy**: `bind *:443 ssl crt /certs/server.pem` (see haproxy.cfg)
- **Nginx**: `listen 443 ssl; ssl_certificate ...` (see nginx-upstream.conf)
- **Traefik**: automatic via ACME certResolver (no manual cert needed)

For **SNI passthrough** (no termination, backends handle their own TLS):
- **HAProxy**: `mode tcp` + `tcp-request inspect-delay` (see haproxy.cfg)
- **Nginx**: `stream` module with `ssl_preread`
- **Traefik**: not supported (Traefik always terminates TLS)

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `MB_PROXY_NETWORK` | no | `mb-proxy` | Shared Docker network name |
| `STATS_USER` | HAProxy | `admin` | HAProxy stats page username |
| `STATS_PASSWORD` | HAProxy | `changeme` | HAProxy stats page password |

## Notes

- HAProxy's stats page is bound to `127.0.0.1:9999` — access via SSH tunnel
  (`ssh -L 9999:127.0.0.1:9999 user@vps`) or put it behind your existing
  reverse proxy with SSO/mTLS.
- For SSL termination, HAProxy expects a single PEM file with the cert and
  key concatenated: `cat server.crt server.key > server.pem`.
- Nginx's open-source version lacks active health checks (only passive
  `max_fails`/`fail_timeout`). For active checks, use HAProxy or Traefik,
  or the commercial Nginx Plus.
- Traefik's WRR with `weight: 0` creates a backup/failover server — it only
  receives traffic when all weighted servers are down.
- All three solutions join the `mb-proxy` network so they can reach backend
  containers by name. Backends should NOT publish ports to the host — the
  load balancer reaches them via the internal Docker network.

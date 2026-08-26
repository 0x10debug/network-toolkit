# Docker Socket-Proxy Template

A hardened [Docker socket-proxy](https://github.com/Tecnativa/docker-socket-proxy)
template for the network-toolkit. It lets other containers talk to the Docker
API **without** handing them the raw `/var/run/docker.sock` — which is
equivalent to root on the host.

## Why You Need This

> **The Docker socket is root access.** Any container that can read
> `/var/run/docker.sock` can start a privileged container, mount the host
> filesystem, read every secret, and pivot to full host compromise. Never
> bind-mount the raw socket into an untrusted or internet-facing container.

A socket-proxy sits in front of the socket and re-exposes the Docker API on
`:2375`, but with an **allowlist**: every endpoint is denied by default, and
you flip on only the ones a consumer needs. Combined with an **internal**
Docker network (no published ports), only containers you explicitly attach to
that network can reach the filtered API.

## Contents

- [`compose.yml`](./compose.yml) — `tecnativa/docker-socket-proxy:0.1.5`
  (pinned), `/var/run/docker.sock` mounted read-only, healthcheck,
  `restart: unless-stopped`, attached to an internal network with no
  published ports
- [`.env.example`](./.env.example) — per-endpoint allowlist switches
  (`CONTAINERS`, `POST`, `IMAGES`, …), all defaulting to `0`

## Security Model

1. **Docker socket = root.** Mounting `/var/run/docker.sock` into a container
   gives it unrestricted control of the Docker daemon and, through it, the
   host.
2. **Proxy, not passthrough.** `docker-socket-proxy` terminates the Docker
   API on `:2375` and forwards only allowlisted endpoints to the real socket.
   Anything not explicitly enabled returns `403`.
3. **Default-deny.** Every endpoint switch defaults to `0` in `.env.example`.
   `CONTAINERS=1` allows listing/inspecting containers (read-only). `POST=0`
   blocks create/kill/exec/restart even when `CONTAINERS=1` is set — so a
   monitoring agent can observe without being able to mutate.
4. **Internal network.** The proxy publishes no ports to the host. It lives on
   an `--internal` Docker network, so only containers attached to that same
   network can dial `http://socket-proxy:2375`. The public internet and other
   Docker networks cannot reach it.
5. **Read-only socket mount.** The host socket is mounted `:ro` so the proxy
   itself cannot be tricked into writing to it; filtering happens at the HTTP
   layer.

## Quick Start

```bash
# 1. Create the internal proxy network (once per host)
docker network create --internal mb-socket-proxy

# 2. Configure the allowlist
cp .env.example .env
#   edit .env: enable only the endpoints your consumer needs

# 3. Launch the proxy
docker compose up -d

# 4. Verify it is filtering (from a container on the same network)
docker run --rm --network mb-socket-proxy curlimages/curl \
  http://socket-proxy:2375/containers/json        # 200 if CONTAINERS=1
docker run --rm --network mb-socket-proxy curlimages/curl \
  -X POST http://socket-proxy:2375/containers/create  # 403 if POST=0
```

## Endpoint Reference

| Switch | Endpoint group | Default | Notes |
|---|---|---|---|
| `CONTAINERS` | `/containers/*` | `1` | List/inspect. Create/kill needs `POST=1` |
| `POST` | write verbs | `0` | Master switch for POST/PUT/DELETE |
| `EXEC` | `/exec/*` | `0` | Run commands inside containers — dangerous |
| `IMAGES` | `/images/*` | `0` | List/pull/build images |
| `INFO` | `/info` | `0` | Daemon info |
| `NETWORKS` | `/networks/*` | `0` | List/inspect networks |
| `NODES` | `/nodes/*` | `0` | Swarm nodes |
| `PLUGINS` | `/plugins/*` | `0` | Plugin management |
| `SERVICES` | `/services/*` | `0` | Swarm services |
| `SESSION` | `/session` | `0` | Interactive attach sessions |
| `SWARM` | `/swarm/*` | `0` | Swarm management |
| `SYSTEM` | `/system/*` | `0` | `df`, `events`, `version` |
| `TASKS` | `/tasks/*` | `0` | Swarm tasks |
| `VOLUMES` | `/volumes/*` | `0` | List/inspect volumes |
| `BUILD` | `/build` | `0` | Build images (write) |
| `COMMIT` | `/commit` | `0` | Commit container to image (write) |
| `CONFIGS` | `/configs/*` | `0` | Swarm configs (write) |
| `DISTRIBUTION` | `/distribution/*` | `0` | Image distribution info |
| `EVENTS` | `/events` | `0` | Stream daemon events |
| `SECRETS` | `/secrets/*` | `0` | Swarm secrets (write) |

**Principle**: start with everything `0`, enable the minimum a consumer needs,
and keep `POST=0` unless that consumer must change Docker state.

## Integrating With Other Templates

Reverse proxies and monitoring tools often want Docker visibility. Instead of
giving them the raw socket, attach them to `mb-socket-proxy` and point them at
the filtered endpoint.

### Traefik (read-only container discovery)

Traefik only needs to *list* containers to read their labels — it never needs
to create or kill them. Enable `CONTAINERS=1` (default) and keep `POST=0`.

```yaml
# in your traefik compose.yml
services:
  traefik:
    # ... existing traefik config ...
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
    # remove the /var/run/docker.sock volume mount
    networks:
      - mb-proxy
      - mb-socket-proxy
networks:
  mb-proxy:
    external: true
  mb-socket-proxy:
    external: true
```

With this, Traefik discovers labeled containers through the filtered proxy and
can no longer mutate Docker state even if compromised.

### Monitoring (e.g. monitor-stack)

A metrics agent that scrapes container stats needs `CONTAINERS=1` plus
`SYSTEM=1` (for `/system/df`) or `INFO=1` (for `/info`). Keep `POST=0`.

```yaml
services:
  monitor-agent:
    environment:
      DOCKER_HOST: tcp://socket-proxy:2375
    networks: [mb-socket-proxy]
networks:
  mb-socket-proxy:
    external: true
```

### Anything that must mutate Docker

If a tool genuinely needs to start/stop containers (e.g. a CI runner),
enable `POST=1` **and** the specific endpoint group it uses. Audit the
resulting surface — `POST=1` + `CONTAINERS=1` lets a caller create, kill, and
exec into arbitrary containers, which is close to raw socket access. Prefer
narrower endpoints where possible.

## Notes

- The proxy image is pinned to `0.1.5`. Bump deliberately and re-audit the
  changelog — newer versions may add or rename endpoint switches.
- The healthcheck hits `/version` over the filtered API. If you disable
  `SYSTEM`/`INFO` and the proxy returns 403 for that path, the healthcheck
  will report unhealthy; either keep a read-only info endpoint enabled or
  adjust the healthcheck `test` to a path you allow.
- `--internal` on the network prevents outbound traffic from the proxy network
  too. If a consumer on that network also needs internet egress, create a
  second non-internal network for that consumer and leave `mb-socket-proxy`
  internal.
- This template does not publish any ports. Do not add a `ports:` mapping —
  that would defeat the entire purpose by exposing the filtered API to the
  host (and potentially the internet).

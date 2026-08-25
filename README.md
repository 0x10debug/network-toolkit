# VPS Network Toolkit — Reverse Proxy, SSL & Tunnel in One Command

Expose your self-hosted apps to the internet with a secure reverse proxy, automatic SSL certificates, and NAT traversal—all configured in one command. Built for VPS and Docker, this toolkit combines Caddy, frp, and DDNS into ready-to-deploy templates. No more piecing together separate tools for reverse proxy, Let's Encrypt, and tunnel setup. Choose a template, enter your domain, and your services are live with HTTPS.

> **Just hardened your VPS?** Deploy the `website` template first — it gives you a reverse proxy with automatic SSL. Then deploy your apps with [compose-recipes](https://github.com/0x10debug/compose-recipes) and route them through the proxy.

## Why This Exists

After deploying apps on your VPS, you need to expose them to the internet. This means:

1. **Reverse proxy** — route domain names to the right containers
2. **SSL certificates** — HTTPS, not HTTP, for security and trust
3. **NAT traversal** — expose home services through your VPS
4. **Dynamic DNS** — keep DNS updated if your IP changes

Each of these is a separate tool (Caddy, acme.sh, frp, ddns-go). Configuring them individually is complex and error-prone. This toolkit combines them into pre-configured templates — pick one, fill in your domain, done.

## Features

- **Automatic HTTPS** — Caddy obtains and renews Let's Encrypt certificates with zero configuration
- **Security headers** — HSTS, X-Content-Type-Options, X-Frame-Options injected automatically
- **NAT traversal** — frp tunnel server for exposing home services through your VPS
- **Dynamic DNS** — ddns-go integration for Cloudflare, Aliyun, Tencent, and more
- **Cloudflare Tunnel** — alternative mode that requires zero inbound ports on your VPS
- **Port audit** — scan all exposed ports and identify security risks
- **Docker network integration** — all apps share the `mb-proxy` network for seamless routing

## Templates

| Template | Components | Use Case |
|---|---|---|
| [website](templates/website/) | Caddy + SSL | Expose a single site with HTTPS |
| [multi-site](templates/multi-site/) | Caddy + SSL | Expose multiple sites with one Caddy instance |
| [tunnel](templates/tunnel/) | Caddy + frp | Expose home services through your VPS |
| [full-stack](templates/full-stack/) | Caddy + frp + DDNS | Everything: proxy, SSL, tunnel, and DDNS |
| [cloudflare](templates/cloudflare/) | Caddy + Cloudflare Tunnel | Zero inbound ports — all traffic via Cloudflare |
| [traefik](templates/traefik/) | Traefik v3.6 + SSL | Docker-native reverse proxy with dashboard and middleware library |

## Quick Start

```bash
# 1. Harden your VPS and install Docker (if not done)
# → https://github.com/0x10debug/vps-bootstrap

# 2. Clone this repo
git clone https://github.com/0x10debug/network-toolkit.git
cd network-toolkit

# 3. List available templates
./mb net list

# 4. Deploy a reverse proxy with automatic SSL
./mb net deploy website

# 5. Add routes for your apps
./mb net proxy add app.example.com app-container:8080

# 6. Check status
./mb net status
```

## Usage

```bash
mb net list                              # List available templates
mb net deploy <template>                 # Deploy a network template
mb net status                            # Show infrastructure status
mb net proxy add <domain> <target>       # Add reverse proxy route
mb net proxy remove <domain>             # Remove reverse proxy route
mb net tunnel add <name>                 # Add tunnel configuration
mb net tunnel status                     # Show tunnel status
mb net ssl list                          # List SSL certificates
mb net ssl renew                         # Force certificate renewal
mb net audit                             # Audit port exposure
mb net update                            # Update network components
mb net help                              # Show help
```

## FAQ

### How to set up reverse proxy on VPS with Docker?

Deploy the `website` template: `mb net deploy website`. Enter your domain and the target container. Caddy starts, obtains an SSL certificate from Let's Encrypt automatically, and routes traffic to your app. Add more routes with `mb net proxy add <domain> <target>`.

### How to get free SSL certificate for self-hosted apps?

Caddy includes automatic Let's Encrypt integration — no manual certificate management needed. When you deploy any template, Caddy obtains certificates for your domains automatically. Check certificate status with `mb net ssl list`.

### How to expose local services to internet via VPS?

Deploy the `tunnel` template on your VPS: `mb net deploy tunnel`. This starts an frp server. Then install the frp client on your home machine, configure it to connect to your VPS, and your home services are accessible via your VPS domain with HTTPS.

### How to set up Cloudflare Tunnel for self-hosted apps?

Deploy the `cloudflare` template: `mb net deploy cloudflare`. This runs `cloudflared` on your VPS, creating an outbound tunnel to Cloudflare's edge. No inbound ports need to be open on your VPS — all traffic flows through Cloudflare. Configure ingress rules in the cloudflared config file.

### How to configure Caddy reverse proxy for multiple sites?

Deploy the `multi-site` template: `mb net deploy multi-site`. The Caddyfile includes multiple domain blocks. Add new domains with `mb net proxy add <domain> <target>`, or edit the Caddyfile directly for complex configurations.

## Documentation

- [Reverse Proxy Guide](docs/reverse-proxy-guide.md) — How to expose apps with HTTPS
- [Tunnel Setup](docs/tunnel-setup.md) — NAT traversal with frp
- [SSL Management](docs/ssl-management.md) — Certificate management and troubleshooting
- [DDNS Setup](docs/ddns-setup.md) — Dynamic DNS configuration
- [Security Checklist](docs/security-checklist.md) — Network exposure security audit

## Components

Reusable configuration snippets for advanced users:

- [Caddy](components/caddy/) — Base Caddyfile and security header snippets
- [Traefik](components/traefik/) — Base static config and middleware snippets (Traefik v3.6)
- [frp](components/frp/) — Server and client configuration templates
- [DDNS](components/ddns/) — ddns-go configuration for multiple DNS providers
- [Cloudflare](components/cloudflare/) — Cloudflare Tunnel ingress configuration

## Related

- [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — One-command VPS initialization and security hardening
- [compose-recipes](https://github.com/0x10debug/compose-recipes) — Self-hosted app suites for VPS
- [monitor-stack](https://github.com/0x10debug/monitor-stack) — Lightweight monitoring stack
- [security-audit](https://github.com/0x10debug/security-audit) — VPS security auditing tool

## License

[MIT](./LICENSE)

# SSL Certificate Management

How SSL certificates work in this toolkit and how to manage them.

## Automatic SSL with Caddy

Caddy handles SSL certificates automatically — you don't need to manually obtain or renew certificates.

### How It Works

1. When a request comes in for `app.example.com`, Caddy checks if it has a certificate
2. If not, Caddy contacts Let's Encrypt and obtains a certificate via the HTTP-01 challenge
3. Caddy stores the certificate in `/data/caddy/data/caddy/certificates/`
4. Caddy automatically renews certificates before they expire (Let's Encrypt certificates are valid for 90 days)

### Prerequisites

- **Ports 80 and 443 must be open** — Let's Encrypt needs to reach port 80 for the HTTP-01 challenge
- **DNS must point to your VPS** — the domain in the Caddyfile must resolve to your VPS IP
- **Firewall must allow inbound on 80/443** — check with `mb net audit`

## Checking Certificates

```bash
mb net ssl list
```

Output:
```
  app.example.com    expires: Sep 15 12:00:00 2026 UTC    days left: 30
  media.example.com  expires: Oct 02 08:30:00 2026 UTC    days left: 47
```

## Forcing Renewal

```bash
mb net ssl renew
```

This restarts Caddy, which triggers a certificate check. Certificates close to expiry will be renewed.

## Using Your Own Certificates

If you have existing certificates (e.g., from acme.sh or certbot), you can use them with Caddy:

```caddyfile
app.example.com {
    tls /path/to/cert.pem /path/to/key.pem
    reverse_proxy app:8080
}
```

## Wildcard Certificates

Wildcard certificates require DNS-01 challenge, which needs a DNS provider API token:

```caddyfile
*.example.com {
    tls {
        dns cloudflare {$CLOUDFLARE_API_TOKEN}
    }
    reverse_proxy app:8080
}
```

Supported DNS providers: Cloudflare, DigitalOcean, Route53, Aliyun, and more. See [Caddy DNS providers](https://github.com/caddy-dns).

## Cloudflare Tunnel (Alternative SSL)

If you use the [Cloudflare template](../templates/cloudflare/), SSL is handled by Cloudflare — no certificates are stored on your VPS. This is useful if:

- You don't want to open ports 80/443 on your VPS
- You're behind a firewall that blocks inbound traffic
- You want Cloudflare's edge caching and DDoS protection

## Troubleshooting

### Certificate not obtained
- Check ports 80/443 are open: `mb net audit`
- Check DNS: `dig app.example.com +short` should return your VPS IP
- Check Caddy logs: `docker logs caddy`
- Verify Let's Encrypt rate limits (5 failed attempts per hour per domain)

### Certificate expired
- Caddy auto-renews, but if it failed: `mb net ssl renew`
- Check if Caddy is running: `docker ps | grep caddy`
- Check if port 443 is accessible from the internet

### "Connection not secure" warnings
- Verify the certificate covers the exact domain (including www if used)
- Check if the certificate has expired
- Verify Caddy is serving the correct certificate

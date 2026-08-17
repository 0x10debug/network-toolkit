# Network Security Checklist

A checklist for securing your VPS network exposure.

## 1. Firewall

- [ ] Firewall is active (UFW or nftables)
- [ ] Default policy: deny incoming, allow outgoing
- [ ] Only necessary ports are open (SSH, 80, 443, and app-specific)
- [ ] SSH port is non-standard (not 22)
- [ ] Run `mb net audit` to verify

```bash
# Check firewall status
ufw status verbose        # Debian/Ubuntu
nft list ruleset          # Alpine

# Audit all exposed ports
mb net audit
```

## 2. SSH

- [ ] Root login disabled (`PermitRootLogin no`)
- [ ] Password authentication disabled (`PasswordAuthentication no`)
- [ ] SSH key is configured for all users
- [ ] SSH port is non-standard
- [ ] Only specific users allowed (`AllowUsers`)

```bash
# Verify SSH config
sshd -T | grep -E "permitrootlogin|passwordauthentication|port"
```

## 3. Reverse Proxy

- [ ] Caddy is running and handling ports 80/443
- [ ] All apps are behind the reverse proxy (not directly exposed)
- [ ] Security headers are injected (HSTS, X-Content-Type-Options, etc.)
- [ ] SSL certificates are valid and not expired
- [ ] HTTP redirects to HTTPS

```bash
# Check Caddy status
docker ps | grep caddy

# Check SSL certificates
mb net ssl list

# Test security headers
curl -I https://app.example.com
```

## 4. Docker Network

- [ ] `mb-proxy` network exists
- [ ] All app containers are on the `mb-proxy` network
- [ ] App containers do NOT expose ports to the host (only via reverse proxy)
- [ ] Database containers are NOT accessible from the internet

```bash
# Check network
docker network inspect mb-proxy

# Check which containers expose ports
docker ps --format "{{.Names}}: {{.Ports}}"
```

## 5. Port Exposure

- [ ] No unnecessary ports exposed to 0.0.0.0
- [ ] Database ports (5432, 3306, 6379) are NOT exposed to the internet
- [ ] Internal services bind to 127.0.0.1 where possible
- [ ] Docker port mappings are intentional and documented

```bash
# Audit all exposed ports
mb net audit

# Check for databases exposed to public
ss -tlnp | grep -E "5432|3306|6379"
```

## 6. SSL/TLS

- [ ] All public-facing sites use HTTPS
- [ ] SSL certificates are valid (not expired, not self-signed for production)
- [ ] HSTS header is set
- [ ] TLS version is 1.2+ (Caddy handles this automatically)
- [ ] No mixed content (all resources loaded via HTTPS)

```bash
# Check SSL
mb net ssl list

# Test with SSL Labs
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=app.example.com
```

## 7. Tunnel Security (if using frp)

- [ ] frp token is strong (32+ characters, randomly generated)
- [ ] TLS encryption is enabled (`transport.tls.enable = true`)
- [ ] frp dashboard is not exposed to the public internet
- [ ] Only necessary tunnels are configured

```bash
# Check frp server config
cat /opt/mb-net/*/frps.toml

# Verify TLS is forced
grep "tls.force" /opt/mb-net/*/frps.toml
```

## 8. DNS

- [ ] DNS records point to the correct VPS IP
- [ ] DDNS is configured if VPS IP is dynamic
- [ ] DNSSEC is enabled (if supported by your provider)
- [ ] No dangling DNS records pointing to old IPs

```bash
# Check DNS
dig app.example.com +short
dig example.com NS +short
```

## 9. Monitoring

- [ ] Uptime monitoring is configured (Uptime Kuma or similar)
- [ ] SSL certificate expiry alerts are set
- [ ] Log monitoring is in place
- [ ] CrowdSec is active and monitoring for attacks

```bash
# Check CrowdSec
cscli status

# Check monitoring
docker ps | grep -E "uptime-kuma|beszel"
```

## 10. Regular Audits

- [ ] Run `mb net audit` weekly
- [ ] Review Docker containers monthly (`docker ps -a`)
- [ ] Check SSL certificates monthly (`mb net ssl list`)
- [ ] Update images regularly (`mb net update`)
- [ ] Review firewall rules after any infrastructure change

## Incident Response

If you suspect a breach, see the [vps-bootstrap incident response guide](https://github.com/0x10debug/vps-bootstrap/blob/main/docs/incident-response.md).

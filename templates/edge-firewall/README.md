# Edge Firewall Template (nftables)

A complete **nftables** ruleset for hardening the network edge of a VPS running
the network-toolkit. Default-deny inbound, allow established/related, loopback,
rate-limited SSH, and HTTP/HTTPS for the reverse-proxy templates. Includes
bogon filtering and a dynamic IP blocklist fed by public threat feeds.

This is a **reference configuration**, not a Docker Compose template — it
configures the host kernel firewall directly. It does not appear in
`mb net list` (which lists Compose-based templates).

## Files

| File | Purpose |
|---|---|
| `nftables.conf` | Complete nftables ruleset (input/forward/output chains, bogon set, blocklist set, SSH rate limit). |
| `ipset-blocklist.conf` | Blocklist sources (Spamhaus, Emerging Threats, AbuseIPDB) + auto-update script reference. |

## Why nftables

nftables is the modern Linux packet-filtering framework (successor to
iptables), shipping as the default in Debian 10+, Ubuntu 20.04+, and most
current distros. It unifies IPv4/IPv6/ARP/bridge filtering in one syntax and
supports named sets, maps, and intervals natively.

## Deploy

```bash
# 1. Review the ruleset — adjust SSH port, open frp port if using tunnel template.
sudo cp nftables.conf /etc/nftables.conf
sudo nft -f /etc/nftables.conf

# 2. Persist across reboots (Debian/Ubuntu).
sudo systemctl enable --now nftables

# 3. Verify.
sudo nft list ruleset
```

> **Don't lock yourself out.** Before loading a default-deny ruleset over SSH,
> open a second SSH session so you keep access if the first rule blocks you.
> Test with `sudo nft -f nftables.conf && echo OK` — if your session drops,
> the ruleset is wrong. Reboot or use a console/rescue session to fix it.

## Rules explained

### input chain — policy `drop`

| Rule | Action | Why |
|---|---|---|
| `iif "lo"` | accept | Loopback must always work. |
| `ct state invalid` | drop | Malformed packets. |
| `ct state established,related` | accept | Return traffic for outbound connections (cloudflared, updates, DNS). |
| `ip saddr @bogons` | drop | Martian/RFC1918 source on public interface — spoofed. |
| `ip saddr @blocklistv4` | drop | Known malicious networks. |
| ICMP echo-request | rate-limit 5/s | Allow ping without enabling ICMP floods. |
| ICMPv6 essential types | accept | IPv6 requires NDP/PMTUD to function. |
| `tcp dport 22` new | rate-limit 5/min + burst 5 | SSH brute-force protection. |
| `tcp dport 22` new (over limit) | drop | Excess SSH attempts dropped. |
| `tcp dport {80,443}` | accept | HTTP/HTTPS for Caddy/Traefik. |
| `udp dport 443` | accept | HTTP/3 (QUIC). |

### forward chain — policy `drop`

The VPS is an endpoint, not a router. Only established/related and loopback
forwarding is allowed. Docker manages its own bridge forwarding in a separate
table, so this does not interfere with container networking.

### output chain — policy `accept`

All outbound allowed — cloudflared tunnels, DNS, package updates, DDNS API
calls. Add egress filtering here only if you have a specific need.

### SSH brute-force protection

The SSH rule allows 5 new connections per minute per source with a burst of 5.
Anything faster is dropped. This stops dictionary attacks while keeping SSH
usable. For stronger protection, also:

- Use key-based auth only (`PasswordAuthentication no` in `sshd_config`).
- Move SSH off port 22 (update the rule to match).
- Pair with fail2ban for log-based banning of repeated failed logins.

### Bogon filtering

The `bogons` / `bogons6` sets contain addresses that should never appear as a
source on the public internet (RFC1918, loopback, link-local, CGNAT,
documentation ranges, multicast, reserved). Dropping them early prevents
spoofing attacks. The list is static; review it when new RFCs allocate ranges.

### GeoIP blocking (optional)

nftables has no built-in GeoIP. To block by country, maintain an nft set of
country CIDRs (from ipdeny.com or Maxmind) and drop `ip saddr @geoip_block`.
See the comment block at the bottom of `nftables.conf` and the auto-update
pattern in `ipset-blocklist.conf`.

## Blocklist auto-update

`ipset-blocklist.conf` documents the threat-feed sources and an idempotent
update script:

1. Copy the script section into `/usr/local/sbin/update-nft-blocklist.sh`.
2. `chmod +x` it.
3. Add to root cron: `17 4 * * * /usr/local/sbin/update-nft-blocklist.sh`.
4. Logs go to `/var/log/nft-blocklist.log`.

The script flushes and rebuilds the `blocklistv4` set each run, so removing a
source automatically removes its CIDRs. Sources:

- **Spamhaus DROP / EDROP** — hijacked/malicious networks (no key needed).
- **Emerging Threats** — known bad IPs (no key needed).
- **AbuseIPDB** — community-reported abusive IPs (needs free API key).

## nftables vs UFW

| | nftables | UFW |
|---|---|---|
| Layer | Kernel netfilter (the actual backend) | Frontend that generates iptables/nftables rules |
| Syntax | Declarative, sets/maps, IPv4+IPv6 unified | Simple `ufw allow 22` commands |
| Power | Full: rate limit, sets, intervals, NAT, mangle | Basic allow/deny by port/IP; rate limiting needs `/etc/ufw/before.rules` |
| Persistence | `nftables.service` loads `/etc/nftables.conf` | `ufw enable` + saved rules |
| Best for | Edge servers needing precise control, blocklists, bogon filtering | Quick "allow SSH + HTTP" on a simple host |

**Recommendation**: Use nftables directly (this template) when you need
rate-limited SSH, bogon filtering, dynamic blocklists, or want a single
version-controlled ruleset. Use UFW for a minimal host where "allow 22, 80,
443" is enough and you don't need blocklists. They are not mutually exclusive
in syntax, but don't run both managers at once — pick one to avoid
conflicting rules.

## Notes

- If you use the `tunnel` or `full-stack` template, uncomment the `frp` port
  7000 rule in `nftables.conf`.
- If you use the `cloudflare` template (Cloudflare Tunnel), you do NOT need
  inbound 80/443 — comment those rules out and keep only SSH. The tunnel is
  outbound-only.
- Always keep a rescue console path available when changing firewall rules on
  a remote VPS.

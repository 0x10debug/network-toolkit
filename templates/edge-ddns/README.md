# Edge DDNS Template (Dynamic DNS)

Keep DNS records pointed at your VPS/home server when its public IP changes.
Two scripts are included: **Cloudflare** (for a domain you own on Cloudflare)
and **DuckDNS** (a free subdomain, no domain needed).

These are **reference scripts**, not Docker Compose templates — they run on the
host via cron. They do not appear in `mb net list` (which lists Compose-based
templates).

## Files

| File | Purpose |
|---|---|
| `cloudflare-ddns.sh` | Update Cloudflare A/AAAA records via the Cloudflare API. IPv4 + IPv6, idempotent, logged. |
| `duckdns-ddns.sh` | Update a free DuckDNS subdomain. Minimal, IPv4 (+ optional IPv6). |

## Cloudflare DDNS

Updates one A (IPv4) and/or AAAA (IPv6) record on a Cloudflare zone to the
host's current public IP. Only writes when the value changes. Requires a
Cloudflare API token with **Zone:DNS:Edit** on the target zone.

### Setup

1. Create an API token at Cloudflare → My Profile → API Tokens → Create
   Token → "Edit zone DNS" template, scoped to your zone.
2. Install the script:

```bash
sudo cp cloudflare-ddns.sh /usr/local/sbin/cloudflare-ddns.sh
sudo chmod +x /usr/local/sbin/cloudflare-ddns.sh
```

3. Configure (via a env file loaded by cron, or edit the CONFIG section):

```bash
# /etc/default/cloudflare-ddns
CF_API_TOKEN=your-token-here
CF_ZONE_NAME=example.com
CF_RECORD_NAME=home.example.com
CF_UPDATE_IPV4=true
CF_UPDATE_IPV6=false
```

4. Add to root cron (`sudo crontab -e`):

```cron
*/5 * * * * . /etc/default/cloudflare-ddns && /usr/local/sbin/cloudflare-ddns.sh >> /var/log/cloudflare-ddns.log 2>&1
```

### Features

- **IPv4 + IPv6** — independently toggle A and AAAA updates.
- **Idempotent** — fetches the current record value and only PUTs on change,
  so repeated cron runs are cheap and safe.
- **Auto-detect** — uses `api.ipify.org` / `api6.ipify.org` for public IP
  detection, or `CF_IPV4_OVERRIDE` / `CF_IPV6_OVERRIDE` to force a value.
- **Logged** — every run logs the action with a timestamp.
- **TTL 60** — low TTL so changes propagate fast.

## DuckDNS DDNS

[DuckDNS](https://www.duckdns.org) is a free DDNS service giving you a
`<name>.duckdns.org` subdomain. No domain registration needed. The script
calls the DuckDNS update endpoint, which auto-detects your IPv4 server-side.

### Setup

1. Sign in at https://www.duckdns.org with a supported provider and create one
   or more subdomains. Note the **token**.
2. Install:

```bash
sudo cp duckdns-ddns.sh /usr/local/sbin/duckdns-ddns.sh
sudo chmod +x /usr/local/sbin/duckdns-ddns.sh
```

3. Add to root cron:

```cron
*/5 * * * * DUCKDNS_TOKEN=your-token DUCKDNS_DOMAINS=myhome /usr/local/sbin/duckdns-ddns.sh >> /var/log/duckdns-ddns.log 2>&1
```

`DUCKDNS_DOMAINS` is a comma-separated list without the `.duckdns.org` suffix,
e.g. `myhome` updates `myhome.duckdns.org`; `myhome,second` updates both.

## Cloudflare vs DuckDNS

| | Cloudflare DDNS | DuckDNS |
|---|---|---|
| Domain | Your own (`home.example.com`) | Free subdomain (`myhome.duckdns.org`) |
| Cost | Free (Cloudflare account) | Free |
| IPv6 | Yes (AAAA record) | Yes (optional) |
| Dependencies | `curl` + `jq` | `curl` only |
| Setup effort | API token + zone config | Token + subdomain |
| Best for | Production / branded domain | Quick home lab / no domain |

**Recommendation**: Use **Cloudflare DDNS** if you already own a domain on
Cloudflare — it keeps your branded hostname and pairs naturally with the
`cloudflare` tunnel template. Use **DuckDNS** for a quick home-lab setup where
you don't want to register a domain or manage API tokens with scoped
permissions.

## Notes

- Run via cron every 5 minutes; both scripts are idempotent and cheap.
- For the `cloudflare` tunnel template, DDNS is usually unnecessary — the
  tunnel is outbound and the domain resolves to Cloudflare, not your IP. Use
  DDNS when you run Caddy/Traefik directly on a VPS with a dynamic IP, or for
  a home server behind a dynamic WAN IP.
- Keep API tokens out of version control. Use a root-only env file
  (`chmod 600 /etc/default/cloudflare-ddns`).

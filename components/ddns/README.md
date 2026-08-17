# DDNS Components

Dynamic DNS keeps a domain's DNS records pointed at a host whose public IP changes over time (a home broadband connection, a VPS on a dynamic range, etc.). This component uses [ddns-go](https://github.com/jeessy2/ddns-go), a lightweight self-hosted DDNS updater.

## Why

If your VPS or home network does not have a static IP, hardcoding an A record will break whenever the IP changes. A DDNS client detects the current public IP at an interval and pushes an update to your DNS provider so the domain always resolves correctly.

## Supported providers

ddns-go supports Cloudflare, Aliyun, Tencent, Dnspod, Huawei, Callback, and Baidu. Set `provider` in the config to the one you use and supply the matching API token.

## Configuration

1. Copy `ddns-go.example.yaml` to `ddns-go.yaml`.
2. Set `provider` to your DNS provider.
3. Set `token` to an API token with permission to edit the relevant DNS records. For Cloudflare this is a scoped API token with `Zone:DNS:Edit`.
4. List the domains/records to update under `domains`. Wildcard records (`*.example.com`) are supported.
5. Enable IPv4 and/or IPv6 detection. By default the public IP is fetched from an external service; alternatively set `interface` to read the IP directly from a local NIC.
6. Set the update `interval` (minutes). 5 minutes is a reasonable default.
7. Set the web UI credentials. Change the default `admin` / `CHANGE_ME` password, or disable the web UI if you do not need it.

## Security notes

- Treat the API token like a password — store it in an env var or a secrets manager, not in a committed file.
- Restrict the web UI port (`:9876`) to a trusted network or put it behind Caddy basic auth.
- Use a scoped DNS token that can only edit the records you actually update, not your whole account.

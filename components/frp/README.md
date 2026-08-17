# frp Components

[frp](https://github.com/fatedier/frp) is a fast reverse proxy that lets you expose a service running behind NAT (e.g. on your home network) to the public internet via a VPS that has a public IP.

## Server vs client

- **`frps.toml.example`** — the frp **server** (`frps`). Runs on your VPS. It listens on `bindPort` (7000) for client connections and exposes the `remotePort` of each proxy to the internet.
- **`frpc.toml.example`** — the frp **client** (`frpc`). Runs on your home machine. It connects out to the server and registers one or more `[[proxies]]` that map a local port to a remote port on the VPS.

## Security

- **Token auth** — set `auth.token` to the same long random string on both server and client. Anyone without the token cannot register a proxy.
- **TLS** — `transport.tls.force = true` on the server rejects non-TLS clients; `transport.tls.enable = true` on the client enables TLS. This encrypts the tunnel end to end.
- **Dashboard** — the server dashboard (`webServer.*`) is optional. If you enable it, change the default `admin` / `CHANGE_ME` credentials and ideally restrict access via firewall or Caddy basic auth.
- **SSH exposure** — exposing SSH over frp is convenient but risky. Prefer key-only auth, a non-default remote port, and an IP allowlist on the VPS firewall.

## Setting up a tunnel from home to VPS

1. Copy `frps.toml.example` to `frps.toml` on the VPS, set `auth.token` and dashboard password.
2. Start `frps` on the VPS (e.g. via systemd or Docker). Open the firewall for `bindPort` (7000) and any `remotePort` you plan to use.
3. Copy `frpc.toml.example` to `frpc.toml` on your home machine. Set `serverAddr` to the VPS IP and `auth.token` to the **same** value as the server.
4. Add `[[proxies]]` entries for each home service you want to expose.
5. Start `frpc` on the home machine. Traffic to `VPS_IP:remotePort` is now forwarded to `localIP:localPort` at home.

## Notes

- These are example files (`.toml.example`). Copy them to `.toml` and fill in real values; never commit real tokens or passwords.
- frp moved from INI to TOML config in v0.52.0. These examples use the TOML format.

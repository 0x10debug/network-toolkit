# VPS 网络工具包 — 一条命令搞定反向代理、SSL 和内网穿透

用安全的反向代理、自动 SSL 证书和 NAT 穿透把你的自托管应用暴露到互联网——全部一条命令配置好。专为 VPS 和 Docker 设计，这个工具包把 Caddy、frp 和 DDNS 组合成可部署模板。不用再分别折腾反代、Let's Encrypt 和穿透配置。选一个模板，填域名，你的服务就通过 HTTPS 上线了。

> **刚加固完 VPS？** 先部署 `website` 模板——它给你一个带自动 SSL 的反向代理。然后用 [compose-recipes](https://github.com/0x10debug/compose-recipes) 部署应用，通过代理路由流量。

## 为什么需要这个工具

在 VPS 上部署应用后，你需要把它们暴露到互联网。这意味着：

1. **反向代理** — 把域名路由到正确的容器
2. **SSL 证书** — 用 HTTPS 而不是 HTTP，保证安全和信任
3. **NAT 穿透** — 通过 VPS 暴露家里的服务
4. **动态域名** — IP 变了时自动更新 DNS

每个都是独立的工具（Caddy、acme.sh、frp、ddns-go）。单独配置复杂且容易出错。这个工具包把它们组合成预配置模板——选一个，填域名，搞定。

## 功能

- **自动 HTTPS** — Caddy 零配置获取和续期 Let's Encrypt 证书
- **安全头** — 自动注入 HSTS、X-Content-Type-Options、X-Frame-Options
- **NAT 穿透** — frp 隧道服务端，通过 VPS 暴露家里的服务
- **动态域名** — ddns-go 集成 Cloudflare、阿里云、腾讯云等
- **Cloudflare 隧道** — 替代模式，VPS 不需要开放任何入站端口
- **端口审计** — 扫描所有暴露端口，识别安全风险
- **Docker 网络集成** — 所有应用共享 `mb-proxy` 网络，无缝路由

## 模板

| 模板 | 组件 | 场景 |
|---|---|---|
| [website](templates/website/) | Caddy + SSL | 单站点 HTTPS |
| [multi-site](templates/multi-site/) | Caddy + SSL | 多域名共用一个 Caddy |
| [tunnel](templates/tunnel/) | Caddy + frp | 通过 VPS 暴露家里的服务 |
| [full-stack](templates/full-stack/) | Caddy + frp + DDNS | 全套：代理、SSL、穿透、DDNS |
| [cloudflare](templates/cloudflare/) | Caddy + Cloudflare 隧道 | 零入站端口——流量全走 Cloudflare |
| [traefik](templates/traefik/) | Traefik v3.6 + SSL | Docker 原生反代，带仪表盘和中间件库 |

## 快速开始

```bash
# 1. 加固 VPS 并安装 Docker（如未完成）
# → https://github.com/0x10debug/vps-bootstrap

# 2. 克隆此 repo
git clone https://github.com/0x10debug/network-toolkit.git
cd network-toolkit

# 3. 列出可用模板
./mb net list

# 4. 部署带自动 SSL 的反向代理
./mb net deploy website

# 5. 为你的应用添加路由
./mb net proxy add app.example.com app-container:8080

# 6. 查看状态
./mb net status
```

## 用法

```bash
mb net list                              # 列出可用模板
mb net deploy <template>                 # 部署网络模板
mb net status                            # 查看基础设施状态
mb net proxy add <domain> <target>       # 添加反代路由
mb net proxy remove <domain>             # 移除反代路由
mb net tunnel add <name>                 # 添加穿透配置
mb net tunnel status                     # 查看穿透状态
mb net ssl list                          # 列出 SSL 证书
mb net ssl renew                         # 强制证书续期
mb net audit                             # 审计端口暴露
mb net update                            # 更新网络组件
mb net help                              # 显示帮助
```

## 常见问题

### 如何在 VPS 上用 Docker 设置反向代理？

部署 `website` 模板：`mb net deploy website`。填域名和目标容器。Caddy 启动后自动从 Let's Encrypt 获取 SSL 证书，把流量路由到你的应用。用 `mb net proxy add <域名> <目标>` 添加更多路由。

### 如何为自托管应用获取免费 SSL 证书？

Caddy 内置 Let's Encrypt 自动集成——不需要手动管理证书。部署任何模板时，Caddy 自动为你的域名获取证书。用 `mb net ssl list` 检查证书状态。

### 如何通过 VPS 把本地服务暴露到互联网？

在 VPS 上部署 `tunnel` 模板：`mb net deploy tunnel`。这会启动 frp 服务端。然后在你的家用机器上安装 frp 客户端，配置连接到 VPS，家里的服务就能通过 VPS 域名以 HTTPS 访问了。

### 如何为自托管应用设置 Cloudflare 隧道？

部署 `cloudflare` 模板：`mb net deploy cloudflare`。这会在 VPS 上运行 `cloudflared`，创建到 Cloudflare 边缘的出站隧道。VPS 不需要开放任何入站端口——所有流量通过 Cloudflare。在 cloudflared 配置文件中配置 ingress 规则。

### 如何为多个站点配置 Caddy 反向代理？

部署 `multi-site` 模板：`mb net deploy multi-site`。Caddyfile 包含多个域名块。用 `mb net proxy add <域名> <目标>` 添加新域名，或直接编辑 Caddyfile 进行复杂配置。

## 文档

- [反向代理指南](docs/reverse-proxy-guide.md) — 如何用 HTTPS 暴露应用
- [穿透配置](docs/tunnel-setup.md) — 用 frp 进行 NAT 穿透
- [SSL 管理](docs/ssl-management.md) — 证书管理和故障排查
- [DDNS 配置](docs/ddns-setup.md) — 动态域名配置
- [安全清单](docs/security-checklist.md) — 网络暴露安全审计

## 组件

供高级用户复用的配置片段：

- [Caddy](components/caddy/) — 基础 Caddyfile 和安全头片段
- [Traefik](components/traefik/) — 基础静态配置和中间件片段（Traefik v3.6）
- [frp](components/frp/) — 服务端和客户端配置模板
- [DDNS](components/ddns/) — ddns-go 多 DNS 提供商配置
- [Cloudflare](components/cloudflare/) — Cloudflare 隧道 ingress 配置

## 相关项目

- [vps-bootstrap](https://github.com/0x10debug/vps-bootstrap) — 一条命令 VPS 初始化和安全加固
- [compose-recipes](https://github.com/0x10debug/compose-recipes) — VPS 自托管应用套件
- [monitor-stack](https://github.com/0x10debug/monitor-stack) — 轻量监控栈
- [security-audit](https://github.com/0x10debug/security-audit) — VPS 安全审计工具

## 许可证

[MIT](./LICENSE)

# Caddy Configuration Examples

Focused Caddy v2.9 configuration examples for specific features. These are
reference configurations — the main deployable templates (website, multi-site,
tunnel, full-stack) live in `templates/` directly and already include HTTP/3
and active health checks.

## Examples

- [`http3/`](./http3/) — HTTP/3 (QUIC) enabled single-site reverse proxy.
  Demonstrates the `protocols h1 h2 h3` directive, UDP 443 port mapping, and
  firewall requirements for QUIC.

## Relationship to the main templates

All main templates (`templates/website`, `templates/multi-site`,
`templates/tunnel`, `templates/full-stack`) were updated to Caddy v2.9 and now
include HTTP/3 support out of the box. The examples in this directory are for
users who want to understand a specific feature in isolation or build a custom
configuration from a minimal starting point.

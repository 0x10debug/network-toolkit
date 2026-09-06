# TEST-REPORT

Living per-iteration test report, maintained per the Testing Discipline iron
rule (main repo AGENTS.md, 2026-09-06).

Layer definitions: L1 static (bash -n, shellcheck, gitleaks, no-Chinese scan),
L2 config validation, L3 runtime smoke in a disposable environment, L4
host-level lifecycle.

---

## 2026-09-06T20:21:45Z — commit 099e68d (Round 2 Day 10 backfill: CI pipeline, Caddyfile repair)

**Layers executed: L1, L2. L3/L4 not run.**

| Check | Result |
|---|---|
| L1 bash -n sweep (8 files + mb) | PASS |
| L1 shellcheck -S warning gate | PASS (0 findings; 4 fixed in iter/network-ci-validate) |
| L1 gitleaks history scan (allowlist: documented authelia:9091 endpoint) | PASS (exit 0) |
| L1 no-Chinese content scan (CI job, run 33998368652) | PASS |
| L2 caddy validate via pinned caddy:2 image, all 7 Caddyfiles | PASS (7 ok, 0 fail) |
| L2 YAML parse, 28 files (CI job) | PASS |

Defects found during this development cycle (fixed pre-push, verified):

- 6 of 7 Caddyfiles failed `caddy validate` before the repair: nonexistent
  global `protocols` option, snippet definitions inside the global options
  block (Caddyfile.base), env placeholders without defaults collapsing site
  headers, and the optional ACME email line. All repaired; 7/7 validate.
- gitleaks false positive on the documented Authelia forward-auth endpoint -
  resolved by path allowlist after the secret-regex allowlist proved unable
  to match (commit 62080e6).

Known issues (open): Traefik config validation (`traefik check-config`) is
not yet in CI - recorded in the work-item ledger (X-NT-1).

Untested (honest boundaries):

- L3 runtime smoke: no reverse proxy was booted with a rendered config this
  cycle; caddy validate proves config acceptance, not routing/TLS behavior.
- L4 host-level: certificate issuance, tunnel bring-up, SSO flows, and
  trusted-proxy semantics not run - blocked on a disposable environment with
  controllable DNS (scheduled with the routes.yaml and trusted-proxy work
  packages).

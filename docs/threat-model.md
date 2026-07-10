# Grimnir — Threat Model (v0.1)

> **Status:** v0.1 — 2026-07-06, owner-reviewed 2026-07-07. Seeded by a local M5 model, then
> verified and edited against the 2026-07-06 blind-spot audit. Every residual-**High** row in §5
> is tracked as a `from:grimnir` ticket (see the *Tracked* column).
>
> Companion to [`architecture.md`](architecture.md) (the *how*) and [`vision.md`](vision.md) (the
> *why*). This is the *what-we-defend-against* — the artifact that was deferred as "Phase B" and is
> named here for the first time.

---

## 1. Scope & assumptions

- **Single operator** (Magnus) — one fully-trusted human; no multi-user model today.
- **Sovereignty:** data *at rest* lives on-prem (Pi 1, Pi 2 / NAS, M5). Deliberate exceptions:
  cloud AI models may process prompts but are not treated as storage authority; Munin ships an
  **encrypted** off-site backup leg (`rclone`-crypt); Cloudflare fronts public ingress.
- **In scope:** confidentiality / integrity / availability of the two pillars (Sovereign Memory,
  Self-Knowing Inference) and the accounting + client data they touch.
- **Threat horizon:** opportunistic and injection-borne compromise, operator error, hardware loss —
  **not** a targeted nation-state adversary.

## 2. Assets (ranked)

| Asset | Why it hurts if lost or leaked |
|---|---|
| Mimir files (client docs, Fortnox exports, personal) | Breach of *third-party* client / financial data — legal + reputational, not just personal |
| Munin memory (SQLite, local embeddings) | Loss = erased context; leak = a searchable index of everything personal; a wrong "fact" silently poisons autonomous action |
| Verdandi audit chain | The record of what was done; if forgeable or lost there is no accountability for autonomous action |
| Secrets & tokens (per-service bearer, OAuth, keychain) | Compromise → substrate takeover / lateral movement |
| noxctl / Fortnox credentials + data | Money movement + customer PII |
| Capability ledger / `m5-routing` | Poisoning re-routes work to the wrong or unsafe model |

## 3. Trust boundaries

- **Fully trusted:** the operator; admin-controlled host accounts and root contexts. Individual
  service processes and dependencies are not automatically trusted once compromised.
- **Semi-trusted (soft):** the Tailscale mesh — treated as an internal network, but any compromised
  device on it can reach services bound to the tailnet/LAN or exposed through tunnels. The
  per-service **bearer auth is the real control**, not the tailnet perimeter.
- **Untrusted:** all *ingested content* (email, web, documents, Telegram messages / forwards / voice
  transcripts), npm dependencies, the public internet.
- **Key crossings:** untrusted content → agent (holding Munin + Mimir + execution) → outbound
  network; Telegram → Ratatoskr → Hugin task; laptop / interactive session → Munin + Mimir.

## 4. Adversaries

- **Prompt-injection via ingested content** — the primary realistic threat: untrusted text steers an
  agent that holds memory + files + execution.
- **Compromised laptop or Telegram account** — inherits the operator's full trust.
- **Malicious / compromised npm dependency** in a Node service.
- **Tailnet-present attacker** (lost phone, compromised device on the mesh).
- **Physical theft / loss** of a Pi or the NAS disk.

## 5. Key threats

| # | Threat | Vector | Current control | Residual | Tracked |
|---|---|---|---|---|---|
| T1 | Exfiltration via the **lethal trifecta** | Injection in ingested content → agent with memory+files+exec → egress | Hugin queue-path injection/exfil scanners + egress policy | **H** — detective only; `bypassPermissions` unconditional | hugin#149 |
| T2 | Same trifecta on **interactive sessions** | Claude Code / Desktop reading raw email/Telegram with full Munin+Mimir access | Operator posture requires Hugin handoff for consequential mutations after untrusted input, with a constrained fresh-session fallback | **H** — procedural, not enforced | grimnir#70 |
| T3 | Command injection → fleet code-exec | Ratatoskr `/repo` path-traversal; LLM output submitted verbatim | Telegram owner-allowlist | **H** | ratatoskr#36 |
| T4 | Autonomous action unattributable / unlogged | Hugin mutates (commits/deploys/writes) but emits nothing to Verdandi; shared static tokens = no per-tenant identity | append-only Verdandi exists but is unfed by Hugin | **H** | hugin#148, verdandi#15 |
| T5 | Audit-chain forgery on a compromised box | Attacker owns Pi 1, rewrites the chain and re-hashes | append-only trigger + SHA-256 chain; `GET /api/verify` | **M** — verify is manual + same-box; no off-box anchor | verdandi#16 |
| T6 | Supply-chain compromise | Malicious transitive npm dep in a Node service | weekly `security-scan.sh` (`npm audit`) + systemd sandbox | **M** | (scan exists) |
| T7 | Physical theft → plaintext data at rest | Stolen Pi / SD card / NAS disk | file perms `0600`; **SD cards likely NOT encrypted — verify** | **H** if unencrypted | brokkr#40 |
| T8 | Silent total-host failure | Pi 1 dies; monitoring + alerting die with it | on-box watchdog only | **M/H** — no off-box dead-man's switch | brokkr#38 |
| T9 | Backup loss / unrecoverable restore | NAS disk failure; restore never tested | Munin encrypted off-site; other stores on-prem only | **H** | brokkr#39 |
| T10 | Poisoned memory drives bad action | A false stored "fact" retrieved and acted on repeatedly | secret-scan on write; no correction / expiry path | **M** | munin-memory#192 |
| T11 | Third-party data retained without enforceable lifecycle / erasure | Client/accounting/person data accumulates across Mimir, Munin, Fortnox exports, backups | Store map and provisional retention defaults now exist; enforcement is per-store/manual and complete erasure is not implemented | **H** | grimnir#66 |

## 6. Explicitly accepted / out-of-scope (for now)

- **Nation-state / targeted APT** — out of scope.
- **Multi-user isolation** — single operator; Munin's multi-principal (Sara) support is access-sharing,
  not a security boundary.
- **The operator as an insider threat** — trusted by definition.
- *Everything in §5 is a **tracked gap**, not an accepted risk.*

## 7. Review cadence

- Re-review **quarterly**, and on any change to: Hugin execution/permissions, Ratatoskr input
  handling, the auth model, or Tailscale / Cloudflare exposure.
- Each residual-**H** row must have an owning ticket and a target; close the row when its control
  moves the risk to **M** or lower.

## 8. Interactive-session posture

The owner-approved handling rule for T2 is defined in
[`interactive-session-posture.md`](interactive-session-posture.md): inspect untrusted content in a
non-mutating context, route consequential mutations through Hugin, and use a narrowly restated fresh
session only when Hugin cannot perform the action. This reduces routine exposure but does not lower
T2 below **High** until the boundary is technically enforced and evidenced.

# Grimnir — Threat Model (v0.3)

> **Status:** v0.3 — source and ticket review dated 2026-11-03, following the owner-reviewed v0.1.
> The [dated review](security-review-2026-11-03.md) records evidence limits, accountable owners,
> completed/cancelled/open ticket dispositions and next review targets. Residual ratings are unchanged;
> this is not new owner risk acceptance or authority to restart stopped work.
>
> Companion to [`architecture.md`](architecture.md) (the *how*) and [`vision.md`](vision.md) (the
> *why*). This is the *what-we-defend-against* — the artifact that was deferred as "Phase B" and is
> named here for the first time.

---

## 1. Scope & assumptions

- **Single operator** (Magnus) — one fully-trusted human; no multi-user model today.
- **Sovereignty:** data *at rest* lives on-prem (Pi 1, Pi 2 / NAS, M5). Deliberate exceptions:
  cloud AI models may process prompts but are not treated as storage authority; Munin and Mimir
  each ship an **encrypted** off-site backup leg (`rclone`-crypt); Cloudflare fronts public ingress.
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
| T1 | Exfiltration via the **lethal trifecta** | Injection in ingested content → agent with memory+files+exec → egress | Hugin scanners and executor-specific profiles; Claude/OpenCode profiles do not describe every executor. Fetch and Git-push allowlists are narrower than universal child-process confinement | **H** — trusted-code remains powerful; scanner and egress coverage are incomplete | HUGIN-149 Done; HUGIN-415 Backlog for CLI compatibility only; [owner/target](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |
| T2 | Same trifecta on **interactive sessions** | Claude Code / Desktop reading raw email/Telegram with full Munin+Mimir access | Owner mandates, content-as-data handling, review and harness permission gates; no exposure-triggered handoff | **H** — prompt-injection containment is not demonstrated | GRIM-234; grimnir#70/GRIM-227 superseded |
| T3 | Command injection → fleet code-exec | Ratatoskr `/repo` path-traversal; LLM-produced repo context | Owner allowlist plus task-writer validation; live probes reject traversal and newline/field injection before task creation | **M** — an owner-authorized task can still execute within an allowed repo | ratatoskr#36 shipped |
| T4 | Autonomous action unattributable / unlogged | Hugin mutates (commits/deploys/writes) without end-to-end tenant identity or durable audit receipt | Hugin persists task provenance; authenticated identity depends on successful signing verification. Durable audit/reversal is required with Verdandi optional; actor-wide adoption is not proven | **H** — end-to-end audit and per-tenant attribution remain unproven | HUGIN-148 and VERD-15 Cancelled; [current disposition](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |
| T5 | Audit-chain forgery or loss | Attacker owns the audit host, or credible history is lost | Durable audit may use supported sinks; Verdandi source safeguards do not establish an operating witnessed chain | **H** — Verdandi is deliberately stopped, legacy physical recovery was declined; no continuity or routine export is claimed | VERD-21 Cancelled; VERD-31 Done, source only; [current disposition](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |
| T6 | Supply-chain compromise | Malicious transitive npm dep in a Node service | Upstream revision-bound nine-repository scan and finite allowlist repaired in GRIM-222/233; scoped dependency fixes verified | **M** — databases/provenance are incomplete prevention; 60 secret-pattern candidates remain untriaged | [2026-11-03 scope and limits](security-review-2026-11-03.md#evidence-and-its-limits) |
| T7 | Physical theft → plaintext data at rest | Stolen host / boot media / NAS disk | File permissions and documented encryption preparation; per-volume encryption and recovery readiness require live evidence | **H** — at-rest protection is not established fleet-wide | BROKKR-89 Backlog (M5), BROKKR-170 Backlog (fleet evidence); [owner/target](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |
| T8 | Silent total-host failure | Control host dies; monitoring + alerting die with it | Historical M5 dead-man/Telegram drill evidence; current operation is not re-probed by this review | **M** — external missed-ping path remains unaccepted pending protected configuration and drill | BROKKR-97 Backlog; no activation authority |
| T9 | Backup loss / unrecoverable restore | Host/storage loss; missing or unusable component recovery | Component-owned encrypted off-site backups and historical Mimir restore evidence dated 2026-07-10; no current all-store recovery proof or operating Verdandi chain | **H** | BROKKR-170 Backlog; BROKKR-39 unresolved legacy reference; [owner/target](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |
| T10 | Poisoned memory drives bad action | A false stored "fact" retrieved and acted on repeatedly | Munin supports explicit correction lineage, compare-and-swap and soft expiry; correctness still depends on evidence and use | **M** | MUNIN-192 Done; [source correction](security-review-2026-11-03.md#source-corrections-behind-the-review) |
| T11 | Third-party data retained without enforceable lifecycle / erasure | Client/accounting/person data accumulates across primary stores and backups | Store map and provisional defaults exist; Munin correction/expiry is narrower than cross-store erasure and backup expiry | **H** | GRIM-66 Cancelled; [owning-store disposition](security-review-2026-11-03.md#residual-high-ownership-and-disposition) |

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

The 2026-11-03 review is recorded in **GRIM-232**, with accountable owners, implementation-ticket
states and concrete next evidence/decision targets in the [review record](security-review-2026-11-03.md).
Next quarterly review: **2027-02-03**, owned by Grimnir. A cancelled implementation is shown as such;
its dated review record is not an active implementation mandate or evidence of risk acceptance.

## 8. Interactive-session posture

The owner decision of 2026-11-03 (GRIM-234) is recorded in
[`interactive-session-posture.md`](interactive-session-posture.md). Sessions continue authorized
work after reading untrusted input; Hugin or a fresh session is no longer required for that reason.
Content, summaries and model reports remain data rather than authority. Owner mandates, independent
review, harness permissions, exact release binding and durable audit/reversal still apply.

The earlier grimnir#70/GRIM-227 exposure-based procedure is superseded. Removing it does not prove
technical containment: injected instructions, poisoned repository or memory content, misleading
review output and malicious tool-returned names remain potential inputs to a capable session.
T2 stays **High**. These are tracked gaps, not accepted risks or evidence that a control shipped.

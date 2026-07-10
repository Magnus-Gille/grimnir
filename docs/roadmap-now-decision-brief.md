# Grimnir Roadmap Now - Decision Brief

> Status: owner decisions adopted 2026-07-10 for grimnir#65, #66, #67, #69, and #70.
> This remains an index, not a full policy pack.

---

## Why these items belong in Grimnir

The current threat model made three system-level gaps visible: continuity, data lifecycle, and
trust posture. They are not new feature ideas; they protect the two pillars named in
[`vision.md`](vision.md):

- **Sovereign Memory:** succession, data mapping, erasure, and interactive-session handling decide
  who can recover, delete, or accidentally leak Munin, Mimir, Verdandi, and related stores.
- **Self-Knowing Inference:** an ROI ledger and Skuld decision make Grimnir measure whether its own
  services earn their place instead of preserving stale automation by habit.

The safe shape is therefore a set of decision records and small checklists, not a large compliance
framework.

## grimnir#65 - Succession / bus factor

**Problem:** Grimnir has one fully trusted operator. If Magnus is unavailable, the sovereign memory
and audit substrate may be inaccessible or unrecoverable, even though it is deliberately not hosted
by a third party.

**Smallest useful artifact:** a private succession envelope, referenced but not stored in this repo,
plus a non-secret public checklist in this repo.

The non-secret checklist should contain:

- out-of-band confirmation that the delegate can locate the private envelope, without recording its
  locator or contents in the repo;
- how to identify the active hardware and repos (`services.json` remains the inventory authority);
- how to stop public ingress, scheduled jobs, and autonomous execution;
- which stores have an established recovery/export procedure, and how to stop and preserve a store
  safely when no such procedure exists;
- who is allowed to receive help from an outside engineer.

**Decision:** Sara is the emergency delegate with `export-and-shutdown` authority. The non-secret
procedure and scope boundary are in [`succession-checklist.md`](succession-checklist.md). Magnus
must still confirm out of band that Sara can locate the private envelope.

**Architecture fit:** this protects Sovereign Memory by keeping ownership of the data and audit
trail recoverable without moving secrets into the repo.

## grimnir#66 - GDPR / data map / retention / erasure

**Problem:** T11 in [`threat-model.md`](threat-model.md) notes that third-party/client/accounting
data accumulates across stores without a formal map, retention default, or erasure path.

**Smallest useful artifact:** a data lifecycle map with one row per store, not a legal policy.

Initial rows to cover:

| Store | Data class | Authority | Retention shape | Erasure shape |
|---|---|---|---|---|
| Munin | memory, summaries, traces, task results | `munin-memory` | owner-defined by namespace | delete/correct entry; log erasure action |
| Mimir | files and generated artifacts | `mimir` | source-folder policy | no delete API; operator removes at the authoritative filesystem/source; encrypted off-site history rotates after 30 days, while append-only NAS backup may retain removed files indefinitely |
| Verdandi | audit events | `verdandi` | append-only with pre-ingest secret redaction | immutable original rows have no implemented PII-erasure mechanism; resolution remains owning-repo target work |
| Heimdall | metrics, alerts, briefing rendering | `heimdall` | operational window | prune metrics through existing maintenance |
| Hugin | task inputs/outputs/workspaces | `hugin` | short-lived workspace, durable result in Munin | remove workspace artifacts; keep audited action record |
| Ratatoskr | Telegram-derived task context | `ratatoskr` | only what is needed for routing/audit | delete local transient records; source deletion is Telegram-side |
| Skuld | daily briefing synthesis | `skuld` | only if briefings are kept | delete generated briefings from Munin if not needed |
| noxctl / Fortnox exports | accounting/client data | `fortnox-mcp` / Fortnox | statutory/accounting rules win | delete local exports when no longer needed |
| Backups | Munin/Mimir copies | Brokkr | configuration-specific | encrypted off-site history has configured rotation; Mimir's NAS `backup-artifacts` copy is append-only/no-delete and may preserve removed files indefinitely |
| M5 ledger | capability/eval evidence, verdict metadata | `gille-inference` | eval evidence window | remove or redact payload-derived artifacts if they contain personal data |

**Decision:** the store map and provisional defaults are adopted in
[`data-lifecycle.md`](data-lifecycle.md): statutory/contractual duties otherwise 24 months after an
engagement ends for client/accounting data; personal memory until explicit correction/deletion with
annual review; six months for operational telemetry; and 30 days for transient task artifacts.

**Architecture fit:** this is Pillar 1 hygiene. It should stay practical: map stores, defaults, and
erasure mechanics before writing broad GDPR prose.

## grimnir#67 - System ROI ledger + exit/off-ramp

**Problem:** Grimnir measures local-model capability, but it does not yet measure whether the system
itself is worth its maintenance cost, risk surface, and operator attention.

**Smallest useful artifact:** a monthly system ROI ledger with evidence categories, plus an explicit
off-ramp rule in the vision.

Suggested ledger fields:

| Field | Why it matters |
|---|---|
| `period` | monthly cadence is enough |
| `ops_minutes` | maintenance burden |
| `frontier_spend_usd` | actual cloud model spend |
| `local_inference_value_usd` | value/savings attributed to M5 routing, quality-adjusted where possible |
| `human_hours_saved_estimate` | rough but visible productivity value |
| `incidents_prevented_or_detected` | value from monitoring, security scan, drift detection |
| `services_cut_or_kept` | evidence that bloat is being controlled |
| `decision` | keep, fix, cut, or revisit |

**Decision:** accepted. [`vision.md`](vision.md#system-roi-and-off-ramp) now requires a monthly
evidence review and cuts or archives a service after two consecutive reviews with no measured use,
pillar-protection role, or owner-reviewed reason to keep it.

**Architecture fit:** this applies the Self-Knowing Inference idea to the system itself. The risk is
false precision, so the first ledger should accept estimates and evidence notes rather than pretend
to be accounting-grade.

## grimnir#69 - Skuld revive-or-cut decision

**Problem:** Skuld is now represented as a timer-only briefing producer, but its actual value is not
yet proven. A daily briefing can either be a useful memory/inference synthesis or a stale automation
that adds maintenance surface.

**Smallest useful artifact:** a time-boxed revive-or-cut decision record.

Two acceptable paths:

- **Revive:** run Skuld for a four-week trial with traces, human usefulness marks, and at least one
  concrete action captured per useful briefing.
- **Cut:** remove Skuld from the deployed component inventory and keep Heimdall/Munin views only if
  another producer exists.

**Decision:** a 28-day trial, defined in
[`skuld-trial-decision.md`](skuld-trial-decision.md). Its first successful briefing starts the clock;
day 28 must produce a recorded `keep` or `cut` decision.

**Architecture fit:** revive fits both pillars only if the briefing reads sovereign memory and
produces measurable orientation value. Cut fits the "cut bloat continuously" principle if that
evidence is absent.

## grimnir#70 - Interactive-session trust posture

**Problem:** T2 in [`threat-model.md`](threat-model.md) is a high residual risk: interactive Claude
Code/Codex/Desktop sessions can read untrusted content while holding memory, files, tools, and
egress. Hugin queue gating does not protect those sessions.

**Smallest useful artifact:** an operator-facing trust posture for interactive sessions, not a new
enforcement framework.

Suggested posture:

- Treat raw email, Telegram forwards, web pages, PDFs, and documents as untrusted until summarized
  or inspected in a read-only pass.
- Do not combine untrusted-content reading with external sends, credential use, deploys, or broad
  filesystem edits in the same reasoning context.
- Mutating work that follows untrusted input must use a Hugin-mediated task path. If Hugin cannot
  perform the action, use a fresh session with a narrowly restated trusted goal.
- Record the reason whenever the fresh-session fallback is used; operator approval selects a safe
  handoff path and does not permit mutation in the tainted context.

**Decision:** route consequential mutations after untrusted input through Hugin, with a constrained
fresh-session fallback when Hugin cannot perform the action. See
[`interactive-session-posture.md`](interactive-session-posture.md).

**Architecture fit:** this protects Sovereign Memory from the current lethal-trifecta gap while
avoiding premature policy bloat. The later technical fix can be narrower once the desired friction
level is explicit.

## grimnir#58 - Tenant validation status

grimnir#58 remains blocked by verdandi#15. The Grimnir-side docs should not claim end-to-end tenant
conformance until off-Pi Verdandi intake and key provisioning exist, and Seam D has been rerun.

**Owner decision required:** none in Grimnir before verdandi#15. The next Grimnir action is to rerun
and update [`tenant-validation-2026-07-04.md`](tenant-validation-2026-07-04.md) after the Verdandi
blocker lands.

## Adopted artifacts

The decision set stays intentionally small:

- [`succession-checklist.md`](succession-checklist.md) for grimnir#65, without secrets.
- [`data-lifecycle.md`](data-lifecycle.md) for grimnir#66, store map first and legal prose second.
- [`vision.md#system-roi-and-off-ramp`](vision.md#system-roi-and-off-ramp) for grimnir#67.
- [`skuld-trial-decision.md`](skuld-trial-decision.md) for grimnir#69.
- [`interactive-session-posture.md`](interactive-session-posture.md) and the corresponding threat
  model note for grimnir#70.

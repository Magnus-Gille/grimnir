# Fable Review — Grimnir Vision, Subsystems & Top 5 Priorities

> **2026-07-09** — produced by Claude (Fable 5) on request: a complete overview of the Grimnir
> vision and its subsystems, plus the five highest-priority/value work items.
> Sources: `docs/vision.md` (v0.2), `docs/architecture.md`, `services.json`,
> `docs/gap-analysis-2026-07-03.md`, `docs/threat-model.md` (v0.1),
> `docs/tenant-contract.md` + `docs/tenant-validation-2026-07-04.md`,
> `docs/roadmap-now-decision-brief.md`, `docs/agent-harness-bakeoff-2026-07-08.md`,
> `docs/observability-and-improvement.md`, `STATUS.md`, Munin `projects/grimnir`,
> and the live GitHub backlog (all component repos + Roadmap board, surveyed today).
> **No work has been started** — this is an assessment only.

---

## 1. The vision in brief

**Thesis (v0.2):** *Grimnir is a sovereign, self-knowing personal-AI substrate that any agent
can safely act through.* The substrate is the identity; the agent — loop, channels, model — is
a replaceable tenant. As models and harnesses commoditize, the scarce assets are *your* memory,
*your* files, *your* accountability record, and *your* learned model of what to route where.

**Two protected pillars** (built, never outsourced):

1. **Sovereign Memory** — Munin (memory) · Mimir (files) · Verdandi (audit). Your data on your
   hardware, auth at every layer, tamper-evident record of what was done with it.
2. **Self-Knowing Inference** — M5 gateway · capability ledger · offloadability eval. A system
   that *learns* what it can trust cheaper compute with and routes accordingly. The most
   original idea in the system.

**Decision rule:** build only what touches Memory or Inference-routing; reuse open-source for
everything in the harness layer, provided it plugs into Munin + the gateway.

**The Arc:** Phase 1 Reactive (largely complete) → **Phase 2 Self-maintaining (current)** →
Phase 3 Proactive collaborator → Phase 4 Trusted autonomous agent. Autonomy rides on the
pillars; it does not replace them.

---

## 2. Subsystem map

**Topology.** Two Raspberry Pi 5s: `huginmunin` (Pi 1) runs the service constellation; Pi 2 is
the NAS running Mimir + backups. Inference nodes on the tailnet: the BosGame M5
(`inference.gille.ai`, gateway :8080 + llama-swap :8091 + capability ledger), an Orin Nano, and
the laptop (intermittent). Services bind loopback; ingress is Cloudflare Tunnel with two-layer
auth (CF Access at the edge + per-service Bearer at origin); Tailscale carries internal traffic.

| Component | Host | Role | State (2026-07-09) |
|---|---|---|---|
| **Munin** | Pi 1 :3030 | Persistent memory (MCP + HTTP, FTS5 + vectors) | Mature (5/5 in gap analysis); OAuth 2.1 + Bearer; the system's strongest asset |
| **Hugin** | Pi 1 :3032 | Task dispatcher / policy-and-routing gateway | Deployed; gating + injection/exfil scanners; provenance unsigned; OpenCode adapter path active |
| **Heimdall** | Pi 1 :3033 | Monitoring dashboard | Deployed; collects fleet metrics; critical alerts are display-only (no push) |
| **Ratatoskr** | Pi 1 :3034 | Telegram router + concierge | Deployed; `/repo` hardening live-validated 2026-07-08; still hardcodes Anthropic SDK (no gateway routing) |
| **Skuld** | Pi 1 timer | Daily briefing synthesizer | SSOT drift: declared in services.json, not actually running; revive-or-cut decision pending (grimnir#69) |
| **Verdandi** | Pi 1 :3036 | Audit log (hash-chained, redact-before-persist) | Live with 67k+ events, but loopback-only — no off-Pi intake, laptop Claude Code is the only emitter |
| **Mimir** | Pi 2 :3031 | Authenticated file server | Deployed; hourly backup rsync; rsync ingest path unscanned for secrets (mimir#13) |
| **Brokkr** | Pi 1 timers | Substrate: OS patching, deps, health | Live; off-box dead-man check merged, not yet deployed/drilled |
| **noxctl** | laptop | Fortnox accounting CLI/MCP | 0.4.0 shipped; healthy |
| **M5 gateway** | M5 :8080 | OpenAI-compatible front door + ledger + admission control | Production-grade; measured delegation savings; `/delegate` and `code_loop` in daily use |

**Cross-cutting layers:**

- **Tenant contract** (`tenant-contract.md`) — the four seams any acting agent must satisfy:
  **A** Munin (auth'd memory access), **B** gateway (ledger-routed inference), **C** Hugin safety
  gating + provenance, **D** Verdandi audit emission. Validated 2026-07-04 with Codex CLI as a
  real non-Claude tenant: A/B/C **transports passed** (the substrate is genuinely
  model-agnostic), but **per-tenant identity is missing at every seam** and Seam D is
  unreachable off-Pi.
- **Threat model** (v0.1, T1–T11) — residual-High today: T1/T2 exfiltration via the lethal
  trifecta (autonomous and interactive paths), T4 unattributable autonomous action, T7
  unencrypted data at rest, T9 untested backup/restore. (T3, Ratatoskr command injection, was
  substantially closed by the 2026-07-08 hardening validation.)
- **Observability loop** (`observability-and-improvement.md`) — trace → score → reflect →
  improve. Trace capture and heuristic scoring are the contract; the reflect/improve stages are
  designed but largely unbuilt.
- **Failure recovery** (`failure-recovery.md`) — every autonomous mutation leaves a reversal
  recipe + audit event. Convention defined; adoption across components is thin.

---

## 3. Where the system actually stands

**Strong:** Munin, the M5 inference substrate (gateway, ledger, eval crons, measured savings),
noxctl, the security perimeter (CF Access, tunnel auth, timing-safe compares), and — as of this
week — registry validation green (7 ok / 0 issues), Ratatoskr hardened and live-validated, and
a completed harness bake-off giving a concrete Claude-decoupling path (OpenCode for the Hugin
coding lane, Goose as general worker).

**The dominant failure pattern** (gap analysis, still true): the **half-open loop** — evidence
emitted that nothing reads, or loops designed that nothing feeds. The emit→consume→decide arc
completes almost nowhere. Concretely: the ledger learns but Hugin's routing barely consumes it
and no production workload feeds it; grimnir-validate has written daily results since April
that nothing reads; Heimdall alerts don't notify anyone; ~1,500 green tests exist but 7 of 10
repos have no CI to run them; Verdandi records everything the laptop does and nothing the
autonomous system does.

**The single most-blocked thread:** grimnir#58 (tenant-contract validation) is blocked on
verdandi#15 (no off-Pi audit intake, no per-tenant key mint). The same missing identity spine
shows up independently as munin-memory#191 (writes attributed to "owner"), hugin#146 (task
provenance self-reported, unsigned), and gille-inference#152 (ledger can't attribute keys).

**Pending owner decisions** (the "now" cluster, decision brief 2026-07-07): succession (#65),
data lifecycle/retention (#66), system ROI + off-ramp (#67), Skuld revive-or-cut (#69),
interactive-session trust posture (#70).

---

## 4. Top 5 priorities

Ranked by vision-centrality × risk reduction × unblocking effect. Each is a coherent program,
not a single ticket.

### P1 — Build the tenant trust spine: identity, provenance, enforced gating, reachable audit

**What:** Give every tenant a distinct credential at all four seams and make the safety gate
preventive, not detective. Concretely: verdandi#15 (off-Pi intake + per-tenant key mint) →
hugin#146 (signed task provenance, Seam C) → hugin#148 (Hugin actually emits to Verdandi) →
munin-memory#191 (per-tenant attribution on writes) → gille-inference#152 (key alias in ledger)
→ hugin#149 (gating enforcement / remove unconditional `bypassPermissions`, T1). Then rerun the
grimnir#58 Seam-D validation and update `tenant-validation-2026-07-04.md`.

**Why first:** This is the thesis sentence — "*any agent* can *safely* act through" — and it is
currently unproven on exactly the safety half. It closes two residual-High threats at once (T1
exfiltration on the autonomous path, T4 unattributable action), it is the explicitly named
blocker in project status, and it is the prerequisite for every Phase 3 trust decision. Five
repos' worth of cross-filed tickets already converge here; the work is specified, not open-ended.

### P2 — Make the sovereign core survivable: tested restore, encryption at rest, off-box dead-man

**What:** brokkr#39 (off-site backup + an actually *tested* restore — the NAS is a single point
of data loss), brokkr#40 (encryption at rest on Pi SD cards + NAS), deploy and drill the merged
off-box dead-man check (brokkr#41 / T8), heimdall#101 (last-push heartbeat that feeds it), and
deploy the merged Verdandi hash-chain checkpoint cadence (verdandi#17, T5).

**Why:** Pillar 1's entire justification is "the asset that cannot be bought back" — yet today a
single disk failure loses it (T9, restore never tested) and a stolen SD card leaks it in
plaintext (T7). Three of the five residual-High threats live here. This is bounded, mostly
mechanical work with no dependencies on anything else, and nothing else in the roadmap matters
if the substrate itself is one incident from unrecoverable.

### P3 — Close Pillar 2's learning loop with real production workload

**What:** Finish the Hugin **OpenCode HarnessAdapter** (the active thread from the bake-off:
gate/provenance → adapter → normalized events → Munin trace + Verdandi event), route at least
one always-on production workload through the gateway so the ledger learns from real traffic
(Ratatoskr triage is the named candidate — ratatoskr#27 also delivers the triage-offloadability
dataset), and give the routing table writers: gille-inference#145 (auto-regenerate
`m5-routing.json` from ledger + cartography). Supporting: hugin#157 (queue/retry when M5 busy).

**Why:** The vision calls self-knowing inference "Grimnir's most original idea, a first-class
pillar" — and the gap analysis found its learning loop severed at both ends: the ledger is real
but no production workload feeds it, and "the learned model of what to route where" is a
hand-edited file that doesn't learn. The harness adapter simultaneously delivers the
Claude-decoupling the bake-off recommended, so one program advances both the pillar and tenant
replaceability.

### P4 — Decide the "now" cluster in one owner sitting, then write the five small docs

**What:** The decision brief has already reduced grimnir#65/#66/#67/#69/#70 to one explicit
owner choice each: name the succession delegate(s) + goal (#65); pick default retention windows
for four data classes (#66); set the service exit threshold (#67); choose Skuld four-week trial
vs. cut now (#69); choose the interactive-session friction level (#70). Then split the brief
into the five planned artifacts (succession checklist, data-lifecycle map, ROI/off-ramp section,
Skuld decision record, interactive-posture note) and start the first monthly ROI ledger entry.

**Why:** Highest value-per-effort item on the board — the analysis is done and only decisions
block execution. It covers the remaining residual-High threat (T2, interactive-session
trifecta — the one exposure Hugin's gating can't fix), T11 (third-party data without a map),
and the bus-factor risk that is existential for a one-operator sovereign system. Every week
undecided is a week the queued follow-on docs and the Skuld question stay stalled.

### P5 — Make Phase 2 real: close the self-maintenance loop (CI, alerts that notify, evidence that gets read)

**What:** Minimal CI across the 7 repos that have none (verdandi#11, ratatoskr#28, skuld#4,
mimir#14, heimdall#104, brokkr#26, grimnir#48 — the gap analysis's "single biggest Phase-2
unlock"); heimdall#112 (push alert-engine reds to Telegram — monitoring that actually
notifies); grimnir#2 (delta-alert on the validate runs that have been written unread since
April); hugin#147 (enable the installed-but-never-activated daily-analysis timer); grimnir#63
(validate's user-scope false reports). Fold in the small sovereignty seam fixes as touched:
skuld#3 (direct SQLite into Munin) and mimir#13 (secret-scan the rsync ingest).

**Why:** Grimnir claims Phase 2 — "keeps itself healthy without being asked" — but the system
cannot currently notice its own failures: tests gate nothing, alerts reach no one, and its own
validation evidence goes unread. This is the causal parent of the incidents the gap analysis
documented (poisoned registry, silent drift, lying READMEs). Closing it is what makes the other
four programs *stay* fixed.

---

## 5. Deliberately not in the top 5

- **munin-memory#192** (memory correction/forgetting, T10) — real, but sequenced after the #66
  retention decisions, which shape it.
- **Security tier grimnir#9–18** — keep on the weekly sweep; grimnir#9 (verify rotation of the
  leaked Anthropic key) is a quick standalone check worth doing opportunistically.
- **Mimir revival details** (mimir#11/#12) and Heimdall dashboard polish (#110, #97, #93…) —
  worthwhile, small, not load-bearing; several fold naturally into P5.
- **Skuld phases 4–5, Ratatoskr photo/voice, Librarian/Sara onboarding** — Phase-3-flavored
  features; premature before P1/P4 settle trust and whether Skuld lives at all.
- **Hugin composition-mechanism convergence** (hugin#117) — needed eventually, but the vision
  caps Hugin as platform; don't invest ahead of the adapter work in P3.

---

*Assessment only — no tickets were modified and no work was started.*

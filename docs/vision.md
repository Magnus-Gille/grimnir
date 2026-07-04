# Grimnir — Vision

> **DRAFT v0.2** — 2026-06-29 (supersedes v0.1, 2026-03-28).
> Captures direction, not commitments. Companion to `architecture.md` (the *how*);
> this is the *why* and the *what-not-to-build*.

---

## The thesis

**Grimnir is a sovereign, self-knowing personal-AI substrate that any agent can safely act through.**

The substrate is the identity. The agent — the loop, the channels, the model — is a replaceable tenant. The market is pouring foundation-scale effort into that tenant layer (OpenClaw, nanoclaw, Hermes, the Claude Agent SDK) and commoditizing it toward zero. Racing there is a losing game and an unnecessary one.

As frontier models and agent harnesses both commoditize, the only scarce, personal, non-replicable assets left are *your* memory, *your* files, *your* accountability record, and *your* learned model of what to route where. **Grimnir owns that substrate and lets any agent plug into it.**

The older "autonomous collaborator" framing (v0.1) isn't wrong — it's the *roadmap of what Grimnir does* (see The Arc). But it isn't the *identity*. The identity is the substrate; autonomy is a capability that rides on top of it.

---

## The two protected pillars

These are the things Grimnir builds and never outsources. Everything else is a tenant.

### Pillar 1 — Sovereign Memory
*Munin (memory) · Mimir (files) · Verdandi (audit).*

Your data, your documents, and a tamper-evident record of what was done with them — on your hardware, auth at every layer, secrets scanned before persistence. The asset that cannot be bought back, shared by every environment (CLI, desktop, web, mobile, Telegram).

### Pillar 2 — Self-Knowing Inference
*M5 home-server gateway · capability ledger · offloadability eval.*

A system that *learns what it can trust cheaper compute with* and routes accordingly — data-grounded, not assumed. No external harness has this; it is Grimnir's most original idea, and a first-class pillar — not a side-experiment.

---

## The decision rule

> **Build only what touches Memory or Inference-routing. Reuse everything in the harness layer — provided it is open-source and plugs into Munin + the gateway.**

This replaces case-by-case "build vs buy" judgement. Ask one question: *does this touch a pillar?*

- **No** → reuse the best open-source option (the Claude Agent SDK today; a nanoclaw-style ingress tomorrow). Keep our own code small.
- **Yes** → build it, because it compounds personally and cannot be reacquired.

### Applied to the harness (Hugin)

Hugin is capped as an agent *platform* and deepened as the **policy-and-routing gateway to the sovereign core**:

| Concern | Pillar? | Stance |
|---|---|---|
| Agent loop | tenant | Reuse the Claude Agent SDK — never hand-roll |
| Channels | tenant | Cap (Telegram is enough); reuse ingress for more |
| Sub-agent fan-out | tenant | Borrow proven patterns; don't invent |
| Capability routing | **Inference** | **Deepen** — make it ledger-driven |
| Safety gating | **Memory** | **Own** — it makes tenants safe against our data |
| Munin task semantics | **Memory** | Keep — substrate glue |

---

## Founding principles

### Sovereignty
All data lives on Magnus's hardware. Cloud AI services are stateless tools — they process but don't store. The Pis and the M5 hold the database, the files, the ledger, and the backups. Non-negotiable.

### Privacy
Auth at every layer. Secrets scanned before storage. Sensitive documents get summaries in memory; full text stays on the box.

### Minimal surface, deep where it must be
*(Revised from v0.1's "Simplicity.")* Most components stay single-purpose and small — SQLite, systemd, no heavy frameworks. But the harness/routing core (Hugin, the gateway) is allowed real depth, because that is where safety and capability-routing live. The discipline is not "always simple"; it is "small everywhere we can, complex only at the two pillars, and never complex by accident."

### Self-knowing by design *(Pillar 1, as a build principle)*
> **Every component should emit evidence of its own competence, and decisions should be made from that evidence rather than from assumption.**

The ledger does this for model routing. The same shape applies to runtime selection, to which tasks are safe to auto-run, and to which of our own services are earning their keep. Instrument first; let the data say what to keep, cut, or route. `docs/observability-and-improvement.md` is the operational home of this principle.

### Cut bloat continuously
Capability that isn't earning its place — empty repos, duplicate services, stale experiments — is removed, not preserved out of sentiment. A smaller, sharper system is the goal, not a larger one. (Standing cut list: merge `hugin-orchestrator` into `hugin`; archive `hugin-munin`; delete `meta-agent` and `agentic-eval`; converge or retire `agent-council`.)

---

## The Arc

The substrate is what Grimnir *is*. The Arc is what it progressively *does* on top — the autonomy roadmap. Each phase rides on the two pillars; none of it replaces them.

### Phase 1: Reactive (largely complete)
*"Tell Grimnir to do X and go to sleep."* Memory, files, task dispatch, monitoring, briefings, mobile access. Human initiates everything.

### Phase 2: Self-maintaining
*"Grimnir keeps itself healthy without being asked."* Notices outdated dependencies and upgrades them; investigates failing health checks; spots patterns in its own data; fixes documentation drift. Human sets direction; Grimnir handles upkeep.

### Phase 3: Proactive collaborator
*"Grimnir does useful work on its own."* Identifies work worth doing — from project context, client commitments, calendar, financials — and does or proposes it. Magnus reviews output, not input.

### Phase 4: Trusted autonomous agent
*"Grimnir acts independently on things that matter."* Client deliverables, business operations, consulting output — meaningful action without prior approval on a growing set of domains, earned through phases 1-3.

---

## What this is *not*

- Not an agent framework competing with OpenClaw/Hermes/nanoclaw — we are a tenant of that ecosystem, not a rival.
- Not a cloud-token product — the opposite thesis (everything on our hardware).
- Not a maximalist constellation of services — each component earns its place or is consolidated away.

---

## Open questions

Answerable only through experience with the system, not upfront design.

### Trust model
At what point should Grimnir act without asking? What guardrails prevent an irreversible, wrong action? The right model emerges from accumulated evidence of reliability across phases 1-3.

### Signal design
What are the right optimization signals per component? Some are obvious (task success rate, latency); others are hard (did the briefing change behavior? was the autonomous fix correct?). Getting signals wrong optimizes for the wrong thing.

### Reuse boundaries
Which open-source harness do we actually adopt for ingress/loop when we outgrow Telegram-only (nanoclaw fork vs. OpenClaw-as-ingress vs. status quo)? The decision rule says *reuse* — but which, and how does it plug into Munin + the gateway without leaking sovereignty?

### Scope boundaries
Where does Grimnir stop? Draft-for-review vs. direct client communication? Read-only vs. write access to financial systems? Boundaries shift as trust accumulates.

### Failure recovery
When Grimnir acts autonomously and gets it wrong, what happens? It must undo its own mistakes, or at least make them visible before they propagate — prerequisite for phases 3-4. The minimal convention (reversal recipe + Verdandi event) is defined in [`failure-recovery.md`](failure-recovery.md); what remains open is *when* to actually trigger a rollback, not how to make one possible.

---

*Built by Magnus Gille, with Claude and Codex. Running on two Raspberry Pis and a BosGame M5 in Mariefred, Sweden.*

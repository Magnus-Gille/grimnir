# Grimnir — Vision

> **DRAFT v0.1** — 2026-03-28. This document is a working draft.
> It captures direction, not commitments.

---

## North Star

Grimnir is an autonomous collaborator that improves itself and does useful work — both when prompted and on its own.

It starts by maintaining its own infrastructure. It graduates to doing real work: client deliverables, consulting output, business operations. The end state is a system that Magnus trusts to act independently on things that matter.

## Founding Principles

### Sovereignty
All data lives on Magnus's hardware. Cloud AI services are stateless tools — they process but don't store. The Pis hold the database, the files, and the backups. This is non-negotiable.

### Privacy
Auth is required at every layer. Secrets are scanned before storage. Sensitive documents get summaries in memory but full text stays on the Pi.

### Simplicity
Each service is single-purpose. No heavy frameworks. SQLite for storage. systemd for process management. If it can't run on a Raspberry Pi, it's too complex.

### Autonomous improvement by design
Every component should have a measurable signal it can optimize toward. Autonomous improvement is not a feature bolted on later — it is a structural property of every service we build. When designing a new capability, the question is always: *"What signal tells us this is working well, and how could the system use that signal to get better on its own?"*

## The Arc

### Phase 1: Reactive (largely complete)
*"Tell Grimnir to do X and go to sleep."*

Memory, files, task dispatch, monitoring, briefings, mobile access. The system does what it's told and reports back. Human initiates everything.

### Phase 2: Self-maintaining
*"Grimnir keeps itself healthy without being asked."*

The system notices when dependencies are outdated and upgrades them. It detects failing health checks and investigates. It spots patterns in its own data and proposes optimizations. It identifies documentation drift and fixes it.

Human still sets direction. Grimnir handles upkeep.

### Phase 3: Proactive collaborator
*"Grimnir does useful work on its own."*

The system identifies work worth doing — from project context, client commitments, calendar, financial data — and either does it or proposes it. It drafts, it researches, it prepares. Magnus reviews output, not input.

### Phase 4: Trusted autonomous agent
*"Grimnir acts independently on things that matter."*

Client deliverables. Business operations. Consulting output. The system has earned enough trust through phases 1-3 that it can take meaningful action without prior approval on a growing set of domains.

## Open Questions

These are not gaps to fill before starting — they are questions that can only be answered through experience with the system.

### Trust model
At what point should Grimnir act without asking? What guardrails prevent it from doing something irreversible and wrong? The current model requires explicit human initiation (submit a task) or human-in-the-loop (Ratatoskr clarifies intent). The right trust model will emerge from accumulated evidence of reliability across phases 1-3 — not from upfront design.

### Signal design
What are the right optimization signals for each component? Some are obvious (task success rate, query latency). Others are harder (did the briefing change Magnus's behavior? was the autonomous fix correct?). Getting signals wrong could optimize for the wrong thing.

### Scope boundaries
Where does Grimnir stop? Should it touch client-facing communication directly, or always draft for review? Should it have access to financial systems beyond read-only? These boundaries will shift as trust accumulates.

### Failure recovery
When Grimnir acts autonomously and gets it wrong, what happens? The system needs to be able to undo its own mistakes, or at minimum make them visible before they propagate. This is prerequisite for phases 3-4.

---

*Built by Magnus Gille, with Claude and Codex. Running on two Raspberry Pis in Mariefred, Sweden.*

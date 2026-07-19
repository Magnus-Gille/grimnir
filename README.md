# Grimnir

Personal AI infrastructure that gives Claude persistent memory, file access, and autonomous task execution across every environment — from a phone on the bus to a terminal at the desk.

Runs on two Raspberry Pis, a MacBook, and a local M5 inference box. All data stays on your hardware.

## Components

| Component | Role | Repo |
|-----------|------|------|
| **Munin** | Persistent memory (MCP server with FTS5 + vector search) | [munin-memory](https://github.com/Magnus-Gille/munin-memory) |
| **Hugin** | Autonomous task dispatcher | [hugin](https://github.com/Magnus-Gille/hugin) |
| **Mimir** | Authenticated file server | [mimir](https://github.com/Magnus-Gille/mimir) |
| **Heimdall** | Monitoring dashboard | [heimdall](https://github.com/Magnus-Gille/heimdall) |
| **Ratatoskr** | Telegram message router | [ratatoskr](https://github.com/Magnus-Gille/ratatoskr) |
| **Skuld** | Daily intelligence briefing | [skuld](https://github.com/grimnir-bot/skuld) |
| **Verdandi** | Tamper-evident audit log | [verdandi](https://github.com/Magnus-Gille/verdandi) |
| **noxctl** | Fortnox accounting CLI + MCP | [fortnox-mcp](https://github.com/Magnus-Gille/fortnox-mcp) |
| **Brokkr** | Platform / substrate — hardware park, OS, storage, network, backups | [brokkr](https://github.com/Magnus-Gille/brokkr) |

Brokkr is the **substrate layer** the others run on (peer to this repo, not a service): it owns the boxes, their OS, the NAS backup disk + Time Machine, and hardware-level health. The hardware inventory itself stays canonical in [`services.json`](services.json) (`nodes`).

All components are named after figures from Norse mythology. See [docs/conventions.md](docs/conventions.md) for the naming guide.

## This repo

This is the system-level documentation and operations repository. No service code lives here — each component has its own repo.

What's here:

- **[docs/architecture.md](docs/architecture.md)** — Full system architecture (topology, components, security, data flow)
- **[docs/conventions.md](docs/conventions.md)** — Naming, ports, service patterns, GitHub ownership
- **[docs/vision.md](docs/vision.md)** — Where the project is heading
- **[docs/learning-task-contract.md](docs/learning-task-contract.md)** — Versioned Hugin↔M5 learning-evidence seam, field ownership, compatibility, and measurable loop milestones
- **[docs/learning-task-contract-v1.schema.json](docs/learning-task-contract-v1.schema.json)** — Canonical discriminated JSON Schema for the seven v1 evidence/accounting record kinds
- **[docs/observability-and-improvement.md](docs/observability-and-improvement.md)** — Current three-plane self-improvement architecture and ordered roadmap
- **[docs/adr-006-learning-improvement-scope.md](docs/adr-006-learning-improvement-scope.md)** — Proposed, component-review-gated decision that v1 improves routing/rosters/prompts/harnesses, not model weights
- **[docs/roadmap-now-decision-brief.md](docs/roadmap-now-decision-brief.md)** — Index of the adopted owner decisions for succession, data lifecycle, ROI/off-ramp, Skuld, and interactive-session trust
- **[docs/succession-checklist.md](docs/succession-checklist.md)** — Non-secret emergency export-and-shutdown procedure
- **[docs/data-lifecycle.md](docs/data-lifecycle.md)** — Practical store, retention, correction, and erasure map
- **[docs/interactive-session-posture.md](docs/interactive-session-posture.md)** — Hugin/fresh-session handoff after untrusted input
- **[docs/agent-harness-bakeoff-2026-07-08.md](docs/agent-harness-bakeoff-2026-07-08.md)** — Evidence note on open-source, model-agnostic agent harnesses for moving Hugin/Grimnir beyond Claude-only execution
- **[services.json](services.json)** — Single source of truth for the component inventory (`components`) and the infrastructure/inference-node inventory (`nodes` — hosts, hardware, role, LLM servers). Query via `scripts/lib/registry.js` (`QUERY=nodes`).
- **[scripts/](scripts/)** — Deploy, security scan, and architecture generation scripts

## Design principles

- **Sovereignty** — All data lives on your hardware. Cloud AI services process but don't store.
- **Simplicity** — Single-purpose Node.js services. SQLite for storage. systemd for process management. No Kubernetes, no heavy frameworks.
- **Privacy** — Auth at every layer. Secrets scanned before storage. Sensitive documents summarized in memory, full text stays on the Pi.

## License

This is a personal infrastructure project. The documentation is public for reference; the architecture is specific to one operator.

---

*Built by Magnus Gille, with Claude and Codex. Running on local hardware in Mariefred, Sweden.*

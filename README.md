# Grimnir

Personal AI infrastructure that gives Claude persistent memory, file access, and autonomous task execution across every environment — from a phone on the bus to a terminal at the desk.

Runs on two Raspberry Pis and a MacBook. All data stays on your hardware.

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

All components are named after figures from Norse mythology. See [docs/conventions.md](docs/conventions.md) for the naming guide.

## This repo

This is the system-level documentation and operations repository. No service code lives here — each component has its own repo.

What's here:

- **[docs/architecture.md](docs/architecture.md)** — Full system architecture (topology, components, security, data flow)
- **[docs/conventions.md](docs/conventions.md)** — Naming, ports, service patterns, GitHub ownership
- **[docs/vision.md](docs/vision.md)** — Where the project is heading
- **[services.json](services.json)** — Single source of truth for component inventory
- **[scripts/](scripts/)** — Deploy, security scan, and architecture generation scripts

## Design principles

- **Sovereignty** — All data lives on your hardware. Cloud AI services process but don't store.
- **Simplicity** — Single-purpose Node.js services. SQLite for storage. systemd for process management. No Kubernetes, no heavy frameworks.
- **Privacy** — Auth at every layer. Secrets scanned before storage. Sensitive documents summarized in memory, full text stays on the Pi.

## License

This is a personal infrastructure project. The documentation is public for reference; the architecture is specific to one operator.

---

*Built by Magnus Gille, with Claude and Codex. Running on two Raspberry Pis in Mariefred, Sweden.*

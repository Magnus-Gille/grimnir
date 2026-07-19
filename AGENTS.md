# Grimnir — project instructions

## What this is

This is the **system-level** documentation repository for the Grimnir personal AI infrastructure. It
contains architecture docs, conventions, and cross-project references.

No service code lives here — each component has its own repo.

This file is the canonical project guidance for all supported agent harnesses. Put portable
changes here; `CLAUDE.md` is only a Claude Code import adapter.

## Agent workflow

- Read ignored `STATUS.md` first when it exists; otherwise use `PROJECT_STATUS.md` for public project
  state.
- Treat `services.local.json` as the private deployment authority when present. The committed
  `services.json` is fictional schema/reference data and is blocked from deployment. See
  `docs/authority.md` for the wider authority map.
- Keep component implementation changes in their owning repositories. Grimnir changes should be
  system-level documentation, registry, deployment orchestration, or cross-component validation.
- Run `make test` for repository changes. Run `shellcheck scripts/*.sh scripts/lib/*.sh
  scripts/tests/*.sh` when shell code changes.
- Do not place credentials, recovery material, private-envelope contents, or private locators in
  git.

## Component repos

> The public component inventory is defined in [`services.json`](services.json). A real installation
> uses ignored `services.local.json` or an explicit `REGISTRY_PATH`.

| Component | Repo | Role |
|-----------|------|------|
| Munin Memory | `munin-memory` | Persistent memory MCP server |
| Hugin | `hugin` | Task dispatcher |
| Mimir | `mimir` | Authenticated file server |
| Heimdall | `heimdall` | Monitoring dashboard |
| gille-inference | `gille-inference` | OpenAI-compatible local inference gateway |
| Ratatoskr | `ratatoskr` | Telegram router + concierge |
| Skuld | `skuld` (optional integration) | Daily intelligence briefing |
| Brokkr | `brokkr` | Platform/substrate layer — hardware, OS, storage, backups (peer, not a service) |

## Key documents

- `docs/architecture.md` — Full system architecture guide (topology, components, security, data flow)
- `docs/full-architecture.md` — Ignored, auto-generated deployment snapshot (run `make docs` on a
  configured host)
- `docs/conventions.md` — Naming, GitHub ownership, service patterns
- `docs/observability-and-improvement.md` — How components capture traces, score outputs, and feed the
  self-improving loop
- `docs/learning-task-contract.md` — Normative Hugin↔M5 learning-evidence seam: field and decision
  owners, privacy/evolution rules, cross-repo fixtures, and measurable definitions of continuous
- `docs/learning-task-contract-v1.schema.json` — Canonical machine-readable v1 union schema; positive
  and adversarial fixtures live under `tests/fixtures/learning-task-contract/`
- `docs/adr-006-learning-improvement-scope.md` — Why v1 improves routes, rosters, prompts, harnesses, and tool
  policy while model-weight training remains a separately gated future program
- `docs/tenant-contract.md` — The minimal agent↔substrate contract any agent must satisfy to act
  through the substrate (Munin access, gateway routing, safety gating, audit emission) plus a cheap
  validation plan
- `docs/failure-recovery.md` — The autonomous-mutation undo convention: every autonomous mutation
  leaves a reversal recipe (`git_revert`, snapshot, or irreversible plus mitigation) and an audit
  event (issue #46)
- `docs/threat-model.md` — Consolidated threat model (v0.1): assets, trust boundaries, adversaries,
  and a T1–T11 key-threats table mapped to owning tickets (from the 2026-07-06 blind-spot audit)
- `docs/succession-checklist.md` — Public, non-secret export-and-shutdown checklist for the emergency
  delegate; private-envelope contents stay out of git
- `docs/data-lifecycle.md` — Store-by-store retention, correction, erasure, and backup-expiry map
- `docs/interactive-session-posture.md` — Required Hugin handoff (or constrained fresh-session
  fallback) for consequential mutations after untrusted input
- `services.json` — Safe public example of the component and node registry schema

## Scripts

| Script | Purpose | Run with |
|--------|---------|----------|
| `scripts/deploy.sh` | Deploy services to Linux hosts (all or selective) | `DEPLOY_USER=operator make deploy ARGS="munin-memory"` |
| `scripts/generate-architecture.sh` | Generate deployment snapshot + full-architecture.md | `make docs` (Pi only) |
| `scripts/security-scan.sh` | Scan all repos for vulnerabilities and secrets | `make security` |

> OS patching (`setup-host-patching.sh`) and maintenance reports (`maintenance-report.sh`) have moved
> to the `brokkr` repo. Use `make patching` / `make maintenance-os` / `make maintenance-deps` from
> `brokkr/`.

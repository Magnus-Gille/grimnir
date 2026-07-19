# Grimnir — project instructions

## What this is

This is the **system-level** documentation repository for the Grimnir personal AI infrastructure. It
contains architecture docs, conventions, and cross-project references.

No service code lives here — each component has its own repo.

This file is the canonical project guidance for all supported agent harnesses. Put portable
changes here; `CLAUDE.md` is only a Claude Code import adapter.

## Agent workflow

- Read `STATUS.md` first for current execution state and resumption context.
- Treat `services.json` as the component-inventory authority; see `docs/authority.md` for the wider
  authority map.
- Keep component implementation changes in their owning repositories. Grimnir changes should be
  system-level documentation, registry, deployment orchestration, or cross-component validation.
- Run `make test` for repository changes. Run `shellcheck scripts/*.sh scripts/lib/*.sh
  scripts/tests/*.sh` when shell code changes.
- Do not place credentials, recovery material, private-envelope contents, or private locators in
  git.

## Component repos

> Component inventory (names, hosts, ports, systemd units) is defined in [`services.json`](services.json).
> All scripts read from it — see `docs/authority.md` for the authority map.

| Component | Repo | Role |
|-----------|------|------|
| Munin Memory | `munin-memory` | Persistent memory MCP server |
| Hugin | `hugin` | Task dispatcher |
| Mimir | `mimir` | Authenticated file server |
| Heimdall | `heimdall` | Monitoring dashboard |
| Ratatoskr | `ratatoskr` | Telegram router + concierge |
| Skuld | `skuld` (grimnir-bot org) | Daily intelligence briefing |
| Fortnox MCP | `fortnox-mcp` | Accounting CLI + MCP |
| Brokkr | `brokkr` | Platform/substrate layer — hardware, OS, storage, backups (peer, not a service) |

## Key documents

- `docs/architecture.md` — Full system architecture guide (topology, components, security, data flow)
- `docs/full-architecture.md` — Ignored, auto-generated comprehensive doc (run `make docs` or
  `scripts/generate-architecture.sh` on the Pi to regenerate a local snapshot)
- `docs/conventions.md` — Naming, GitHub ownership, service patterns
- `docs/role-separation.md` — Why the canonical grimnir checkout must not double as a deploy target
  or hugin workspace, and the validate check that alarms on drift (issue #47)
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
- `docs/tenant-validation-2026-07-04.md` — Evidence note from the first real non-Claude tenant run
  (Codex CLI, grimnir#58): seams A/B/C passed on transport, D blocked, per-tenant identity missing
  everywhere; harness in `scripts/tenant-validation/`
- `docs/failure-recovery.md` — The autonomous-mutation undo convention: every autonomous mutation
  leaves a reversal recipe (`git_revert`, snapshot, or irreversible plus mitigation) and an audit
  event (issue #46)
- `docs/gap-analysis-2026-07-03.md` — Critic-corrected ecosystem gap analysis vs vision v0.2: ranked
  gaps, quick wins, cut list, and corrections log (the source of the 23-ticket fleet program)
- `docs/threat-model.md` — Consolidated threat model (v0.1): assets, trust boundaries, adversaries,
  and a T1–T11 key-threats table mapped to owning tickets (from the 2026-07-06 blind-spot audit)
- `docs/roadmap-now-decision-brief.md` — Index of the adopted "now" decisions: succession (#65),
  GDPR/data lifecycle (#66), system ROI/off-ramp (#67), Skuld revive-or-cut (#69), interactive-session
  trust posture (#70), and the #58 Verdandi blocker
- `docs/succession-checklist.md` — Public, non-secret export-and-shutdown checklist for the emergency
  delegate; private-envelope contents stay out of git
- `docs/data-lifecycle.md` — Store-by-store retention, correction, erasure, and backup-expiry map
- `docs/interactive-session-posture.md` — Required Hugin handoff (or constrained fresh-session
  fallback) for consequential mutations after untrusted input
- `docs/skuld-trial-decision.md` — 28-day evidence record and keep/cut gate for the Skuld briefing
  producer
- `docs/agent-harness-bakeoff-2026-07-08.md` — Evidence note on open-source, model-agnostic agent
  harnesses. Goose and OpenCode both completed M5-backed edit/test loops; OpenCode is the recommended
  first Hugin coding-lane adapter, Goose the general-worker candidate.
- `services.json` — **Single source of truth** for component inventory (names, hosts, ports, systemd
  units). All scripts read from it via `scripts/lib/registry.js`

## Scripts

| Script | Purpose | Run with |
|--------|---------|----------|
| `scripts/deploy.sh` | Deploy services to Pi hosts (all or selective) | `make deploy` or `make deploy ARGS="munin-memory"` |
| `scripts/generate-architecture.sh` | Generate deployment snapshot + full-architecture.md | `make docs` (Pi only) |
| `scripts/security-scan.sh` | Scan all repos for vulnerabilities and secrets | `make security` |

> OS patching (`setup-host-patching.sh`) and maintenance reports (`maintenance-report.sh`) have moved
> to the `brokkr` repo. Use `make patching` / `make maintenance-os` / `make maintenance-deps` from
> `brokkr/`.

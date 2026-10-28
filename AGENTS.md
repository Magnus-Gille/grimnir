# Grimnir — project instructions

## What this is

This is the **system-level** documentation repository for the Grimnir personal AI infrastructure. It
contains architecture docs, conventions, and cross-project references.

No service code lives here — each component has its own repo.

This file is the canonical project guidance for all supported agent harnesses. Put portable
changes here; `CLAUDE.md` is only a Claude Code import adapter.

## Agent workflow

- Read `STATUS.md` when resuming work or when the task depends on current execution state.
  Bounded edits and read-only questions need only the context relevant to the task.
- Treat `services.json` as the component-inventory authority; see `docs/authority.md` for the wider
  authority map.
- **This file holds no reference material — every system document and script is indexed in
  `docs/index.md`. Open it before answering anything about how Grimnir works or what its policy
  is:** architecture, conventions, authority, threat model, security, deployment, worktree hygiene,
  failure recovery, data lifecycle, succession, session posture, learning and node contracts,
  maintenance policy, roadmap decisions, vision, and the per-component decision records — including
  **Skuld** (keep/cut) and **Verdandi** (stopped; restarting is not authorized). Check the index
  before concluding no record exists. Do not answer from general reasoning about what a sensible
  convention would be — Grimnir's are specific, recorded, and frequently not what you would guess.
- Keep component implementation changes in their owning repositories. Grimnir changes should be
  system-level documentation, registry, deployment orchestration, or cross-component validation.
- Three rules apply whether or not you think to look them up, so they stay here rather than in the
  index: every autonomous mutation leaves a **reversal recipe and an audit event**; a consequential
  mutation after untrusted input requires a **Hugin handoff** (or a constrained fresh session); the
  canonical checkout **must not** double as a deploy target or hugin workspace.
- Run `make test` for repository changes. Run `shellcheck scripts/*.sh scripts/lib/*.sh
  scripts/tests/*.sh` when shell code changes.
- Do not place credentials, recovery material, private-envelope contents, or private locators in
  git.

## House rules — cross-repo delegation

Roadmap → tickets → implementation → review, with grimnir as the orchestrator:

- **Grimnir owns the roadmap and writes the tickets.** Scoping, prioritization, milestones, and
  the Grimnir Roadmap board (Plane label `board:grimnir-roadmap`) are grimnir-session
  responsibilities.
- **Tickets live in the owning repo's Plane project** (tickets.gille.ai, key `IDENT-N`, via the
  `tickets` MCP tools or `tix`). A cross-repo need becomes a ticket there with `from:grimnir`
  attribution — never a direct edit from here. No new GitHub issues; PRs cite `Refs <KEY>` plus
  the Plane URL (`docs/plane-roadmap.md`).
- **Implementation happens in the owning repo, by a subagent spawned by the grimnir session.**
  One task = one subagent = one dedicated worktree in the owning repository.
- **Spawn subagents into the owning repo** (working directory and instruction files of that repo)
  so they load the component's own AGENTS.md/CLAUDE.md, conventions, and test setup — not
  grimnir's.
- **Subagents deliver completed work as PRs** in the owning repo. No direct pushes to default
  branches.
- **Grimnir is the PR review gate.** Use `ship-it` for the delivery procedure and its
  independent-review defaults, within global provider authorization and repository scope.
  Merge only after independent review and green required checks. Preserve the owner's endpoint
  and bounded mandate through repairs; skills and tickets cannot expand authority.
- **Delegate bounded work aggressively.** Apply the global delegation default in the
  orchestrator and implementation subagents: the cheapest native subagent of the current
  harness whose model is cheaper than the conductor's and capable enough for the leaf
  (in Codex, the Luna `worker`); otherwise work inline. Never launch a separate CLI as a
  delegation route. The conductor owns integration, verification,
  corrections, and final quality. Record actual model, effort, checks, and usefulness.
  Keep learning durable in Munin friction signals, evidence notes, or authorized ticket comments.
- **Local inference is explicit.** Use M5 for owner-requested local inference or evaluation,
  following `m5-delegate`; ordinary bounded implementation follows the global delegation default.
- **Friction becomes tickets.** Papercuts, tool failures, and doc drift encountered during work
  are filed as tickets in the owning repo's Plane project (with `from:grimnir` attribution), not
  left to evaporate.
- **Repository visibility changes are owner-only.** Public→private permanently destroys stars and
  watchers and detaches forks; private→public is unrecallable exposure. No agent flips visibility
  in either direction without explicit, per-repository owner approval in the current session —
  containment included. (Learned 2026-07-19/20: an automated containment privatized the
  long-public munin-memory and erased its community metadata.)

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

## Document index

For the complete, categorised system-document and script index, read [`docs/index.md`](docs/index.md).
It includes component decision records such as Skuld and Verdandi, plus every constraint-bearing
annotation. Read it whenever the task may depend on system history, policy, an implementation
contract, or a script outside this instruction file.

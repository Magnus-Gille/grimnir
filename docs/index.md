# Document index

Every system-level document in this repository, with enough description to tell whether it
answers your question. `AGENTS.md` links here rather than inlining this list, so the list can
grow without adding cost to every session.

Annotations that carry a constraint — not just a location — are preserved here verbatim. Read
the annotation, not only the filename.

## Architecture and conventions

- `docs/architecture.md` — Full system architecture guide (topology, components, security, data flow)
- `docs/full-architecture.md` — Ignored, auto-generated comprehensive doc (run `make docs` or
  `scripts/generate-architecture.sh` on the Pi to regenerate a local snapshot)
- `docs/conventions.md` — Naming, GitHub ownership, service patterns
- `docs/authority.md` — The authority map: which file is the source of truth for what
- `services.json` — **Single source of truth** for component inventory (names, hosts, ports, systemd
  units). All scripts read from it via `scripts/lib/registry.js`
- `docs/network-operating-model.md` — How the network is operated
- `docs/node-substrate-contract.md` and `docs/adr-007-node-substrate-contract.md` — The node↔substrate
  contract and the ADR behind it; machine-readable schema in
  `docs/node-substrate-contract-v1.schema.json`

## Roles, deployment, and hygiene

- `docs/role-separation.md` — Why the canonical grimnir checkout must not double as a deploy target
  or hugin workspace, and the validate check that alarms on drift (issue #47)
- `docs/worktree-hygiene.md` — Multi-agent worktree/deployment hygiene protocol: stale/dirty/orphaned
  worktree detection, canonical-checkout and deploy-target role violations, non-destructive
  remediation recipes, and how to run the audit (`scripts/worktree-hygiene-audit.sh`, issue #87)
- `docs/deployment-source-binding.md` — Binding deploys to an explicit worktree + revision
- `docs/systemd-runtime-rendering.md` — How systemd units are rendered at runtime
- `docs/placement-validation.md` — Validating desired placement against explicit Brokkr
  observations; schema in `docs/placement-validation-v1.schema.json`
- `docs/scheduled-tasks.md` — Scheduled task conventions
- `docs/maintenance-policy-contract.md` — Versioned, intent-only `maintenance-policy`/`maintenance-decision`
  contract for unattended substrate upkeep (selectors, IANA timezone/DST, windows, missed-window/overdue/
  maximum-deferral decision rules, deterministic policy digest); machine schema
  `docs/maintenance-policy-v1.schema.json`, fixtures and validator under
  `tests/fixtures/maintenance-policy` and `tests/scripts/validate-maintenance-policy-contract.mjs`
- `docs/failure-recovery.md` — The autonomous-mutation undo convention: every autonomous mutation
  leaves a reversal recipe (`git_revert`, snapshot, or irreversible plus mitigation) and an audit
  event (issue #46)

## Learning and improvement loop

- `docs/observability-and-improvement.md` — How components capture traces, score outputs, and feed the
  self-improving loop
- `docs/learning-task-contract.md` — Normative Hugin↔M5 learning-evidence seam: field and decision
  owners, privacy/evolution rules, cross-repo fixtures, and measurable definitions of continuous
- `docs/learning-task-contract-v1.schema.json` — Canonical machine-readable v1 union schema; positive
  and adversarial fixtures live under `tests/fixtures/learning-task-contract/`
- `docs/adr-006-learning-improvement-scope.md` — Why v1 improves routes, rosters, prompts, harnesses, and tool
  policy while model-weight training remains a separately gated future program
- `docs/autonomous-improvement-design.md` — Design v0.1 for removing the human approval step from
  the operating loop (owner decision 2026-07-20): reversibility axiom, mechanical promotion
  predicates, verifier-anchored auto-calibration, watchdog/auto-revert, protected lanes, tier ladder

## Security, trust, and lifecycle

- `docs/threat-model.md` — Consolidated threat model (v0.1): assets, trust boundaries, adversaries,
  and a T1–T11 key-threats table mapped to owning tickets (from the 2026-07-06 blind-spot audit)
- `docs/tenant-contract.md` — The minimal agent↔substrate contract any agent must satisfy to act
  through the substrate (Munin access, gateway routing, safety gating, audit emission) plus a cheap
  validation plan
- `docs/tenant-validation-2026-07-04.md` — Evidence note from the first real non-Claude tenant run
  (Codex CLI, grimnir#58): seams A/B/C passed on transport, D blocked, per-tenant identity missing
  everywhere; harness in `scripts/tenant-validation/`
- `docs/interactive-session-posture.md` — Required Hugin handoff (or constrained fresh-session
  fallback) for consequential mutations after untrusted input
- `docs/succession-checklist.md` — Public, non-secret export-and-shutdown checklist for the emergency
  delegate; private-envelope contents stay out of git
- `docs/data-lifecycle.md` — Store-by-store retention, correction, erasure, and backup-expiry map

- `docs/instruction-ab-evidence-2026-07-25.md` — Measured before/after evidence for the
  `AGENTS.md` → `docs/index.md` split (grimnir#143): method, per-run results, the confabulation and
  partial-enumeration findings, and the harness defect found mid-flight. Harness
  `scripts/tests/ab-instructions-eval.sh`, probes under `tests/fixtures/instruction-probes/`.

## Vision and superseded plans

- `docs/vision.md` — **DRAFT v0.2 (2026-06-29), supersedes v0.1.** Direction, not commitments:
  the *why* and the *what-not-to-build*, including the decision rule ("reuse the harness layer;
  build only what touches Memory or Inference-routing"). Companion to `architecture.md`. Read this
  first when a plan and the vision appear to conflict — v0.2 wins.
- `docs/ecosystem-review-plan.md` — Ecosystem review plan, revision 2 (post-debate). Predates
  `vision.md` v0.2, but its core — cross-service contracts (Step 0, grimnir#7) — remains the active
  program. **Where this plan and v0.2 conflict, v0.2 wins.**
- `docs/GRIMNIR_DEVELOPMENT_PLAN.md` — ⛔ **SUPERSEDED by `vision.md` v0.2 (2026-06-29). Do not
  execute this plan.** It proposes deepening Hugin's home-built orchestration layer, exactly what
  the current decision rule caps. Kept for historical context only.

## Roadmap, reviews, and decisions

- `docs/gap-analysis-2026-07-03.md` — Critic-corrected ecosystem gap analysis vs vision v0.2: ranked
  gaps, quick wins, cut list, and corrections log (the source of the 23-ticket fleet program)
- `docs/vision-review-fable-2026-07-09.md` and `docs/vision-review-sol-2026-07-09.md` — Independent
  Fable + Sol vision/priority reviews from 2026-07-09 that preceded the roadmap-now decisions
- `docs/roadmap-now-decision-brief.md` — Index of the adopted "now" decisions: succession (#65),
  GDPR/data lifecycle (#66), system ROI/off-ramp (#67), Skuld revive-or-cut (#69), interactive-session
  trust posture (#70), and the #58 Verdandi blocker
- `docs/verdandi-purpose-reset-2026-07-13.md` — 2026-07-13 purpose-reset evidence note feeding
  verdandi#21 and draft PR verdandi#22; **not authorization to restart Verdandi**
- `docs/verdandi-user-stories-and-product-fit-2026-07-13.md` — 2026-07-13 user-stories and
  product-fit evidence note feeding verdandi#21 and draft PR verdandi#22; **not authorization to
  restart Verdandi**
- `docs/skuld-trial-decision.md` — 28-day evidence record and keep/cut gate for the Skuld briefing
  producer
- `docs/agent-harness-bakeoff-2026-07-08.md` — Evidence note on open-source, model-agnostic agent
  harnesses. Goose and OpenCode both completed M5-backed edit/test loops; OpenCode is the recommended
  first Hugin coding-lane adapter, Goose the general-worker candidate.

## Scripts

| Script | Purpose | Run with |
|--------|---------|----------|
| `scripts/deploy.sh` | Deploy registered services from explicitly bound revisions | `make deploy ARGS="service=/absolute/worktree@FULL_COMMIT_SHA"` |
| `scripts/guarded-deploy.sh` | Bind arbitrary owning-repo deploy commands to an expected worktree + revision | See `docs/deployment-source-binding.md` |
| `scripts/generate-architecture.sh` | Generate deployment snapshot + full-architecture.md | `make docs` (Pi only) |
| `scripts/output-audit.py` | Audit owner+AI repository output over a date window | `python3 scripts/output-audit.py` (reads an untracked local identities config; see `scripts/output-audit-identities.example.json`) |
| `scripts/security-scan.sh` | Scan all repos for vulnerabilities and secrets | `make security` |
| `scripts/worktree-hygiene-audit.sh` | Read-only audit of stale/dirty/orphaned worktrees, canonical-checkout drift, and deploy-target role violations across owned repos | `scripts/worktree-hygiene-audit.sh` (also wired into `scripts/generate-architecture.sh --validate`); tests via `make test-worktree-hygiene` |
| `scripts/tests/ab-instructions-eval.sh` | A/B a change to the agent-instruction files against a frozen retrieval probe set | `scripts/tests/ab-instructions-eval.sh --before DIR --after DIR` |
| `scripts/tests/ab-rescore.sh` | Recompute A/B verdicts from retained raw streams after a detector fix, instead of re-running the eval | `scripts/tests/ab-rescore.sh RAW_DIR` |
| `tests/scripts/test-doc-index.sh` | Guard: fails when a doc exists but is not indexed here, when a required constraint annotation is dropped, or when a behavioural rule leaves `AGENTS.md` | `make test` |

> OS patching (`setup-host-patching.sh`) and maintenance reports (`maintenance-report.sh`) have moved
> to the `brokkr` repo. Use `make patching` / `make maintenance-os` / `make maintenance-deps` from
> `brokkr/`.

# Grimnir System — Status

**Last session:** 2026-07-04
**Branch:** main

## Completed This Session (2026-07-03→04) — headless ticket fleet: all 23 gap tickets shipped + deployed

The full execution of the gap analysis below: **every one of the 23 `from:grimnir` tickets resolved,
27 PRs merged, the fleet deployed current, and both structural fixes live in production.**

- **Method:** one headless `claude -p` session per ticket, each in an isolated git worktree of the
  owning repo (repo CLAUDE.md visible), gated permissions (`acceptEdits` + scoped allowlist — the
  classifier correctly refused `--dangerously-skip-permissions`). Every PR triple-gated: session
  self-ran Codex (`review-pr-codex`), orchestrator posted a Claude review **comment** (never an
  approval — self-approval correctly blocked), m5 qwen3-coder first-pass where the box cooperated.
  Spend-limit interrupt overnight: 5 sessions resumed cleanly via `claude -p --continue`.
- **Cross-model review earned its keep:** 2 criticals (verdandi write-scope never enforced —
  read-only keys could forge audit events; hugin `..` traversal bypassing the workspace guard),
  1 high (Option-A `pull --ff-only` exits 0 on local-ahead/dirty — the exact #44 class), ~8 mediums.
  All fixed test-first or declined with posted rationale.
- **Structural fixes LIVE on huginmunin:** grimnir now deploys via `git pull --ff-only` with
  enforced post-conditions (#54 + #55 gitignore + #56 bash-3.2 empty-array fix — two latent deploy
  bugs surfaced and fixed during acceptance); hugin task workspaces isolated under
  `~/hugin-workspaces` (`HUGIN_REPOS_ROOT` set, service restarted). #44/#33 class: detected (#53)
  **and** prevented (hugin#143).
- **Pillar 2 loop closed:** routing-table generator (gille-inference#148) run against the live
  ledger (620 attempts + 416 cartography rows, 16/16 types), adopted via gille-inference#149,
  synced to the runtime — the gateway now serves a **learned** table. reason-hard regressed to
  escalate-frontier (its 06-23 extra-probes evidence is lost from disk — fail-safe correct;
  re-probe filed as gille-inference#150).
- **Fleet deploys:** all 8 services shipped current (verdandi auth enforcement, mimir secret-scan,
  ratatoskr evidence emitter, skuld authenticated Munin seam live). Caught mid-deploy: local
  checkouts were stale post-merge — pulled all + redeployed; mimir deployed from an isolated
  worktree (`mimir=<path>` override) to avoid touching its feature-branch checkout.
- **Cuts executed:** 7 repos deleted (snapshots in `~/mimir/archive/repo-snapshots-2026-07-03/`).
- **New tickets from discoveries:** heimdall#108 (descriptor `value` stripped), claude-config#1
  (Keychain token + outbox flush), brokkr#29/#30, gille-inference#150 (re-probe).

### Pending / next
- Sara's key revocation (#9) re-test; router check (#11); board hygiene.
- Policy blessings: verdandi event vocabulary (§3.1 of its ingest design), MODEL_META.unsafeFor
  list, fleet lint convention (ESLint won 4 repos; ratatoskr tsc-only), Actions SHA-pinning.
- Fleet npm-audit triage (criticals in ratatoskr+skuld transitives); flaky-timing-test sweep (3 repos).
- mimir local checkout: on `feat/offsite-cloud-backup` (content-merged) with dirty STATUS.md —
  owner decision; skuld's 3-month STATUS.md diff likewise.
- brokkr clone into hugin-workspaces failed (machine account lacks access) — add collaborator, rerun.
- Adoption tickets on request: failure-recovery convention (hugin/brokkr), verdandi multi-env ingest.
- services.json: reconcile fortnox-mcp→noxctl repo rename.

## Completed Previous Session (2026-07-03) — vision-v0.2 gap analysis + cut execution

Ran a 17-agent gap analysis of all 11 components against vision v0.2 (11 assessors + 2 bloat
auditors + synthesis + 3 adversarial critics). Durable artifact: **`docs/gap-analysis-2026-07-03.md`**
(ranked gaps, 10 sequenced quick wins, safety-verified cut list, corrections log).

- **Ranked gaps:** (1) self-knowing loop closes almost nowhere (emit→consume→decide arc);
  (2) Pillar 2 severed at both ends (Hugin↔ledger, routing table has no writers, no production
  workload feeds it); (3) accountability record laptop-only + mis-classified + unintegrated —
  **critic correction: Verdandi is ALIVE (67k+ events), not dead**; (4) Phase 2 can't maintain
  itself (registry poisoned again, 7/10 repos no CI); (5) sovereignty seam leaks; (6) tenant
  replaceability unvalidated (no non-Claude agent has ever acted through the substrate).
- **23 `from:grimnir` tickets filed** across owning repos + board-verified (repo-ownership
  convention — tickets, not tree edits): verdandi#9/#10/#11, ratatoskr#27/#28, skuld#3/#4/#5,
  mimir#13/#14, hugin#139, brokkr#26/#27, heimdall#104/#105, noxctl#53, gille-inference#145/#146,
  munin-memory#189, grimnir#45/#46/#47/#48. Full table in the gap-analysis doc §4.
- **hugin#117:** 2 of 5 cut-list boxes were **already done and tracking never noticed**
  (hugin-orchestrator merged via PR #108 on 2026-06-17; hugin-munin archived) — ticked with
  evidence. Worktree retained for in-flight PR2 (`.env` keys to salvage before removal).
- **Cuts prepared:** snapshots of meta-agent / agentic-eval / codex-review-toolkit /
  claude-playground / transcriber → `~/mimir/archive/repo-snapshots-2026-07-03/` (meta-agent +
  codex-review-toolkit have no remote — snapshots are the only copies). `rm -rf` of the 7 targets
  + the Pi checkout reconcile/redeploy (#44) blocked by the permission classifier → handed to
  Magnus as one-liners. agent-council deferred (needs re-fetch + 30-min diff vs gille-inference).
- **Doc stamps:** `GRIMNIR_DEVELOPMENT_PLAN.md` marked SUPERSEDED (contradicts v0.2);
  `ecosystem-review-plan.md` got a context note (NOT superseded — backs live Step-0 work, #7).
- **Discovered:** fortnox-mcp repo renamed → `noxctl` on GitHub; `services.json` still says
  `fortnox-mcp` (registry drift, reconcile with #47/#48 work). ⚠️ Concurrent session live on
  hugin (`feat/orchestrator-homeserver-provider`) — implements the Pillar-2 ledger wiring;
  coordinate, don't duplicate.

### Pending / next
- Magnus: run the Pi reconcile + `make deploy ARGS="grimnir"` (#44), then the 7-repo `rm -rf`.
- Quick-win queue (sequenced in gap doc §2): verdandi#9 hygiene → validate delta-alert (#2) →
  CI stamp-out (7 repos) → mimir#11/#12 revival → ratatoskr#27 evidence emitter → doc-truth sweep.
- Carry-over: #9 (Sara key revoke re-test), #11 (router check on home LAN), #33 (self-update
  grimnir — subsumed by #44/#47 role separation).

## Completed Previous Session (2026-06-30) — roadmap quick-wins + deploy cluster

Triaged the Roadmap board (86 items → 59 open) and cleared the trivials + the deploy cluster.

- **#3 closed** — WiFi/Ollama-over-Tailscale instability is stale; inference moved to the M5 box, tailnet healthy.
- **#8 closed** — unit-scope mechanism already shipped (`c5f5303`/#20); verified live systemd scopes on huginmunin match `services.json` (hugin/verdandi=user, rest=system), duplicates gone.
- **#9 (Anthropic key leak) — STILL OPEN, action on Sara.** tallriksvis is offline (`…OFFLINE-leaked-key-20260615`, no port serves it), but I tested the leaked key against the Anthropic API → **HTTP 200, still live**. Emailed Sara (`sara@gille.ai`) with revoke steps. Re-ping for a 401 once she revokes, then close.
- **#11 (router HTTP mgmt) — open.** Couldn't confirm: laptop was off the home LAN (10.175.x, not 192.168.0.x). Needs an `http://192.168.0.1` check from an allowlisted client on home WiFi.
- **#21 → PR #37 MERGED (`2fbe5d4`)** — delta-aware Telegram alert on escalated security-scan findings. Codex review (after a credits-out Claude self-review stand-in) caught 4 real issues — baseline-read-failure false positives, poisoned-record escalation suppression, octal-parse silent-miss, test-gap — all fixed; 29/29 tests. Added `scripts/lib/escalation.sh` (`scan_escalated` + strict `parse_prev_counts`, shared with the test).
- **#31 re-scoped** to a per-service version-drift self-check (deploy.sh already restarts; the 2026-06-17 outage was an out-of-band bump). Mirrored to **hugin#123** (on board).
- **#33** — root cause confirmed: grimnir's auto-update never redeploys grimnir's own repo (Pi stuck at `fa66789`). **Redeployed from main → drift cleared** (Pi now `2fbe5d4`). Self-update-own-repo feature remains tracked on #33.
- **Tidy-up:** closed shipped **munin-memory #122 & #70**. Flagged 4 MAYBE-stale issues for confirmation (hugin#119, munin#5, ratatoskr#1, heimdall#74) and hugin#38 (closed but board still "In Progress").

### Pending / next
- #9: awaiting Sara's revocation → re-test for 401.
- #11: on-home-LAN router check.
- #33: implement self-update-grimnir; hugin#123: implement the SDK version-drift self-check.
- Board hygiene: hugin#38 In-Progress→Done; #8/#3 Todo→Done.

## Completed Previous Session (2026-06-29)

### Vision re-centered + architecture synced to reality — PR #35 merged (`61bc3d0`)
- **Trigger:** "educate me" session — how much of Grimnir is an agent harness, how much overlaps
  with nanoclaw / OpenClaw / Hermes-agent, and where to build vs reuse. Two subagents ran: an
  external-harness research briefing + an audit of the agent-orchestration repos.
- **`docs/vision.md` v0.1 → v0.2:** re-centered from "autonomous collaborator that does my work"
  to **"a sovereign, self-knowing personal-AI substrate that any agent can safely act through."**
  Two protected pillars — **Sovereign Memory** (Munin/Mimir/Verdandi) + **Self-Knowing Inference**
  (M5 gateway + capability ledger + offloadability eval). Decision rule: *build only what touches a
  pillar; reuse the harness layer when it's OSS and plugs into Munin + the gateway.* Preserved the
  4-phase Arc + Open Questions, reframed as what Grimnir *does* on the substrate, not its identity.
  → **Closes the carried-over "reconcile DRAFT v0.1 docs with reality" next-step.**
- **`docs/architecture.md` synced:** Hugin corrected to current reality (Claude Agent SDK +
  multi-runtime router + pipeline DAGs + delegation broker + safety scanners — no longer "spawns
  `claude -p`"); M5 marked **live** at `inference.gille.ai`; offloadability-on-Heimdall noted;
  `hugin`/`hugin-orchestrator` repo drift flagged.
- **Munin:** `decisions/grimnir-vision` (thesis + decision log) written.
- **Cross-repo cleanup filed:** **hugin#117** "Consolidate agent-orchestration repo sprawl"
  (merge `hugin-orchestrator`→`hugin`; archive `hugin-munin`; delete `meta-agent`+`agentic-eval`;
  converge/retire `agent-council`) — on Roadmap board #1. Recorded, **not executed**.

> **Previously (2026-06-15→16):** automated software-update system shipped (grimnir #26 + heimdall #21,
> unattended-upgrades + maintenance timers on both Pis + laptop brew job). Detail in Munin
> `decisions/auto-updates` + `projects/grimnir`.

## Next Steps (carried over — ecosystem review program)
1. **grimnir#7** — cross-service contracts section in `docs/architecture.md` (blocks integration work)
2. **Phase A — Integration fixes** — MuninClient copy for Ratatoskr, CommonJS adapter for Heimdall,
   Skuld interface wrap, three contract tests, per-file contract ownership comments
3. **Phase B — Targeted `/security-review`** — munin-memory → ratatoskr → hugin; draft `docs/threat-model.md`
4. **hugin#26** — autonomous dependency bump (note: the **detect+report** half now exists via
   `brokkr-maintenance-deps`; the auto-bump half is still deliberately deferred)
5. **grimnir#5** — doc drift detection
6. **review-pr-codex skill** — fix the prereq check: it bails on missing `OPENAI_API_KEY` even when
   Codex is authenticated via ChatGPT sign-in (caused both review subagents to abort on first try)
7. **UPS for both Pis** — grimnir#4

## Blockers
- None

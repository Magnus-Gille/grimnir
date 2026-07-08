# Grimnir System — Status

**Last session:** 2026-07-08 (Codex close) — Hugin PR #150 production verification and deploy hardening
**Branch:** main

## Completed This Session (2026-07-08) — Hugin PR #150 deployment closure

Closed the Hugin PR #150 production follow-up with a delegated Codex subagent and an M5 `mellum`
advisory check, while keeping final acceptance in this thread.

- **Hugin production state:** `/home/magnus/repos/hugin` was deployed via Grimnir's registry-aware
  selective deploy. The final runtime state includes PR #150 plus the later Hugin #152 mainline fix;
  the exact deployed commit is tracked in `/home/magnus/repos/hugin/.deployed-commit`.
- **Live evidence:** `hugin.service` is active/enabled under the user manager; `/health` reports
  `status:"ok"`, `polling:true`, and `queue_depth:0`.
- **Permission evidence:** live probe logs reached Claude initialization and showed default/read-only
  plus malformed trusted-code requests use `dontAsk`, while explicit `Capabilities: code` plus
  `Permission profile: trusted-code` uses `bypassPermissions`.
- **Validator evidence:** `./scripts/generate-architecture.sh --validate` on `huginmunin` reported
  **7 ok, 0 issues, 0 warnings** after the final Hugin marker repair.
- **Quality repair:** the review caught that deploying from a detached Git worktree can rsync a
  `.git` file pointer and corrupt the remote checkout metadata. Repaired the remote Hugin checkout,
  then hardened both Grimnir `scripts/deploy.sh` and Hugin `scripts/deploy-pi.sh` to exclude worktree
  `.git` files as well as `.git/` directories.

### Pending / next
- Claude on the Pi is quota-blocked until **2026-07-09 21:00 Europe/Stockholm**, so one post-reset
  end-to-end Claude runtime task should still be run to prove execution past initialization.
- Hugin #152 is already included in the final production marker because `main` advanced during
  closeout; the next Hugin target should be chosen from the remaining queue.

## Completed This Session (2026-07-08) — PR #71 production reconciliation

Reconciled the PR #71 handoff against live production state on `huginmunin`. No PR #71 code was
reopened or reimplemented.

- **Live checkout:** `/home/magnus/repos/grimnir` is on `main`, clean, synced with `origin/main`,
  and contains PR #71 (`9b74fd6`) plus the post-merge validation fixes (`4eb0984`, `83de3d9`).
- **Deployment evidence:** affected deployed components have `.deployed-commit` stamps:
  hugin `6deabc197d49`, heimdall `1e26f0580ed2`, skuld `8057c0af787c`, ratatoskr `1148ea294cc3`,
  and mimir `fe470a964069` in the latest validator output.
- **Unit evidence:** `hugin.service` is active/enabled through the user manager;
  `hugin-daily-analysis.timer` is active as a system timer; `skuld.timer` is active/enabled through
  the user manager and triggers `skuld.service`; Heimdall, Ratatoskr, and Grimnir timers are active
  through the system manager.
- **Skuld evidence:** registry has `skuld.port = null`, `systemd_units = [{ name: "skuld",
  type: "timer", scope: "user" }]`; no listener is present on `:3040`.
- **Fresh validator run:** `./scripts/generate-architecture.sh --validate` on `huginmunin` at
  `2026-07-08T09:58:45Z` reported **7 ok, 0 issues, 0 warnings** and wrote
  `validation/registry/latest` to Munin.
- **Generator follow-up:** normal `docs/full-architecture.md` generation no longer carries stale
  Skuld `:3040` references after regeneration. This session also fixed the normal snapshot health
  probe to reuse the host-aware `health_status_local/remote` helpers instead of localhost-only curl,
  matching the PR #71 validator behavior.

### Pending / next
- No PR #71 deploy action remains. Future deploy work belongs to newer merged component PRs
  (`brokkr#41`, `ratatoskr#37`, `verdandi#17`, `gille-inference#189`, `hugin#150`), not PR #71.

## Completed This Session (2026-07-07) — roadmap "now" cluster decision brief

Created `docs/roadmap-now-decision-brief.md` as the smallest safe Grimnir-side progress for the
current Roadmap "now" cluster. The brief deliberately does **not** create a large policy framework;
it captures owner decisions and lightweight next artifacts for:

- **grimnir#65** succession / bus factor: decide emergency delegate(s) and whether the desired
  outcome is recover, export-and-shutdown, or keep-running temporarily.
- **grimnir#66** GDPR / data map / retention / erasure: choose default retention windows for
  client/accounting data, personal memory, operational telemetry, and transient task artifacts.
- **grimnir#67** system ROI ledger + exit/off-ramp: define the cut/keep threshold for services with
  no measured use, no pillar-protection role, and no owner-reviewed reason to keep.
- **grimnir#69** Skuld revive-or-cut: choose either a four-week measured briefing trial or cut now.
- **grimnir#70** interactive-session trust posture: choose advisory-only, fresh-session-required
  after untrusted input, or route consequential mutations through Hugin.
- **grimnir#58** remains blocked by **verdandi#15**; Grimnir should not claim end-to-end tenant
  conformance until off-Pi Verdandi intake/key provisioning exists and Seam D is rerun.

Indexed the new brief from `README.md` and `CLAUDE.md`. PR #72 merged as `30580d3` after local
review, M5 review, and green GitHub checks. This was docs-only; no production deploy was needed.

Ran a repo-local fanout for the rest of the "now" cluster. No non-Grimnir repo changes were accepted
from the subagents; their outputs were patch plans only, reviewed against `docs/vision.md`,
`docs/tenant-contract.md`, `docs/authority.md`, and the current threat model:

- **Accept direction:** brokkr#38 belongs in Brokkr as off-box host liveness, but its alert path
  must not depend only on huginmunin-hosted Heimdall/Munin.
- **Accept direction:** verdandi#16 checkpoint/anchor work is safe before verdandi#15; verdandi#15
  must add tenant-bound keys/events before exposing off-Pi intake.
- **Accept direction:** hugin#149 is the highest-risk Hugin fix; keep an explicit compatibility
  escape hatch while removing unconditional `bypassPermissions`.
- **Accept direction:** ratatoskr#36 validation belongs in `task-writer`, not only the Telegram
  command handler, because LLM-produced task context is untrusted too.
- **Accept direction:** munin-memory#191 should precede #192; ownership-aware correction/forgetting
  needs server-derived tenant identity first.
- **Accept direction:** gille-inference#152 is the next safe inference-side step; keep #154 blocked
  on verdandi#15 and keep #156 guarded by trusted-verifier evidence.

### Pending / next
- Owner decisions above are the blockers for splitting this brief into final docs.
- After decisions: create `docs/succession-checklist.md`, `docs/data-lifecycle.md`, a short
  `docs/vision.md` ROI/off-ramp section, a Skuld decision record, and the interactive-session
  posture note.
- Keep grimnir#58 parked until verdandi#15 lands.

## Completed This Session (2026-07-07) — threat model v0.1 reviewed and merged

Reviewed PR #68 against the current architecture/registry state, rebased it onto current main, and
merged it as `0853fc7`.

- **Owner-review gate closed:** `docs/threat-model.md` is no longer marked draft / needs owner review.
- **Review fixes:** tightened overbroad trust-boundary language (local processes are not trusted after
  compromise), corrected the Tailscale/loopback statement, softened the cloud-AI "stateless" claim to
  "not storage authority", and added **T11** for GDPR / third-party data retention and erasure risk
  (`grimnir#66`).
- **Indexing:** `CLAUDE.md` now lists `docs/threat-model.md`; `STATUS.md` references the reviewed
  T1-T11 table.
- **Verification:** local `make test`, `shellcheck`, and `bash -n` passed on the rebased branch; GitHub
  CI for PR #68 passed before merge.

### Pending / next
- Highest-leverage cheap ops follow-up remains brokkr#38: off-box dead-man's switch.
- Grimnir-owned decision tickets still need working sessions: #65 succession, #67 ROI ledger,
  #69 Skuld SSOT decision, #70 interactive-session trust posture.

## Completed This Session (2026-07-07) — registry units are deploy/validation truth, Skuld port drift removed

Followed up the adversarial repo review with a focused branch for the operationally risky findings.
PR #71 merged (`9b74fd6`), then live validation exposed two validator regressions that were fixed
directly on main (`4eb0984`, `83de3d9`) and deployed.

- **Registry projection:** `QUERY=deploy` now carries full `systemd_units` JSON, and `QUERY=validate`
  carries `deploy_path` so consumers do not collapse multi-unit components to `systemd_units[0]` or
  assume `~/repos/<repo>`.
- **Deploy flow:** `scripts/deploy.sh` now installs every declared unit from either `systemd/` or
  root-level unit files, restarts services by scope, enables timers by scope, and installs matching
  oneshot service companions for timers when present. This directly addresses the hugin daily-analysis
  and Skuld timer classes.
- **Validation/snapshot flow:** `scripts/generate-architecture.sh --validate` now honors user vs system
  scope, checks timers as timers, and reports rsync deployment stamps instead of assuming rsync targets
  are git checkouts. Snapshot generation now includes unit scope and type-aware rows.
- **Live-regression fixes after merge:** validation now checks user units through Magnus's user manager
  even when `grimnir-validate.service` runs as root, and health probes try localhost plus bound local
  interface addresses so Heimdall/Ratatoskr services bound to Tailscale validate correctly.
- **Registry truth:** Skuld no longer declares port `3040`; it is a timer-only briefing producer whose
  web view is rendered by Heimdall from Munin. A follow-up M5-assisted review caught that the
  root-level `skuld.service` has no `User=`, so `skuld.timer` is now explicitly user-scoped in the
  registry and pinned by the smoke test.
- **Deployment:** Deployed `grimnir`, `hugin`, `heimdall`, `skuld` (from a clean temporary worktree),
  then redeployed `ratatoskr` and `mimir` to add `.deployed-commit` stamps required by the validator.
- **Docs:** Updated `README.md`, `docs/architecture.md`, `docs/scheduled-tasks.md`, and `CLAUDE.md`
  to remove the stale Skuld web/API surface and M5 “awaiting delivery” wording, and to describe
  deploy modes more honestly.
- **Verification:** `make test` passed; CI-equivalent `shellcheck scripts/*.sh scripts/lib/*.sh
  scripts/tests/*.sh` passed; `bash -n` passed for shell scripts; registry projections and
  `validate-registry.js` passed after the M5 review follow-up. Final live
  `grimnir-validate.service` run on huginmunin: **7 ok, 0 issues, 0 warnings**.

## Completed This Session (2026-07-06) — blind-spot audit: vision alignment + threat-model v0.1 + 14 from:grimnir tickets

Full blind-spot check of the system vs vision v0.2. **Verdict:** the vision is sharply articulated
and the two pillars are real; the *unseen* gaps cluster in **continuity, whole-system security/trust,
and strategic worth** — the "self-knowing" principle is applied to models/components but never to the
system's own recoverability, trustworthiness, or ROI.

- **Method:** 5 parallel sub-agent component profilers (munin / hugin / heimdall+ratatoskr /
  mimir+verdandi+brokkr+skuld+fortnox / doc-corpus) + ground-truth checks on huginmunin + an M5
  independent adversarial cross-check (`qwen3-30b-instruct`; `gpt-oss-120b` timed out under load —
  matches the ask-path flakiness note). All verbose profiling kept out of root context.
- **Net-new findings** (beyond the 2026-07-03 gap analysis): no human succession/bus-factor plan;
  no off-box dead-man's switch (Heimdall + the only alert channel share fate with the host they
  watch, and alert-engine reds are display-only) — a real power outage already forced manual
  restarts (grimnir#4); off-site backup is Munin-only and restore has never been tested (the NAS is
  a data-loss SPOF); Verdandi's real hash-chain is never verified on a cadence and has no off-box
  anchor; Munin cannot correct/forget a wrong "fact"; GDPR/third-party data untreated; system-level
  ROI never measured.
- **Sharpened knowns:** Hugin runs every task `bypassPermissions` (exfil guard is detective-only)
  and emits nothing to Verdandi — the autonomous actor is the least-audited actor; the lethal
  trifecta is open on interactive sessions (gating exists only on the Hugin queue path).
- **Ground truth:** Skuld is `deploy:true` in services.json but has no unit on the box and has never
  run (`systemctl is-enabled` → not-found; journal empty); `munin-offsite.timer` IS live and firing.
- **Artifacts:** `docs/threat-model.md` v0.1 (**PR #68**) — first consolidated threat model, T1–T11
  mapped to owning tickets. **14 `from:grimnir` tickets filed + on the Roadmap board:**
  grimnir#65 (succession), #66 (GDPR), #67 (system-ROI), #69 (Skuld SSOT drift), #70 (interactive
  trifecta); brokkr#38 (off-box dead-man's switch), #39 (off-site+restore), #40 (encryption-at-rest);
  heimdall#112 (push alerts); hugin#148 (→Verdandi), #149 (scope permissions); ratatoskr#36
  (/repo traversal); verdandi#16 (verify+anchor); munin-memory#192 (memory correction).

### Pending / next
- **Highest-leverage, cheapest:** brokkr#38 (off-box dead-man's switch — one laptop cron).
- PR #68 threat model review/merge completed 2026-07-07.
- Grimnir-owned decision tickets await a working session: #65 (succession envelope), #67 (ROI ledger
  + exit paragraph in vision.md), #69 (revive Skuld or cut it from services.json), #70 (trust posture
  for interactive sessions).
- T7/brokkr#40 needs an on-box check: are the SD cards / NAS disk actually encrypted at rest?

## Completed Previous Session (2026-07-05 pm) — grimnir hygiene: #43 + #33 shipped, deployed, verified; 3 follow-ups filed

Picked up "what's next" → a self-contained grimnir-owned hygiene sweep. PR #62 merged
(`66bfda1`) + deployed to huginmunin, closing #43 and #33.

- **#33 (deploy drift) — false positive, now genuinely fixed.** Production grimnir HEAD has
  tracked origin/main all along (kept current by session `git pull --ff-only`), but
  `.deployed-commit` — the marker Heimdall's drift detector reads — is only re-stamped by
  `deploy.sh`, so a tree pulled forward OUTSIDE a deploy leaves it stale and Heimdall
  false-flags all 4 grimnir units as behind. Fix: `restamp_deploy_marker()` in
  `scripts/lib/registry-checkout.sh` self-heals the marker in the `--validate` flow when the
  checkout is verified clean-on-main. **Verified end-to-end on the Pi:** staled the marker →
  triggered the sandboxed validate service → healed back to HEAD, 0 warnings.
- **#43 (SSOT).** Added `hugin-daily-analysis.timer` to `services.json` (appended second so
  `registry.js` still derives hugin's deploy scope from `systemd_units[0]` — deploy stays
  user/rsync). **Discovery:** that timer is installed on huginmunin but was never
  `enable --now`'d — **hugin's daily journal analysis has never run.**
- **Cross-model review (2 Codex rounds, gpt-5.5 xhigh) earned its keep:** round 1 caught the
  self-heal was a *silent no-op under `grimnir-validate.service`'s read-only sandbox*
  (`ReadOnlyPaths=/home/magnus/repos` + `ProtectHome=read-only`) — fixed with a single-file
  `ReadWritePaths=-…/.deployed-commit` exception + a visible WARN (killed the `|| true` swallow).
  Round 2 caught a symlink-TOCTOU — now refused. Tests: registry-checkout 42/42, registry-smoke
  27/27; shellcheck + `bash -n` clean.

### Follow-ups filed (all on the Roadmap board)
- **hugin#147** — enable the dormant `hugin-daily-analysis.timer` (daily journal analysis has
  never run). Hugin-owned.
- **grimnir#63** — `grimnir-validate` ignores `scope: user` (always uses system
  `systemctl is-active`), so user-scoped units like `hugin.service` chronically false-report
  `inactive`. Pre-existing; grimnir-owned — the natural next pickup.
- **brokkr#36** — when brokkr's dep auto-bump lands it must restart services whose
  `node_modules` changed. **#31 closed** — routed here + interim convention (route dep upgrades
  through `deploy.sh`, which restarts).

## Completed Previous Session (2026-07-05 am) — close-the-loop experiment + full model sweep + honest routing table LIVE

An autonomous overnight experiment proving Pillar 2's loop closes end-to-end, a full 7-model
capability sweep, then 8 PRs shipped and the honest routing table synced to production.

- **Close-the-loop experiment** (~530 gateway calls, ledger 743→1,198 rows): fresh probes →
  durable ledger → #153-guarded regen. reason-hard restored to delegate-local (gpt-oss-120b
  23/24 — its first ledger evidence; #150 gap closed); sql promoted (explore→delegate-local).
  Alarm drill replayed the #150 incident (deleted evidence) → guard refused write, exit 1,
  EVIDENCE-MISSING + ROUTING_REGRESSION_JSON correct. **Report: `~/mimir/research/grimnir/
  m5-close-the-loop-2026-07-04.md`** (indexed in Munin documents/research).
- **Full 7-model sweep** (~1,200 loopback calls, misconfig probe). **Triage:** mellum wins
  (88% vs qwen3-30b 83%; ratatoskr#33 filed to switch). **Code review vs 34 seeded bugs:**
  **gpt-oss-120b is the best local reviewer (82% recall / 93% precision)**; mellum — the old
  table's code-review verdict — is the WORST (6% recall / 25% precision). **Misconfig findings:**
  gpt-oss-120b 27/120 triage HTTP-500s (harmony/PEG format, model-layer, non-deterministic);
  gemma4+tongyi-dr budget-starved (run-wrong, not weak). Confirmed on both tasks.
- **8 PRs merged** (all triple-reviewed; Codex back online mid-session): #159 (triage vocab #155),
  #163 (verdict hygiene #156 — exclude structural verifiers), #165 (gpu-lease post-release write
  race — flaky ENOTEMPTY, real fix), #167 (#164 retry-on-format-500), #169 (#168 whitelist
  hygiene — judgment types admit only trusted verifiers), **#157 (adopt honest routing table)**.
- **Honest routing table LIVE on the M5 gateway** (synced 13:23Z): code-review→escalate-frontier
  (honest — no trusted local reviewer verifier yet), reason-hard→delegate-local(gpt-oss-120b),
  sql→delegate-local, triage vocab present. Backup at box `docs/m5-routing.json.bak-20260705-132254`.
  **Pillar 2 now closes end-to-end IN PRODUCTION**: traffic → ledger → guarded regen → adoption → serving.

### Pending / next (this session's additions)
- **gille-inference#158** (ground-truth code-review probe) — THE keystone: its trusted verifier,
  added to `HOMESERVER_TRUSTED_JUDGMENT_VERIFIERS`, flips code-review escalate→local(gpt-oss-120b).
  The #168 whitelist is its socket. Design-heavy (needs a scoring mechanism decision).
- **gille-inference#166** (grammar-constrained structured output — prevents #164 500s at source),
  **#161** (generator prototype-key guard), **brokkr#32** (llama.cpp harmony upgrade — box ops).
- **ratatoskr#33** (switch triage default to mellum — one env line + restart on huginmunin).
- Operational: headless fleet MUST run on **opus** (Fable is spend-capped — killed a session).
  gpt-oss-120b unreachable on the M5 ask-path 4× under load (#164/brokkr#32) — blocks using it
  as the fleet's own local-review leg until reachability is fixed.

## Completed Previous Session (2026-07-04 pm) — vision re-check, fleet run 2, first production Pillar-2 traffic

Post-fleet alignment re-check against vision v0.2, then a second ticket fleet (4 tickets, all-Fable
+ M5-heavy variant), merged and **activated in production same-day**.

- **Alignment re-check (corrected two prior claims against source):** §1.2 Pillar 2 was NOT fully
  closed — ratatoskr/skuld still hardcoded the Anthropic SDK, so the learned routing table trained
  on self-referential orchestrator traffic; conversely the hugin verdict layer verified as a REAL
  consumer (adaptive verify gate drives delegate-local/escalate/explore). New binding constraint
  named: **signal design** (raw cost savings could reward cheap-but-wrong).
- **4 tickets filed and resolved via ticket-fleet** (one worktree + headless `claude-fable-5`
  session each; triple review: Codex + orchestrator leg + m5 qwen3-coder first-pass):
  - **hugin#144 → PR #145** (merged `6deabc1`): quality-adjusted savings — verdict-joined
    economics; fail = zero credit, verifier spend booked; QA ≤ raw by design. Judgment call
    accepted: unknown-keeps-credit (bucketed for later discount).
  - **ratatoskr#31 → PR #32** (merged `a1121c9`): triage via gateway `POST /delegate` (deliberate,
    endorsed deviation — /delegate records ledger attempts server-side). **ACTIVATED**: key minted,
    env set on huginmunin, deployed, smoke-passed (`outcome:pass`, 3.9s warm). Live metrics show a
    real Telegram triage **served by M5** + one visible cold-swap fallback — §1.2c closed in fact.
  - **grimnir#58 → PR #59** (merged `4620d6d`, honest partial): **first non-Claude tenant (Codex)
    acted through 3/4 substrate seams** live; Seam D blocked (Verdandi has no off-Pi intake).
    Central finding with receipts: per-tenant identity unimplemented everywhere (all writes
    collapse to `principal_id: owner`). #58 stays OPEN until verdandi#15 + Seam D re-run.
  - **gille-inference#151 → PR #153** (merged `6789dbc`): Pillar-2 self-guard — durable probe
    ledger, missing-vs-absent distinction, `--accept-downgrades` refuse-write gate + Heimdall
    alarm. Codex was out of credits: self-review fallback honestly labeled; **real Codex pass owed**.
- **Follow-up tickets filed** (`from:grimnir`, on board): verdandi#15 (**blocking**: off-Pi audit
  intake + key provisioning), munin-memory#191 (per-tenant principals), hugin#146 (task
  provenance/signing), gille-inference#152 (ledger key alias), gille-inference#154 (Verdandi event
  on regression alarm; blocked by #15).
- **M5 delegation-quality data logged** (RQ6/RQ7, in Munin): qwen3-coder review legs clean+correct
  on 3 TS diffs but confabulated 5/6 findings on a shell/docs diff — verify-before-trust caught
  all of it. Local codegen usable-with-supervision (every draft needed 2–3 corrections).
- **Ops:** two sessions died simultaneously to an API connection drop (15:20:00); both resumed
  cleanly via `--continue` with M5-enabled resume script. gille-inference now has a canonical
  laptop checkout (`~/repos/gille-inference` — previously none existed anywhere).

### Pending / next (this session's additions)
- **verdandi#15 is the critical path** — unblocks #58 closure, Seam D re-run, and gille-inference#154.
- Codex pass on gille-inference PR #153 when credits return.
- hugin next deploy activates quality-adjusted savings; next routing-table regen exercises the guard.
- Per-tenant identity is the substrate's next structural theme (munin-memory#191, hugin#146,
  gille-inference#152 as the arc).
- Scheduled mini-gap-analysis: deliberately held until ratatoskr#31 + grimnir#58 accrue data.
- (Inherited pending list from the morning session below remains valid.)

## Completed Previous Session (2026-07-03→04) — headless ticket fleet: all 23 gap tickets shipped + deployed

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

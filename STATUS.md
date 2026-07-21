# Grimnir System — Status

**Last session:** 2026-07-21 (Claude Code, Fable 5) — Phase 4 complete: the autonomous improvement loop is ARMED
**Branch:** `main` at `3fdab1e` (canonical checkout reconciled and fast-forwarded at close)

## The headline

The self-improving delegation loop now operates with **no human in the operating path**
(owner decision 2026-07-20, design: `docs/autonomous-improvement-design.md`). Epic
grimnir#88 Phase 4 is fully built, reviewed, deployed, and armed.

**Live right now:**

- **M5** — `gille-autonomy-tick.timer`, daily 05:30 UTC (user-scope, `Linger=yes` confirmed,
  kill switch OFF, Tier 0). The gi#49 autonomy controller runs watchdog → evidence review →
  predicates → tier decision each tick. Tier 1 (verifier-backed auto-adoption with canary,
  72h watch-window, auto-revert, quarantine) self-unlocks after 10 healthy cycles; the
  ladder promotes/demotes autonomy on the operating record thereafter.
- **Pi** — `hugin-experiment-cadence.timer`, daily 05:00 CEST (propose→package→observe→conclude;
  `promote` structurally unreachable). Harness-lane sampler live at 10%
  (`HUGIN_HARNESS_LANE_FRACTION=0.1` in hugin `.env`).
- **Deployed tips:** gille `d05194f` (M5, `home-server-eval`), hugin `03a1804` (Pi).
  The adopted 7-change routing table (hash `24047a1…`) has survived 5 deploys (gi#44 fix proven).

**Owner controls:** pause = `AUTONOMY_KILL_SWITCH=on` in `/home/magnus/home-server-eval/.env`;
full stop = `systemctl --user disable --now gille-autonomy-tick.timer` on M5.
`ROUTING_LIFECYCLE_ADMIN_KEY` is installed in the M5 `.env` (mode 600) — adoption is zero-flag.

## Completed this session (2026-07-20 → 21)

- Phase 1–3 build-out merged + deployed (see epic #88 annotations): accounting (#232/#241/gi#3),
  publication recovery (hugin#225), checkout isolation (hugin#236), retention with default-off
  prune gate (gi#9), external Codex/Pi receipt pair (hugin#237 + gi#10), scout hardening (gi#12),
  routing-adopt operability (gi#37/#38), worktree-hygiene audit (grimnir#96), adoption
  deploy-durability (gi#44/#30, proven live).
- Phase 4 autonomy: design doc (PR #97), watchdog (gi#47), verifier-anchored auto-calibration
  (gi#48), experiment cadence (h#266 + timer PR #271), standing harness lane (h#267),
  autonomy controller (gi#49, subsumed gi#46; PRs #53/#55), tick timer as deploy-managed IaC (PR #54).
- **The gi#49 controller survived a 7-round adversarial Sol (gpt-5.6-sol, xhigh) review loop**:
  trajectory 12→8→5→3→6→3→2→SHIP, ~90 red/green regression tests, gille suite 3,075→3,199,
  Gate D 84/84 throughout. Final verdict: "No material findings… below the established
  single-host Tier-0 ship bar." Cross-model review is now proven load-bearing for this system.

## In progress / next steps (priority order)

1. **Watch the first scheduled ticks** (M5 05:30 UTC, Pi 05:00 CEST) — `systemctl --user status
   gille-autonomy-tick` on M5; exit 3 = unresolved-revert attention state.
2. Wire `AUTONOMY_NOTIFY_CMD` on M5 to Ratatoskr so adoptions/reverts/tier-changes push to Telegram.
3. gi#57 — three LOW Sol follow-ups (revert-path only; cannot trigger before Tier 1 + a breach).
4. hugin#272 — cadence fuel: candidate-pool assembler + gille outcome-export resolver (until then
   the experiment tick observes/concludes but does not propose).
5. Remaining epic tail: gi#11 (served-model refresh), gi#13 (ground-truth reviewer adoption),
   gi#14 (Verdandi audit events — blocked on verdandi#15), #79, #90, hugin#192 harness campaign.
6. Worktree cleanup: ~85 registered worktrees across grimnir/gille/hugin from this + prior
   sessions (many merged/stale). Use the NEW audit: `bash scripts/worktree-hygiene-audit.sh`
   (read-only; per-item remediation). Not cleaned at close — not explicitly authorized.

## Blockers

None for the loop itself. Non-blocking: hugin/gille canonical checkouts carry co-tenant dirty
state (AGENTS/CLAUDE/STATUS mods) — left untouched per git-safety; all session work went through
dedicated worktrees and PRs.

## Verification at close

- gille: typecheck clean, 193 files / 3,199 tests, Gate D 84/84, CI green on every merged PR.
- hugin: build clean, 142 files / 2,232+ tests, CI green on every merged PR.
- Live: M5 timer next-fire confirmed, linger confirmed, deployed-controller dry-run tick healthy
  (`tier 0→0, cycle: advancing`); Pi broker health 200, cadence timer next-fire confirmed.
- Durable records: Munin milestones + decision log (2026-07-20/21), epic #88 fully annotated,
  Sol loop record on PR #55.

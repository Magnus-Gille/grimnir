# Grimnir System — Status

**Last session:** 2026-06-30
**Branch:** main

## Completed This Session (2026-06-30) — roadmap quick-wins + deploy cluster

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
   `grimnir-maintenance-deps`; the auto-bump half is still deliberately deferred)
5. **grimnir#5** — doc drift detection
6. **review-pr-codex skill** — fix the prereq check: it bails on missing `OPENAI_API_KEY` even when
   Codex is authenticated via ChatGPT sign-in (caused both review subagents to abort on first try)
7. **UPS for both Pis** — grimnir#4

## Blockers
- None

# Grimnir System — Status

**Last session:** 2026-03-30
**Branch:** main

## Completed This Session

### Tallriksvis deployment — Caddy on Pi
- Installed Caddy 2.11.2 on huginmunin, port 80, systemd-enabled
- Web root: `/home/magnus/www/tallriksvis/`
- Authorized Sara's SSH key (`sara@saras-mac`) for rsync deploys
- Deploy instructions saved to `~/Desktop/tallriksvis-deploy-instructions.md`
- Waiting for Sara to run rsync to complete first deploy

### Ollama runtime for Hugin — implemented and deployed (`b51a601` in hugin)
- Added `ollama` as third Hugin runtime alongside `claude` and `codex`
- New files: `ollama-executor.ts` (streaming), `ollama-hosts.ts` (lazy resolution), `context-loader.ts` (declarative Munin context injection)
- Task schema extensions: `Ollama-host`, `Fallback`, `Context-refs`, `Context-budget`
- Fallback restricted to infra failures only (unreachable, 5xx) — semantic failure is experiment data
- Extended invocation journal with 15+ fields for experiment observability (host/model requested vs effective, memory snapshots, token counts, context resolution)
- 7 new test cases, all 44 tests passing
- Deployed to Pi and validated end-to-end: task submitted → Hugin claimed → ollama inference → result in Munin

### Ollama installed on Pi
- Installed ollama 0.19.0, systemd service enabled
- Pulled `qwen2.5:3b` (1.9 GB, fits comfortably, no swap) and `qwen2.5:7b` (4.7 GB, tight, uses swap)
- Default model set to `qwen2.5:3b`
- Listening on `0.0.0.0:11434` for Tailscale/LAN access
- Pi 1 memory: ~800 MB services, 6.7 GB available before model load, ~4.6 GB with 3b loaded

### Pi 1 resource baseline measured
- Munin: 417 MB, Ratatoskr: 112 MB, Hugin: 104 MB, Heimdall: 66 MB
- Total services + system: ~1.2 GB used, 6.7 GB available
- qwen2.5:3b: +2.1 GB when loaded, 4.6 GB remaining — safe
- qwen2.5:7b: +4.9 GB when loaded, 2.0 GB remaining + 427 MB swap — risky with concurrent Claude tasks

### Seidr architecture debate (2 rounds)
- Debated Seidr (Agent Context Server) proposal with Codex
- Outcome: Don't build Seidr yet. Build one concrete non-Claude worker first, then decide on abstraction.
- Key finding: "portable skills" as proposed are a category error — only intent/constraints/capabilities are portable, not execution strategy
- Documented in `debate/seidr-architecture-*.md`

### Ollama runtime debate (2 rounds)
- Debated the implementation plan with Codex
- 6 design improvements: streaming (not non-streaming), lazy host resolution (not polling), infra-only fallback, Context-refs in task schema (not Hugin semantic policy), journal analysis as smoke test (not the experiment), extended journal schema
- Documented in `debate/ollama-runtime-*.md`

### End-to-end smoke test passed
- Submitted `qwen2.5:3b` task via Munin → Hugin claimed → ollama streamed response → result written to Munin
- Response: correct markdown table of Swedish cities by population
- Duration: 41s (including cold model load), exit code 0
- Journal entry verified with all extended fields populated

## In Progress

### Ollama experiment — next tasks
- ~~Journal analysis daily task (smoke test)~~ — systemd timer deployed and verified (2026-03-30)
- Stale-status review task (real experiment) — defined in plan but not yet submitted
- Need to observe whether qwen2.5:3b quality is adequate for bounded Grimnir tasks

## Next Session — Recommended Order

### 1. Submit the real experiment task (Munin stale-status review)
The portability test: read project statuses via Context-refs, apply conventions, produce structured review. This exercises context bootstrap, conventions awareness, and judgment.

### 2. SCION Phase A1+A2 — Agent state model
High value given task volume. Define phase enum + Munin entry format (A1), emit phase transitions from Hugin lifecycle (A2). ~6h. Plan at `docs/GRIMNIR_DEVELOPMENT_PLAN.md`.

### 3. Review first timer-triggered security scan results (after April 5)
Check Munin for `security/scans/2026-04-05`.

### 4. Skuld Fortnox integration
Phase 2 of Skuld: invoice aging, revenue pulse, payment status via noxctl.

### Lower priority
- Per-service Munin tokens (security #3)
- Extend auto-deploy to remaining services
- SCION Phase B (worktree isolation) — after A is proven

## Blockers
None

## Key References
- Implementation plan: `~/.claude/plans/floating-knitting-shell.md`
- Seidr debate: `debate/seidr-architecture-summary.md`
- Ollama debate: `debate/ollama-runtime-summary.md`
- Pi ollama endpoint: `http://100.97.117.37:11434` (Tailscale) or `http://huginmunin.local:11434` (mDNS)

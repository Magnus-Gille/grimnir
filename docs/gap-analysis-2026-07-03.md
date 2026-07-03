# Ecosystem Gap Analysis — vision v0.2 vs reality

> **2026-07-03.** Multi-agent analysis: 11 component assessors (one per repo, evidence-first),
> 2 bloat auditors, 1 synthesis, 3 adversarial critics (gap-ranking, effort-honesty, cut-safety).
> ~1.2M subagent tokens, 380 tool calls. Yardstick: `docs/vision.md` v0.2.
> Findings below are **critic-corrected** — where the critics refuted the synthesis, the
> correction is stated and the original claim noted. See §5 for the corrections log.

## TL;DR

Grimnir is strong exactly where sustained attention has lived — Munin (5/5 maturity), the M5
inference substrate, noxctl — and hollow at the **connective tissue**. The dominant failure
pattern is the **half-open loop**: evidence emitted that nothing reads, or loops designed that
nothing feeds. Most of the gap is **wiring, not building**: the top holes close by connecting
ends that already exist. Roughly two focused weeks of quick wins would move the system from
"two strong pillars and a pile of open loops" to a substrate whose record, routing, and
self-maintenance loops actually close.

## 1. Largest gaps (ranked)

### 1.1 The self-knowing loop closes almost nowhere *(cross-cutting; the vision's load-bearing principle)*
Eight assessors reported this under eight names. **Emission end:** mimir, ratatoskr, skuld,
fortnox emit no competence evidence (empty `metrics: []`, hardcoded `status: 'pass'`,
`MuninClient.log()` with zero callers, swallowed collector failures — a degraded briefing looks
identical to a full one). **Consumption end:** where evidence *is* collected, nothing decides
from it — grimnir-validate has written daily results to Munin since April that nothing reads;
Heimdall never scores its own alerts (its named north-star metric); Hugin's delegation ratings
are append-only. The emit→consume→decide arc completes only in munin-memory's dev-time
decisions and the security-scan delta alert. This gap is the causal parent of §1.3 and §1.4:
the silent failures below were invisible precisely because the noticing loop is what's missing.

### 1.2 Pillar 2's learning loop is severed at both ends
The M5 gateway, capability ledger, and eval crons are real and production-grade — but:
(a) **Hugin has zero ledger integration** — `src/router.ts` ranks on static attributes; the
ledger-gated `/delegate` executor existed only as tested-but-unimported code *(being wired
2026-07-03 on `feat/orchestrator-homeserver-provider` — in flight)*;
(b) **`m5-routing.json`** — literally "your learned model of what to route where" — is a
hand-edited snapshot with readers but no writers: the learned model doesn't learn;
(c) **no production workload feeds it** — ratatoskr triage and skuld synthesis both hardcode
the Anthropic cloud SDK, generating zero routing-outcome data.
Highest vision-centrality in the document ("most original idea, first-class pillar").

### 1.3 The accountability record is laptop-only, mis-classified, and unintegrated
**Corrected finding** — the synthesis called Verdandi "functionally nonexistent"; the critics
proved that wrong: the live service holds **67,000+ hash-chained events** with continuous
laptop ingestion (verified through 2026-07-03 16:21). What *is* true: the only emitter is the
laptop Claude Code hook — zero ingest for Desktop/Web/Mobile/Telegram/Pi-side Hugin tasks and
zero sibling-repo emitters; the severity taxonomy silently broke in the May MCP→CLI move
(noxctl/m365 money-and-email actions land as debug-grade shell events); GET endpoints are
unauthenticated tailnet-wide; the token sits plaintext in `~/.zshenv`; and the 4,601-event
outbox is a ~7% failure tail whose flush script is broken by design (format mismatch + batch
cap). Nothing has been discarded yet — the backlog is fully recoverable.

### 1.4 Phase 2 can't maintain itself
The production registry checkout on huginmunin was broken at analysis time (stranded on a
June-15 hugin task branch; tree one deploy behind — missing exactly #42, the services.json
stale-node fix; second incident of class #33, whose issue was never closed). **7 of 10 repos
have no CI** — ~1,500 existing green tests gate nothing. "Fixes documentation drift" is
inverted: four READMEs actively assert falsehoods (heimdall "implementation pending", brokkr
"nothing deployed", skuld's removed web server, mimir's test count).

### 1.5 Sovereignty leaks at internal seams
The perimeter holds (CF Access, tunnel auth, timing-safe compares) but "auth at every layer"
fails between components: skuld opens a writable SQLite connection directly into Munin's DB
(bypassing auth, secret-scan, audit, and hardcoding internal schema); Mimir's rsync ingest
scans nothing (a secret in `~/mimir/` becomes bearer-servable and publicly shareable);
Verdandi's reads are unauthenticated; shared static tokens mean the substrate cannot attribute
*which* tenant did what. Each leak is component-local and mechanically fixable — heimdall's
`muninRpc` shows the correct seam.

### 1.6 Tenant replaceability is unvalidated *(critic-surfaced; missed by the primary synthesis)*
The thesis sentence — "a substrate **any agent** can safely act through" — has zero supporting
evidence: every acting integration hardcodes the Anthropic SDK; no second agent brand has ever
acted through the substrate. Related: no failure-recovery/undo story exists anywhere, and
Phase-2 autonomy (auto-upgrades, task-dispatched mutations) is exactly where one is needed.

**Directionality note:** in the days after v0.2 capped Hugin as a platform, effort flowed into
the capped layer (fanout engine, PRs #125–127) while the ledger integration the vision assigned
sat unshipped; Hugin now carries four overlapping composition mechanisms. The concurrent
homeserver-provider work is the corrective.

## 2. Quick wins (sequenced; effort critic-verified)

| # | Win | Where | Effort | Note |
|---|-----|-------|--------|------|
| 1 | Fix poisoned production registry: redeploy from main, reconcile checkout to main | grimnir#44/#43 | ~1h acute | Role-separation is **cross-repo** (hugin hardcodes the workspace root) — ticketed separately, not a half-day add-on |
| 2 | Verdandi hygiene: Keychain token, severity remap, GET auth, fix sync-outbox, flush backlog | verdandi | ~1 day | Reframed from "reconnect" — the service is alive |
| 3 | Wire ledger-gated homeserver executor into Hugin routing | hugin | — | **In flight in a concurrent session — coordinate, don't duplicate** |
| 4 | Auto-regenerate `m5-routing.json` from ledger + cartography | inference repo | 1–2 d | `qwen36-a3b` hole needs a GPU cartography run — consume the Sunday scout cron, don't race it |
| 5 | grimnir-validate delta-alert (reuse `scripts/lib/escalation.sh`) | grimnir#2 | 1 d | Inert until win 1 lands (validate runs in the poisoned checkout) |
| 6 | Heimdall agent heartbeat → wedge-watchdog acceptance test | heimdall#101 | ~1 d | brokkr#14 already CLOSED (watchdog merged, PR #24) — only heartbeat + SIGSTOP test remain |
| 7 | Minimal CI across the 7 repos that have none | per-repo | ~2 d total | The single biggest Phase-2 unlock; 7 assessors independently listed it |
| 8 | Mimir revival: tailnet bind, HEIMDALL_* env vars, merge offsite-backup branch | mimir#11/#12 | half-day | Dead shipped instrumentation goes live |
| 9 | Ratatoskr evidence emitter: triage logging + real descriptor metrics | ratatoskr | 1 d | Also generates the triage-offloadability dataset for Pillar 2 |
| 10 | Fleet documentation-truth sweep | per-repo | 1 d | Four lying READMEs; shipped-but-open issues; stale cut-list tracking |

## 3. Prune / cut list (safety critic-verified)

**Positive confirmation:** no cut target appears in services.json, launchd, crontab, or any
skill path — no hidden scheduler or registry dependency anywhere.

**Standing cut list (vision §Cut bloat) — 2 of 5 were already done and tracking never noticed:**
- ✅ `hugin-orchestrator` merge — done via hugin PR #108 (2026-06-17), 0 unique commits remain.
  **Worktree deliberately retained** (hugin STATUS.md) for PR2's gitignored `.env`
  (OpenRouter/Berget keys) — salvage keys + remove after PR2 lands.
- ✅ `hugin-munin` — already archived on GitHub.
- 🗑️ `meta-agent` — zero commits ever, no remote; **snapshot is the only copy** → snapshot taken, delete.
- 🗑️ `agentic-eval` — a zip + one doc, not a git repo → snapshot taken, delete.
- 📦 `agent-council` — retire over converge (3.5 months dormant vs. gille-inference active).
  Re-fetch force-pushed remote + 30-min unique-content diff first, then `gh repo archive`.

**Safe immediate deletes (snapshots in `~/mimir/archive/repo-snapshots-2026-07-03/`):**
`scion`, `ivy-tendril` (verified unmodified upstream clones, no snapshot needed),
`codex-review-toolkit` (content duplicated in claude-skills), `claude-playground`,
`transcriber` (corrupt .git; whole tree snapshotted).

**Do-with-care (not executed; some ticketed):**
- `debate/` dirs across 6 repos (~2MB transcripts) → relocate to `~/mimir/` + Munin index.
  **Do NOT delete grimnir's 76 gitignored transcripts** — sole copies incl. the vision-v0.2-era
  debates; relocate them like the rest.
- ~250 stale merged branches fleet-wide → mass-delete + enable GitHub auto-delete-head-branches.
  The 108 aider-eval branches are local-only true merges (tagging optional; the GitHub setting
  won't prevent local accumulation). **Keep** grimnir's June-15 task branch until #44 resolves.
- fortnox `LEGACY_DUAL_WRITE` ("REMOVE IN 0.3.0", shipping 0.4.0): dual-write flip safe;
  legacy *reader* removal breaks external npm installs → semver-signaled release (ticketed).
- `autolab` / `freja`: commit/copy untracked work first (autolab has **no remote at all**),
  then archive as out-of-scope. **Don't archive** the network-security-evaluation bundle —
  grimnir#9 (leaked-key verification) and #10 still open.
- Pre-pivot docs: `GRIMNIR_DEVELOPMENT_PLAN.md` stamped superseded (this PR);
  munin prd/technical-spec, skuld ROADMAP 7–8, hugin `sprints/` — ticketed to owners.
- Retire outright: gille-inference `improve-loop` (zero production runs ever) + `lmstudio`
  backend default (ticketed).
- Hugin's four composition mechanisms → decision item: pick one for new work, deprecate the
  rest; full convergence needs its own session with the 1,184-test suite as the net.
- verdandi dead schema surface (unused tables, permanently-null checkpoint fields) → drop or
  move behind the Phase-3 migration; do in the same session as the hygiene win.

## 4. Cross-repo tickets filed (2026-07-03, `from:grimnir`, all on the Roadmap board)

| Ticket | Scope |
|--------|-------|
| verdandi#9 | Audit hygiene: Keychain token, post-MCP severity mapping, GET auth, sync-outbox fix |
| verdandi#10 | Multi-environment ingest coverage (only laptop CC emits today) |
| verdandi#11, ratatoskr#28, skuld#4, mimir#14, heimdall#104, brokkr#26, grimnir#48 | Minimal CI per repo (the 7 with none) |
| ratatoskr#27 | Emit competence evidence: triage logging + real descriptor metrics |
| skuld#3 | Stop writing directly into Munin's SQLite — use the authenticated API seam |
| skuld#5, brokkr#27, heimdall#105, munin-memory#189 | Doc-truth sweep per repo |
| mimir#13 | Secret-scan the rsync ingest path |
| hugin#139 | Configurable task-workspace root (registry-poisoning class fix, hugin side) |
| grimnir#47 | Separate deploy target / git checkout / hugin workspace roles (grimnir side) |
| noxctl#53 | Dependabot + semver-signaled LEGACY_DUAL_WRITE/legacy-reader removal |
| gille-inference#145 | Auto-regenerate m5-routing.json (writers for the routing table) |
| gille-inference#146 | Retire improve-loop + flip lmstudio backend default |
| grimnir#45 | Vision gap: tenant replaceability unvalidated |
| grimnir#46 | Vision gap: no failure-recovery / undo story |

*(Repo note: fortnox-mcp was renamed `noxctl` on GitHub — services.json still says `fortnox-mcp`; registry drift to reconcile.)*

## 5. Corrections log (what the adversarial pass changed)

1. **Verdandi is alive, not severed** — the single biggest factual miss in the primary
   synthesis. Live server, 67k+ events, continuous laptop ingestion. The gap reframes from
   "dead letter" to "single-channel + mis-classified + unintegrated". The irreversibility
   argument ("outbox actively discarding") was also wrong: trim threshold 10,000, outbox at
   4,601 — fully backfillable.
2. **brokkr#14 already closed** (watchdog merged via PR #24) — quick-win 6 shrinks to
   heartbeat + acceptance test.
3. **hugin quick-win in flight** — `feat/orchestrator-homeserver-provider` started the same
   day as the analysis; treat as coordination, not backlog.
4. **Registry role-separation is cross-repo** (hugin hardcodes `/home/magnus/repos/`) — not
   part of a half-day fix; needs `from:grimnir` tickets.
5. **aider-eval branch facts** — 108 local-only true merges, not ~196 remote; prevention via
   GitHub setting doesn't apply to local-only branches.
6. **grimnir's debate transcripts are gitignored sole copies** — the synthesis's "delete"
   sub-action was the one unsafe instruction in its cut list; relocate instead.
7. **grimnir#9 mischaracterized** by the synthesis as printer/router remediation — it is the
   leaked-Anthropic-key verification, still open, and blocks archiving the security bundle.
8. **`ecosystem-review-plan.md` is not superseded** (this session's own correction) — it backs
   the open Step-0 contract-spec work and serves v0.2 directly; it gets a context note, not a
   supersession stamp.
9. **grimnir#33 was never closed** — the synthesis's "resolved-then-recurred" framing
   understated the Phase-2 gap: the first incident of the class was neither fixed nor
   tracked to closure.

## 6. Method note

Fan-out: one assessor per component with the full vision text, instructed evidence-first
(read code, not READMEs; cite paths/issues). Barrier, then synthesis ranked by
*vision-centrality × thinness × compounding-cost-of-delay*. Three adversarial critics with
spot-check tool access re-verified every gap, effort estimate, and cut against the repos.
Two synthesis claims were refuted, several weakened; confirmed claims are marked as such
above. Raw run: session workflow `wf_3e476b31-f00` (17 agents, 0 failures).

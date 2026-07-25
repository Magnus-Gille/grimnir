# Grimnir System — Status

**Last session:** 2026-07-25 (Claude) — context-engineering pass on the instruction files
**Prior session, same day:** publication, roadmap batch, and substrate-contract work
**Latest system revision:** grimnir `1497326` (2026-07-25 session record)

## The headline

Two repositories were taken public to escape a GitHub Actions billing wall, the stabilization
sweep's loose ends were closed, and eight roadmap tickets shipped across six repositories with
four certified production deploys. The substrate maintenance program is now unblocked: Grimnir
defines `maintenance-policy` v1 and Brokkr already consumes it through a read-only planner.
Munin Memory remained excluded throughout (parallel session).

## Completed this session — context-engineering pass (later session, 2026-07-25)

Applied Anthropic's Claude-5-generation context-engineering guidance to the instruction files, and
measured the result rather than assuming it.

- **PR #143 (open, unreviewed)** — moves the 30-entry document index and scripts table out of
  `AGENTS.md` into `docs/index.md`. `AGENTS.md` 1273 → 698 words, 2,474 fewer prompt tokens per
  session, at **measured retrieval parity** (28/30 both arms; policy and control constraints 9/9
  both arms). Took four iterations; the first regressed and was caught by measurement, not review.
- **New capability: `scripts/tests/ab-instructions-eval.sh`** — A/B harness that runs a frozen probe
  set through headless Claude Code in two worktrees differing only in instruction files, scoring
  doc-hit mechanically from the tool-call stream. Plus `ab-rescore.sh` to re-score retained raw
  streams without paying for re-runs. Reusable for the three MCP tool-surface tickets below and for
  the global `claude-config/AGENTS.md` pass.
- **New guard: `tests/scripts/test-doc-index.sh`** (in `make test`) — asserts the index stays
  reachable in one hop, lists every doc, has no broken pointers, and preserves constraint-bearing
  annotations verbatim.
- **Cross-repo tickets filed** — munin-memory #257, hugin #318, gille-inference #81: expressive tool
  schemas over prose examples. Each explicitly scopes safety/policy text *out* of trimming.

### Findings worth carrying forward

- **Progressive disclosure fails by confabulation, not slow retrieval.** When the agent did not know
  a document existed it produced a confident, well-structured, invented answer — six runs made zero
  tool calls. Inline descriptions signal *that a recorded answer exists*, not just where.
- **Partial enumerations read as exhaustive.** Every topic named in the pointer scored perfectly;
  everything omitted became invisible. This recurred at two levels — first topics, then component
  names ("is *Skuld* worth keeping", "restart *Verdandi*").
- **Guard found pre-existing rot**, unrelated to the change: `docs/vision.md` (the v0.2 decision
  rule), `docs/ecosystem-review-plan.md`, and `docs/GRIMNIR_DEVELOPMENT_PLAN.md` were missing from
  the original index — the last carrying an invisible "⛔ do not execute this plan" marker.
- **My own harness had an arm-biasing defect** (`jq -e` returns only the last stream value, so
  doc-hit counted only final tool calls; the after arm makes more calls and was penalised). Found by
  reading transcripts when a result looked wrong. Retained raw streams made the correction cost one
  re-score instead of 78 re-runs.

Evidence: `docs/instruction-ab-evidence-2026-07-25.md`.

## Completed this session — publication and roadmap batch (earlier session, 2026-07-25)

### Publication (owner-approved, per repository)

- **Ratatoskr and Verdandi are public.** Full-history `gitleaks` scans found no real secrets across
  108 commits. Added README, MIT LICENSE, and SECURITY.md to both; Verdandi's README states its
  stopped status honestly (publication is a visibility change, not a restart). Two real tailnet IPs
  were scrubbed from Ratatoskr — the second (the M5 gateway address) was caught only by an
  independent adversarial review after the first pass missed it. Retired CGNAT addresses remain in
  old history as documented, accepted residual risk.
- Publication also cleared the immediate CI blocker: both repositories now run Actions on the free
  public tier.

### Roadmap tickets shipped

- **Grimnir #134** — `maintenance-policy` v1: closed schema, intent-only contract with explicit DST
  behavior, a deterministic `maintenance-policy-digest-jcs-v1` digest, and 12 adversarial fixture
  categories. Unblocks the Brokkr maintenance epic.
- **Brokkr #33** — read-only maintenance observation and plan, the contract's first consumer.
  Consumes the Grimnir schema and fixtures as a SHA-pinned vendor copy rather than re-deriving them.
- **Gille Inference #74** — bounded local-review lane (`review-bounded`) with three contract-shaped
  subtask kinds, a deterministic verifier, and an advisory-only guardrail; `code-review` stays
  frontier-only. **#57** — three watchdog revert-path follow-ups, red/green. **#15** — corrected
  `$HS_API_KEY` documentation with a consistency test. **#73** — Node 24 action pins.
- **Heimdall #5** — thermal zones discovered from sysfs by declared type (zone index is boot-order,
  not an identifier); fixed in all three collectors. **#6** — insight KPI thresholds moved to shared,
  documented bands where unknown never renders as good.
- **Hugin #316**, **fortnox-mcp #81**, **Ratatoskr #52**, **Verdandi #24** — Node 24 immutable action
  pins and deployment-checkout cleanliness.

### Deploys (all certified against the running service)

- Gille Inference `abe9f08` then `7dd9ddf` to M5: tailnet health, authenticated capability probe 200,
  autonomy timer re-armed, marker stamped only after every check passed.
- Heimdall `71e6429` to the control node, plus the Python fleet agent to the NAS. Live-verified by
  a post-restart CPU temperature sample on the control node and a real Pi sysfs reading from the NAS.

### Repository hygiene

- 96 stale worktrees and merged branches removed across ten repositories, each verified clean and
  byte-identical to its merged PR head first. Nine canonical checkouts fast-forwarded.

## Important incidents and learnings

- **A wrong assumption, corrected in the record.** The Heimdall NAS temperature fix was reviewed on
  the assumption that the NAS reports through the SSH forced-command probe. It does not —
  `/home/heimdall` and the `heimdall` user do not exist on the NAS (likely lost in the relocation
  rebuild); it reports through the Python push agent. Filed as heimdall#23: the SSH storage probe is
  either dead code that looks canonical or an intended path failing silently.
- **The M5 review lane splits along task shape, and that is now measured.** Bounded single-question
  reviews were reliable across both sessions, including a substring-edge case and a four-part
  shell-semantics check. A whole-patch adversarial review produced four findings, all refuted — one
  would have removed claim-token fencing. A later bounded review reasoned a guardrail correctly and
  then stamped the opposite verdict label. Conclusion, recorded on gille-inference#25 and encoded in
  #74: score machine-checkable structured fields, never a model's prose verdict.
- **Contract claims were verified by independent computation, not by re-running their own tests.**
  The maintenance-policy DST fixtures were checked against the real tz database, and its digest was
  reproduced by a second implementation written from the prose spec alone.

## Next steps (priority order)

0. **PR #143 needs an independent review before merge** (house rule: prefer Codex sol high-effort).
   It is rebased on `1497326` with `make test` 117/0 green. Note for the reviewer: #141's two
   maintenance-policy discoverability assertions were repointed at `docs/index.md`, with an explicit
   `AGENTS.md → docs/index.md` one-hop assertion added, so that intent is still enforced.


1. **Owner: fix GitHub Actions billing.** Private-repo CI is still refused at job start; skuld PR #12
   is reviewed and one click from merge once it can run. Grimnir #140 scopes the self-hosted-runner
   alternative (private repositories only — never a public repo).
2. Brokkr #40 — surface unservable policy-requested update classes at the plan envelope level before
   #10/#35 consume the plan.
3. Gille Inference #80 — normalize caller-supplied `task_type` so the advisory-only guardrail cannot
   be bypassed by whitespace or case.
4. Heimdall #23 — decide whether the SSH storage probe is retired or repaired.
5. Grimnir #139 (fleet-wide action-pin policy) and #136 (Claude capacity preflight) are in flight in
   other sessions; skuld #13 proposes routing the commitment extractor to M5.
6. Carry over from the prior sweep: reconcile repository origins from #115, and schedule the pending
   M5 reboot and Pi firmware updates when work can tolerate interruption.

## Open questions from the context-engineering pass

- `session-posture` probe scored 1/3 in **both** arms in run 4 after 3/3 in runs 1–2. Unexplained
  probe variance, not caused by the change; worth understanding before leaning on that probe again.
- The four eval runs cost roughly $25–30 in Sonnet tokens. The global `claude-config/AGENTS.md`
  pass will cost similar and affects all 18 repos.
- Not yet done: the global `AGENTS.md` pass itself (portable rules → Codex and Pi), which was the
  original question that started the session.

## Blockers / owner input

- **GitHub Actions billing** — the only true blocker. It refuses private-repo CI jobs before they
  start, which forced the publication decision and still holds skuld #12.
- Disruptive maintenance timing (M5 reboot, Pi firmware) remains unscheduled.

## Verification at close

- Every merged PR had green CI plus independent review; each also received a bounded M5 pass, with
  declines recorded on the PR when M5 findings did not survive validation.
- Gille Inference: `7dd9ddf` deployed; live `/v1/capabilities/review-lane` confirms `code-review`
  frontier-only and `review-bounded` local-advisory with `promoted: false`.
- Heimdall: `71e6429` live, `/api/health` reports the exact merged SHA; post-deploy temperature
  samples confirmed on both the control node and the NAS.
- Grimnir: `make test` 117 passed / 0 failed; the node-substrate contract still validates 10/10, so
  v1 consumers are unaffected by the new maintenance contract.
- Brokkr: full suite and shellcheck clean; the maintenance planner's non-mutation property was
  verified structurally (single exec call site behind an allowlist, argv array, no shell).

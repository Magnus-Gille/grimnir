# Grimnir Ecosystem Review — Plan (Revision 2, post-debate)

## Context

The Grimnir ecosystem has grown to 9 repos (~89K LOC) and cross-agent bugs are
starting to surface — bugs that per-repo reviews can't catch because they live
in the spaces *between* services. Examples: `hugin/src/munin-client.ts` and
`ratatoskr/src/munin-client.ts` are divergent implementations of the same
client with different field sets (hugin has `classification`, retries, batching,
rate limiting; ratatoskr has none of those); heimdall has six separate files
that hand-roll JSON-RPC calls to Munin with hardcoded URLs; skuld reads Munin's
SQLite directly, bypassing access control and schema evolution; nobody owns
the cross-service contracts.

This is Revision 2. The original 5-phase program was stress-tested in an
adversarial debate with Codex (`debate/ecosystem-review-*`). Codex found 15
critique points, 5 caught by self-review and 10 by cross-model review. The
revision below is the outcome of the debate and supersedes the original
5-phase plan. Key shifts:

- **Contract spec first** — before any code changes, document who owns
  what. Codex's "most important next step".
- **Drop Phase 0 bootstrap.** The proposed "read-only baseline runner"
  couldn't actually run (heimdall has no `build` script; most repos lack
  `lint`/`format:check`/`typecheck`/`deadcode` scripts). It was a multi-repo
  implementation task disguised as setup.
- **Drop shared-package workspace strategy.** `munin-memory/packages/` does
  not solve distribution when consumers are separate repos with their own
  `package.json` and independent deploy paths.
- **Collapse 5 phases to 2 active + 1 conditional.**
- **Three contract tests, not one.** The original had three regression
  surfaces; the first revision compressed them to one; that was too much
  compression.
- **Heimdall gets an adapter, not a copy.** Heimdall is CommonJS JS with no
  build step. Hugin's TS client can't literally be copied in. The adapter is
  thin, tested against a fixture, and has the same observable semantics.
- **Drop:** knip, shared ESLint/tsconfig/prettier, weekly review runner,
  Skuld briefing integration, Heimdall dashboard card, auto-fix Hugin tasks,
  `/review-repo` and `/review-integration` skills, per-repo quality sweep,
  architecture review doc, heimdall JS→TS migration.

**User decisions captured (2026-04-09):**
- Full program was originally chosen, then narrowed after debate.
- Findings go to GitHub Issues only (dual-tracking dropped).
- **This turn is plan-only.** No code changes. Execution happens in follow-up
  sessions.

---

## Ecosystem snapshot (verified 2026-04-09)

| Repo | LOC | Lang | ESLint | Prettier | TS strict | CI | Tests | Role |
|---|---|---|---|---|---|---|---|---|
| munin-memory | 37,729 | TS | — | — | ✅ | ✅ | vitest | Central memory hub |
| hugin | 14,530 | TS | — | — | ✅ | — | vitest | Task dispatcher |
| fortnox-mcp | 13,700 | TS | ✅ | ✅ | ✅ | ✅ | vitest | Accounting CLI/MCP |
| heimdall | 12,488 | JS (CommonJS) | — | — | — | — | node:test | Monitoring dashboard |
| ratatoskr | 3,174 | TS | — | — | ✅ | — | vitest | Telegram router |
| skuld | 2,934 | TS | — | — | ✅ | — | vitest | Morning briefing |
| verdandi | 1,839 | TS | — | — | ✅ | — | vitest | Audit log |
| grimnir | 1,495 | sh | — | — | — | — | — | Orchestrator |
| mimir | 1,095 | TS | — | — | ✅ | — | vitest | File server |

**Notes from debate verification:**
- Only `fortnox-mcp` has husky; other repos do NOT have `.husky/` at all.
- Fortnox's actual CI runs `npm ci / build / test / format:check`, NOT
  `tsc --noEmit`. "Copy fortnox CI" is not literal for any other repo.
- `munin-memory/src/tools.ts` alone is ~6,460 lines; `/security-review` may
  need to be sharded by module.
- `grimnir/scripts/deploy.sh` builds each repo independently and runs
  `npm install --omit=dev` on the target host. It has no knowledge of a
  cross-repo package graph. Any shared-package strategy has to either work
  with this deploy path or replace it.
- Heimdall's `test/` directory has 13 `node:test` files. Green-state not
  verified at time of planning — any migration work must start from a known
  baseline.

---

## Known cross-agent risks (the "why now")

These are the concrete integration defects the program targets.

1. **MuninClient divergence.** Hugin's client (~337 LOC) has retries,
   timeouts, exponential backoff, batching, rate limiting, and
   `MuninEntry.classification`. Ratatoskr's client (~159 LOC) has none of
   those and lacks `classification`. They are not drop-in interchangeable.
2. **Skuld reads Munin's SQLite directly** (`skuld/src/collectors/munin.ts`).
   Bypasses HTTP, access control, schema evolution. Intentional optimization,
   but unmarked as a contract.
3. **Heimdall has 6 Munin-touching files** (`munin-projects.js`, `collector.js`,
   `self-heal.js`, `skuld-briefing.js`, `munin-sync.js`, `mcp-probe.js`) —
   each re-implements JSON-RPC construction with hardcoded URLs.
4. **Heimdall self-heal writes to Hugin's `tasks/*` namespace** — an
   undocumented cross-service contract that will break silently if Hugin's
   task schema evolves.
5. **No shared type definitions** — every service has its own `Task`,
   `MuninEntry`, `HealthReport`.
6. **No cross-repo contract enforcement** — breaking change in Munin's schema
   can ship before any consumer catches it.
7. **Contract ownership undefined.** Nobody owns the Munin HTTP client
   contract, the Hugin task submission schema, or Skuld's fast-path vs
   fallback behavior. This is the root cause Codex identified.

---

## The approach: 2 active phases + 1 conditional

```
Step 0    →   Phase A (integration)   ↔   Phase B (security)   →   Phase C (conditional)
Contract          (concurrent where capacity allows)               minimum CI floor
spec                                                                  (if needed)
```

### Step 0 — Write the contract spec (before anything else)

**This is the single most important deliverable.** It's ~1 session of
documentation work with no code changes. Everything downstream depends on it.

**Deliverable:** a new section in `grimnir/docs/architecture.md` titled
"Cross-service contracts" containing:

1. **Named contracts.** Each contract gets a name and a short description:
   - *Munin HTTP client contract* — bearer auth, JSON-RPC 2.0 transport,
     retry semantics on 429/5xx, backoff policy, session correlation header,
     classification field rules.
   - *Hugin task submission contract* — the shape of `tasks/*` entries that
     Hugin will accept as work. Namespace, required fields, acceptable
     task types, result reporting.
   - *Skuld fast-path vs fallback contract* — which SQLite reads are
     allowed, which must fall back to HTTP, how equivalence is guaranteed
     across the two paths.
   - *Heimdall → Hugin self-heal contract* — the task shape heimdall uses
     to enqueue recovery work.
   - *Verdandi event intake contract* — already partially documented in
     verdandi's CLAUDE.md but not from the cross-service view.

2. **Named owners per contract.** Not "canonical by fiat". Explicit:
   - Munin HTTP client contract: **owned by munin-memory** (the server is
     the authority on the protocol it serves). Hugin's current
     implementation happens to be the best reference but is not the owner.
   - Hugin task submission contract: **owned by hugin**.
   - Skuld fast-path contract: **owned by munin-memory** (the schema
     authority). Skuld is a consumer of a specifically-permitted
     read-only fast path.
   - Heimdall → Hugin self-heal contract: **owned by hugin** (it's a sub-
     schema of the task submission contract).
   - Verdandi event intake contract: **owned by verdandi**.

3. **Regression matrix** — for each contract, the minimum tests required
   to prevent drift. This is a list, not one test.

4. **Evolution rules** — how a contract owner signals a change, how
   consumers are migrated, who runs the migration.

**Exit criterion:** the section exists and has been reviewed. Nothing
else in the program ships until it does.

**Critical files for Step 0:**
- `/Users/magnus/repos/grimnir/docs/architecture.md` — where the section lands
- `/Users/magnus/repos/hugin/src/munin-client.ts` — reference implementation to cite
- `/Users/magnus/repos/ratatoskr/src/munin-client.ts` — divergent implementation
- `/Users/magnus/repos/skuld/src/collectors/munin.ts` — fast-path reader
- `/Users/magnus/repos/verdandi/src/` — event intake implementation
- `/Users/magnus/repos/munin-memory/src/tools.ts` — MCP tool definitions (schema authority)

---

### Phase A — Integration fixes (2-3 sessions)

**Goal:** address the seven known cross-agent risks using the contracts
from Step 0 as the spec.

**Work items:**

1. **MuninClient for Ratatoskr: copy-and-normalize from Hugin.** Both are TS
   with similar module systems. Copy Hugin's client into
   `ratatoskr/src/munin-client.ts` verbatim, delete the old file, fix the
   imports in callers. Hash-check in CI: `sha256sum` of Hugin's canonical
   file must match Ratatoskr's copy. Any drift fails CI.

2. **MuninClient for Heimdall: thin adapter, not translation.** Because
   Heimdall is CommonJS JS with no build step, Hugin's TS client cannot be
   literally copied. Instead:
   - Create `heimdall/src/lib/munin-client.js` as a small CommonJS module
     that exposes the same observable API surface as the TS client:
     `read`, `write`, `readBatch`, `query`, `log`.
   - Internally, reimplement the retry/backoff/timeout/bearer-auth behavior
     using Node's built-in `fetch` and the same config env vars.
   - Document in the file header that it is a deliberate re-implementation
     of the contract owned by munin-memory, *not* a copy of Hugin's code.
   - Back it with a fixture-based contract test (see #4 below) so drift is
     detected semantically, not by hash.
   - Replace the six hand-rolled call sites (`munin-projects.js`,
     `collector.js`, `self-heal.js`, `skuld-briefing.js`, `munin-sync.js`,
     `mcp-probe.js`) with calls to the new adapter. Pure refactor, no
     behavior change. Existing `node:test` suite should stay green.

3. **Skuld: interface wrap around direct SQLite.** Create
   `skuld/src/collectors/munin-fast-path.ts` that exposes the *same TS
   interface* as a MuninClient would (same method signatures, same return
   types). The SQLite reader lives behind that interface. Add an HTTP-based
   implementation as a fallback for when Skuld runs off-Pi. Consumers
   import the interface, not the implementation.

4. **Contract tests (three, not one):**
   - **Test 1 — MuninClient round-trip.** Runs in CI against a real local
     Munin instance. Verifies every method (`read`, `write`, `readBatch`,
     `query`, `log`) works end-to-end with bearer auth, retries, and
     classification field handling. Lives in the munin-memory repo (since
     munin-memory owns the contract).
   - **Test 2 — Skuld SQLite/HTTP equivalence.** Runs in CI in the skuld
     repo. Reads `projects/*/status` through both the fast path and the
     HTTP fallback against the same Munin instance and asserts
     equivalence. Any schema change in Munin that breaks the fast path
     surfaces here.
   - **Test 3 — Hugin task-shape regression for heimdall self-heal.** Runs
     in CI in the hugin repo. Constructs a task entry matching heimdall's
     self-heal submission shape and verifies hugin's task pickup still
     accepts it. Guards against drift in the cross-service contract.

5. **Contract ownership documented per-file.** Every file that implements a
   contract (the Ratatoskr copy, the Heimdall adapter, the Skuld
   interface, hugin's canonical client) gets a header comment linking back
   to `grimnir/docs/architecture.md#cross-service-contracts` with the
   contract name.

6. **Heimdall JS→TS migration:** **NOT in this plan.** Deferred
   indefinitely. Heimdall stays CommonJS JS.

**Execution mechanism:** one session per work item, serialized. Item #1
and #2 can run in the same session. Items #4 (tests) run after #1-#3 are
committed. Item #5 is a final tidy-up.

**Exit criterion:** `grimnir/docs/architecture.md` has the contracts
section; ratatoskr's MuninClient hash-matches hugin's; heimdall's six
call sites all go through the adapter; skuld's direct SQLite access is
behind an interface; the three contract tests run green in CI on their
respective repos.

**Critical files:**
- `/Users/magnus/repos/hugin/src/munin-client.ts` — source of the canonical TS client
- `/Users/magnus/repos/ratatoskr/src/munin-client.ts` — target of copy
- `/Users/magnus/repos/heimdall/src/lib/munin-client.js` (new) — CommonJS adapter
- `/Users/magnus/repos/heimdall/src/{munin-projects,collector,self-heal,skuld-briefing,munin-sync,mcp-probe}.js` — consumers to be migrated
- `/Users/magnus/repos/skuld/src/collectors/munin.ts` — SQLite reader to wrap
- `/Users/magnus/repos/skuld/src/collectors/munin-fast-path.ts` (new) — interface wrap

---

### Phase B — Targeted security review (3 sessions, concurrent with Phase A where possible)

**Goal:** `/security-review` on the three highest-blast-radius repos.

**Order and rationale:**

1. **munin-memory first.** Holds all memories, API keys (in env, not stored),
   the audit log, the consolidation worker's OpenRouter integration.
   Compromise = total ecosystem compromise. Shard by module if needed
   (`tools.ts` → `db.ts` → `index.ts` → `consolidation.ts` → everything
   else). Runs in parallel with Phase A's early items.

2. **hugin second.** Executes CLI commands via `@anthropic-ai/claude-agent-sdk`.
   Prompt-injection into Hugin = arbitrary code execution on the Pi.
   **Scheduled AFTER Phase A #1 completes** — the canonical client behavior
   must be stable before reviewing how hugin uses it, because transport-
   level security findings (bearer auth, session correlation, retry-on-5xx)
   may force changes to the canonical client.

3. **ratatoskr third.** Accepts arbitrary Telegram input and triages it
   into tasks. Prompt injection, webhook handling, bot token storage.

**Not in scope for this phase:** mimir, fortnox-mcp, heimdall, verdandi,
skuld. They have lower blast radius and can wait. (This is a deliberate
narrowing from the original 9-repo plan; the "nice to have" repos are
explicitly deferred.)

**Per-repo workflow:**
1. Run `/security-review` on the repo, sharded if needed.
2. Open one GitHub issue on the repo titled `security review: <repo>` with
   severity-grouped checklist (blocker/major/minor).
3. Label: `review/security`, severity labels.
4. Add to Grimnir Roadmap project via `gh project item-add`.
5. Fix blockers + majors immediately in a follow-up PR.

**Critical coupling with Phase A:** if munin-memory's security review
surfaces findings that invalidate the canonical Hugin client (auth
handling, session correlation, retry semantics), the Phase A items #1
and #2 must be redone. Check for this explicitly before declaring Phase A
done.

**Deliverable:** a `grimnir/docs/threat-model.md` with three sections (one
per reviewed repo) listing trust boundaries, data flows, LLM Top 10
mappings, and the consolidated fix list. Not a full ecosystem threat model —
just the three repos.

**Exit criterion:** threat-model.md exists; three GitHub issues exist; zero
blockers open; any security finding that invalidates Phase A has been
applied to the canonical client.

---

### Phase C — Minimum CI floor (1 session, conditional)

**Goal:** install the minimum CI that keeps Phase A's fixes from drifting.
**Run this phase only if Phase A's hash check and contract tests are not
already catching real drift on their own.**

**Concrete deliverables (if run):**

1. **A single GitHub Actions workflow file** per repo that runs:
   - `npm ci`
   - `npm run build` (skip for heimdall — no build script)
   - `npm test`
   - For repos with the hash check: verify MuninClient hash matches.
   - For repos with contract tests: run them.

2. **No shared ESLint config.** No shared prettier. No shared tsconfig. No
   knip. No `format:check`. Each repo keeps its own (current) config. The
   only thing this phase adds is a test runner in CI.

3. **Heimdall CI uses `node --test`** instead of the vitest pattern used
   elsewhere. Do not migrate to vitest during this phase.

**Explicit failure condition — do NOT run Phase C if:**
- Phase A's tests already catch the drift scenarios the CI would cover.
- The user has moved on to other work and Phase C starts becoming a
  "someday" task.
- Any repo requires more than trivial config changes to accept the
  workflow (e.g., adding a `build` script where none exists is not
  trivial — that's out of scope).

**Why this is conditional:** Codex's critique that "a conditional CI
floor for a solo maintainer is the class of work that never ships" is
accepted. If it never ships, that's fine as long as Phase A's tests are
doing the drift-detection job. Phase C exists as a safety net, not a
commitment.

**Exit criterion (if run):** each of the 3-5 active repos
(hugin, ratatoskr, skuld, munin-memory, heimdall) has a CI workflow that
runs on PR and blocks merge on test failure.

---

## Explicitly dropped from this plan

| Dropped item | Why |
|---|---|
| Phase 0 bootstrap | Required multi-repo implementation work disguised as setup. The proposed runner couldn't actually run. |
| Shared workspace packages inside `munin-memory/packages/` | Consumers are separate repos with their own deploy paths; workspace doesn't solve distribution. |
| Shared ESLint / tsconfig / prettier | Load-bearing Phase 0 content that no longer exists. Per-repo configs stay. |
| `knip` adoption | No evidence dead code is a current failure source. `tsc --noUnusedLocals` alone is fine if anything. |
| `ts-prune`, `depcheck`, `ts-unused-exports` | Same reason. |
| Heimdall JS→TS migration | Aesthetic, not on critical path. Deferred indefinitely. |
| Per-repo quality sweep (Phase 3 in v1) | Project-completion work, not bug-fix work. 8 sessions of lint cleanup is not what the user needs. |
| Architecture review document (Phase 4 in v1) | Speculative. Do it if Phase A+B surface a real need. |
| Maintenance loop (Phase 5 in v1) | Weekly review runner, Skuld briefing integration, Heimdall dashboard card, auto-fix Hugin tasks, `/review-repo` skill, `/review-integration` skill — all deferred indefinitely. |
| Dual tracking (GitHub + Munin findings) | Divergence risk. GitHub Issues only. |
| Weekly `grimnir-review.timer` | Part of the dropped maintenance loop. |
| Full 9-repo security review | Narrowed to the 3 repos with catastrophic blast radius (munin-memory, hugin, ratatoskr). The others can wait. |
| mimir security review in this pass | Explicitly deferred. It's important but lower-blast-radius than the central hub. Open a separate issue to track. |
| Python tooling (ruff, vulture) | No Python in the ecosystem. |
| Message queue adoption (Redis/NATS) | Overkill for solo-user Pi; retry semantics centralized in MuninClient instead. |

---

## Execution with Claude Code

**Session-by-session breakdown (minimum path):**

| Session | Content | Model |
|---|---|---|
| 1 | Step 0 — write the contracts spec in `architecture.md` | opus |
| 2 | Phase A #1+#2 — canonical MuninClient in ratatoskr (copy), heimdall adapter (new) | sonnet |
| 3 | Phase A #3 — skuld interface wrap | sonnet |
| 4 | Phase A #4 — three contract tests | sonnet |
| 5 | Phase A #5 — header comments documenting contract ownership per file | haiku |
| 6 | Phase B — `/security-review` on munin-memory (sharded) | opus |
| 7 | Phase B — `/security-review` on hugin (after Phase A #1 stable) | opus |
| 8 | Phase B — `/security-review` on ratatoskr | opus |
| 9 | Draft `grimnir/docs/threat-model.md` from the three reviews | sonnet |
| 10 (conditional) | Phase C — minimum CI floor on relevant repos, only if needed | sonnet |

Minimum program: ~9 sessions. Conditional 10th if Phase A's tests don't
provide enough coverage.

**Subagent usage:**
- Step 0: direct work in the main session (documentation, not code).
- Phase A: one implementer subagent per work item.
- Phase B: no subagents — `/security-review` skill is expensive and
  benefits from focused context per repo.
- Phase C: one implementer subagent if run.

**Findings workflow (GitHub Issues only):**
1. Open one GitHub issue per reviewed repo per phase.
2. Title format: `<phase>: <scope> — <repo>`.
3. Labels: `review/<dimension>`, `severity/<level>`.
4. Add to Grimnir Roadmap project: `gh project item-add 1 --owner Magnus-Gille --url <issue-url>`.
5. Issue body links to the relevant contract in
   `grimnir/docs/architecture.md#cross-service-contracts`.

---

## Risks and mitigations (post-debate)

| Risk | Mitigation |
|---|---|
| Step 0 contract spec drifts from reality because nobody validates it | Phase A's contract tests are the validation. If the spec is wrong, tests fail. |
| Hugin's canonical client has subtle bugs that propagate to ratatoskr via copy | Phase B's hugin security review runs *after* the copy is stable — any bug found there gets fixed in the canonical source and re-propagates. |
| Heimdall adapter semantics drift from the canonical TS client | The adapter's fixture-based contract test (Phase A #4 test 1 runs against heimdall's adapter too). Add heimdall to the test matrix. |
| munin-memory security review finds transport-level issues that invalidate the canonical client | Known risk — explicitly checked for before declaring Phase A done. Phase B hugin review scheduled after Phase A #1 to force the question. |
| The user skips Step 0 because it feels like "just documentation" | This plan file says explicitly: **nothing else ships until Step 0 is done**. If the user pushes past it, the debate's core finding is being ignored. |
| Phase C never ships | Acceptable as long as Phase A's tests are catching drift. Phase C exists as a safety net, not a commitment. |
| The three contract tests become one because "it's easier" | Explicit in this plan: three tests, not one. Codex's critique C12 is the reason. |
| Solo-maintainer burnout on a 9-session program | 9 sessions is already a sharp narrowing from the original 20+. Each session produces a visible artifact. Step 0 alone probably unblocks the most urgent concerns. |
| A security finding in `munin-memory` requires a schema migration | Out of scope; open a separate issue. This plan only addresses review, not schema evolution. |

---

## What "done" looks like

- `grimnir/docs/architecture.md` has a "Cross-service contracts" section
  with named contracts, named owners, and a regression matrix.
- Ratatoskr's `munin-client.ts` is a hash-verified copy of hugin's.
- Heimdall's six Munin call sites all go through `heimdall/src/lib/munin-client.js`.
- Skuld's direct SQLite access is behind an interface with an HTTP fallback
  implementation.
- Three contract tests run green in CI on their respective repos.
- `grimnir/docs/threat-model.md` exists with sections for munin-memory,
  hugin, and ratatoskr.
- Zero open `review/security` blockers on those three repos.
- (Optionally, if Phase C ran) each of the 3-5 active repos has a CI
  workflow running `npm test` and the contract tests on PR.

That's it. This is **bug-fix done**, not **project-completion done**.

---

## Verification

**Per-step verification:**
- **Step 0:** `grimnir/docs/architecture.md` has the contracts section. Each
  contract has a named owner. A regression matrix lists the required tests.
- **Phase A #1:** `sha256sum hugin/src/munin-client.ts ratatoskr/src/munin-client.ts` returns matching hashes. Ratatoskr's tests still pass.
- **Phase A #2:** All six heimdall files import `./lib/munin-client.js`. No
  more hardcoded `http://127.0.0.1:3030/mcp`. `node --test` passes.
- **Phase A #3:** Skuld's briefing generation works with the SQLite fast
  path. A feature flag switches to the HTTP fallback and the briefing
  still works.
- **Phase A #4:** Three separate test files, each runnable via
  `npm test -- --grep=contract`. CI runs them on PR.
- **Phase A #5:** Every implementation file has a header comment pointing
  to the contract section.
- **Phase B:** `threat-model.md` exists. Three GitHub issues exist. Zero
  blockers open on the three reviewed repos.
- **Phase C (if run):** CI workflow files exist in the repo. PRs fail if
  tests fail.

**End-to-end smoke test:**
1. Make a change in ratatoskr's `munin-client.ts` that diverges from
   hugin's — CI fails on the hash check.
2. Make a change in munin-memory's schema that breaks the Skuld fast path
   — the Skuld SQLite/HTTP equivalence test fails.
3. Make a change in hugin's task pickup that rejects heimdall-shaped
   self-heal entries — the Hugin regression test fails.
4. Read `grimnir/docs/architecture.md` from a fresh Claude session and
   confirm the contract ownership is unambiguous.

---

## Debate trail

Full stress-test of this plan is in `/Users/magnus/repos/grimnir/debate/`:
- `ecosystem-review-snapshot.md` — original 5-phase plan
- `ecosystem-review-claude-draft.md` — debate position summary
- `ecosystem-review-claude-self-review.md` — self-critique (caught 5/15)
- `ecosystem-review-codex-critique.md` — Codex Round 1 (8 findings)
- `ecosystem-review-claude-response-1.md` — Round 1 response with concessions
- `ecosystem-review-codex-rebuttal-1.md` — Codex Round 2 (7 new findings)
- `ecosystem-review-critique-log.json` — structured log of 15 critique points
- `ecosystem-review-summary.md` — final verdict and action items

Codex's single most important next step, accepted and incorporated as Step 0:
*"Before doing any copying or parallel security work, write the contract spec
first: a short `grimnir/docs/architecture.md` section that names the canonical
Munin transport contract, the Hugin task-schema contract, the owner of each
contract, and the minimum regression matrix required to protect them."*

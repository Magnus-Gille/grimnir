# Grimnir Development Plan — SCION Pattern Integration

> **DRAFT v0.1** — 2026-03-29. Plan only — no implementation.
> Patterns sourced from SCION↔Grimnir technical review.
> Debated with synthetic Codex adversarial review (see §5).

---

## 1. Executive Summary

Three architectural patterns from SCION are candidates for integration into Grimnir:

| Pattern | What it enables | Primary target |
|---------|----------------|----------------|
| **3D Agent State Model** (Phase/Activity/Detail) | Rich observability into what Hugin-spawned agents are doing | Hugin + Munin + Heimdall |
| **Git Worktree Isolation** | Safe parallel task execution without repo conflicts | Hugin |
| **Template Chain Config Inheritance** | Composable, DRY task specifications | Hugin + all task submitters |

These patterns are ordered by implementation sequence — state model first (enables observability for everything else), worktrees second (unlocks parallelism), templates third (quality-of-life once the execution model matures).

---

## 2. Pattern Designs

### 2.1 — 3D Agent State Model (Phase / Activity / Detail)

**Problem:** Hugin currently tracks task state with flat tags: `pending`, `running`, `completed`, `failed`. A running task is a black box — there is no visibility into what the agent is doing, how far along it is, or whether it's stuck.

**Current state:** The only signal during execution is the heartbeat (`tasks/_heartbeat`), which reports `current_task` and `uptime_s`. No granularity within a running task.

**Proposed model:**

```
┌─────────────────────────────────────────────────────┐
│                   Agent State Cube                   │
├──────────┬──────────────────┬────────────────────────┤
│  Phase   │    Activity      │  Detail                │
├──────────┼──────────────────┼────────────────────────┤
│ queued   │ —                │ —                      │
│ claiming │ —                │ CAS attempt count      │
│ starting │ resolving-context│ repo:heimdall → path   │
│ starting │ spawning-runtime │ agent-sdk / spawn      │
│ running  │ reading          │ src/index.ts           │
│ running  │ writing          │ src/self-heal.js       │
│ running  │ testing          │ npm test               │
│ running  │ searching        │ grep "health"          │
│ running  │ thinking         │ —                      │
│ running  │ tool-use         │ memory_write(...)      │
│ running  │ waiting          │ rate-limited / quota   │
│ post-run │ pushing          │ git push origin main   │
│ post-run │ writing-result   │ Munin result entry     │
│ post-run │ notifying        │ telegram:12345678      │
│ done     │ completed        │ exit 0, 142s           │
│ done     │ failed           │ exit 1, error msg      │
│ done     │ timed-out        │ exceeded 300s          │
└──────────┴──────────────────┴────────────────────────┘
```

**Storage:** Extend the heartbeat entry (`tasks/_heartbeat`) or write per-task state entries:

```
Namespace: tasks/<task-id>
Key: agent-state
Content: { "phase": "running", "activity": "writing", "detail": "src/self-heal.js", "updated_at": "..." }
Tags: ["agent-state"]
```

**Data sources for Activity/Detail:**
- **Agent SDK executor:** Parse streaming message events (`tool_use`, `text`) to infer activity. The SDK already emits structured events.
- **Legacy spawn executor:** Parse stdout line-by-line for patterns (tool names, file paths, test output). Heuristic, not authoritative.
- **Post-run phases:** Controlled by Hugin directly (deterministic).

**Consumers:**
- **Heimdall:** Real-time task progress card on dashboard (phase indicator + activity text)
- **Ratatoskr:** `/status` command returns human-readable activity ("writing src/self-heal.js" instead of just "running")
- **Skuld:** Briefing can reference task progress context
- **Debugging:** When a task hangs, the last activity/detail shows where it got stuck

**Schema evolution:** Start with Phase only (low effort). Add Activity when SDK event parsing is built. Detail is optional enrichment.

### 2.2 — Git Worktree Isolation Strategy

**Problem:** Hugin executes one task at a time in the repo's main working directory. This means:
- No parallelism — a 5-minute task blocks the queue even if other tasks target different repos
- Shared state — a failed task can leave dirty git state that affects subsequent tasks
- No isolation — two tasks targeting the same repo cannot run concurrently

**Current state:** `currentTask` is a singleton. The poll loop processes one task, completes it, then polls again. The `postTaskGitPush()` function assumes it owns the repo.

**Proposed strategy:**

```
Before (current):
  /home/magnus/repos/heimdall/     ← Hugin works directly here
  /home/magnus/repos/munin-memory/ ← One at a time

After (worktree isolation):
  /home/magnus/repos/heimdall/                          ← Main worktree (untouched)
  /tmp/hugin-worktrees/heimdall-<task-id>/              ← Ephemeral per-task worktree
  /tmp/hugin-worktrees/munin-memory-<task-id>/          ← Can run in parallel
```

**Lifecycle:**

```
1. Task claimed
2. git worktree add /tmp/hugin-worktrees/<repo>-<task-id> -b hugin/<task-id>
3. Runtime spawned in worktree directory
4. On completion:
   a. If exit 0: merge branch into main (or fast-forward), push
   b. If failed: log the branch name for forensics, prune worktree
5. git worktree remove /tmp/hugin-worktrees/<repo>-<task-id>
```

**Parallelism model (phased):**

| Level | Description | Concurrency |
|-------|-------------|-------------|
| **L0** (current) | Sequential, shared directory | 1 task |
| **L1** (worktree, sequential) | Sequential, isolated worktree per task | 1 task, clean state |
| **L2** (worktree, cross-repo parallel) | Parallel across different repos | N tasks (1 per repo) |
| **L3** (worktree, same-repo parallel) | Parallel within same repo via worktrees | N tasks (merge complexity) |

**Recommendation:** Implement L1 first — same sequential model, but each task gets a fresh worktree. This provides isolation benefits without concurrency complexity. L2 follows naturally. L3 is future work with significant merge-conflict risk.

**Constraints on Pi:**
- Disk: Worktrees are cheap (shared `.git` objects), but `/tmp` on Pi is tmpfs (RAM). With 8 GB RAM, budget ~1 GB for worktrees.
- Alternative: Use `/home/magnus/.hugin/worktrees/` on SD card instead of tmpfs.
- Cleanup: Worktrees must be pruned aggressively — `git worktree prune` on startup and after each task.

**Impact on existing code:**
- `resolveContext()` returns worktree path instead of repo path
- `postTaskGitPush()` pushes from worktree, then cleans up
- New `WorktreeManager` class handles create/merge/prune lifecycle
- Health endpoint reports active worktrees

### 2.3 — Template Chain Config Inheritance

**Problem:** Task specs are flat markdown with all fields inline. Common patterns are repeated across tasks:
- Every Claude task sets `Runtime: claude`, `Timeout: 300000`
- Every Heimdall task sets `Context: repo:heimdall`
- Every Ratatoskr-submitted task sets `Reply-to: telegram:...`

There is no way to define defaults, override selectively, or compose task specifications from reusable fragments.

**Current state:** Each task submitter (Claude Desktop, Ratatoskr, Heimdall self-heal) constructs the full task spec from scratch. Ratatoskr hardcodes `Runtime: claude`. Self-heal hardcodes its timeout.

**Proposed inheritance chain:**

```
┌─────────────────────────────────────────────────────┐
│                 Template Resolution                  │
│                                                      │
│  base.yaml          ← System-wide defaults           │
│    ↓ merges into                                     │
│  runtime/claude.yaml ← Runtime-specific overrides    │
│    ↓ merges into                                     │
│  context/heimdall.yaml ← Repo/context overrides      │
│    ↓ merges into                                     │
│  submitter/ratatoskr.yaml ← Submitter overrides      │
│    ↓ merges into                                     │
│  inline task fields   ← Per-task overrides (highest) │
└─────────────────────────────────────────────────────┘
```

**Example templates:**

```yaml
# templates/base.yaml
timeout: 300000
reply_format: summary
runtime: claude
model: default

# templates/runtime/claude.yaml
inherits: base
executor: sdk

# templates/runtime/codex.yaml
inherits: base
executor: spawn
timeout: 600000  # Codex tasks tend to run longer

# templates/context/heimdall.yaml
inherits: runtime/claude
timeout: 180000  # Heimdall tasks are fast
type_tags: ["type:infrastructure"]

# templates/submitter/ratatoskr.yaml
inherits: runtime/claude
reply_format: summary
type_tags: ["type:telegram"]

# templates/submitter/self-heal.yaml
inherits: runtime/claude
timeout: 120000
type_tags: ["type:self-heal", "type:infrastructure"]
```

**Resolution algorithm:**
1. Parse task spec, extract `Template:` field (if present)
2. Load template file, recursively resolve `inherits:` chain
3. Deep-merge: base → runtime → context → submitter → inline fields
4. Inline fields always win (highest precedence)

**Storage location:** `~/.hugin/templates/` on Pi (deployed with Hugin, not in Munin).

**Backward compatibility:** Templates are opt-in. Existing task specs without `Template:` work exactly as before. The chain only activates when:
- A `Template:` field is present in the task spec, OR
- Hugin auto-matches based on `Runtime:` + `Context:` + `Submitted by:` fields

**New task spec field:**
```markdown
- **Template:** context/heimdall
```

---

## 3. Implementation Plan

### Phase A: 3D Agent State — Observability Foundation

| Item | Priority | Effort | Depends on | Risk |
|------|----------|--------|------------|------|
| A1: Define state schema (Phase enum + Munin entry format) | **High** | 2h | — | Low — schema only |
| A2: Emit Phase transitions from Hugin (queued→claiming→running→done) | **High** | 4h | A1 | Low — wraps existing lifecycle |
| A3: Parse SDK streaming events for Activity inference | **Medium** | 6h | A1, A2 | Medium — SDK event format may change |
| A4: Heimdall task progress card (reads agent-state entries) | **Medium** | 4h | A2 | Low — read-only UI |
| A5: Ratatoskr `/status` enrichment (show activity not just "running") | **Low** | 2h | A2 | Low |
| A6: Detail-level parsing (file paths, test names from stdout) | **Low** | 4h | A3 | Medium — heuristic, fragile |

**Sequence:** A1 → A2 → A3 → A4 (can parallel with A3) → A5 → A6

**Total effort:** ~22h | **Calendar estimate:** 1–2 weeks (interleaved with other work)

### Phase B: Git Worktree Isolation

| Item | Priority | Effort | Depends on | Risk |
|------|----------|--------|------------|------|
| B1: `WorktreeManager` class (create, merge, prune, cleanup) | **High** | 6h | — | Medium — git edge cases |
| B2: Integrate into Hugin task lifecycle (L1: sequential + worktree) | **High** | 4h | B1 | Medium — changes core execution path |
| B3: Startup recovery (prune orphaned worktrees) | **High** | 2h | B1 | Low |
| B4: Update `postTaskGitPush()` for worktree branches | **High** | 3h | B2 | Medium — merge strategy decisions |
| B5: Health endpoint reports active worktrees | **Low** | 1h | B2 | Low |
| B6: L2 parallelism (concurrent cross-repo execution) | **Medium** | 8h | B2 | High — concurrency bugs, Pi resource limits |
| B7: L3 same-repo parallelism (worktree per task, merge conflicts) | **Low** | 12h | B6 | High — merge conflicts, race conditions |

**Sequence:** B1 → B2 + B3 (parallel) → B4 → B5 → B6 → B7

**Total effort:** ~36h | **Calendar estimate:** 2–3 weeks

**Gate:** B6 (parallel execution) should NOT proceed until A2 (phase transitions) is live — parallelism without observability is blind.

### Phase C: Template Chain Config Inheritance

| Item | Priority | Effort | Depends on | Risk |
|------|----------|--------|------------|------|
| C1: Template schema design (YAML format, inheritance rules) | **Medium** | 2h | — | Low |
| C2: Template loader with recursive `inherits:` resolution | **Medium** | 4h | C1 | Low — well-understood pattern |
| C3: Deep-merge into Hugin `parseTask()` | **Medium** | 4h | C2 | Medium — must not break existing tasks |
| C4: Auto-matching (infer template from Runtime + Context + Submitter) | **Low** | 3h | C3 | Medium — implicit behavior can surprise |
| C5: Ship default templates (base, runtime/*, context/*, submitter/*) | **Medium** | 2h | C1 | Low |
| C6: Ratatoskr uses templates instead of hardcoded defaults | **Low** | 2h | C3 | Low |
| C7: Heimdall self-heal uses templates | **Low** | 1h | C3 | Low |

**Sequence:** C1 → C2 → C3 + C5 (parallel) → C4 → C6 + C7 (parallel)

**Total effort:** ~18h | **Calendar estimate:** 1 week

### Overall Sequence

```
Week 1–2:  Phase A (state model) — foundation for observability
Week 2–3:  Phase B1–B5 (worktree L1) — isolation without parallelism
Week 3–4:  Phase C (templates) — DRY task specs
Week 4+:   Phase B6 (L2 parallelism) — only after A+B1 are proven stable
Future:    Phase B7 (L3 same-repo) — deferred until clear need emerges
```

### Priority Summary

| Priority | Items | Total Effort |
|----------|-------|-------------|
| **High** | A1, A2, B1, B2, B3, B4 | ~21h |
| **Medium** | A3, A4, B6, C1, C2, C3, C5 | ~32h |
| **Low** | A5, A6, B5, B7, C4, C6, C7 | ~23h |

---

## 4. Risk Register

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| **SDK event format changes** break Activity parsing (A3) | Medium | Medium | Pin SDK version; treat Activity as best-effort, never fail task on parse error |
| **Worktree merge conflicts** on same-repo parallel (B7) | High | High | Defer B7 until clear need; L1/L2 avoid this entirely |
| **Pi disk/RAM pressure** from worktrees (B2+) | Medium | Low | Use SD card path not tmpfs; aggressive pruning; monitor via Heimdall |
| **Template auto-matching** causes unexpected behavior (C4) | Medium | Medium | Make auto-matching opt-in via env var; log which template was applied |
| **Observability overhead** — frequent Munin writes from state updates (A2) | Low | Medium | Throttle state writes to max 1/10s per task; batch Phase transitions |
| **Breaking existing task specs** during template integration (C3) | High | Low | Templates are strictly additive; zero-template path is identical to current |
| **Concurrency bugs** in L2 parallel execution (B6) | High | Medium | Comprehensive test suite; staged rollout (2 concurrent max, then increase) |
| **Scope creep** — building L3 before L1 is proven | Medium | Medium | Hard gate: B7 requires 2 weeks of stable B6 operation |

---

## 5. Adversarial Review — Synthetic Codex Debate

The following debate follows Grimnir's established pattern: Claude drafts, Codex critiques, resolution is recorded.

### Round 1: Codex Critiques

**Critique 1: "The 3D state model is over-engineered for a single-user system."**

> Grimnir runs on two Raspberry Pis for one person. The current tag-based state (pending/running/completed/failed) covers 95% of use cases. The Activity and Detail dimensions add write amplification to Munin (potentially dozens of state updates per task) for observability that Magnus will check maybe once a week. YAGNI applies — build it when the single-task sequential model actually causes a missed diagnosis.

**Critique 2: "Worktrees on a Pi are a resource trap."**

> A Raspberry Pi 5 has 8 GB RAM and an SD card. Git worktrees share objects but still duplicate the working tree. A medium repo (100 MB working tree) × 3 concurrent tasks = 300 MB of duplicated files. On tmpfs, that's RAM gone. On SD card, that's write amplification on flash storage with limited endurance. The current "one task at a time" model is not a bug — it's a feature that matches the hardware constraints. Parallelism should be solved by adding a second Pi as a worker, not by squeezing more concurrency out of one.

**Critique 3: "Template inheritance adds indirection without clear payoff."**

> Grimnir has exactly 3 task submitters: Claude environments (manual), Ratatoskr (Telegram), and Heimdall self-heal. Each submits maybe 5-10 tasks/day. The "DRY" benefit of templates saves ~3 lines per task spec. Meanwhile, debugging a task failure now requires tracing through a 4-level inheritance chain to understand what timeout was actually applied. For a system this small, explicit is better than implicit. Just hardcode the defaults in each submitter.

**Critique 4: "Phase B6 (cross-repo parallelism) has hidden complexity."**

> When two tasks run in parallel and both write results to Munin, they share the same Munin connection. If one task's result write fails and retries while the other is mid-write, you get interleaved or lost results. The current `currentTask` singleton is load-bearing — it's not just a variable, it's a concurrency guard. Removing it requires proper task isolation including independent Munin clients, separate log streams, and process-level isolation. That's a much bigger lift than "change the poll loop to spawn multiple."

**Critique 5: "You're sequencing this backwards."**

> Templates (Phase C) should come before worktrees (Phase B). Templates are low-risk, immediately useful, and make worktree integration easier (worktree-specific config can be a template layer). Building worktrees first means you'll retrofit template support into the worktree manager later.

### Round 2: Claude Responses

**Response to Critique 1 (over-engineering):**

*Partially accepted.* The full 3D model is premature. However, Phase transitions (A1+A2) are cheap — 4-5 state writes per task lifecycle, all at natural boundaries that already exist in the code. This gives Heimdall the ability to show "post-processing" vs "running" vs "claiming" which solves real debugging scenarios (e.g., "why has this task been 'running' for 10 minutes?" → it's actually stuck in post-push). **Amendment:** A3 (Activity inference) and A6 (Detail parsing) are demoted to "build when L2 parallelism makes the black-box problem acute."

**Response to Critique 2 (Pi resource trap):**

*Accepted in part.* tmpfs is wrong — worktrees go on SD card at `~/.hugin/worktrees/`. But the core value of worktrees is isolation, not parallelism. Even at L1 (sequential), a worktree prevents dirty git state from leaking between tasks. The "add a second Pi" alternative is valid for scaling but doesn't solve the isolation problem. **Amendment:** B6/B7 effort estimates increased; B7 explicitly deferred to "future" with a hardware prerequisite (second compute Pi or SSD upgrade).

**Response to Critique 3 (template indirection):**

*Mostly accepted.* With 3 submitters and <10 tasks/day, the DRY savings are marginal. However, templates become valuable if/when: (a) Grimnir reaches Phase 3 (proactive — system submits its own tasks), or (b) new submitters emerge. **Amendment:** Phase C priority downgraded from Medium to Low for C4 (auto-matching). C1-C3 remain Medium as infrastructure investment. Add mandatory logging: every task result includes `resolved_template: base → runtime/claude → inline` for debuggability.

**Response to Critique 4 (hidden parallelism complexity):**

*Accepted.* B6 effort estimate was underscoped. Each parallel task needs: independent MuninClient instance, separate log stream, isolated output buffer, and process-level signal handling. **Amendment:** B6 effort revised from 8h to 14h. New prerequisite: B6 requires a `TaskRunner` class that encapsulates all per-task state (extracted from the current module-level singletons).

**Response to Critique 5 (sequencing):**

*Rejected.* Templates are useful but not blocking. The state model (Phase A) is prerequisite for everything — without observability, you can't safely validate worktree behavior or debug template resolution. Worktrees (Phase B) unlock the isolation guarantee that makes Grimnir trustworthy enough for Phase 2 (self-maintaining) of the vision. Templates (Phase C) are quality-of-life. The sequence A→B→C reflects dependency, not just priority.

### Debate Resolution

| Critique | Verdict | Impact on plan |
|----------|---------|----------------|
| Over-engineered state model | Partially accepted | A3, A6 demoted; A1+A2 unchanged |
| Pi resource trap | Partially accepted | Worktrees on SD card, not tmpfs; B7 deferred with hardware gate |
| Template indirection | Mostly accepted | C4 demoted to Low; mandatory template resolution logging added |
| Hidden parallelism complexity | Accepted | B6 effort ↑ to 14h; TaskRunner extraction prerequisite added |
| Backwards sequencing | Rejected | A→B→C order maintained; rationale strengthened |

### Revised Effort Totals (Post-Debate)

| Phase | Original | Revised | Delta |
|-------|----------|---------|-------|
| A (State Model) | 22h | 16h | −6h (A3/A6 deprioritized) |
| B (Worktrees) | 36h | 42h | +6h (B6 rescoped) |
| C (Templates) | 18h | 18h | unchanged |
| **Total** | **76h** | **76h** | net zero |

---

## 6. Success Criteria

| Pattern | Success metric | Measurable by |
|---------|---------------|---------------|
| 3D State Model | Heimdall shows task phase in real-time; mean time to diagnose stuck tasks drops | Heimdall dashboard + operator experience |
| Worktree Isolation | Zero dirty-state incidents between consecutive tasks; task failure never corrupts repo | Hugin invocation journal (no "recovered stale" entries from state leaks) |
| Template Chain | New submitter can be added with <20 lines of config (no task spec boilerplate) | Lines of code per new submitter |

---

## 7. Dependencies & Prerequisites

| Prerequisite | Required by | Status |
|--------------|-------------|--------|
| Agent SDK streaming events API stability | A3 | ⚠️ Verify SDK version pinning |
| Munin write throughput (state update frequency) | A2 | ✅ Current throughput sufficient for 1/10s writes |
| SD card write endurance for worktree churn | B2+ | ⚠️ Monitor with Heimdall disk metrics |
| `TaskRunner` class extraction from Hugin singletons | B6 | 🔲 New prerequisite from debate |
| YAML parser dependency in Hugin | C2 | ✅ Trivial (js-yaml or built-in) |

---

## 8. What This Plan Does NOT Cover

- **Multi-Pi worker pool** — Distributing tasks across multiple Pis. Valid scaling path but out of scope.
- **Agent memory between tasks** — Agents sharing learned context across tasks. Addressed by Munin's existing memory model.
- **Rollback/undo for autonomous actions** — Critical for Phase 3-4 of vision. Separate design needed.
- **Cost optimization** — Task routing based on quota/cost. Hugin already tracks quota; routing logic is separate.
- **SCION integration itself** — This plan adopts SCION's *patterns*, not its codebase.

---

*Plan authored by Claude, debated with synthetic Codex adversarial review.*
*Built for the Grimnir system — two Raspberry Pis in Mariefred, Sweden.*

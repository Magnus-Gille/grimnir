# Documentation Authority Map

> Which source is canonical for each category of fact.
> When facts disagree, the authoritative source wins. All other sources must be updated to match.

## Fact ownership

| Fact type | Authoritative source | Derived by / consumers |
|-----------|---------------------|------------------------|
| **Port assignments** | `services.json` | `generate-architecture.sh`, `deploy.sh`, `security-scan.sh`, `docs/architecture.md` |
| **SSH and consumer-health hostnames** | `services.json` | `deploy.sh`, `generate-architecture.sh`, `docs/architecture.md` |
| **Deploy paths, targets, desired runtime state, systemd units & timer semantics** | `services.json` | `deploy.sh`, `generate-architecture.sh` |
| **Systemd unit structure / templates** | Owning component repo | `deploy.sh` installs install-ready units byte-for-byte or renders the bounded registry placeholders |
| **Host systemd runtime identity, home, deploy target, private-environment paths and exact external sandbox dependencies** | `services.json` | `deploy.sh`, `render-systemd-units.sh` |
| **Persistent/runtime paths and component-specific rsync exclusions** | `services.json` | `deploy.sh`, registry validation |
| **Global rsync safety exclusions** (`.env`, `.git`, dependencies, tests, deploy marker) | `scripts/deploy.sh` | deploy persistence tests |
| **Deployment source identity** (expected worktree + immutable revision) | `scripts/lib/deploy-source.sh` | deploy source-revision tests |
| **Component inventory** | `services.json` | all scripts, `docs/conventions.md` (references it) |
| **Repo names / GitHub ownership / canonical local checkout mapping** | `services.json` (`components[].repo` plus `repository_authority`) | `docs/conventions.md`, worktree-hygiene audit |
| **Service patterns / conventions** | `docs/conventions.md` | per-repo CLAUDE.md |
| **Component roles (short)** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **System design philosophy / rationale** | `docs/architecture.md` | per-repo CLAUDE.md (may reference) |
| **Component design rationale** | Per-repo `CLAUDE.md` | `docs/architecture.md` (may summarize), generator (inlines) |
| **Live deployment state** | `generate-architecture.sh` output | Skuld, Heimdall |
| **Project status / roadmap** | Munin `projects/*/status` | Skuld briefing, workbench |
| **Cross-component data flow** | `docs/architecture.md` | generator (may diagram) |
| **Learning-task seam, field/decision ownership & compatibility rules** | `docs/learning-task-contract.md` plus `docs/learning-task-contract-v1.schema.json` | Hugin and `gille-inference` producer/consumer schemas and fixtures |
| **Self-improvement mechanism state & delivery sequence** | `docs/observability-and-improvement.md` | `docs/architecture.md`, component plans and Roadmap issues |
| **Improvement scope (routing/configuration vs model weights)** | `docs/adr-006-learning-improvement-scope.md` | learning docs, Hugin and `gille-inference` |
| **Hugin task/product facts** | Hugin's versioned task, result, receipt and experiment schemas | LearningTaskContract projection, Heimdall |
| **M5 exposure, served-model, capability & micro-routing facts** | `gille-inference` versioned schemas and ledger | LearningTaskContract projection, Hugin, Heimdall |
| **Desired node topology, workload placement and cross-component substrate policy** | `services.json` and [ADR-007](adr-007-node-substrate-contract.md) | Brokkr planning, workload contracts, Heimdall presentation |
| **Observed node capability, location/network/storage realization and substrate reconciliation evidence** | Brokkr's versioned observation/evidence contract | Grimnir drift view, component preflight, Heimdall presentation |
| **Workload requirements, drain/verify hooks, service-data migration and workload rollback** | Owning component repository's versioned contract | Brokkr lifecycle adapter, Grimnir planning, Heimdall presentation |
| **Node/workload reconciliation lifecycle result** | Brokkr for substrate steps; owning component for workload hooks | Grimnir promotion decision, Heimdall presentation |
| **Norse naming / mythology mapping** | `docs/conventions.md` | all docs |

## Rules

1. **Single writer per fact.** Each fact type has exactly one authoritative source. Other documents may restate the fact for readability, but the authoritative source is what gets updated first.

2. **Scripts read from `services.json`, never hardcode.** `deploy.sh`, `security-scan.sh`, and `generate-architecture.sh` all read component metadata (ports, hosts, deploy paths, units) from `services.json` via `scripts/lib/registry.js`. Hardcoded service lists in scripts are bugs.

3. **Restatements must cite.** When `docs/architecture.md` restates a port or hostname from `docs/conventions.md`, it should be understood as derived. If a discrepancy is found, `docs/conventions.md` wins.

4. **Munin is live state, not architecture.** Munin project statuses reflect current work and blockers. They are not authoritative for system design, ports, or conventions.

5. **Per-repo CLAUDE.md owns component-level detail.** If `docs/architecture.md` and a component's `CLAUDE.md` disagree on how that component works, the component's `CLAUDE.md` wins (it's closer to the code).

6. **Persistent paths mean runtime data, not globally protected deploy metadata.** Each
   rsync-deployed component declares its mutable runtime/data locations in `persistent_paths`.
   Component-specific in-target locations require a matching `rsync_excludes` entry. The deploy
   script separately preserves `.env` for every rsync component as global credential policy, so a
   component with `persistent_paths: []` does not imply that its in-target `.env` may be deleted.

7. **Deployment markers certify acceptance, not merely copied files.** `deploy.sh` captures the
   prior valid SHA and removes the marker before the first rsync/git-pull tree mutation. Dependency,
   unit-refresh, restart, or health failure leaves the target markerless/unknown until a verified
   rollback or redeploy writes a new accepted SHA.

8. **Timers are controller state, not just unit files.** After daemon reload, deploys enable and
   restart every declared timer. Timers default to recurring and must expose a concrete next trigger
   before acceptance. A timer whose only trigger is legitimately single-fire, such as a lone
   `OnBootSec`, must be declared with `timer_semantics: "one-shot"` in `services.json`.

9. **Unit rendering is explicit and bounded.** The owning component repo owns unit structure.
   Components without `systemd_runtime` remain install-ready artifacts: central deploy selects
   `systemd/{unit}` before root `{unit}` and installs the selected bytes. Opted-in components may
   use only the host placeholders defined in
   [`systemd-runtime-rendering.md`](systemd-runtime-rendering.md); the renderer validates runtime
   identity and every relevant path before restart. Unknown active placeholders always fail.
   Private values remain in required, host-owned environment files.

10. **The learning contract assigns authority; it does not centralize evidence.** Hugin owns its
    task/execution/product/correction and prompt/harness-experiment facts. `gille-inference` owns
    direct gateway-origin identity plus M5 exposure, effective serving identity, capability
    evidence, and micro-routing facts. A copy in Munin, Heimdall, or another repo remains derived
    and cannot fabricate the producer's verdict.

11. **Cross-repo contract changes are two-consumer changes.** A LearningTaskContract change is not
    complete until immutable synthetic fixtures pass in both Hugin and `gille-inference` and both
    owners review it. Unknown or incompatible decision-driving semantics fail closed.

12. **Runtime and deployment applicability are separate registry facts.**
    `desired_runtime_state` is `active`, `stopped`, or `not-applicable` (an omitted value defaults
    to strict `active` for compatibility). Active components require active declared units and
    successful HTTP health when a port is declared. Stopped components require cleanly inactive
    units and are not HTTP-probed; active or failed units are drift. Not-applicable components
    declare neither units nor a health port. Independently, only `deploy: true` components have a
    meaningful `.deployed-commit` marker. A `deploy: false` platform peer such as Brokkr can still
    have active timers, but marker validation is skipped.

13. **Desired, observed, required and lifecycle-result facts never overwrite each other.**
    `services.json` says what topology and placement are intended; it does not prove a host can
    currently realize them. Brokkr observations say what was evidenced on a node; they do not
    rewrite intent. Component requirements and hooks define application behaviour; Brokkr does
    not absorb them. A lifecycle result records one attempt and is neither desired state nor an
    observation. See [ADR-007](adr-007-node-substrate-contract.md).

14. **Decision-driving uncertainty fails closed.** Missing, stale, malformed or incompatible
    observed evidence, a required Brokkr preflight, or a required workload hook is `unknown` or
    `blocked`, never an inferred success. Heimdall can transport and present evidence but is not
    a topology authority. Private network identity, Wi-Fi details, credentials and live locators
    remain in owner-only overlays; public shared schemas use safe examples.

15. **Mutating hooks are attempt-bound and compensated.** Read-only preflight is distinct from
    drain, apply, rollback and other mutating lifecycle actions. Their invocations and results bind
    to the exact plan, desired revision, observations, deadline and idempotency key. A failed,
    timed-out or partial mutation must restore and verify its declared baseline before another
    attempt; old evidence cannot be replayed to promote a new plan.

16. **Substrate partial failure is Brokkr-owned rollback.** A failed, timed-out or partially
    applied network, storage or location action restores and verifies its recorded substrate
    pre-state before workload compensation or retry. Incomplete substrate rollback is terminally
    blocked; a later attempt cannot relabel it as fresh work.

## Validation

The generator should warn on discrepancies it can detect:
- Port in `services.json` vs port in component's source code / env config
- Systemd units in `services.json` vs units actually present on the host
- Component repos in `services.json` vs directories in `~/repos/`
- Deploy path in `services.json` vs WorkingDirectory / EnvironmentFile paths in unit files
- Git-pull checkout HEAD vs the exact live `origin/main` SHA (an unreachable origin is never current)
- Missing, symlinked, or malformed rsync deployment markers

The standalone worktree-hygiene audit additionally warns when a canonical
local checkout's `origin` disagrees with the GitHub repository identity in
`services.json.repository_authority`, including archived predecessors.

## Document boundary: `architecture.md` vs `snapshot.md`

The generator assembles `full-architecture.md` from two sources. This table defines what belongs where.

| Fact domain | Owned by | Examples |
|-------------|----------|----------|
| System topology, hardware, network model | `architecture.md` | Pi specs, Tailscale IPs, port assignments, architecture diagram |
| Component roles, design rationale | `architecture.md` | What Munin does, why Hugin is single-threaded, security model |
| Deployment patterns, access matrix | `architecture.md` | How deploys work, which env can access which service |
| Tech stack, conventions | `architecture.md` | Node.js version, SQLite choice, systemd for scheduling |
| Roadmap, design philosophy | `architecture.md` | "What's Next", north star, debate process |
| GitHub ownership, naming | `architecture.md` (derived from `conventions.md`) | Repo names, org accounts |
| **Service runtime state** | `snapshot.md` | systemd active/inactive, PID, memory, uptime |
| **Health check results** | `snapshot.md` | HTTP status codes from `/health` endpoints |
| **Git version per repo** | `snapshot.md` | Current commit hash, branch, dirty status |
| **Munin project statuses** | `snapshot.md` | Current phase, blockers, recent activity (from Munin) |
| **Dependency inventory** | `snapshot.md` (optional appendix) | npm packages across all repos |

**Rules:**
1. `snapshot.md` must never contain roles, ports, or topology — those are architecture facts.
2. `architecture.md` must never contain timestamped operational state.
3. The generator reads `architecture.md` as-is and appends `snapshot.md`. No parsing, no splicing, no placeholders.
4. If a fact could go in either place, it belongs in `architecture.md` (stable wins).

## Change protocol

When a fact changes (e.g., a service moves to a new port):

1. Update the authoritative source first (`services.json` for ports/hosts/deploy paths/units, `conventions.md` for patterns/naming)
2. Update all derived sources (or note them for the next session)
3. No script should need updating — they all read from `services.json` via `scripts/lib/registry.js`

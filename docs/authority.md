# Documentation Authority Map

> Which source is canonical for each category of fact.
> When facts disagree, the authoritative source wins. All other sources must be updated to match.

## Fact ownership

| Fact type | Authoritative source | Derived by / consumers |
|-----------|---------------------|------------------------|
| **Port assignments** | `services.json` | `generate-architecture.sh`, `deploy.sh`, `security-scan.sh`, `docs/architecture.md` |
| **Hostnames / hosts** | `services.json` | `deploy.sh`, `generate-architecture.sh`, `docs/architecture.md` |
| **Deploy paths, targets, systemd units & timer semantics** | `services.json` | `deploy.sh`, `generate-architecture.sh` |
| **Install-ready systemd unit contents** | Owning component repo | `deploy.sh` installs selected `systemd/{unit}` or root `{unit}` bytes without rendering |
| **Persistent/runtime paths and component-specific rsync exclusions** | `services.json` | `deploy.sh`, registry validation |
| **Global rsync safety exclusions** (`.env`, `.git`, dependencies, tests, deploy marker) | `scripts/deploy.sh` | deploy persistence tests |
| **Component inventory** | `services.json` | all scripts, `docs/conventions.md` (references it) |
| **Repo names / GitHub ownership** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **Service patterns / conventions** | `docs/conventions.md` | per-repo CLAUDE.md |
| **Component roles (short)** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **System design philosophy / rationale** | `docs/architecture.md` | per-repo CLAUDE.md (may reference) |
| **Component design rationale** | Per-repo `CLAUDE.md` | `docs/architecture.md` (may summarize), generator (inlines) |
| **Live deployment state** | `generate-architecture.sh` output | Skuld, Heimdall |
| **Project status / roadmap** | Munin `projects/*/status` | Skuld briefing, workbench |
| **Cross-component data flow** | `docs/architecture.md` | generator (may diagram) |
| **Learning-task seam, field/decision ownership & compatibility rules** | `docs/learning-task-contract.md` | Hugin and `gille-inference` producer/consumer schemas and fixtures |
| **Self-improvement mechanism state & delivery sequence** | `docs/observability-and-improvement.md` | `docs/architecture.md`, component plans and Roadmap issues |
| **Improvement scope (routing/configuration vs model weights)** | `docs/adr-006-learning-improvement-scope.md` | learning docs, Hugin and `gille-inference` |
| **Hugin task/product facts** | Hugin's versioned task, result, receipt and experiment schemas | LearningTaskContract projection, Heimdall |
| **M5 exposure, served-model, capability & micro-routing facts** | `gille-inference` versioned schemas and ledger | LearningTaskContract projection, Hugin, Heimdall |
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

9. **Declared unit sources are install-ready artifacts, not templates.** The owning component repo
   owns unit contents. Central deploy selects `systemd/{unit}` before root `{unit}` and installs the
   selected bytes without component-specific rendering. Unresolved angle-bracket identifiers on
   active unit lines fail preflight; template files must use a different name or live outside those
   selected paths. Placeholder prose in comments is allowed.

10. **The learning contract assigns authority; it does not centralize evidence.** Hugin owns task,
    execution, product, correction, and prompt/harness-experiment facts. `gille-inference` owns M5
    exposure, effective serving identity, capability evidence, and micro-routing facts. A copy in
    Munin, Heimdall, or another repo remains derived and cannot fabricate the producer's verdict.

11. **Cross-repo contract changes are two-consumer changes.** A LearningTaskContract change is not
    complete until immutable synthetic fixtures pass in both Hugin and `gille-inference` and both
    owners review it. Unknown or incompatible decision-driving semantics fail closed.

## Validation

The generator should warn on discrepancies it can detect:
- Port in `services.json` vs port in component's source code / env config
- Systemd units in `services.json` vs units actually present on the host
- Component repos in `services.json` vs directories in `~/repos/`
- Deploy path in `services.json` vs WorkingDirectory / EnvironmentFile paths in unit files
- Git-pull checkout HEAD vs the exact live `origin/main` SHA (an unreachable origin is never current)
- Missing, symlinked, or malformed rsync deployment markers

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

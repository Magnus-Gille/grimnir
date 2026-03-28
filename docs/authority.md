# Documentation Authority Map

> Which source is canonical for each category of fact.
> When facts disagree, the authoritative source wins. All other sources must be updated to match.

## Fact ownership

| Fact type | Authoritative source | Derived by / consumers |
|-----------|---------------------|------------------------|
| **Port assignments** | `docs/conventions.md` | `generate-architecture.sh`, `docs/architecture.md`, per-repo CLAUDE.md |
| **Hostnames / network topology** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **Deploy paths** | `docs/conventions.md` | per-repo deploy scripts, systemd units |
| **Repo names / GitHub ownership** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **Service patterns / conventions** | `docs/conventions.md` | per-repo CLAUDE.md |
| **Component roles (short)** | `docs/conventions.md` | `docs/architecture.md`, generator |
| **System design philosophy / rationale** | `docs/architecture.md` | per-repo CLAUDE.md (may reference) |
| **Component design rationale** | Per-repo `CLAUDE.md` | `docs/architecture.md` (may summarize), generator (inlines) |
| **Live deployment state** | `generate-architecture.sh` output | Skuld, Heimdall |
| **Project status / roadmap** | Munin `projects/*/status` | Skuld briefing, workbench |
| **Cross-component data flow** | `docs/architecture.md` | generator (may diagram) |
| **Norse naming / mythology mapping** | `docs/conventions.md` | all docs |

## Rules

1. **Single writer per fact.** Each fact type has exactly one authoritative source. Other documents may restate the fact for readability, but the authoritative source is what gets updated first.

2. **Generator reads, never invents.** `generate-architecture.sh` should read port assignments, roles, and hostnames from `docs/conventions.md` (or the repos themselves) rather than hardcoding them. Hardcoded values in the generator are bugs.

3. **Restatements must cite.** When `docs/architecture.md` restates a port or hostname from `docs/conventions.md`, it should be understood as derived. If a discrepancy is found, `docs/conventions.md` wins.

4. **Munin is live state, not architecture.** Munin project statuses reflect current work and blockers. They are not authoritative for system design, ports, or conventions.

5. **Per-repo CLAUDE.md owns component-level detail.** If `docs/architecture.md` and a component's `CLAUDE.md` disagree on how that component works, the component's `CLAUDE.md` wins (it's closer to the code).

## Validation

The generator should warn on discrepancies it can detect:
- Port in `conventions.md` vs port in component's source code / env config
- Port in `conventions.md` vs port hardcoded in the generator itself
- Service name mismatches between conventions and actual repos

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

1. Update the authoritative source first
2. Update all derived sources (or note them for the next session)
3. If the generator hardcodes the value, fix the generator too

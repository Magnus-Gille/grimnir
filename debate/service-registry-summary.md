# Debate Summary: Centralized Service Registry

**Date:** 2026-04-01
**Participants:** Claude (proposer), Codex (adversarial reviewer)
**Rounds:** 2

## Concessions accepted by both sides

1. **The problem is real** — 4+ hardcoded service lists have already drifted, causing Heimdall alerts
2. **node -e inline code generation is too fragile** — must use a proper JS helper with env vars, --input-type=commonjs, and error handling
3. **The authority split must be clean** — registry either replaces conventions.md's machine-readable facts entirely, or stays narrow. No middle ground.
4. **Heimdall validation is future work** — only generator-side validation is achievable now

## Defenses accepted by Codex

1. **JSON over TSV** — nested systemd_units data is a real requirement, not theoretical
2. **"Just fix the drift" doesn't prevent recurrence** — structural fix is warranted
3. **Making it truly authoritative is the right standard** — if doing this, go all the way

## Key issue surfaced in Round 2

**The central modeling decision:** Is the registry for "deployable Pi runtime services" or "all Grimnir components/repos"?

- `fortnox-mcp`/`noxctl` is laptop-only, no Pi host, no systemd unit — but `security-scan.sh` scans it
- If registry = Pi services only, `security-scan.sh` needs a separate repo list
- If registry = all components, the schema broadens and `host`/`systemd_units` become optional again

**Resolution for implementation:** The registry covers **all Grimnir components**, not just deployed services. The entity is "a Grimnir component" with optional deployment metadata. Components that aren't deployed to Pi simply have `host: null` and empty `systemd_units`. This is acceptable because:
- The set is small (8 components) and well-defined
- The alternative (two registries) is worse than a few null fields
- All three script consumers need component awareness, not just deploy awareness

## Unresolved disagreements

- Codex prefers a narrower manifest under `scripts/`; Claude argues repo root is appropriate for a system-level source of truth. Going with repo root since it replaces conventions.md's machine data.
- Cross-host validation remains unaddressed (generator only runs on Pi 1). Accepted as a known limitation.

## Action items

1. Create `services.json` at repo root with all 8 components
2. Create `scripts/lib/registry.js` — proper helper with error handling
3. Refactor `deploy.sh` to read from registry
4. Refactor `security-scan.sh` to read from registry
5. Refactor `generate-architecture.sh` to read from registry
6. Update `conventions.md` — remove duplicated machine-readable data, reference registry
7. Update `authority.md` — services.json owns component metadata

## All debate files

- `debate/service-registry-claude-draft.md`
- `debate/service-registry-claude-self-review.md`
- `debate/service-registry-codex-critique.md`
- `debate/service-registry-claude-response-1.md`
- `debate/service-registry-codex-rebuttal-1.md`
- `debate/service-registry-critique-log.json`
- `debate/service-registry-summary.md`

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~2m             | codex         |
| Codex R2   | ~2m             | codex         |

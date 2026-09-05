# Instruction cleanup — 5 September 2026

Owner-authorized cleanup based on the supplied Astra prompting article and the local instruction audit. The changes narrow activation and remove conflicting ceremony while retaining account, credential, publication, deployment, user-work, ownership, and independent-review boundaries.

## Scope

- Global completion guidance, conditional Grimnir state reads, five Claude agent roles, Codex worker repair loops, and PR commands.
- Shared/private skill reconciliation, precise calendar/mail/skill-discovery/M5/Cloudflare triggers, and conditional references for multi-workflow skills.
- Canonical Codex adapters remain separate where harness behavior differs. Personal upstream Cloudflare changes are hash-bound overlays; managed plugin caches and package locks are unchanged.

## Maintenance and reversal

Canonical sources are in claude-config, claude-skills, and skills-private. Codex variants are documented under claude-skills/codex; private skills share their canonical body and interface metadata. Native-only M5 and Presentify skills now have canonical source directories. The worker override source is claude-config/agent-overrides. Upstream overlays and their before/after hashes are in claude-skills/overrides.

The durable local receipt at `~/.local/state/codex/instruction-cleanup/2026-09-05/` holds the activation script, manifest, reviewed sources, review evidence, and original-file backups. The activation manifest records every exact source, destination, original hash, revised hash, and backup. Activation refuses concurrent modifications; rollback also requires the destination still match the installed revision. No unrelated dirty files are included. Retain the durable receipt until the installed changes have been committed or reversal is no longer needed. To reverse an unchanged installation, run `python3 ~/.local/state/codex/instruction-cleanup/2026-09-05/activation.py rollback`; the script refuses to overwrite later edits. Temporary worktrees are working copies, not the sole recovery record. The initial local activation did not publish or deploy anything. Subsequent Git publication uses the owning repositories’ PR workflows; reversal of merged changes uses a reviewed Git revert.

## Verification

Configuration suite: 42 passed. Both existing close script suites passed. The full Grimnir suite, required agent-instruction audit, changed-skill frontmatter/reference checks, worker TOML parsing, and disposable application of all nine hash-bound upstream overlays passed. Static instruction checks do not establish actual Astra routing performance; the existing live skill evaluator swaps a global symlink and was deliberately not run during concurrent sessions.

## Independent debate

Fable 5.1 round 1 supported the direction and requested corrections before activation: restore explicit close activation, remove leftover account IDs, make rollback durable, and finish this evidence record. Further grounded findings led to repository-declared handoff precedence, consistent reviewer role defaults, scoped provider-disclosure authority, explicit merge/preview semantics, PR staged-secret checks, and completed issue-routing guidance. The existing account map confirms Outlook connector use. Local CLI help confirmed the reviewer isolation flags before invocation.

The [two-round debate](../debate/astra-instructions-2026-09-05-summary.md) used actual `claude-fable-5-1` in both rounds. Fable accepted the source changes and the connector/isolation defenses. Round 2 found residual wording and a stale evidence report; those were corrected and final checks regenerated before activation. No third round was requested by either participant. Worker effort remains unchanged without quality evidence for a lower setting. Actual routing behavior remains unmeasured; static trigger checks establish instruction structure only.

## Acceptance and local activation

The five largest refactored skill roots fell from 13,872 to 2,743 words (about 80%); supporting references retain detailed workflows. This measures root size, not total distribution size or model performance. The required final checks cover the full Grimnir suite, 42 configuration tests, close scripts, agent-instruction audit, changed-skill structure/links, adapter mirrors, nine overlays, and guarded activation/rollback fixtures.

Activation requires the durable archive first, then guarded apply and exact hash readback. The durable receipt's `activation.log` and `instruction-audit-live.log` record the execution outcome. Original unrelated working-tree changes are excluded. The initial activation left all changes local and uncommitted. Magnus subsequently authorized the full Git publication workflow: scoped commits, task-branch pushes, PRs, checks, and merges in the four owning repositories. Publication results are recorded in the PR history and Munin; deployment, account operations, and mail sends remain outside this work.

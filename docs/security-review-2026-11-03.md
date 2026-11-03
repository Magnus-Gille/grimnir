# Security review — 2026-11-03

This is the substantive source and ticket reconciliation for [GRIM-232](https://tickets.gille.ai/gille/browse/GRIM-232/)
(F4/F5 in the supplied audit). It updates the [threat model](threat-model.md), not the owner's risk
acceptance or production authority. Residual High ratings remain High. Next quarterly review:
**2027-02-03**, owned by Grimnir, or earlier on the triggers in the threat model.

## Evidence and its limits

Plane states below were read on 2026-11-03. A Done ticket establishes its recorded deliverable,
not a fresh live probe of every related control. Cancelled work is not an active implementation
mandate and does not imply that its underlying risk was accepted.

Hugin source is bound to accepted release
[`42bba96c574f00e57121e33f60c78292ad6a7683`](https://github.com/Magnus-Gille/hugin/tree/42bba96c574f00e57121e33f60c78292ad6a7683).
Munin source is bound to
[`ed96ce564066ee8200a28a90a50ba4ef47e54d7d`](https://github.com/Magnus-Gille/munin-memory/tree/ed96ce564066ee8200a28a90a50ba4ef47e54d7d).
These revisions were deployed and verified in HUGIN-406 and MUNIN-427. This documentation review
does not repeat runtime policy, credential-mode, network-isolation or restore drills.

As of this review, the dependency remediation delivered HUGIN-406, MUNIN-427, HEIM-86, MIMIR-74 and
RATA-68 through their verified production endpoints; VERD-31 and SKULD-26 reached source-only
endpoints. GRIM-233 and GRIM-222 repaired the scanner's allowlist and upstream-source coverage.
Their check evidence is scoped to those tickets. A complete nine-repository scan is coverage
evidence, not a declaration that all security risks are resolved. Sixty secret-pattern candidates
remain untriaged (Munin 6, Hugin 22, Heimdall 3, Mimir 21, Verdandi 7, Brokkr 1); candidate values
are excluded from this record. Test-file location alone is not a false-positive determination.

## Residual-High ownership and disposition

GRIM-232 is the dated review record for every row below. The implementation ticket column
deliberately exposes completed, cancelled and missing mandates; this review does not manufacture
an active implementation programme from those historical references.

| Threat | Accountable owner | Current ticket/disposition | Concrete next evidence or decision |
|---|---|---|---|
| T1 — task-agent exfiltration | Hugin; Grimnir reviews the system boundary | [HUGIN-149](https://tickets.gille.ai/gille/browse/HUGIN-149/) **Done** for permission-profile scoping. [HUGIN-415](https://tickets.gille.ai/gille/browse/HUGIN-415/) **Backlog** for Codex CLI compatibility, not a universal containment fix. | Review child-process filesystem/network confinement separately from runtime labels; do not claim process-wide egress isolation from the fetch wrapper. Revisit by 2027-02-03. |
| T2 — interactive prompt injection | Grimnir; owner controls mandates | [GRIM-234](https://tickets.gille.ai/gille/browse/GRIM-234/) **Done** removes the mandatory exposure-triggered handoff. GRIM-70 and GRIM-227 are Done historical decisions, not open technical containment work. | Preserve content-as-data handling and current authority gates. Technical containment remains unproven; any further control design needs its own scope. Revisit by 2027-02-03. |
| T4 — unattributed or unaudited mutation | Each mutation actor; Grimnir owns the convention | [HUGIN-148](https://tickets.gille.ai/gille/browse/HUGIN-148/) and [VERD-15](https://tickets.gille.ai/gille/browse/VERD-15/) **Cancelled**. GRIM-234 changes the permitted durable sink, not actor adoption. No active implementation ticket for universal end-to-end attribution was established by this review. | Require actor-specific evidence of durable intent/outcome/reversal and authenticated identity before claiming adoption. Cancellation is preserved; a new implementation needs an owner-scoped decision. Review by 2027-02-03. |
| T5 — audit-chain loss or forgery | Grimnir; Verdandi owner for any future product decision | [VERD-21](https://tickets.gille.ai/gille/browse/VERD-21/) and VERD-15 **Cancelled**; [VERD-31](https://tickets.gille.ai/gille/browse/VERD-31/) **Done, source only**. Verdandi is deliberately stopped. Legacy physical recovery was declined. | Do not request image-first recovery, continuity, a new genesis or activation as if approved. Any future audit product requires a new explicit owner decision; review the remaining assurance gap by 2027-02-03. |
| T7 — theft of plaintext storage | Brokkr | [BROKKR-89](https://tickets.gille.ai/gille/browse/BROKKR-89/) **Backlog** covers M5 root encryption; [BROKKR-170](https://tickets.gille.ai/gille/browse/BROKKR-170/) **Backlog** covers read-only fleet storage evidence. The old brokkr#40 reference is not the current implementation target. | Establish encryption and recovery readiness per volume; M5 preparation does not prove Pi or NAS encryption. Any destructive migration remains an attended, separately approved operation. Evidence review is pending BROKKR-170. |
| T9 — backup or restore failure | Each service for its data; Brokkr for storage substrate; Grimnir for cross-store review | [BROKKR-170](https://tickets.gille.ai/gille/browse/BROKKR-170/) **Backlog** captures backup/restore evidence. The old BROKKR-39 could not be resolved and is not an active mandate. VERD-21 remains Cancelled. | Date each component's last restore evidence; encrypted transport alone is insufficient. The historical Mimir 2026-07-10 restore does not prove current all-store recovery. Verdandi has no operating chain or routine DR; no restart follows from this gap. Review by 2027-02-03 or when BROKKR-170 completes. |
| T11 — incomplete lifecycle and erasure | Owning stores; Grimnir coordinates the map | [GRIM-66](https://tickets.gille.ai/gille/browse/GRIM-66/) **Cancelled**. [MUNIN-192](https://tickets.gille.ai/gille/browse/MUNIN-192/) **Done** supplies Munin correction/expiry, not cross-store erasure. [MUNIN-358](https://tickets.gille.ai/gille/browse/MUNIN-358/) **Backlog** has narrower code-health scope and is not a general erasure mandate. | Keep the [store map](data-lifecycle.md) and unresolved backup/derived-copy gaps explicit. No deletion or retention job is authorized here. New cross-store implementation requires owner scope; review by 2027-02-03. |

The rows with cancelled or completed implementation tickets remain assurance gaps. Their review
target is the date above, not an invented delivery deadline. Closing GRIM-232 means the documented
reconciliation passed its checks; it does not close these threats or revive cancelled projects.

## Source corrections behind the review

- **Hugin permissions vary by executor.** `src/index.ts:1386` limits `trusted-code` selection to
  code-capable requests; `src/sdk-executor.ts:64` maps Claude profiles to `dontAsk` or
  `bypassPermissions`, and `src/opencode-executor.ts:191` maps OpenCode profiles. Codex is treated
  as mutation-capable in `src/index.ts:6162` and still uses `--full-auto` at line 3048. The
  incompatible installed CLI invocation is tracked by HUGIN-415. The Pi worker's cwd/allowed-root
  checks (`src/orchestrator/worker-executor.ts:265`) are not OS filesystem confinement.
- **Egress scope is narrower than a host firewall.** `src/egress-policy.ts:79` wraps Node fetch;
  `src/task-helpers.ts:1260` checks Git push destinations. Hugin's
  `docs/security-critical-holes-live-evaluation.md:112` explicitly limits this first-pass control.
  It does not establish universal filtering of spawned processes.
- **Provenance is conditional.** Hugin `docs/security/task-signing.md` defines off/warn/require;
  off is the source default, not a measured live configuration here. A claimed submitter is not
  authenticated unless verification succeeds. `src/index.ts:1837,1935` stores structured
  provenance and attempts a separate lifecycle log, whose failure is handled. This is not proof
  of a durable reversal recipe for every mutation.
- **Verdandi is stopped by decision.** The [purpose-reset record](verdandi-purpose-reset-2026-07-13.md#new-genesis-decision-and-activation-gates)
  records deletion of the legacy database and declined physical recovery. The previous threat
  table's “pending image-first recovery” wording was obsolete. The proposed reset is not an
  accepted design or activation mandate. [Failure recovery](failure-recovery.md#durable-audit-transport)
  now permits other durable sinks without claiming tamper-evidence or per-tenant identity.
- **Munin has correction and expiry.** The accepted source's `src/types.ts` and `src/tools.ts`
  expose `supersedes`, compare-and-swap and `valid_until`; current API schemas expose them too.
  “No correction / expiry path” is obsolete. These features do not establish erasure from all
  stores, derived copies, audit history or backups; T10 remains Medium and T11 remains High.

## Historical handoff reconciliation

GitHub readback on 2026-11-03 confirmed:

| Source PR | Merge receipt | Remaining acceptance |
|---|---|---|
| [Brokkr PR 95](https://github.com/Magnus-Gille/brokkr/pull/95) | `ee62f4e53a0080d5bea1a2a612b4a0b860c06aa6`, 2026-08-10T12:45:55Z | BROKKR-90 attended live apply/probes/recovery; not established by this merge |
| [Brokkr PR 96](https://github.com/Magnus-Gille/brokkr/pull/96) | `565d33f93fd44d763144a9b65c7d4a5f18c6cfd0`, 2026-08-10T14:32:22Z | BROKKR-91 private bindings and attended live acceptance; not established by this merge |

[STATUS.md](../STATUS.md) retains the August snapshot as history and removes obsolete merge prompts.
Other historical deployment instructions are not current mandates. Existing uncommitted user
additions in the canonical checkout are outside this worktree's change and must be preserved.

The Skuld component label now agrees with `services.json`, [conventions](conventions.md) and the
[2026-07-23 ownership resolution](worktree-hygiene.md): `Magnus-Gille/skuld` is authoritative;
the bot is not the repository owner. No repository visibility, target or credentials changed.

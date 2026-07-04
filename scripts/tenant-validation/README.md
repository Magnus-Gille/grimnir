# Tenant-contract validation harness (grimnir#58)

One-shot harness that drives the **Codex CLI as a non-Claude tenant** through the four
substrate seams of `docs/tenant-contract.md`. Run on 2026-07-04; results in
`docs/tenant-validation-2026-07-04.md`.

| File | What |
|---|---|
| `run-codex-tenant.sh` | Runner: resolves the M5 gateway key via `m5-auth` (Keychain → child env only, never on disk) and invokes `codex exec` full-auto with the prompt below. |
| `codex-tenant-prompt-2026-07-04.md` | The tenant's mission brief — the scaffold/tenant line is documented in the evidence note. |
| `codex-run-report-2026-07-04.md` | **Written by the tenant itself** during the run — first-person, seam-by-seam, verbatim errors. |

The raw `codex exec` transcript (`codex-exec-transcript-2026-07-04.log`) is gitignored
(`*.log`): it duplicates the report and contains internal Munin content.

Re-running: the run mutates live state (Munin `traces/codex-tenant`, a real Hugin task,
a gateway ledger entry). Date-stamp a new prompt file rather than re-running this one as-is.

Post-review hardening (Codex review of PR #59, after the run): the runner now fails fast
when `m5-auth` returns nothing, and filters the tenant's shell environment to an allowlist
(`include_only`). The 2026-07-04 run itself executed with unfiltered `inherit=all`.

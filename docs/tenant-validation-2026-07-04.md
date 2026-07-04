# Tenant-Contract Validation Run — 2026-07-04

> Evidence note for grimnir#58: the first real **non-Claude tenant** driven through the
> substrate seams defined in [`tenant-contract.md`](tenant-contract.md). Companion artifacts:
> the harness under [`scripts/tenant-validation/`](../scripts/tenant-validation/) and the
> tenant's own first-person report,
> [`codex-run-report-2026-07-04.md`](../scripts/tenant-validation/codex-run-report-2026-07-04.md).

## Executive summary

On 2026-07-04, a non-Claude agent (Codex CLI 0.142.5, tenant identity `codex-cli`) executed
one real task through the Grimnir substrate: classifying an ops note. Seam B (M5 gateway)
**passed** — Codex inferred the `POST /delegate` schema from the gateway's 400 error envelope
and obtained classification `admin` from local model mellum in 253 ms, with a ledger entry
created (`ledgerId d02b06a5…`). Seam A (Munin write over authenticated HTTP/MCP) **passed on
transport but failed on attribution** — the write succeeded, but `provenance.principal_id`
was `owner`, indistinguishable from Claude sessions. Seam C (Hugin safety-gated task path)
**passed** — Codex submitted an unsigned task as `Submitted by: codex-cli` (no per-tenant
signing key exists), Hugin picked it up 24 s after the write and ran it on Pi-local ollama
`qwen2.5:3b`, which independently also classified the note `admin`, with the sensitivity gate
classifying content `internal`. Seam D (Verdandi audit emission) was **blocked** — connection
refused on every attempt: the intake is loopback-only on Pi 1 with no off-Pi network path,
and no per-tenant key provisioning exists. Overall: three of four seam transports are proven
model-agnostic; **per-tenant identity — the contract's core axiom (§2) — is unimplemented at
every seam**; four follow-up tickets filed.

## What ran

| | |
|---|---|
| Tenant | Codex CLI (`codex-cli 0.142.5`), headless `codex exec`, full-auto |
| Task | Classify one benign ops note into `admin` / `commitment` / `project` |
| Harness | `scripts/tenant-validation/run-codex-tenant.sh` + prompt file (committed) |
| Credentials | M5 gateway: shared **owner** key via `m5-auth` (Keychain → child env, never on disk). Munin: Codex CLI's **own pre-configured** `munin-memory` MCP bridge. Hugin signing: none (deliberately unsigned). Verdandi: none exists. |
| Duration | ~7 minutes wall clock (13:06–13:13 UTC), including a 90 s Hugin-pickup wait |
| Cost | Zero frontier tokens for the tenant's inference (mellum + qwen2.5:3b are local) |

### Where the tenant/scaffold line was drawn (honesty note)

The orchestrating Claude session **scaffolded**: the prompt file (mission, seam order,
endpoint addresses, the Hugin task body template with its tag conventions, the instruction to
submit unsigned), the runner script, and the credential plumbing (`m5-auth` → env). The
**tenant decided and executed**: every seam call (all curl/MCP traffic originated from the
Codex process), the `/delegate` schema discovery from the gateway's error envelope, the
decision to stop probing after two attempts rather than falling back, calling
`memory_orient` to satisfy the Munin tool contract, generating the task id/timestamps,
reading back status/result, and writing its own report. The Hugin task **format** was given
to the tenant (it did not reverse-engineer the convention); a tenant without that scaffold
would have had to discover it from existing Munin entries — there is no published task-schema
document, which is itself a small contract gap (see Findings).

## Seam-by-seam results

| Seam | Called | As whom | Result | Attribution |
|---|---|---|---|---|
| **B — Gateway** | `POST /delegate` on `100.76.72.59:8080` (2 calls: `{}` → 400 schema probe, then `{prompt}` → 200) | Shared **owner** gateway key (env) | **PASS** — `admin` via mellum, 253 ms, `ledgerId d02b06a5-33bc-4061-b441-f676a9e8d6ec`; ledger entry independently confirmed (`taskType:"classify"`, `source:"gateway"`, 13:08:03 UTC) | **Gap** — response carries no caller identity; `GET /ledger` exposes `source` but no key alias; tenant ran on the owner's shared key |
| **A — Munin** | `memory_orient`, `memory_write traces/codex-tenant/run-2026-07-04`, `memory_log` via Codex's own MCP bridge (HTTP, no SQLite) | Codex CLI's own bridge credential (`MUNIN_AUTH_TOKEN` in *its* config — never read by the orchestrator) | **PASS (transport)** — entry `cda356d6…` created 13:08:57, log `bac19e42…` | **FAIL (attribution)** — `provenance: {"principal_id":"owner","owner_principal_id":"owner"}` — identical to Claude-session writes and to Hugin's own heartbeat writes |
| **C — Gating** | `memory_write tasks/20260704-130911-tenant-validation-classify/status`, tags `[pending, runtime:ollama, type:admin]`, **unsigned**, `Submitted by: codex-cli` | `codex-cli` (self-reported in body); Munin principal again `owner` | **PASS** — Hugin started it 13:09:51 (24 s after the write landed), executor ollama `qwen2.5:3b` on the Pi, exit 0 in 14 s, result `admin` (independent agreement with the tenant's mellum call); `result-structured` shows the gate's sensitivity classifier ran (`{"effective":"internal","mismatch":false}`) | **Gap** — `Submitted by` is convention-grade (unverified); no `codex-cli` signing keyId exists; `result-structured` carries **no submitter field at all**; unsigned submission accepted silently |
| **D — Verdandi** | `GET /health`, `POST /api/events` ×2 (no auth; dummy bearer) on `100.97.117.37:3036` | `codex-tenant` (would-be) | **BLOCKED** — all three: `curl: (7) Failed to connect to 100.97.117.37 port 3036 after 3 ms: Couldn't connect to server` | Not exercisable: no off-Pi network path (loopback-only bind; no `verdandi.gille.ai`), and no per-tenant key is provisionable |

## What the contract got right (validated)

- **The seams are real and sufficient.** One bounded task naturally decomposed into exactly
  the four contract seams; nothing else was needed.
- **Seam A/B transports are model-agnostic**, as claimed: an OpenAI-ecosystem agent spoke
  both without any Claude-shaped adaptation. The gateway is, as §3B predicts, the seam where
  "any agent" is most naturally true — it even auto-inferred `taskType` and model from a bare
  prompt.
- **Seam C's framing ("not a standalone gate API — route through Hugin's task path") is
  accurate and workable**: a non-Claude tenant used it end to end, and the gate's sensitivity
  classification demonstrably ran on tenant-submitted content.
- **`/delegate` as the ledger-writing path** works exactly as specified: one call, one ledger
  entry, zero frontier tokens.

## What the contract missed (amended, marked `validated-by-run-2026-07-04`)

1. **The identity axiom (§2) is unimplemented at every seam — including inside the
   substrate.** Not only did the tenant's writes collapse to `principal_id: "owner"`; so do
   Hugin's own heartbeat and task-lifecycle writes. There is no per-actor attribution
   anywhere today, so "the write appears attributed to the tenant" (Seam A conformance) and
   "provenance-stamped with the tenant identity" (Seam C) are currently unsatisfiable, and
   audit history (`memory_history.agent_id`) is uniformly `owner`.
2. **Seam D assumes a reachable intake; there is none off-Pi.** "Any runtime can emit" is
   false for any tenant not running on Pi 1: the port is loopback-bound, there is no tailnet
   or public exposure, and connection refused precedes any auth question. The spec needs a
   reachability requirement, not just an auth shape. (verdandi#15)
3. **No credential provisioning story exists for any seam.** The contract mandates
   per-tenant keys but never says where a tenant gets one. The gateway is the only seam with
   a mint mechanism (`keys mint`, owner-manual over SSH); Munin, Hugin signing, and Verdandi
   have none at all. (munin-memory#191, hugin#146, verdandi#15, gille-inference#152)
4. **Ledger attribution is not externally checkable.** Seam B's conformance check ("the call
   is attributed to the tenant's gateway key") cannot be verified from `GET /ledger` — entries
   expose `source` but no key alias. (gille-inference#152)
5. **The task-submission schema is folk knowledge.** The Hugin task body/tags convention
   lives in a laptop-local skill file, not in any tenant-readable contract document — a
   tenant can't conform to Seam C without being handed the format out of band.
6. **Unsigned submissions are accepted silently** (signing policy `off`/`warn`), which makes
   the Seam C signing obligation optional in practice. Contract updated to note the default.

Not exercised, deliberately: the Seam C prompt-injection/exfiltration canary (planting
injections in the production task queue was out of scope for this run) and Seam A's
secret-rejection check. Both remain unvalidated conformance items.

## Blocking sub-tickets filed

| Ticket | Seam | Blocking? |
|---|---|---|
| [verdandi#15](https://github.com/Magnus-Gille/verdandi/issues/15) | D | **Yes** — seam not exercisable at all |
| [munin-memory#191](https://github.com/Magnus-Gille/munin-memory/issues/191) | A | Yes, for attribution (transport passed) |
| [hugin#146](https://github.com/Magnus-Gille/hugin/issues/146) | C | Yes, for attribution (gate + execution passed) |
| [gille-inference#152](https://github.com/Magnus-Gille/gille-inference/issues/152) | B | No — observability follow-up |

All four carry `from:grimnir` and are on the Grimnir Roadmap board.

## Verdict

The thesis sentence now has its first supporting instance — with a precise asterisk. A
genuinely non-Claude agent **acted through** the substrate: memory, inference routing, and
safety-gated execution all worked on the first run, on unmodified vendor-neutral transports.
What no seam could do is say **who** acted. Until per-tenant credentials exist, tenant
replaceability is real but tenant *accountability* is not: a conforming tenant and a
misbehaving one would be indistinguishable in every record the substrate keeps. That is the
single blocker between "a second agent brand can act through the substrate" (now proven) and
"a second agent brand is a first-class, auditable tenant" (the contract's actual bar).

# Verdandi Purpose Reset — Landscape Research and Proposed ADR

> **Status:** Proposed for owner review; not accepted and not an authorization to restart Verdandi.
> **Date:** 2026-07-13
> **Tracks:** [verdandi#21](https://github.com/Magnus-Gille/verdandi/issues/21)
> **Decision boundary:** research and definition only. No deployment, new genesis, or integration is
> authorized by this document.

## Executive recommendation

Retire Verdandi v1's purpose as a general log of agent activity, human decisions, tool calls, and
reasoning. Do **not** replace it with an LLM-observability platform, SIEM, workflow engine, or generic
audit-log product.

Keep the Verdandi name and repo only for a schema-breaking, narrowly continued v2:

> **Verdandi is Grimnir's append-only ledger of consequential action receipts. It binds an
> authenticated actor and authority-bearing intent to an independently observed outcome, an
> authoritative-system reference, and reversal evidence. Its purpose is to make autonomous changes
> attributable, reviewable, and recoverable—not to record everything an agent did.**

This is a conditional continuation, not a vote for another permanent service. A new genesis is
warranted only after the minimum contract, two real mutation adapters, one consumer, independent
anchoring, restore evidence, and owner acceptance all exist. If that proof is not worth building—or
if the receipts are not used in an operating decision within two monthly reviews—retire Verdandi
and remove it from the protected-pillar description.

## Why the reset changes the answer

The original system accumulated approximately 67,000 events, predominantly from one laptop Claude
Code hook. The database is now lost by accepted owner decision. More important than the loss itself,
the history had no material consumer, no external integrity anchor, incomplete actor identity, and
classification gaps. It was high-volume evidence of collection, not evidence of accountability.

The old design began with the question “how do we capture agent activity?” The useful question is:

> **Which future decision becomes safer or possible because this record exists?**

If no gate, alert, rollback, incident review, or trust decision consumes an entry, the entry should
not exist. This follows Grimnir's current strategy directly:

- **Sovereign Memory:** accountability evidence is worth owning when it protects the ability to let
  replaceable tenants act on personal systems.
- **Self-Knowing Inference:** execution quality and model competence belong in traces and the M5
  capability ledger, not in Verdandi.
- **Minimal surface:** a component earns its place only where it provides a non-replicable pillar
  capability and has measured use.
- **Instrument first, then decide:** a ledger that has no concrete consumer cannot show value merely
  by growing.

## First-principles requirements

### Primary user and job

The primary user is Magnus in two modes:

1. **Before an autonomous mutation:** the substrate must know that a named tenant is authorized to
   perform a bounded action and that a reversal/mitigation path exists.
2. **After the mutation:** Magnus or an automated consumer must be able to establish what actually
   changed, whether it matched the authorized intent, how the result was verified, and how to undo
   or contain it.

Secondary consumers are Hugin's mutation gate, Heimdall's exception view, rollback tooling, and a
periodic autonomy/trust review. They consume structured receipts or exceptions, not raw sessions.

### Authoritative role

Verdandi is authoritative for one relationship:

```text
authority + intended effect -> observed effect + source reference + reversal evidence
```

It is **not** authoritative for the changed object itself. Git remains authoritative for code;
Fortnox for accounting records; calendar/email providers for their objects; the filesystem/Mimir
for files; Munin for current memory and project state; Hugin for task execution; OpenTelemetry-style
traces for execution detail.

Verdandi records a minimal cross-system receipt pointing to those authorities. It must not become a
second copy of their content.

### Unique value relative to existing records

| Existing record | What it proves | What it does not prove |
|---|---|---|
| Munin state/log | Current remembered truth and chronological project decisions | Tamper-evident action receipts, external outcome, or pre-action authority |
| Git/PR history | Exact code result, review, and merge metadata | Non-code actions or one cross-system identity/rollback contract |
| Hugin task record | What work was dispatched and how execution ended | That an external mutation happened as claimed or remains in place |
| Service logs / OTel traces | Execution path, errors, latency, model/tool behavior | Authorization, durable accountability, or authoritative result |
| Provider audit/history | Domain-specific result | Why Grimnir acted, under whose delegated authority, or how to reverse it |

Verdandi is justified only if it joins these otherwise separate facts without duplicating their
payloads.

## Current software landscape

No current product provides the whole Grimnir requirement. The market has mature parts, but they
solve different problems.

| Category / examples | What is reusable | Why it is not the Verdandi answer |
|---|---|---|
| **AI observability:** [Arize Phoenix](https://arize.com/docs/phoenix/), [Langfuse](https://langfuse.com/pricing-self-host) | Self-hosted traces, sessions, evaluations, OTel ingestion, UIs | Optimizes and debugs model execution; does not establish authority, authoritative outcome, reversal, or tamper evidence. It overlaps Munin traces and the M5 ledger. |
| **Telemetry standard:** [OpenTelemetry logs/events](https://opentelemetry.io/docs/specs/otel/logs/data-model/) | Stable log model, trace/span correlation, event naming; Collector ecosystem | Transport/schema interoperability, not an accountability or integrity system. Use `trace_id` correlation but do not store OTel traffic in Verdandi. |
| **Application audit products:** [WorkOS Audit Logs](https://workos.com/docs/audit-logs), [Retraced](https://github.com/retracedhq/retraced) | Useful actor/action/target vocabulary, validation, search/export patterns | WorkOS is cloud-hosted; Retraced is a comparatively heavy application/Kubernetes/search stack. Both trust emitters and lack the intent→verified-outcome→reversal contract. |
| **Managed tamper-proof audit:** [Pangea Secure Audit Log](https://pangea.cloud/docs/audit/overview/about) | Merkle membership/consistency proof and redaction patterns | Managed cloud conflicts with sovereignty and still does not decide selection, authority, or outcome semantics. |
| **Authorization decision logs:** [OPA](https://www.openpolicyagent.org/docs/management-decision-logs), [Cerbos](https://docs.cerbos.dev/cerbos/latest/configuration/audit.html) | Decision IDs, server-side masking/drop rules, policy version and allow/deny lineage | Proves what a policy engine decided, not what the caller subsequently changed. Useful at Hugin's gate, insufficient as the action ledger. |
| **Durable workflow:** [Temporal](https://docs.temporal.io/) | Ordered execution history, crash recovery, deterministic replay | Requires moving execution into its workflow runtime, duplicates Hugin/harness concerns, and does not cover direct tenants or external source truth. |
| **Code intent/provenance:** [happi/warrant](https://github.com/happi/warrant) | Strong pattern: bind intent, exact code, and authorization when code becomes real; content digests and verification | Code/Git-specific, very young, and not a solution for files, messages, finance, keys, or arbitrary tenants. Adopt the semantic pattern, not the product as Grimnir's audit layer. |
| **Signed supply-chain attestations:** [in-toto](https://in-toto.io/), DSSE/Sigstore | Standard signed statements about who performed which ordered software-supply-chain steps | Excellent envelope/signature ideas but supply-chain scoped; does not supply action selection, runtime identity, retention, or consumers. A custom DSSE predicate is an optional future envelope, not an MVP dependency. |
| **Cryptographic data store:** [immudb](https://docs.immudb.io/master/immudb.html) | Append-only data, client verification, signed database states, external auditor model | Replaces storage but not semantics. Another database/service would add operational surface while existing SQLite append primitives are adequate at Grimnir volume. |
| **Transparency log:** [Sigstore Rekor](https://docs.sigstore.dev/logging/overview/) | Inclusion/consistency proofs and independent witnesses | Optimized for public software-signing metadata. Public use leaks metadata; private operation is excessive for one owner. Borrow the independent-witness principle. |
| **Workload identity:** [SPIFFE/SPIRE](https://spiffe.io/docs/latest/spiffe-about/spiffe-concepts/), [step-ca](https://smallstep.com/docs/step-ca/) | Cryptographically verifiable workload credentials and rotation | Correct at larger scale but too much PKI/control-plane surface for the current fleet. Verdandi still needs a minimal tenant mint/revoke path even if a federation arrives later. |
| **Tailnet ingress:** [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve) | Keeps the service loopback-only while exposing HTTPS on the tailnet; adds user identity headers for user-originated requests | Solves reachability and some human identity, not process/tenant identity—tagged-device traffic does not get user headers. It is a candidate transport for the rewritten #15, not the identity model. |

### Corrections to the April 2026 research

The earlier 40+ framework survey remains useful, especially its findings on W3C PROV, data
minimization, same-host trust, and external anchoring. Three assumptions should not carry forward:

1. **Comprehensive chat/tool capture is not a unique requirement.** It proved to be the main source
   of volume and privacy risk, while providing no material consumer value.
2. **HumanLayer is no longer the open-source HITL building block described in April.** Its current
   product is an AI coding platform; on-prem and audit logs are enterprise features, and the site
   says the product itself is not yet open source.
3. **A local hash chain is not an external anchor.** Verdandi's daily checkpoint currently writes a
   local file and explicitly disclaims RFC 3161 backing. It detects accidental/local discontinuity
   while the checkpoint survives; it does not defeat a Pi-1 compromise that can rewrite the database
   and its local checkpoint. The Grimnir threat model correctly still calls this out.

## Proposed v2 contract

### Event-selection rule

An action is ledger-worthy only when all three are true:

1. It changes authoritative state, sends something externally, changes identity/security posture,
   spends or commits money, deletes/restores data, or deploys/publishes executable behavior.
2. It is performed by an agent/service under delegated authority, or it changes the Grimnir
   substrate's own trust/continuity controls.
3. A named consumer can block, alert, reverse, investigate, or update a trust decision from the
   receipt.

Human work performed directly in an authoritative system is not duplicated merely for completeness.
If a human authorizes a tenant through Grimnir, the authorization is part of the receipt.

### Must log

| Example | Required evidence |
|---|---|
| Agent opens/pushes/merges a PR or deploys a revision | Intent/authority ref, repo + immutable commit/PR/deploy marker, observed result, `git_revert` recipe |
| Agent changes production config, systemd state, ACL, credential, or key | Bounded target, pre-state snapshot/ref, observed post-state, rollback/ref or mitigation |
| Agent creates/updates/deletes a calendar, ticket, file, memory entry, or external record | Stable source-system ref/digest, operation, observed result, reversal/snapshot |
| Agent sends an email/message or performs another irreversible external action | Pre-action intent receipt, recipient/target pseudonymous ref, provider result ref, mitigation |
| Agent performs a Fortnox write or other financially consequential mutation | Owner/policy authority, operation class, authoritative Fortnox ref, readback result, supported reversal/mitigation; never full financial payload |
| Autonomous rollback, restore, or erasure | Original action ref, authority, stores affected, verified result, residual gaps |
| Break-glass action while the ledger is impaired | Durable local gap receipt, named human authority, reason, later reconciliation outcome |

### Must not log

| Example | Correct home |
|---|---|
| LLM prompts, responses, chain-of-thought, chats, and every tool call | Ephemeral harness history or scoped OTel trace when needed |
| Reads, searches, health checks, polling, model calls, token/cost detail | Service logs, Munin traces, M5 ledger, Heimdall metrics |
| Hugin task start/complete with no consequential side effect | Hugin/Munin task record |
| Draft documents/code before publication or authoritative commit | Workspace/git branch; no action receipt yet |
| Full diffs, messages, invoices, calendar bodies, credentials, personal data payloads | Authoritative system only; Verdandi stores ref/digest/minimal summary |
| Post-session “decision extraction” inferred by an LLM | Munin memory if useful, explicitly labeled as interpretation—not audit evidence |
| Human actions performed directly in GitHub/Fortnox/etc. with no Grimnir delegation | The source system's own history unless a specific substrate-security rule requires a receipt |

### Record shape

The minimum model is two append-only records plus an exception record:

- `action.intent` — accepted **before** a consequential autonomous mutation.
- `action.outcome` — appended after independent readback from the authoritative system.
- `action.gap` — appended/reconciled when an intent has no timely authoritative outcome, the receipt
  path failed, or break-glass was used.

Representative shape (names are illustrative; the accepted ADR should freeze the schema):

```jsonc
{
  "schema": "grimnir.action-receipt.v1",
  "kind": "action.intent",
  "action_id": "019...",                // stable correlation id, not the content digest
  "generation_id": "verdandi-receipts-1",
  "actor_id": "tenant:codex-cli",       // server-derived from credential
  "principal_id": "person:magnus",      // or named policy/grant
  "authority_ref": "hugin:grant/...",
  "action_class": "deployment.apply",
  "target_ref": "service:hugin",
  "expected_effect": "deploy commit <sha>",
  "risk": "consequential",
  "reversal": { "kind": "git_revert", "ref": "<sha-or-pr>" },
  "trace_id": "...",                    // correlation only; trace is stored elsewhere
  "privacy_class": "internal",
  "retention_policy_ref": "grimnir:data-lifecycle/v1"
}
```

```jsonc
{
  "schema": "grimnir.action-receipt.v1",
  "kind": "action.outcome",
  "action_id": "019...",
  "observer_id": "adapter:grimnir-deploy", // not merely the acting tenant
  "status": "succeeded",
  "actual_effect": "production marker equals <sha>",
  "authority_object_ref": "deploy:hugin/<sha>",
  "authority_object_digest": "sha256:...",
  "evidence": "authority_readback",
  "intent_drift": "none",
  "reversal_verified": true
}
```

Key rules:

- `actor_id` says which tenant attempted the action; `principal_id` says whose authority it used;
  `observer_id` says who verified the outcome. Do not collapse them into `component`.
- UUID/ULID-style `action_id` provides stable pre-action correlation. Each canonical record also has
  a content digest, but content-addressing is not the business identifier.
- An actor's self-reported success is `declared`, never `authority_readback`. It cannot improve the
  tenant's trust score until an independent adapter observes the authoritative system.
- Intent and outcome are separate immutable records. Corrections and reversals append new records;
  no historical row is edited to make intent and reality agree.
- Reversal evidence follows [`failure-recovery.md`](failure-recovery.md): `git_revert`, `snapshot`,
  or `irreversible` with mitigation.

### Consumers and actions

| Consumer | Input | Concrete action |
|---|---|---|
| Hugin / mutation adapter | Accepted intent receipt | Permit mutation; deny an autonomous mutation lacking required receipt/reversal fields |
| Outcome adapter | Provider/git/readback result | Append authoritative outcome; flag intent drift |
| Heimdall | Open intent past TTL, failed/drifted outcome, gap, checkpoint/restore failure | One exception alert; no generic event dashboard |
| Rollback tooling / operator CLI | Action + reversal records | Show or execute the named recovery recipe under separate authority |
| Monthly trust/ROI review | Aggregates of authority-readback success, drift, rollback, and gaps | Keep/fix/cut tenant autonomy scopes; self-reports do not count |
| Incident review | Selected receipt chain + authoritative refs | Reconstruct who authorized what, what changed, and containment status |

Skuld should not receive every receipt. It may summarize unresolved exceptions only after Heimdall's
consumer proves useful.

### Identity

The immediate minimum is one revocable, scoped credential per tenant with `mint`, `list`, `rotate`,
and `revoke`; the server derives `actor_id` from the credential. Tailscale Serve is a good candidate
for tailnet-only HTTPS reachability while the backend stays on localhost, but its user headers do not
replace tenant identity.

At this scale, bearer credentials provide authenticated attribution, not strong non-repudiation.
The accepted design must say so. SPIFFE/SPIRE or a private CA should be adopted only if the broader
Grimnir identity spine chooses them; Verdandi should not create a fleet PKI by itself.

### Failure semantics

The old blanket “fail-open for operations, fail-loud for audit” rule is too weak for autonomous
mutations. It contradicts the thesis that any tenant can **safely** act through the substrate.

- **Autonomous consequential mutation:** fail closed before mutation if an intent receipt cannot be
  durably accepted or no reversal/mitigation is present.
- **Outcome write after an already executed mutation:** persist to a durable local outbox, mark the
  task incomplete/degraded, and alert until authoritative readback is reconciled. Do not pretend the
  action failed merely because the receipt path failed.
- **Read-only, draft, telemetry, or diagnostic work:** Verdandi is not on the path and cannot block it.
- **Human break-glass/recovery:** may proceed when delay is riskier, but must create a durable local
  gap receipt and an alert for later reconciliation.

This makes audit availability part of the autonomy safety boundary without making it a dependency
for ordinary work.

### Privacy, retention, erasure, and continuity

- **Minimize by schema, not regex alone.** Free-form payloads are rejected. Receipts contain stable
  internal refs, small controlled summaries, and digests; secrets and source content never enter the
  ledger.
- **Retention follows the explained action.** Keep a receipt at least as long as the authoritative
  object/action it explains, using `docs/data-lifecycle.md`. Non-domain operational telemetry remains
  outside Verdandi and follows the six-month default. No event-type prefix silently creates a legal
  retention claim.
- **Erasure remains honest.** Corrections are appended. If a minimal identifier must be erased, keep
  only the non-identifying commitment and an erasure receipt, and narrow subsequent integrity claims;
  never say an erased semantic record is still fully verifiable.
- **Hash-chain verification is necessary but insufficient.** The chain head must be witnessed outside
  Verdandi's host and outside the writer's rewrite authority. A one-way append-only target on a second
  Grimnir host preserves sovereignty; a public TSA/transparency service is optional only after an
  explicit metadata-leakage decision.
- **Recovery must be tested.** A regular export plus restore verification is a new-genesis gate, not
  a post-launch backlog item.

## Build, reuse, or retire

### Option A — retire Verdandi and rely on existing authorities

**Advantages:** smallest surface; no new privacy store; source histories already prove many outcomes.

**Failure:** no uniform pre-action authority, tenant identity, independent outcome, and reversal link
across code, files, communications, finance, and infrastructure. The tenant contract and Phase 3/4
autonomy would lose a checkable accountability seam.

**Verdict:** viable if Grimnir declines consequential autonomy. Not the current strategy's best fit.

### Option B — replace Verdandi with an off-the-shelf product

**Advantages:** mature storage, search, UIs, or cryptographic proofs depending on product.

**Failure:** every candidate solves a lower layer or adjacent job. The cloud products violate
sovereignty; the self-hosted audit/search stacks are too heavy; cryptographic stores do not supply
selection/identity/outcome semantics; AI observability duplicates existing systems.

**Verdict:** reject a whole-product replacement. Reuse standards and patterns selectively.

### Option C — narrow continuation in the existing repo

Keep the useful primitives: Fastify/SQLite scale, server-side identity derivation, canonicalization,
single-writer atomic append, idempotency, authenticated reads, generation manifests, verification,
and checkpoint machinery. Replace the v1 schema and delete the generic capture surfaces:

- Claude Code hook and universal tool telemetry;
- session details and encrypted raw/debug layers;
- generic accounting/email/calendar/file/memory/task/Telegram taxonomy;
- automatic severity→retention assumptions;
- rubber-stamp/dwell-time analysis;
- post-session decision extraction and generic dashboard ambitions.

Add only the action-receipt schema, tenant lifecycle, authoritative outcome adapters, independent
anchor, durable outbox, restore proof, and exception query.

**Verdict: recommended**, subject to the stop conditions below.

## New-genesis decision and activation gates

### Decision

**No new genesis now.** A new genesis is conditionally warranted after owner acceptance and the
activation gates pass. It would be a new product generation, not restoration or continuation.

The generation manifest must permanently disclose:

- predecessor: legacy Verdandi v1;
- predecessor continuity: `none`;
- incident: legacy database deleted 2026-07-13; physical recovery declined;
- approximate lost history: 67,000 events, never represented as an exact verified count;
- schema/purpose discontinuity: generic activity events replaced by action receipts;
- first v2 chain head and independently witnessed checkpoint.

### Gates before activation

1. Owner explicitly accepts the purpose, scope, non-goals, and failure semantics.
2. The schema has fixtures proving every `must log` class and rejecting every `must not log` class.
3. Tenant identity has mint/list/rotate/revoke and server-derived actor tests.
4. Tailnet-only off-Pi intake works without exposing the service publicly.
5. Two real adapters pass end to end, one of them a non-Claude tenant and one independently reading
   an authoritative outcome. Dry-run/sandbox fixtures may be used for financial paths.
6. Hugin or another mutation gate demonstrably fails closed before an unaudited autonomous mutation.
7. Heimdall or an operator CLI consumes stale/failed/drifted receipts and causes a concrete action.
8. A checkpoint is witnessed across an independent trust boundary; a full export/restore test passes.
9. Retention and erasure behavior is tested on the v2 schema.
10. `services.json`, the architecture, tenant contract, failure-recovery convention, threat model,
    and data-lifecycle map are updated together before deployment.

### Stop conditions after activation

Retire Verdandi if any of these remains true for two consecutive monthly reviews:

- no operating decision, rollback, denied mutation, or incident review consumed a receipt;
- most outcomes remain actor-declared rather than independently observed;
- integrations drift back to tool/session telemetry;
- the service costs more operator time than the autonomous actions it protects;
- source-system records plus Hugin provenance answer every real query without the cross-system link.

## Existing issue disposition

| Issue | Disposition | Rationale / replacement scope |
|---|---|---|
| [#1 Phase 2 integrations and rubber-stamp detection](https://github.com/Magnus-Gille/verdandi/issues/1) | **Supersede and close** | Drop rubber-stamp scoring, generic Hugin lifecycle and Telegram receipt telemetry. Refile narrow adapters for consequential Hugin/noxctl/Ratatoskr mutations, durable outbox, and scoped read/write identity only after ADR acceptance. |
| [#2 Phase 3 GDPR compliance](https://github.com/Magnus-Gille/verdandi/issues/2) | **Rewrite** | Retain data minimization, tested retention/erasure, and independent anchoring. Drop the preselected pseudonym-key DB and RFC 3161 implementation as foregone conclusions. Schema-level exclusion is the first privacy control. |
| [#3 Phase 4 dashboard and analysis integrations](https://github.com/Magnus-Gille/verdandi/issues/3) | **Supersede and close** | No generic widget, cross-session analysis, or post-session extraction. Create only an exception consumer for stale/failed/drifted/gap receipts after v2 evidence exists. |
| [#5 warrant-inspired rebuild](https://github.com/Magnus-Gille/verdandi/issues/5) | **Supersede and close** | Adopt intent/outcome separation, final-state evidence, and content digests. Reject universal intent refs, content hash as the action identifier, `.verdandi/` per-repo stores, leases, and a code-only model as Verdandi's architecture. |
| [#15 off-Pi intake and per-tenant identity](https://github.com/Magnus-Gille/verdandi/issues/15) | **Retain but rewrite** | Still a real blocker. Narrow it to tailnet-only receipt intake plus mint/list/rotate/revoke or federated identity, and update tenant-contract language from “every consequential action event” to the accepted receipt contract. Tailscale Serve is a candidate transport, not the identity solution. |

One extra finding should be carried into #21 even though it is not in the requested disposition list:
issue #16 was closed after local recurring checkpoints landed, but the current implementation and
threat model both show that **independent** anchoring is still absent. Treat an off-host witness as an
unresolved activation requirement; do not reopen or edit the closed issue without owner direction.

## Explicit non-goals

- Full chat, reasoning, prompt, tool-call, or session capture.
- A replacement for Munin, Mimir, Git, Hugin history, service logs, OTel, or provider records.
- A general SIEM, event bus, workflow engine, policy engine, or LLM-evaluation platform.
- Proving that a client statement is true merely because it was authenticated and hash-chained.
- Storing source payloads “for later analysis.”
- A dashboard before a real exception consumer exists.
- A Grimnir-specific PKI when the ecosystem identity spine has not selected one.
- Restarting v1 or backfilling the lost chain.

## Proposed owner decision

Accept **Option C: narrow continuation**, with the definition and gates above. In the same decision:

1. retire the v1 generic audit/telemetry purpose permanently;
2. approve “consequential action receipt ledger” as Verdandi's sole purpose;
3. require fail-closed pre-action receipts for autonomous consequential mutations;
4. authorize contract/fixture work only—still no deployment or new genesis;
5. apply the issue dispositions above;
6. require a second owner review after the gates are evidenced and before genesis.

If Magnus does not want audit availability on the autonomous-mutation critical path, select Option A
and retire Verdandi. A fail-open generic log is not valuable enough to justify resurrection.

## Primary sources consulted

- [OpenTelemetry Logs Data Model](https://opentelemetry.io/docs/specs/otel/logs/data-model/)
- [Arize Phoenix documentation](https://arize.com/docs/phoenix/)
- [Langfuse self-hosted feature matrix](https://langfuse.com/pricing-self-host)
- [OPA Decision Logs](https://www.openpolicyagent.org/docs/management-decision-logs)
- [Cerbos audit configuration](https://docs.cerbos.dev/cerbos/latest/configuration/audit.html)
- [Temporal documentation](https://docs.temporal.io/)
- [happi/warrant](https://github.com/happi/warrant)
- [in-toto](https://in-toto.io/)
- [immudb](https://docs.immudb.io/master/immudb.html)
- [Sigstore Rekor](https://docs.sigstore.dev/logging/overview/)
- [WorkOS Audit Logs](https://workos.com/docs/audit-logs)
- [Retraced](https://github.com/retracedhq/retraced)
- [Pangea Secure Audit Log](https://pangea.cloud/docs/audit/overview/about)
- [SPIFFE concepts](https://spiffe.io/docs/latest/spiffe-about/spiffe-concepts/)
- [step-ca](https://smallstep.com/docs/step-ca/)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)

The April 2026 internal landscape survey, architecture proposal, ingest/trust specification, and
adversarial review in Mimir were also read. They remain historical inputs, not current authority.

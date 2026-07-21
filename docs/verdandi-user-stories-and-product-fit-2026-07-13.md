# Verdandi Action Receipts — User Stories and Product Fit

> **Status:** Candidate product brief for owner review; not an accepted backlog and not an
> authorization to restart Verdandi.
> **Date:** 2026-07-13
> **Companion to:** [Verdandi Purpose Reset](verdandi-purpose-reset-2026-07-13.md)
> **Tracks:** [verdandi#21](https://github.com/Magnus-Gille/verdandi/issues/21)

## Product conclusion

The reusable product should not primarily be “the Verdandi server.” It should be a small **Action
Receipt Protocol** with SDK/middleware and authoritative-system adapters. Verdandi can be Grimnir's
self-hosted reference ledger and verification service.

That separation makes the idea fit naturally inside Hugin, noxctl, deployment tooling, SaaS admin
planes, agent SDKs, and physical control systems without forcing each product to adopt Grimnir's
database or UI:

```text
actor/agent
    |
    v
product mutation boundary -- durable action.intent --> receipt ledger
    |                                                    |
    v                                                    v
authoritative system ------- independent readback --> action.outcome
    |                                                    |
    +---------------- reversal / mitigation <------------+
```

The product's distinctive promise is:

> Before an autonomous consequential action, record who is acting, under whose authority, what
> effect is permitted, and how failure will be contained. Afterward, independently establish what
> the authoritative system says happened and preserve enough evidence to investigate or reverse it.

This is narrower than observability and stronger than an emitter-authored audit log. The mutation
boundary—not the model loop—is the correct integration point.

## Story conventions

These are candidate stories, not implementation commitments.

- **P0 — proof/activation:** required before a Verdandi v2 genesis or real autonomous mutation.
- **P1 — operational value:** required before the system can justify remaining a permanent service.
- **P2 — conditional expansion:** build only after observed usage establishes the need.

“Authoritative readback” means a query to the source of truth after the attempted action. A success
response from the acting tool is not, by itself, sufficient evidence. “Independent” means the
outcome is emitted by a constrained adapter/observer rather than asserted by the LLM or tenant that
requested the change.

## Personas

| Persona | Job |
|---|---|
| **Owner/operator** | Delegate useful autonomy without losing control, attribution, or recovery. |
| **Acting tenant** | Know whether a mutation is allowed and leave a valid receipt without learning ledger internals. |
| **Mutation-boundary integrator** | Add the control once around a product's write path rather than to every agent. |
| **Outcome-adapter author** | Convert source-system readback into minimal, trustworthy outcome evidence. |
| **Reviewer/incident responder** | See exceptions and reconstruct one consequential action quickly. |
| **Privacy/data steward** | Minimize sensitive duplication and apply retention or erasure policy demonstrably. |

## Candidate story bank — 64 stories

### 1. Selection, authority, and pre-action control

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-SEL-01 | P0 | As a mutation-boundary integrator, I want a deterministic rule for whether an operation is consequential so that reads and harmless drafts bypass the ledger. | Shared fixtures classify representative operations consistently; ordinary reads work while Verdandi is unavailable. |
| AR-SEL-02 | P0 | As an acting tenant, I want the gate to durably accept `action.intent` before execution so that the authorization record cannot be invented afterward. | A test proves no provider write occurs when intent persistence fails. |
| AR-SEL-03 | P0 | As an owner, I want every intent bounded by action class, target, and expected effect so that a vague approval cannot authorize an arbitrary change. | The schema rejects missing or wildcard bounds outside explicit policy. |
| AR-SEL-04 | P0 | As an owner, I want the receipt to name both actor and principal/authority so that “which agent acted?” and “on whose authority?” have separate answers. | Both identities appear in the stored intent and are server-derived or grant-backed. |
| AR-SEL-05 | P0 | As an owner, I want a reversal recipe or explicit irreversible-action mitigation before execution so that “undo” is considered before risk is taken. | Consequential actions lacking either are rejected; irreversible examples require a named mitigation. |
| AR-SEL-06 | P1 | As an owner, I want human approval references attached to the exact bounded intent so that approval for one object cannot be replayed for another. | Changing the target/effect invalidates the approval digest or grant. |
| AR-SEL-07 | P1 | As a product integrator, I want policy to distinguish human-directed, policy-preapproved, and fully autonomous actions so that control strength matches delegated authority. | Fixtures demonstrate distinct authority modes and review requirements. |
| AR-SEL-08 | P2 | As a product integrator, I want domain risk hints to assist selection so that well-described tools need less hand configuration. | Hints affect classification only after local policy validation and never serve as authorization or proof. |

### 2. Authoritative outcome and drift

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-OUT-01 | P0 | As an owner, I want an observer distinct from the acting tenant to read back the result so that a tenant cannot certify its own claim. | Outcome identity is adapter-scoped and a tenant credential cannot emit it. |
| AR-OUT-02 | P0 | As a reviewer, I want the receipt to point to the stable source-system object or revision so that I can inspect the authority rather than trust copied prose. | The outcome contains a resolvable immutable reference or a documented stable identifier. |
| AR-OUT-03 | P0 | As a reviewer, I want expected and actual effects compared into a small drift vocabulary so that mismatches are machine-actionable. | At least `none`, `partial`, `unexpected`, `unverifiable`, and `missing` are covered by fixtures. |
| AR-OUT-04 | P0 | As an operator, I want intents without timely outcomes to become gaps so that silence cannot look like success. | A deterministic timeout creates an alertable `action.gap`. |
| AR-OUT-05 | P0 | As an integrator, I want idempotent correlation across retries so that network retries do not create multiple authorized actions. | Reusing an idempotency key returns the same action; conflicting payloads are rejected. |
| AR-OUT-06 | P1 | As an adapter author, I want to attach a digest of the authoritative post-state without copying it so that later drift can be checked privately. | Canonicalization and digest fixtures pass across equivalent provider responses. |
| AR-OUT-07 | P1 | As an operator, I want asynchronous providers reconciled later so that queued writes are neither prematurely successful nor permanently ambiguous. | A pending outcome can become succeeded/failed only through adapter readback, with history preserved. |
| AR-OUT-08 | P2 | As a reviewer, I want multi-target actions decomposed into per-target effects so that partial batch success is visible and recoverable. | A batch fixture reports exact successful, failed, and unknown targets without duplicating payloads. |

### 3. Reversal, mitigation, and incident recovery

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-REC-01 | P0 | As an incident responder, I want the intent, outcome, authority, and reversal evidence for one action in one view so that reconstruction takes minutes, not log archaeology. | An action-ID query returns the linked receipt chain and source references. |
| AR-REC-02 | P0 | As an owner, I want reversal recipes to use a small validated vocabulary so that free-text “undo this” is not mistaken for executable recovery. | `git_revert`, `snapshot_restore`, provider inverse, and `irreversible+mitigation` fixtures validate. |
| AR-REC-03 | P0 | As an acting tenant, I want rollback itself to be a new consequential action linked to the original so that recovery remains attributable and reviewable. | A rollback produces its own intent/outcome pair and `reverses_action_id`. |
| AR-REC-04 | P0 | As an operator, I want rollback success verified from the source of truth so that an executed command is not confused with restored state. | The original adapter confirms the restored revision/object state. |
| AR-REC-05 | P1 | As an incident responder, I want irreversible actions to expose the promised mitigation so that I know the next containment step immediately. | A sent-message fixture shows provider reference plus correction/notification procedure, not a fake undo. |
| AR-REC-06 | P1 | As a data steward, I want restore and erasure actions to report every affected store and any residual gap so that partial completion is explicit. | A multi-store test cannot report success while one required store remains unknown. |
| AR-REC-07 | P1 | As an operator, I want to ask what consequential changes occurred since a trusted checkpoint so that incident scope can be bounded. | Query output is derived from verified receipt order and flags unanchored intervals. |
| AR-REC-08 | P2 | As an incident responder, I want a portable evidence pack with verification instructions so that I can investigate while the live service is impaired. | Export verifies offline without exposing source payloads or credentials. |

### 4. Tenant identity and delegated authority

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-ID-01 | P0 | As an owner, I want one credential per tenant so that Codex, Claude, Hugin, and a domain service cannot be conflated. | Mint/list/rotate/revoke works and two tenants produce distinct actor IDs. |
| AR-ID-02 | P0 | As a reviewer, I want actor identity derived by the server from authentication so that callers cannot self-label as another tenant. | A spoofed `actor_id` is ignored or rejected. |
| AR-ID-03 | P0 | As an owner, I want a tenant's credential scoped to allowed action classes and roles so that receipt access does not grant universal mutation authority. | Cross-scope intent and outcome attempts are denied. |
| AR-ID-04 | P0 | As an owner, I want immediate revocation so that a compromised tenant cannot create new valid intents. | Revoked credentials fail while historical receipt verification remains intact. |
| AR-ID-05 | P1 | As a reviewer, I want historical identity immutable across key rotation so that old receipts retain a stable actor while keys change safely. | Rotated keys map to the same tenant record with distinct validity intervals. |
| AR-ID-06 | P1 | As an owner, I want principal authority separated from workload identity so that a service can act for Magnus, a policy, or another bounded grant without ambiguity. | Receipt fixtures distinguish `actor_id`, `principal_id`, and `authority_ref`. |
| AR-ID-07 | P1 | As an adapter author, I want observer-only credentials so that readback components cannot authorize or perform mutations. | Observer credentials can append outcomes for allowed domains but cannot create intents. |
| AR-ID-08 | P2 | As an operator, I want short-lived workload credentials when the fleet warrants them so that static-key exposure is bounded without changing receipt semantics. | A credential-provider conformance test works without requiring Verdandi to become a PKI. |

### 5. Review, exception handling, and autonomy governance

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-REV-01 | P0 | As an operator, I want Heimdall to show only unresolved gaps, failures, drift, and integrity problems so that Verdandi creates decisions rather than another feed. | Normal successful receipts create no dashboard alert. |
| AR-REV-02 | P0 | As an operator, I want stale intents ranked by risk and age so that the most dangerous ambiguity is handled first. | A deterministic view orders seeded gaps correctly. |
| AR-REV-03 | P1 | As an owner, I want to inspect all evidence for one exception without searching raw service logs so that review is fast but source-linked. | One view links intent, outcome/gap, task/trace, authority object, and reversal. |
| AR-REV-04 | P1 | As an owner, I want an exception resolved only by verified outcome, verified reversal, or an explicit accepted residual risk so that “dismiss” is not silent deletion. | Resolution produces an attributable append-only record. |
| AR-REV-05 | P1 | As an owner, I want a monthly autonomy review by action class and tenant so that delegation can expand or contract from evidence. | Report shows counts, gaps, drift, reversals, and review decisions—not a synthetic trust score. |
| AR-REV-06 | P1 | As a component owner, I want repeated failures grouped by adapter/action class so that systemic integration defects are distinguishable from tenant mistakes. | Seeded recurrence produces a consolidated issue candidate with supporting action IDs. |
| AR-REV-07 | P2 | As an owner, I want policy-change proposals based on reviewed receipts so that evidence can improve autonomy without policy changing itself. | Suggestions require human acceptance and cite the exact receipt set. |
| AR-REV-08 | P2 | As an auditor/reviewer, I want a redacted, scoped export so that I can evaluate a period or incident without broad ledger access. | Export obeys tenant, time, action-class, and privacy filters and remains verifiable. |

### 6. Privacy, retention, and data lifecycle

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-PRV-01 | P0 | As a data steward, I want receipts to contain references, digests, and bounded summaries rather than prompts, messages, diffs, or records so that the ledger does not become a shadow data store. | Schema and redaction tests reject representative sensitive payload fields. |
| AR-PRV-02 | P0 | As an integrator, I want conservative classification defaults so that omitted labels never make evidence less protected. | Unlabeled events receive the configured floor; callers cannot downgrade it. |
| AR-PRV-03 | P0 | As an owner, I want secrets rejected before persistence so that hash chaining does not make accidental credentials harder to remove. | Seeded API keys, tokens, and credential fields never reach durable storage. |
| AR-PRV-04 | P0 | As a data steward, I want retention selected by evidence class and action domain so that “append-only” does not silently mean “keep all personal metadata forever.” | Policy fixtures yield explicit expiry/retain behavior for each supported class. |
| AR-PRV-05 | P1 | As a data subject/owner, I want approved erasure or crypto-shredding to leave a verifiable tombstone so that privacy obligations and chain continuity can coexist honestly. | Removed protected fields are unrecoverable; the tombstone states what category was erased and why. |
| AR-PRV-06 | P1 | As a reviewer, I want access to receipt metadata separately authorized from source-object access so that a ledger link does not bypass the source system's controls. | A receipt reader cannot dereference a protected source without separate authorization. |
| AR-PRV-07 | P1 | As a data steward, I want export and backup scopes to preserve classification so that moving evidence does not downgrade it. | Restored/exported fixtures retain policy labels and access checks. |
| AR-PRV-08 | P2 | As an owner, I want measurable metadata-leakage checks before external anchoring so that integrity proofs do not reveal sensitive action timing or targets. | The anchor contains only approved aggregate/checkpoint material. |

### 7. Integrity, continuity, and degraded operation

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-OPS-01 | P0 | As an operator, I want complete-chain verification so that corruption or discontinuity is detected before evidence is trusted. | A clean fixture passes; deletion, reordering, and mutation fixtures fail at the expected record. |
| AR-OPS-02 | P0 | As an owner, I want checkpoints witnessed outside Verdandi's host so that a Pi compromise cannot rewrite both ledger and proof undetectably. | A verifier compares a restored ledger to an independently retained checkpoint. |
| AR-OPS-03 | P0 | As an operator, I want backup restoration tested, not merely scheduled, so that evidence continuity is demonstrated after host loss. | A clean-room restore passes schema, chain, anchor, identity, and query checks. |
| AR-OPS-04 | P0 | As an owner, I want consequential autonomous mutations to fail closed when intent or reversal evidence cannot be durably accepted so that audit impairment cannot silently increase autonomy risk. | Fault injection proves the provider is untouched. |
| AR-OPS-05 | P0 | As an operator, I want a bounded break-glass path with a durable local gap receipt so that essential recovery is possible without pretending the ledger was healthy. | An outage drill records authority/reason locally and later reconciles it visibly. |
| AR-OPS-06 | P1 | As an operator, I want health signals for intake, pending outcomes, anchor age, backup age, and verification without exposing receipt contents so that Heimdall can monitor the control plane safely. | Health contract and seeded alerts cover each failure mode. |
| AR-OPS-07 | P1 | As an integrator, I want explicit generation and schema boundaries so that breaking changes cannot imply false continuity. | Mixed-generation verification reports the boundary and never chains across an unproved reset. |
| AR-OPS-08 | P2 | As an operator, I want signed/offline verification tooling independent of the running API so that a compromised application cannot be its own sole verifier. | A small read-only verifier detects tampered database/export fixtures. |

### 8. Developer experience and product integration

| ID | Pri | User story | Acceptance evidence |
|---|---:|---|---|
| AR-DEV-01 | P0 | As an integrator, I want versioned JSON Schemas and positive/negative fixtures so that products can implement the contract without importing Verdandi internals. | CI validates at least two independent implementations against the same fixtures. |
| AR-DEV-02 | P0 | As an integrator, I want a small TypeScript client/middleware API so that intent-before-write and outcome-after-readback are hard to order incorrectly. | Reference example demonstrates gate, provider call, observer readback, and failure paths. |
| AR-DEV-03 | P0 | As an adapter author, I want actor and observer capabilities separated in the SDK so that integration convenience cannot collapse the trust boundary. | Compile/runtime tests reject outcome emission from actor-only clients. |
| AR-DEV-04 | P0 | As a product owner, I want a conformance harness with a fake provider so that fail-closed, idempotency, drift, and reversal can be proved before live access. | The harness runs locally and makes no external mutation. |
| AR-DEV-05 | P1 | As an MCP host integrator, I want tool annotations to seed risk classification so that `readOnly`, `destructive`, idempotency, and open-world hints are reusable without being trusted as proof. | Local policy overrides dishonest/missing annotations and defaults cautiously. |
| AR-DEV-06 | P1 | As an observability integrator, I want optional trace correlation so that execution detail can be found without copying traces into receipts. | A receipt holds only `trace_id`/task reference and works when the trace has expired. |
| AR-DEV-07 | P2 | As a platform integrator, I want an optional CloudEvents envelope so that existing brokers can transport receipts without changing receipt semantics. | Round-trip preserves the receipt schema; CloudEvents fields are not used as authority evidence. |
| AR-DEV-08 | P2 | As a security integrator, I want optional signed-statement envelopes so that higher-risk deployments can add portable authenticity without making PKI mandatory for the Grimnir MVP. | Signature verification is layered over, not embedded into, business semantics. |

## Anti-stories — explicitly not the product

These requests should be rejected or routed elsewhere unless a later, named consumer changes the
evidence:

1. As a developer, I want every prompt, completion, and chain-of-thought in Verdandi so that I can
   debug models. Use scoped traces/evaluations instead.
2. As an operator, I want every tool call and read operation in Verdandi so that nothing is missed.
   Use service logs or OpenTelemetry; volume is not accountability.
3. As a product owner, I want Verdandi to be the universal source of truth. Source systems remain
   authoritative; receipts point to them.
4. As an analyst, I want complete email, invoice, file, calendar, or diff contents copied into the
   ledger. Store a stable reference/digest and read the protected source when authorized.
5. As an agent author, I want the LLM to decide whether its own action succeeded. A constrained
   observer must perform authoritative readback.
6. As an integrator, I want a successful HTTP response to count as verified outcome. Provider
   acceptance and authoritative post-state are different facts.
7. As an owner, I want human actions copied from every provider for completeness. Only delegated
   Grimnir actions or specifically selected substrate-control actions belong here.
8. As an operator, I want a real-time stream of all successful receipts. The default consumer is an
   exception view; successful history is queried on demand.
9. As a manager, I want one opaque “agent trust score.” Review concrete gaps, drift, reversals, and
   action classes; do not launder judgment into a number.
10. As an integrator, I want Verdandi availability to gate reads, drafts, and non-consequential
    work. The fail-closed boundary applies only to autonomous consequential mutation.
11. As a vendor, I want to claim regulatory compliance because receipts are hash-chained. The
    protocol can provide evidence, not legal compliance by itself.
12. As a maintainer, I want another workflow runtime, policy engine, SIEM, or observability UI
    bundled into Verdandi. Integrate with those layers; do not absorb them.

## Where it fits in Grimnir

The same protocol should appear in different products at their **write boundary**, while Verdandi
stores and verifies the shared receipt relationship.

| Product | Receipt-worthy boundary | Authoritative readback | Reversal/mitigation | Recommendation |
|---|---|---|---|---|
| **Grimnir deploy tooling** | Apply a service revision or unit/config artifact | Production marker, installed-file digest, service health, exact Git SHA | `git_revert`, prior artifact/unit restore, redeploy | **First adapter.** The source refs, rollback convention, and marker discipline largely exist already. |
| **Hugin** | Dispatch/permit a task that crosses into a consequential write | Domain adapter, not the task's own success status | Domain recipe carried through the task contract | **Core integration.** Put receipt selection and fail-closed intent at the mutation gateway, not in prompts. |
| **Heimdall** | No mutations needed for the first slice | Verdandi verification/gap health | Links to runbook/action detail | **First consumer.** Show only stale intents, drift, failed outcomes, anchor/restore problems, and unresolved gaps. |
| **noxctl / Fortnox MCP** | Create/update/book/send/delete a financial object | Fortnox object ID plus fresh GET/readback | Supported inverse, correcting entry, or explicit irreversible mitigation | **Strong second domain, sandbox first.** High consequence and good source authority; never duplicate invoice/accounting payloads. |
| **Brokkr** | Change host config, systemd state, storage, backup, ACL, or key posture | Host/provider state, file digest, snapshot or service status | Pre-state snapshot, config restore, service rollback | Strong operational fit after the deploy adapter; use only for autonomous/substrate mutations, not routine metrics. |
| **Mimir** | Delete, restore, move, or change access to protected files | Filesystem/object metadata and digest | Snapshot/backup restore or verified erasure record | Future fit when Mimir gains writes; its present read-only serving path should not be gated. |
| **Ratatoskr** | Send an external message or execute a routed consequential command | Telegram/provider message ID or domain adapter result | Correction/notification for sends; domain recipe for commands | Useful but privacy-sensitive. Log target reference minimally; do not ingest messages or routing chatter. |
| **Munin Memory** | Destructive correction, namespace erasure, classification/security change, or autonomous overwrite with operational consequence | Fresh memory read/history reference | Prior value/snapshot or explicit erasure semantics | Select narrowly. Logging every memory write would recreate v1 volume and duplicate Munin's own history. |
| **M5 inference gateway** | Change model availability, routing policy, admin config, key, or download/load state | Gateway/admin state and artifact digest | Prior config/model state or containment | Admin-plane fit only. Inference calls, prompts, latency, token use, and model scores stay in traces/ledger designed for inference. |
| **Skuld** | Publish/send a briefing autonomously, if that becomes consequential | Delivery/provider reference | Correction/notification | Not a general receipt consumer. It may summarize unresolved exceptions only after Heimdall proves the view useful. |
| **Any Grimnir tenant** | The common consequential-action seam in the tenant contract | Domain-specific observer | Standard recipe vocabulary | This is the portability payoff: tenants adopt one contract without writing directly to Verdandi's database. |

### Recommended Grimnir event path

1. Hugin or product-local middleware classifies a requested operation using local policy. MCP tool
   annotations may inform this classification, but the MCP specification requires clients to treat
   annotations as untrusted unless the server is trusted.
2. For a consequential autonomous mutation, the middleware submits a bounded intent using the
   authenticated tenant identity and authority reference.
3. Verdandi durably accepts or rejects the intent. Rejection prevents the mutation.
4. The product performs the write against the authoritative system.
5. A domain adapter reads the authoritative state back using observer-only capability.
6. Verdandi appends outcome or gap. Heimdall receives only exception/health state.
7. Reversal is another action with its own intent, readback, and link to the original.

## Where it could fit in other products

### Product-category fit

| Product category | Where the protocol sits | Strong value case | Main caveat |
|---|---|---|---|
| **MCP hosts and tool gateways** | Around execution of destructive/open-world tools; annotations seed classification and structured results help adapters | Adds durable pre-action authority and post-action verification across many agent tools | Tool annotations are hints, not trustworthy declarations; a server-provided success result is not independent outcome. |
| **Agent SDKs and harnesses** | A middleware hook around consequential tool invocations | Makes autonomy controls portable across model vendors and agent runtimes | Keep it outside prompt/trace capture; the model must not control receipt truth. |
| **Coding agents / DevOps** | PR creation/merge, release, deployment, infrastructure apply, secret or environment change | Git SHAs, PRs, deployment markers, and provider state make outcomes unusually verifiable and reversals concrete | GitHub artifact attestations prove build provenance, not the full runtime authorization→deployment→rollback relationship; link rather than duplicate them. |
| **Accounting, payments, and finance automation** | Immediately around create/book/send/pay/correct operations | High consequence, stable source IDs, bounded action classes, strong need for principal authority and corrective evidence | Domain/legal rules define valid reversal; do not promise compliance or store financial payloads. |
| **Enterprise SaaS admin/control planes** | User/role/ACL/key/config changes made by automation | Joins delegated authority to provider readback and rollback across otherwise disconnected SaaS systems | Provider audit logs may already cover outcome; value exists only if cross-system authority/recovery is missing. |
| **RPA and back-office automation** | At connectors that mutate CRM, ERP, ticketing, HR, procurement, or records | Replaces screenshot/task-success assertions with source-object verification and partial-batch drift | UI-only systems may lack stable readback and IDs; unsupported actions should remain human-gated. |
| **Personal assistants** | Send email/message, change calendar, buy/book, share/delete files | Makes personal autonomy reviewable with explicit irreversible-action mitigation | Very privacy-sensitive; references and recipient pseudonyms must replace content capture. |
| **Infrastructure and IT operations** | Config deploy, service restart, ACL/key change, backup/restore, host remediation | Strong pre-state/post-state and reversal patterns; incident responders are obvious consumers | Avoid duplicating config/log/metrics payloads; link to Git, CMDB, or provider authority. |
| **Data lifecycle and privacy tooling** | Delete, restore, retention, legal-hold, export, or access-policy operations | Can prove which stores were addressed and expose residual gaps rather than declaring broad success | Append-only integrity and erasure obligations must be designed together; tombstones are not universal legal answers. |
| **Robotics, drones, labs, and industrial/IoT control** | Immediately before actuator commands and after sensor/controller confirmation | Physical actions make authority, bounded intent, independent observation, and mitigation unusually valuable | Safety certification, real-time constraints, and domain interlocks exceed this protocol; the ledger is evidence, not the safety controller. |
| **Smart-home agents** | Door/lock, alarm, appliance, energy, access-code, or purchase actions | Small action vocabulary and local control align with sovereign receipts | Consumer usability and outage behavior are critical; do not gate harmless automations or pretend all physical outcomes are observable. |
| **API gateways / policy engines** | After allow/deny, before upstream mutation, then joined to a domain readback adapter | Complements policy decision logs by proving what actually happened after authorization | A gateway often sees only request/response, not authoritative post-state; adapter coverage is the real work. |
| **Regulated/high-stakes workflow products** | As an evidence layer linked to existing approval, record, and retention systems | Clear actor/principal split, source references, exceptions, and recovery evidence can strengthen controls | Requirements are jurisdiction/domain-specific. Sell evidence primitives, never blanket compliance. |

### Fit with adjacent standards and products

- [MCP tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools) provide a useful
  invocation boundary, structured results, and risk annotations. Their own security guidance calls
  for user confirmation on sensitive operations and says annotations are untrusted unless the
  server is trusted. Action receipts can consume these hints, but must add identity, durable
  authority, independent readback, and reversal.
- [CloudEvents](https://cloudevents.io/) is a good optional event **envelope** when products already
  use brokers. It should not define authorization, integrity, or outcome semantics.
- OpenTelemetry trace/task identifiers are useful correlation references. Execution telemetry can
  expire independently; the minimal receipt must remain meaningful without the trace.
- [GitHub artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)
  can establish signed build provenance. A deploy receipt should link to an attestation when one
  exists, while separately proving runtime authority, observed deployment state, and reversal.
- OPA/Cerbos-style decision logs can supply `authority_ref` and policy version. They prove a policy
  decision, not the external mutation or its continuing source state.
- Provider audit logs can be authoritative outcome evidence or supporting references. Verdandi
  should not re-ingest their full content.

## Product packaging options

| Option | Assessment |
|---|---|
| **A. Grimnir-only Verdandi service** | Useful as the first proof, but makes every adopter depend on a particular service and obscures which semantics are portable. |
| **B. Open protocol + SDK/middleware + adapters; Verdandi as reference server** | **Recommended if the internal proof succeeds.** Keeps the contract small, enables embedding in existing products, and makes adapter quality the product moat. |
| **C. Standalone generic audit-log SaaS** | Reject now. It enters a crowded category, weakens sovereignty, rewards ingestion volume, and still cannot independently observe domain outcomes without adapters. |
| **D. Feature copied independently into Hugin/noxctl/etc.** | Reject duplication. Products should own classification and readback adapters, but share schemas, client behavior, and verification semantics. |

If externalized, a sensible package family would be:

```text
@action-receipts/schema        versioned protocol + fixtures
@action-receipts/client        intent/gap/query client
@action-receipts/middleware    fail-closed mutation wrapper
@action-receipts/adapter-sdk   constrained authoritative outcome API
verdandi                       self-hosted reference ledger/verifier
verdandi-verify                offline verification CLI/library
```

The name **Verdandi** can remain the Grimnir component. A neutral protocol name is easier to embed
elsewhere and avoids making the server the architecture.

## Recommended proof sequence

### Stage 0 — contract, no genesis

Freeze only enough semantics to run fixtures: selection rule, intent/outcome/gap, actor/principal/
observer split, action ID/idempotency, reversal vocabulary, privacy fields, and failure behavior.
Build the conformance harness before a real ingestion path.

### Stage 1 — deploy adapter, simulated first

Use Grimnir deployment as the first vertical slice because it already has exact revisions,
transactional markers, health gates, and `git_revert` recovery. Prove:

- intent accepted before mutation;
- exact production revision read back by an observer;
- failure and missing-marker drift;
- reversal as a linked action;
- Verdandi outage leaves production untouched;
- independent checkpoint and clean-room restore.

### Stage 2 — Hugin gate and Heimdall exception consumer

Put shared selection/fail-closed middleware at Hugin's consequential mutation boundary. Add only an
exception/health surface to Heimdall. Run an owner review after real exceptions have been handled.

### Stage 3 — independent second tenant and domain

Add a non-Claude tenant and the noxctl/Fortnox adapter against mocks or a safe sandbox/dry-run
harness. This tests per-tenant identity, financial-domain minimization, provider readback, and
irreversible/corrective semantics without authorizing a live accounting write.

### Stage 4 — decide whether there is a product

Publish/extract the protocol only if two independent integrations implement it without Verdandi
internals and receipts have changed at least one real operating decision. Otherwise keep it an
internal Grimnir seam or retire it.

## Minimum activation backlog

The 64 stories are a discovery bank. The smallest defensible activation slice is:

1. AR-SEL-01 through AR-SEL-05 — selection, durable intent, bounded authority, reversal.
2. AR-OUT-01 through AR-OUT-05 — independent observer, source reference, drift, gaps, idempotency.
3. AR-REC-01 through AR-REC-04 — reconstruct and verify reversal.
4. AR-ID-01 through AR-ID-04 plus AR-ID-07 — per-tenant identity, scope/revoke, observer isolation.
5. AR-REV-01 and AR-REV-02 — a concrete exception consumer.
6. AR-PRV-01 through AR-PRV-04 — minimization, classification, secret rejection, retention.
7. AR-OPS-01 through AR-OPS-05 — verification, independent anchor, restore, fail-closed,
   break-glass.
8. AR-DEV-01 through AR-DEV-04 — schemas, safe middleware, role separation, conformance harness.

That is already a meaningful control product. P1/P2 work should not delay proof of this vertical
slice or create a broad platform before use exists.

## Success measures and falsifiers

Verdandi v2 earns permanence only if it changes decisions or recovery outcomes. Measure:

- percentage of selected actions with timely authoritative outcomes;
- unresolved gap age by risk;
- rate and class of intent drift;
- reversals attempted and independently verified;
- time to reconstruct one consequential action during review/incident;
- receipts referenced in a rollback, incident, policy change, or autonomy decision;
- payload-minimization and retention/erasure test results;
- false-positive burden from selection and Heimdall exceptions;
- adapter maintenance cost per real consequential action.

Stop or narrow the product if, across two monthly reviews:

- no receipt informs a gate, exception response, rollback, incident, or autonomy decision;
- most “outcomes” are still assertions from the acting tenant;
- event selection expands toward prompts, tool telemetry, or generic task history;
- source payload duplication or privacy exceptions become routine;
- independent anchoring/restore verification is not operational;
- integrators must understand Verdandi internals rather than the protocol;
- adapter cost exceeds the value of the actions being protected.

## Owner decisions still required

1. Is the protocol/server separation the desired definition, or should this remain explicitly
   Grimnir-internal even if successful?
2. Is fail-closed correct for **autonomous consequential mutations**, with a durable break-glass
   path for recovery?
3. Is Grimnir deploy tooling the right first vertical slice and Heimdall the first consumer?
4. Should noxctl/Fortnox be the second domain under mocks/sandbox, or should Brokkr host operations
   come first?
5. Which P1 stories, if any, are prerequisites for owner trust beyond the proposed P0 activation
   backlog?

Until those decisions and the purpose-reset activation gates are accepted, Verdandi remains stopped
and this document remains product discovery rather than a delivery plan.

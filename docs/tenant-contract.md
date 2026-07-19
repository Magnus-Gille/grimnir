# Agent tenant contract

An agent or harness is a tenant of the Grimnir substrate. A conforming tenant can be replaced without
bypassing memory, inference, safety, or audit controls.

## Identity axiom

Every tenant presents a distinct identity at every consequential seam. Borrowing another tenant's
credential is impersonation: it defeats attribution, quota, revocation, policy, and audit.

Identity must survive the complete path from request through task state, runtime invocation, result,
audit event, and reversal record.

## Seam A: memory

The substrate provides authenticated MCP or HTTP access to Munin Memory.

The tenant must:

- use its own credential and owned namespaces;
- use the service protocol rather than opening Munin's SQLite database;
- preserve classification and provenance fields;
- use compare-and-swap or the documented concurrency mechanism for updates;
- accept server-side size, secret, and policy rejection;
- avoid copying full artifacts into memory when a bounded Mimir reference is sufficient.

Conformance evidence: a write and read under the tenant identity, a rejected secret canary, and a
demonstrated concurrent-update conflict path.

## Seam B: inference

The substrate provides an authenticated OpenAI-compatible inference boundary. gille-inference is the
reference local gateway, but another compatible provider may be selected.

The tenant must:

- make provider/runtime selection configurable rather than hard-coding one SDK as the only path;
- use its own key and accept quota, model allowlist, timeout, and admission decisions;
- label task type and sensitivity sufficiently for policy and routing evaluation;
- avoid sending data to a remote provider unless the deployment policy permits that boundary;
- record enough outcome evidence to evaluate routing without retaining unnecessary prompt content.

Conformance evidence: successful allowed inference, denied disallowed model, visible attribution, and
a bounded routing outcome record.

## Seam C: safety gating

Hugin is the reference gate for asynchronous actions. Any mutating, egressing, credentialed, or shell
action must pass a policy boundary before execution.

The tenant must:

- provide authenticated provenance, declared capabilities, sensitivity, and an intended target;
- separate processing of untrusted content from consequential mutation;
- accept denials and surface them rather than retrying through a side channel;
- avoid ambient credentials that bypass the gate;
- fail closed when workspace preparation, identity validation, or policy evaluation fails;
- constrain time, output, network, and concurrency in proportion to impact.

Conformance evidence: one benign bounded action passes with tenant attribution, while prompt-injection,
path-escape, excessive-capability, and failed-workspace canaries are blocked before execution.

## Seam D: audit and recovery

The deployment provides an append-only or tamper-evident audit destination. Verdandi is an optional
implementation, not a required public repository.

For every consequential action, the tenant must emit:

- tenant identity and correlation identifier;
- target, declared reason, and policy decision;
- outcome and bounded diagnostics;
- evidence grade distinguishing mechanism-proven from self-reported facts;
- a reversal recipe or an explicit irreversible marker with mitigation.

The tenant must not fabricate server-authoritative identity, time, or integrity fields. Audit failure
must be visible; high-impact policies may require it to block the action.

Conformance evidence: action and reversal records can be correlated, integrity verification passes,
and the event is attributed to the tenant rather than a shared owner identity.

## File access

When a tenant uses Mimir, it must authenticate with its own identity, remain within the configured
root, respect content and size limits, and avoid treating a proxy-controlled header as trustworthy
unless the peer proxy is explicitly allowlisted.

## Observability

Health and diagnostics should reveal only what a tenant or operator needs. A tenant must not require
unauthenticated access to topology, alerts, task content, or mutation endpoints. Correlation IDs are
preferred over full payload duplication.

## Conformance checklist

- [ ] A distinct tenant identity is visible end to end and can be revoked independently.
- [ ] Memory uses authenticated service APIs and owned namespaces, never direct database access.
- [ ] Inference is provider-configurable, policy-bound, and outcome-measured.
- [ ] Consequential actions pass a fail-closed gate with explicit capabilities.
- [ ] Untrusted-content processing is separated from mutation.
- [ ] File access is bounded and authenticated with safe proxy trust.
- [ ] Every consequential action has correlated audit and reversal evidence.
- [ ] Logs, traces, and health surfaces minimize user data and topology.
- [ ] Timeout, quota, concurrency, and egress behavior have negative tests.

A tenant is conforming only when every applicable item has executed evidence. Documentation or a
shared credential alone is not conformance.

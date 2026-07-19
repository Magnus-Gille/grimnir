# Grimnir vision

Grimnir is a self-hosted, inspectable substrate that lets replaceable agents use durable personal
context and act through explicit safety boundaries.

The substrate is the product idea. An agent loop, model, user interface, or message channel is a
tenant and should be replaceable.

## Two durable assets

### Sovereign knowledge

Memory and files accumulate context that cannot be recreated by switching tools. Grimnir keeps the
authoritative copy under operator control, with authentication, provenance, correction, deletion,
backup, and restore as first-class concerns.

Self-hosting applies to authoritative storage, not automatically to every computation. A configured
remote model or integration receives whatever the deployment sends to it.

### Evidence-driven inference

Inference should be routed by measured capability, sensitivity, cost, latency, and availability rather
than a permanent assumption that one model is best. Local inference is valuable where its observed
quality and privacy properties fit the task; remote inference remains a replaceable option.

Here, “learns” means evidence-backed route and roster selection plus controlled optimization of
prompts, harnesses, and tool policy. It does **not** mean that the capability ledger trains model
weights. [ADR-006](adr-006-learning-improvement-scope.md) keeps weight training outside v1 pending
separate owner, privacy, dataset, evaluation, deployment, and rollback gates. The versioned
cross-repository evidence seam is [LearningTaskContract v1](learning-task-contract.md), and
[observability-and-improvement.md](observability-and-improvement.md) distinguishes implemented,
shadow, manual, and future stages. “Continuous” is a measured end-to-end claim, not a synonym for a
timer or a growing ledger.

## Design rules

- Build the memory, policy, measurement, and recovery seams that compound for the operator.
- Reuse open-source agent harnesses and interfaces where they satisfy the tenant contract.
- Keep services single-purpose and operationally understandable.
- Add complexity only where it enforces safety or improves measured routing.
- Remove components that have no measured use or named risk-reduction role.
- Require evidence before expanding unattended authority.

## Autonomy arc

1. **Reactive:** a person submits work; the system supplies memory, files, inference, and results.
2. **Self-maintaining:** the system detects drift and proposes or performs bounded maintenance.
3. **Proactive:** the system identifies useful work and prepares it for review.
4. **Trusted autonomy:** selected domains gain unattended execution after measured reliability,
   least-privilege credentials, and tested reversal paths.

Later phases are not promises. Each requires evidence from the preceding phase and can be rolled back.

## What Grimnir is not

- not a hosted multi-tenant service;
- not a model provider;
- not a chat UI competing with assistant frontends;
- not a reason to build every integration in-house;
- not secure merely because it runs on a private network.

## Open questions

- Which actions can earn unattended authority, and how is that authority revoked?
- Which evaluation signals predict real operator value rather than benchmark performance?
- How should component compatibility be versioned across independent repositories?
- What is the smallest reproducible installation worth supporting?
- Which optional integrations should become public reference adapters?

The tenant, recovery, observability, and lifecycle documents turn these questions into checkable
contracts rather than relying on trust in a particular agent.

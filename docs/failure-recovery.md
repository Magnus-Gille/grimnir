# Failure recovery and undo convention

Every autonomous mutation must leave enough evidence to understand and reverse it, or to contain its
effects when reversal is impossible. This is a contract, not a separate required service.

## Scope

The convention applies to writes made without a person approving that exact action at execution time,
including:

- repository commits, pull requests, or merges;
- production configuration and database changes;
- tickets, calendars, messages, financial systems, and other external APIs;
- deployments and host maintenance.

Read-only work has no state to restore, but still needs bounded diagnostics. A synchronous human-
approved mutation may use the surrounding approval system as its control record.

## Required records

Every autonomous mutation emits:

1. an **audit record** containing actor, target, reason, policy decision, outcome, and correlation ID;
2. exactly one **reversal recipe** described below.

The deployment chooses the append-only or tamper-evident audit sink. Verdandi is one optional
implementation; it is not a hidden dependency of the public ecosystem.

## Reversal recipe kinds

| Kind | Use when | Required data |
|---|---|---|
| `git_revert` | state changed through one or more git commits | repository plus immutable commit or merge reference sufficient for a safe `git revert` |
| `snapshot` | non-git state had a recoverable pre-mutation value | immutable pre-state reference, integrity evidence, and restore procedure |
| `compensating_action` | an external system supports an explicit inverse operation | inverse operation, target, preconditions, and idempotency key |
| `irreversible` | no safe inverse exists | `irreversible: true`, containment/notification mitigation, and required human follow-up |

Do not label an action reversible unless the recipe has been mechanically validated for that target.
An email or payment is not reversible merely because another message or transaction can be sent.

## Example event

```json
{
  "type": "mutation",
  "actor": "hugin:tenant-example",
  "component": "brokkr",
  "trace_id": "018f-example",
  "data": {
    "action": "dependency-bump",
    "target": "example/service",
    "outcome": "pull-request-opened",
    "reversal": {
      "kind": "git_revert",
      "ref": "https://example.invalid/example/service/commit/0123456789abcdef"
    }
  }
}
```

Server-authoritative time, identity, and integrity fields are added by the selected audit sink. Payloads
must be minimized and must not contain credentials or full user content.

## Deployment behavior

The central deployer records the prior accepted commit, removes the acceptance marker before the first
tree mutation, and writes a new marker only after install, unit refresh, restart, and health gates pass.

Rsync is not transactional. If transport or a later gate fails after mutation starts, treat the target
as unknown and either complete a verified redeploy or deploy the previously accepted commit. Never let
an old marker certify partially changed files.

## Safety rules

- Capture pre-state before mutating.
- Use immutable references rather than branch names or "latest" snapshots.
- Keep recipes per mutation; one task may produce several records.
- Verify the resulting state and record bounded evidence.
- Make audit failure visible. High-impact policies should fail closed when required audit cannot be
  persisted.
- Test restoration or compensation regularly; an unexecuted recipe is a hypothesis.
- Automatic rollback is a separate policy decision and needs its own authorization and loop guards.

This convention complements [`tenant-contract.md`](tenant-contract.md) and
[`observability-and-improvement.md`](observability-and-improvement.md).

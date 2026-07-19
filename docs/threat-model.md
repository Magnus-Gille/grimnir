# Grimnir threat model

This is a reference threat model. Every installation must revise it for its users, data, network,
providers, integrations, and physical controls.

## Assets

| Asset | Main failure modes |
|---|---|
| Mimir files | disclosure, destructive writes, unrecoverable loss |
| Munin memory | disclosure, poisoned facts, loss of accumulated context |
| Task and audit records | forged attribution, suppressed failures, missing reversal evidence |
| Service and provider credentials | lateral movement, impersonation, unexpected cost |
| Inference routing evidence | poisoned evaluations or unsafe model selection |
| Host and backup configuration | fleet takeover or failed recovery |

## Trust boundaries

- **Humans:** an operator may be fully trusted for administration, but mistakes and compromised
  accounts remain in scope.
- **Services:** each process is trusted only for its documented role and credentials.
- **Private networks:** useful exposure reduction, never an authorization mechanism by themselves.
- **Ingested content:** email, web pages, documents, messages, model output, and retrieved memory are
  untrusted instructions.
- **Dependencies and providers:** package registries, model services, tunnels, notification channels,
  and backup providers are separate trust domains.
- **Physical hosts:** theft, disk failure, power loss, and operator lockout remain possible.

## Priority threats and controls

| Threat | Typical path | Required control | Residual concern |
|---|---|---|---|
| Prompt-driven exfiltration | untrusted content → agent with files, memory, tools, and egress | classify content; separate read from action; gate tools and egress; use scoped credentials | scanners are not proof of benign intent |
| Workspace escape or command injection | crafted task or path → shell/runtime | validated bounded roots; argument-safe execution; fail closed on workspace setup | intentionally powerful coding tasks remain high impact |
| Broken authorization | shared keys, trusted proxy mistakes, unauthenticated mutation endpoints | distinct identities; explicit proxy allowlists; authorization on every mutation | operational key rotation and revocation |
| Memory poisoning | false or malicious fact repeatedly retrieved | provenance, ownership, compare-and-swap, correction and expiry | subtle falsehoods are hard to detect automatically |
| Supply-chain compromise | malicious dependency or build action | pinned lockfiles/actions, review, dependency scans, minimal runtime privileges | ecosystem scanners have incomplete coverage |
| Secret disclosure | committed config, logs, traces, errors, process arguments | secret manager, redaction, current/history scans, bounded diagnostics | old forks, caches, and external logs |
| Audit loss or forgery | action succeeds without durable attributable record | fail-loud audit emission, off-host anchors, reversal recipe | audit sinks can fail with the service host |
| Data loss | disk/host failure or destructive automation | encrypted backups, separate failure domain, recurring restore tests | backup presence is not recoverability |
| Physical theft | unencrypted storage or credentials on device | full-disk encryption, locked boot, revocable secrets | availability during recovery |
| Monitoring blind spot | service host and monitor fail together | independent dead-man signal and bounded alert payload | external alert providers add a trust domain |
| Lifecycle failure | personal or third-party data retained indefinitely | store map, retention enforcement, correction/deletion, backup expiry | immutable audit evidence requires minimization design |

## Autonomous-action requirements

An unattended action is permitted only when all of the following are true:

1. the requesting principal is attributable;
2. inputs and intended effect are bounded;
3. the executor has only the required capability and egress;
4. the outcome is independently observable;
5. a reversal recipe or explicit irreversible mitigation exists;
6. policy can revoke the authority without redeploying unrelated services.

## Accepted scope limits

The reference design primarily targets a small, operator-controlled installation. Strong hostile
multi-tenancy and targeted advanced adversaries require additional isolation and review. This scope
limit does not make the priority threats above accepted risks.

## Review triggers

Review this model at least quarterly and whenever a deployment changes authentication, user count,
network exposure, execution tools, inference provider, backup provider, or autonomous authority.

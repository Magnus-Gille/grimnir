# Documentation authority map

This map prevents configuration from silently diverging across repositories and documents.

## Fact ownership

| Fact type | Authoritative source | Consumers |
|---|---|---|
| Public registry schema and example topology | `services.json` | tests, public documentation |
| A real installation's hosts, ports, paths, enabled components, and units | ignored `services.local.json` or explicit `REGISTRY_PATH` | deploy, scan, and snapshot scripts |
| Grimnir control-plane system account and deploy path | committed Grimnir systemd units (`grimnir`, `/srv/grimnir/control-plane`) | registry validation and deployment |
| Install-ready systemd unit contents | owning component repository | deployment tooling |
| Global deploy safety rules | `scripts/deploy.sh` and `scripts/lib/deploy-safety.sh` | deployment tests |
| Repository names and component roles | `docs/conventions.md` | README and architecture |
| Cross-component design and data flow | `docs/architecture.md` | component documentation |
| Agent-to-substrate obligations | `docs/tenant-contract.md` | agent and harness adapters |
| Learning-task seam, field ownership, and compatibility | `docs/learning-task-contract.md` plus `docs/learning-task-contract-v1.schema.json` | Hugin and `gille-inference` producer/consumer schemas and fixtures |
| Improvement maturity and delivery sequence | `docs/observability-and-improvement.md` | architecture summaries and component plans |
| Improvement scope: routing/configuration versus model weights | `docs/adr-006-learning-improvement-scope.md` | learning docs, Hugin, and `gille-inference` |
| Hugin task and product facts | Hugin's versioned task, result, receipt, and experiment schemas | LearningTaskContract projection and Heimdall |
| Inference exposure, served-model, capability, and micro-routing facts | `gille-inference` versioned schemas and ledger | LearningTaskContract projection, Hugin, and Heimdall |
| Component behavior | code and tests in the owning repository | architecture summaries |
| Live health and versions | ignored generated deployment snapshot | operators only |
| Public project maturity | `PROJECT_STATUS.md` | README |
| Private execution state | ignored `STATUS.md` | local operators and agents |

## Rules

1. **One writer per fact.** Restatements cite the owning artifact and are updated after it.
2. **Example data never deploys.** The committed registry has `"public_example": true`; the deployer
   rejects it before network or filesystem mutation.
3. **Scripts share the selected registry.** `REGISTRY_PATH` wins. Otherwise an ignored
   `services.local.json` wins over the public example.
4. **Secrets are not registry data.** Credentials, tokens, recovery material, private locators, and
   personal data belong in a secret manager or ignored local configuration.
5. **Runtime data is not deployment data.** Mutable paths are declared in `persistent_paths`; an
   in-target runtime path also needs a matching `rsync_excludes` rule.
6. **Deployment markers certify acceptance.** A marker is written only after dependencies, unit
   refresh, restart, and health checks succeed.
7. **Timers are controller state.** Deployment enables and restarts declared timers. A deliberately
   one-shot timer must declare `timer_semantics: "one-shot"`.
8. **Unit files are install-ready artifacts.** Deployment does not render component-specific
   templates. Active unit lines with unresolved placeholders fail preflight.
9. **Runtime and deployment identities are separate.** Grimnir's own system units run as the
   non-login `grimnir` account from `/srv/grimnir/control-plane`; registry validation rejects another
   Grimnir deploy path. `DEPLOY_USER` is mandatory, selects a separate SSH operator, and never
   rewrites systemd `User=`.
10. **Scheduled secrets use systemd credentials.** The committed scan and validation units load the
    Munin key from root-owned `/etc/grimnir/credentials/munin-api-key`; secrets do not belong in
    `Environment=`. The scanner reads separate source checkouts from `/srv/grimnir/source` because
    rsync deployment targets intentionally contain no Git metadata.
11. **Learning facts retain their owners.** The cross-repository contract defines joins and
    compatibility; it does not let one producer overwrite the other's task, product, exposure, or
    capability verdicts. Storage and dashboards do not acquire decision authority.
12. **Maturity labels are evidence claims.** Implemented, shadow, manual, and future behavior must
    remain distinct. A configured timer, growing ledger, or rejected challenger is not a closed
    self-improvement loop.

## Generated snapshots

`scripts/generate-architecture.sh` may append ignored `docs/snapshot.md` to the stable architecture.
The snapshot may contain live state and therefore must never be committed.

Stable facts such as roles, boundaries, and protocols belong in `architecture.md`. Timestamped
service state, versions, host checks, and deployment results belong only in the ignored snapshot.

## Change protocol

When a deployment fact changes:

1. change the private selected registry;
2. validate it with `node scripts/lib/validate-registry.js`;
3. update stable public documentation only if the architecture or schema changed;
4. regenerate the ignored local snapshot;
5. deploy and verify one component at a time.

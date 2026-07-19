# Scheduled-task patterns

The selected private registry owns the enabled systemd units. Schedules live in the owning
component's timer files, not in this document.

Typical installations use recurring tasks for:

| Owner | Task class | Purpose |
|---|---|---|
| Heimdall | collection and retention | sample bounded health metrics, reconcile alerts, and prune old data |
| Hugin | journal analysis | summarize execution reliability and anomalies |
| Grimnir | security and registry validation | detect vulnerable dependencies, accidental secrets, and configuration drift |
| Brokkr | OS and dependency maintenance | report patches, reboot requirements, storage health, and stale packages |
| Optional producer | briefings | synthesize operator-selected sources into a scheduled report |

## Adding a task

1. Put the script and install-ready service/timer units in the owning repository.
2. Choose retention, timeout, privilege, network, and failure-notification behavior.
3. Add the units to the selected private registry.
4. Add regression tests for the task's safety boundary.
5. Deploy the owning component and verify the next trigger and one real execution.

Do not publish a live timer inventory, host schedule, notification destination, or task output in this
repository.

# Ticket system monitoring and registry position (GRIM-245)

Plane CE and ticket-gateway run on the M5 and are the ticket system for every repository and
agent. This record states how they are watched and why they are not in `services.json`.

## Monitoring

Heimdall polls ticket-gateway's unauthenticated `GET /health`
(`{"status":"ok","plane":{"reachable":true}}`). The gateway reports on itself and on whether it
reaches Plane's API, so one poll covers both services.

- Configuration: `TICKET_GATEWAY_HEALTH_URL` in Heimdall's private environment file. Unset, the
  probe is skipped. The live URL stays out of git.
- Alerts: `Ticket gateway unhealthy` (HTTP error, redirect, timeout, non-JSON, or
  `status != ok`) and `Plane unreachable from ticket gateway` (`plane.reachable != true`). Each
  fires after two consecutive failed polls and resolves on the first good poll, like the M5
  inference and Munin MCP probes.
- Severity: both rules are `warning`, which does not use Heimdall's critical Telegram path. An outage
  shows in Heimdall but does not page. Making either rule `critical` is an owner decision.
- Implementation: heimdall `src/ticket-system.js` with tests in `test/ticket-system.test.js` (heimdall#112; merge it first or together with this record).
- Not covered: Plane's own web UI behind Cloudflare Access (an unauthenticated request gets a
  302), the nightly `plane-backup.timer` (backup freshness belongs to Brokkr's backup evidence),
  and gateway latency trends beyond the stored `ticket_latency_ms` metric.

## Registry position

Decision (confirmed by the owner 2026-11-17): **ticket-system stays outside `services.json` for now.**

- ticket-gateway does not fit `owning_repo_deployments`: its deploy script takes a positional SHA
  instead of `--release`, writes no deployed-marker (it switches a symlink), and demands Cloudflare
  Access variables the M5 env file already holds.
- Plane runs as a Docker Compose project, which the registry and `deploy.sh` do not model.
- Heimdall derives its polled set from `components`, so a registry entry would not add monitoring;
  the synthetic probe above does.

Revisit when ticket-system adapts `deploy/m5/deploy-gateway.sh` to the `--release <sha>` plus
deployed-marker contract (request filed in the ticket-system Plane project). At that point the
gateway can become an `owning_repo_deployments` entry. Plane stays out unless the registry grows a
container-workload shape.

Reversal: remove `TICKET_GATEWAY_HEALTH_URL` and restart Heimdall to stop the probe and drop the card; no data migration is involved. An alert already open at that moment is closed by the stale-alert reaper after its window.

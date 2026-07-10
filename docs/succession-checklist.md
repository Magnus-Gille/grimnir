# Grimnir — Emergency Succession Checklist

> **Decision:** Sara is the emergency delegate. Her authority is limited to **export-and-shutdown**.
> This public checklist contains no credentials, recovery material, or private-envelope contents.

## Authority and trigger

Use this checklist only when Magnus is unavailable and the system must be preserved or made safe.
Sara may:

- obtain the private succession envelope through the out-of-repo location shared with her;
- ask an outside engineer for hands-on help, while retaining decision authority herself;
- stop public ingress, timers, autonomous execution, and services;
- make a recoverable export of stores that have a documented procedure, preserve any blocked store,
  and include the non-secret configuration needed to understand the result; and
- power down the hosts after completed exports are verified and blocked stores are preserved.

This authority does **not** include continuing normal operation, adding users, sending messages as
Magnus, changing financial records, deleting source data, or making unrelated repairs. The outside
engineer receives only the minimum access needed for the export-and-shutdown procedure and gains no
independent authority.

## Before an emergency

- [ ] Magnus has told Sara where the private succession envelope is held.
- [ ] Sara can identify the envelope without any locator or secret being committed to this repo.
- [ ] The envelope identifies how to obtain credentials; it does not depend on this checklist
      containing them.
- [ ] A dry walkthrough has confirmed that Sara understands the boundary: export, verify, contain,
      shut down.
- [ ] Verdandi's owning repo has a routine, tested export-and-restore procedure. **This does not
      exist today; export-and-shutdown readiness remains blocked until it does.**

The envelope-location boxes are owner-maintained, out-of-band prerequisites. The Verdandi box is a
technical prerequisite. Until all are confirmed, this checklist is not operationally complete and
must not be described as a tested whole-substrate export procedure.

## Current recovery procedures

Only these component-owned procedures are established today:

- **Munin:** use the
  [encrypted snapshot and verification procedure](https://github.com/Magnus-Gille/munin-memory/blob/main/docs/offsite-backup.md#verification-acceptance-criteria)
  to create and scratch-restore a fresh `munin.sqlite`; use its separate
  [disaster-recovery procedure](https://github.com/Magnus-Gille/munin-memory/blob/main/docs/offsite-backup.md#disaster-recovery-pi-is-gone)
  if the source host is gone. Both require `PRAGMA integrity_check`; the live database is replaced
  only while the server is stopped.
- **Mimir:** use the
  [encrypted backup and verification procedure](https://github.com/Magnus-Gille/mimir/blob/main/docs/offsite-backup.md#verification-acceptance-criteria)
  to run `cryptcheck` and a scratch restore/diff; use its separate
  [disaster-recovery procedure](https://github.com/Magnus-Gille/mimir/blob/main/docs/offsite-backup.md#disaster-recovery-pi-is-gone)
  if the source host is gone.
- **Verdandi:** there is **no routine export/disaster-recovery procedure**. The existing
  [offline recovery and new-genesis runbook](https://github.com/Magnus-Gille/verdandi/blob/main/docs/offline-recovery-and-new-genesis.md)
  is incident-specific forensic recovery, not a normal export path, and must not be represented as
  one.

## Emergency procedure

1. **Record the start.** Note the time, reason for activation, people involved, and any known host
   or account compromise. Keep these notes with the private incident record, not in this repo.
2. **Establish inventory from authority.** Use [`services.json`](../services.json) for hosts,
   components, deploy paths, and systemd units. Use [`authority.md`](authority.md) to resolve any
   conflicting documentation. Do not rely on a copied service list in the private envelope.
3. **Contain before investigating.** Stop Cloudflare/public ingress, then stop scheduled and
   autonomous execution. Unit names and user/system scope come from `services.json`; use the
   matching `systemctl --user stop ...` or `sudo systemctl stop ...` command. Do not disable
   Tailscale until the export is complete if it is the only safe administrative path.
4. **Preserve, do not repair.** Do not upgrade, redeploy, rotate databases, prune backups, or rewrite
   audit history. If compromise is suspected, isolate the affected host and use only its documented
   recovery path. Where none exists, stop and preserve the source instead of improvising a repair or
   export.
5. **Recover/export Munin and Mimir.** Use the two linked component-owned procedures above, including
   their verification steps. Include the relevant non-secret configuration manifests and
   `services.json`, but never copy credentials into this repo or the export manifest.
6. **Contain Verdandi without claiming an export.** Stop Verdandi and keep it stopped. Preserve the
   original storage as-is; do not start the service, create a new genesis, run repair tools, or copy
   a lone SQLite database without its related WAL/SHM and generation evidence. If storage loss or
   corruption is suspected, follow the incident-specific runbook's read-only preservation rules.
   Record this as a blocker, not as a successful Verdandi export.
7. **Anchor off-host.** Place the verified Munin/Mimir emergency export on the NAS. If the NAS is
   the failed or suspected component, use the alternate destination named in the private envelope.
8. **Verify before shutdown.** Record checksums and prove that each completed export can be listed
   and opened with its documented recovery path. A copy operation completing is not sufficient
   evidence. Verdandi remains explicitly blocked until its own routine procedure exists.
9. **Shut down.** Stop remaining Grimnir services, then shut down the Pi hosts, NAS services, and
   inference hosts cleanly. Leave public ingress disabled.
10. **Hand off the record.** Sara retains the incident notes, export location, checksums, and any
   outside-engineer access record. Restart or recovery requires a new decision; it is outside this
   delegation.

## Completion evidence

The emergency containment record is complete only when it shows:

- public ingress and autonomous execution stopped;
- Munin and Mimir export locations and verification results;
- Verdandi's stopped/preserved state and the unresolved routine-export blocker;
- the authoritative `services.json` revision used;
- the off-host destination and checksums;
- all temporary outside-engineer access removed or disabled; and
- each host's shutdown result.

That record may honestly show a blocked Verdandi export. It does not make the whole-substrate export
complete or operationally ready.

This checklist implements the owner decision for grimnir#65. It is intentionally smaller than a
general disaster-recovery or keep-running runbook. A successful Munin/Mimir export plus safe
Verdandi preservation is the best current emergency outcome; it is not evidence that the full
export-and-shutdown path has been drilled.

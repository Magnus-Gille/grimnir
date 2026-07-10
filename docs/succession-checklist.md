# Grimnir — Emergency Succession Checklist

> **Decision:** Sara is the emergency delegate. Her authority is limited to **export-and-shutdown**.
> This public checklist contains no credentials, recovery material, or private-envelope contents.

## Authority and trigger

Use this checklist only when Magnus is unavailable and the system must be preserved or made safe.
Sara may:

- obtain the private succession envelope through the out-of-repo location shared with her;
- ask an outside engineer for hands-on help, while retaining decision authority herself;
- stop public ingress, timers, autonomous execution, and services;
- make a recoverable export of the sovereign stores and the non-secret configuration needed to
  understand it; and
- power down the hosts after the export is verified.

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

The first two boxes are an owner-maintained, out-of-band prerequisite. If they have not been
confirmed, this checklist is not operationally complete.

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
   audit history. If compromise is suspected, isolate the affected host and export from the latest
   known-good source instead of trying to restore service.
5. **Export the sovereign stores.** Export Munin, Mimir, and Verdandi using their owning repos'
   documented backup/export procedures. Include the relevant non-secret configuration manifests
   and `services.json`, but never copy credentials into this repo or the export manifest.
6. **Anchor off-host.** Place the verified emergency export on the NAS. If the NAS is the failed or
   suspected component, use the alternate destination named in the private envelope.
7. **Verify before shutdown.** Record checksums and prove that each export can be listed and opened
   with its documented recovery path. A copy operation completing is not sufficient evidence.
8. **Shut down.** Stop remaining Grimnir services, then shut down the Pi hosts, NAS services, and
   inference hosts cleanly. Leave public ingress disabled.
9. **Hand off the record.** Sara retains the incident notes, export location, checksums, and any
   outside-engineer access record. Restart or recovery requires a new decision; it is outside this
   delegation.

## Completion evidence

The emergency action is complete only when the record shows:

- public ingress and autonomous execution stopped;
- Munin, Mimir, and Verdandi export locations and verification results;
- the authoritative `services.json` revision used;
- the off-host destination and checksums;
- all temporary outside-engineer access removed or disabled; and
- each host's shutdown result.

This checklist implements the owner decision for grimnir#65. It is intentionally smaller than a
general disaster-recovery or keep-running runbook.

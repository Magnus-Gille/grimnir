# Emergency export-and-shutdown checklist

This public checklist intentionally contains no people, credentials, hostnames, locations, recovery
keys, or private-envelope details. A real installation must maintain those facts out of repository.

## Preparation

- [ ] A named delegate has explicit, written export-and-shutdown authority.
- [ ] The delegate can obtain a private recovery package without this repository revealing where it
      is or how it is protected.
- [ ] Every authoritative store has a component-owned export, integrity-check, restore, and shutdown
      procedure.
- [ ] At least one verified copy can be placed in a separate failure domain.
- [ ] A dry walkthrough has confirmed the boundary: contain, export, verify, and shut down—not resume
      normal operation or improvise repairs.

If any store lacks a tested export path, record it as a blocker and preserve the source rather than
claiming readiness.

## Emergency procedure

1. **Record activation.** Keep time, reason, participants, and suspected compromise in a private
   incident record.
2. **Establish inventory.** Use the selected private registry and the authority map. Never substitute
   the committed public example.
3. **Contain.** Stop public ingress, schedulers, and autonomous execution before investigating.
4. **Preserve.** Do not upgrade, prune, rewrite audit history, or rotate databases. Isolate suspected
   hosts and use read-only preservation where possible.
5. **Export by owner procedure.** Stop writers as required; copy databases with their required
   companion files; include non-secret schema/configuration manifests.
6. **Verify.** Run integrity checks, record checksums, and perform a scratch restore or equivalent
   open/read test. A successful copy command is not verification.
7. **Move off-host.** Place verified encrypted exports in the preselected separate failure domain.
8. **Shut down.** Stop remaining services and hosts cleanly. Leave external ingress disabled.
9. **Remove temporary access.** Revoke any engineer or emergency credentials created for the event.
10. **Hand off the record.** Restart or recovery is a new decision outside export-and-shutdown
    authority.

## Completion evidence

- ingress and autonomous work stopped;
- each store identified as exported-and-verified or blocked-and-preserved;
- selected private-registry revision recorded without copying secrets;
- encrypted export destinations and checksums recorded privately;
- temporary access revoked;
- shutdown result recorded per host.

Review this checklist after every architecture or recovery-procedure change.

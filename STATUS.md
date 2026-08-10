# Grimnir System — Status

**Last session:** 2026-08-01 (Codex) — M5 security hardening is implemented through reviewed,
owner-gated rollout points
**Status base:** Grimnir `beb6282ca7d74d13517ef335172e6fd2dba8370a`

## Current phase

The W0–W5 software runway remains complete and ADR-008 mutation authority remains globally
disarmed. The 2026-08-01 security program hardened the public inference edge, service identities,
agent policy, substrate tests, and staged access controls. Completed deployments are verified;
remaining production or merge mutations are held behind exact owner approvals and attended safety
ceremonies.

No credential, private address, backup locator, or private account detail belongs in this handoff.

## Verified outcomes

### gille-inference

- Issue #150 is complete and deployed: the public inference edge uses HTTPS.
- Issue #151 is complete and deployed at
  `c45a0654f6768ad9a0d9fd7854166cc19efcd5cb`: gateway, tunnel, and inference workloads use
  dedicated service identities with isolation and live health/authentication checks.
- Issue #152's code merged in PR #170 as
  `a2c119dc0dde6f7aa44d60c9db25d2d71a399297`. Its deployment is superseded by current main
  `ff797087c4ab763883eae1f2e839a413b0497945`, which also contains the diagnostic hardening below;
  production deployment awaits exact owner approval.
- Issue #168 closed through PR #171, merged as
  `ff797087c4ab763883eae1f2e839a413b0497945`. Adoption-report failures now expose stable,
  content-free reasons and have regression coverage across the supported result space.
- The exact `ff797087c4ab763883eae1f2e839a413b0497945` deployment preflight passed source binding,
  67 focused tests, typechecks, diff validation, and the documented dry-run. Official verification
  confirmed that production still runs `c45a0654f6768ad9a0d9fd7854166cc19efcd5cb` and passed its
  source spot checks, then failed closed only because `DEPLOY_PUBLIC_HTTP_URL` and
  `DEPLOY_PUBLIC_HTTPS_URL` were unavailable. Their non-secret private locator values must be
  exported in the private operator environment and never pasted into chat or committed.
- Issue #166 has a reviewed branch at
  `75a2f85a7625b4be731ebaae25bc73039a29fce9`; PR publication was blocked by the execution
  platform, so it remains unmerged.
- Issue #169 was already fixed by PR #170. Tracker reconciliation was blocked; do not fabricate
  another implementation.

### Brokkr

- Issue #89's safe full-disk-encryption preparation merged through PR #93 as
  `bd23a1118b275d04dc534066ba9d9ff274374b19`. The destructive live migration is deliberately
  postponed to an attended post-travel window with verified backup and rollback ceremony.
- Issue #90 / PR #95 is refreshed on base
  `c53b79d7808c74b33c6a485010559566e396f929`, reviewed PASS, green, and mergeable at exact head
  `6cec78c3a0b616a061cfd150503a32b276e3fcd3`. Its security patch-id is unchanged and its body says
  `Part of #90`. Code merge does not close #90: the issue remains open until the owner-attended live
  apply, probes, and rollback evidence satisfy acceptance. No staged or live firewall, SSH, or
  Samba mutation has occurred.
- Issue #91 / PR #96 is reviewed PASS, green, and ready at exact head
  `f870f69a90640c2688a0edfc9220a638dbf514ec`. Merge requires owner approval. The issue remains
  open for owner-attended private binding, official policy validation, live apply, probes, and
  rollback; no live tailnet or firewall mutation has occurred.
- Issues #84 and #94 were fixed by PR #85; Brokkr main reached
  `c53b79d7808c74b33c6a485010559566e396f929`. Issue #92 was reconciled and closed after the
  current tests verified the underlying timestamp behavior.

### Agent policy

- claude-config #22, #24, and #26 completed through PR #23
  (`d61b37e9165da7b6f3386fc4326c8e3d66dd4195`), PR #25
  (`61b064ae7e14d3acbc54fcc71213488ac7237d9e`), and PR #27
  (`bae16253b15fc20ae941d130c8bc05d8adf02d99`).
- Portable policy, tainted-session boundaries, and instruction-audit gates are active. Current
  audits are healthy except the known archived LumiKin #61 wrapper drift.

## Owner approvals still required

Enter these exact phrases in the active Codex chat when ready:

1. `Approve merge Brokkr PR #95 at 6cec78c`
2. `Approve merge Brokkr PR #96 at f870f69`
3. `Approve M5 deploy gille-inference ff79708`

An attempted iMessage notification failed safely because Messages automation could not acquire a
window. No message was delivered, and no alternate personal contact locator was stored or used.

## Safety gates and blockers

- Deploy gille-inference only from exact accepted revision
  `ff797087c4ab763883eae1f2e839a413b0497945`, after the owner approval above. Re-run health,
  authentication, inference, and adoption-recorder probes after deployment.
- Brokkr PR #95 may be merged only at reviewed head
  `6cec78c3a0b616a061cfd150503a32b276e3fcd3` after its exact approval. Issue #90 remains open for
  the separate owner-attended live apply, probes, and rollback evidence.
- Brokkr PR #96 may be merged after its exact approval, but issue #91 stays open until the owner
  validates private device bindings and completes apply/probe/rollback from a physically safe
  two-session ceremony.
- Full-disk encryption remains an attended post-travel operation. Do not start it remotely or
  unattended.
- gille-inference #166 needs a normal PR publication path before merge review can complete. Issue
  #169 only needs tracker reconciliation against the already-merged fix.
- The broader L4 autonomy ceremony is still pending. No controller, mutation lane, or live canary
  is armed by this security program.

## M5 adoption evidence

- The macOS temporary-directory leaf used `qwen3-coder-next-80b` and was **partial**: useful input
  required frontier verification and correction before acceptance.
- The tailnet policy leaf used `mellum` and was **pass** after deterministic verification.
- Adoption-recorder rejection before the `ff797087` deployment is expected evidence of the old
  production behavior, not proof that the merged diagnostic fix failed.

## Exact next steps

1. Obtain the three current exact approvals above in Codex chat.
2. Merge Brokkr PRs #95 and #96 only at their reviewed heads and after green CI; do not combine
   merge approval with live application authority.
3. Deploy gille-inference `ff797087c4ab763883eae1f2e839a413b0497945` through its exact-source
   gate and run the post-deploy probes.
4. Reconcile gille-inference #166/#169 without duplicating completed work.
5. Schedule attended post-travel windows for Brokkr #89, #90, and #91 live ceremonies.
6. Keep W0–W5 mutation classes disarmed until their separate owner ceremony and real production
   evidence gates are satisfied.

## Verification standard

Every completed code path above was reviewed against an exact revision and exercised with focused
and repository-level checks in its owning repo. Merge state is not deployment evidence; staging is
not live application; code review is not owner authorization. Resume from the explicit gates above
rather than inferring authority from this status file.

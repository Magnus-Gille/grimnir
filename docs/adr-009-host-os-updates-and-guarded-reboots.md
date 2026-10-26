# ADR-009: Host OS updates and guarded reboots (owner policy outside the ADR-008 lane)

- **Status:** accepted on merge — owner decision recorded 2026-10-26
- **Date:** 2026-10-26
- **Decision owner:** Magnus (owner host policy); Grimnir system architecture records it
- **Implementing component:** Brokkr (apt policy, patching setup, guarded-reboot job)
- **Related:** [ADR-008](adr-008-autonomy-constitution.md) (unchanged),
  [failure-recovery.md](failure-recovery.md), [maintenance-policy-contract.md](maintenance-policy-contract.md)

## Context

Until now the hosts installed **security updates only** through unattended-upgrades. Brokkr's apt
policy deliberately excluded regular Debian and Raspberry Pi archive packages, including kernel and
firmware, and never rebooted automatically: "the operator schedules reboots when convenient".

That left real exposure in practice:

- The inference node ran a kernel 39 days old while patched kernels had been installed for 18 days;
  installed is not running, and the reboot never came.
- On Raspberry Pi hosts the kernel, firmware and `rpi-eeprom` come from the Raspberry Pi archive,
  which is not part of the Debian-Security origin, so kernel fixes there were never automatic.
- Network-exposed third-party daemons (Tailscale) and roughly 130 regular updates per host waited
  for a person.

ADR-008 governs agent and controller autonomy (Levels 4 and 5). It rejected "broad unattended
maintenance" inside that lane and lists firmware and reboots among the protected lanes a controller
may never mechanically promote. The Debian maintenance executor built for ADR-008 is disarmed and,
by construction, Debian-only, security/bugfix-only, and never reboots. Arming it cannot provide
regular updates, Pi firmware, or reboots.

The owner wants regular OS updates and Raspberry Pi firmware to apply automatically, with reboots
that wait for a safe moment.

## Decision

### 1. Scope: owner host policy, not an autonomy class

This ADR sets owner policy for the operating system's own deterministic update mechanisms
(unattended-upgrades and the stock `rpi-eeprom-update` boot service) plus one deterministic Brokkr
job that reboots when it is safe. No model or agent decides anything in this path, no controller is
armed, no ADR-008 coverage row changes, and ADR-008's constitution and protected lanes stay exactly
as they are. An agent may implement and deploy this policy as reviewed code, but may not widen it:
new origins, firmware mechanisms, hosts, or reboot conditions need the owner (a successor ADR or an
explicit owner change recorded here).

### 2. Package origins

Applied daily by the stock apt timers through unattended-upgrades, as Brokkr-managed drop-ins:

- **Debian / Raspberry Pi OS hosts:** Debian `stable`, `stable-updates` and `stable-security`; the
  Raspberry Pi Foundation archive (kernel, firmware, `rpi-eeprom`); the Claude Code repository
  (stable channel); Tailscale; GitHub CLI.
- **Ubuntu hosts:** the distribution defaults (release, `-security`, ESM) plus `-updates`; Tailscale;
  the Claude Code repository. Not `-backports` and not `-proposed`.

Phased updates are honoured. Packages that would prompt about a configuration file are skipped by
unattended-upgrades and show up in the maintenance report. Nothing is ever downgraded (package
downgrade stays a protected lane).

### 3. Firmware

- **Raspberry Pi bootloader EEPROM:** apt installs the updated `rpi-eeprom` package; the stock
  `rpi-eeprom-update` boot service applies it at the next guarded reboot (default release channel).
- **UEFI/BIOS and Secure Boot dbx (fwupd):** stays detect-and-report only. A boot-chain change can
  break TPM-bound unlock on a host that has, or will get, full-disk encryption.

### 4. Guarded reboot

One Brokkr job per host, running as the operator user; its only privileged actions are `sudo -n`
reads and `sudo -n systemctl reboot`.

- **Triggers:** `/var/run/reboot-required`, a running kernel older than the newest installed kernel
  *of the same flavour*, or a pending EEPROM update. needrestart's raw kernel status is not a
  trigger: it compares different Raspberry Pi kernel flavours and reports a false positive.
- **Window:** nightly, staggered per host, so a host and the host that monitors it are never down
  in the same window.
- **Guards (any of them defers the reboot to the next night):** a configured workload unit has
  spawned work (for example a running Hugin task); system load above a threshold; an interactive
  terminal used within the last 60 minutes; a host kill-switch file; a boot volume that would need
  interactive unlock; the same trigger surviving the previous guarded reboot (loop guard: alert and
  stop retrying that trigger). Idle interactive sessions may be terminated by a reboot.
- **Escalation:** after three deferred nights the job alerts.
- **Rollout:** report-only for the first week (it logs and alerts what it would do). Reboot mode is
  an explicit owner switch.
- **After boot:** a health check about ten minutes after boot verifies the kernel, that the reboot
  triggers cleared, that no unit failed, and that the services running before the reboot run again;
  any deviation alerts.

### 5. Audit and reversal

Under [failure-recovery.md](failure-recovery.md), every executed reboot is an autonomous mutation.
While Verdandi is stopped, its audit event is:

- an append-only local audit record on the host;
- a Telegram notice before the reboot and after the health check;
- projection into Munin `maintenance/os/<host>` by the daily `brokkr-maintenance-os` report.

The reversal recipe is `irreversible`. Mitigation: the post-boot health check and alert, the
kill switch, and the previous kernel kept installed for manual boot selection. Package upgrades by
unattended-upgrades are recorded in `/var/log/apt/history.log`; their reversal is also
`irreversible`, with a manual, owner-run downgrade as the only undo (no automation downgrades).

### 6. Turning it off

Creating the host kill-switch file stops reboots immediately. Removing the Brokkr origin drop-ins
returns unattended-upgrades to the previous security-only policy.

## Consequences

- Kernels, firmware and network daemons are patched without a person; the gap between "installed"
  and "running" shrinks from weeks to normally one night.
- Regular (non-security) updates now land unattended and can regress a service; the post-boot
  health check makes that visible the same morning instead of preventing it.
- Reboots cause short, windowed downtime of the control node's services and of inference.
- A failed EEPROM write needs physical access to recover (bootloader recovery image).
- A host whose guards never clear stays unpatched in memory; the three-night alert surfaces it.
- Before the inference node's root volume is encrypted without unattended unlock, this policy must
  be revisited; until then the unlock guard refuses to reboot such a volume.

## Alternatives considered

1. **Arm the ADR-008 maintenance lane.** Rejected: it cannot do this by construction, and its
   protected lanes are not to be loosened for host policy.
2. **unattended-upgrades `Automatic-Reboot`.** Rejected: no workload guard, no loop guard, no
   post-boot health check, and no audit trail.
3. **Keep updates and reboots manual.** Rejected by the owner: the 39-day kernel shows manual
   reboots do not happen in time.
4. **Kernel live patching.** Not chosen now; it would not cover firmware or the Raspberry Pi hosts.

## Non-goals

- No agent- or model-driven maintenance, no package downgrades, no firmware updates beyond the
  Raspberry Pi EEPROM, and no macOS workstation updates.
- No change to ADR-008, its constitution, coverage registry or protected lanes.

## Verification

- Each host's `unattended-upgrade --dry-run -d` lists exactly the origins in section 2.
- Brokkr's hermetic tests cover the guarded-reboot decision table (triggers, guards, loop guard,
  escalation, report mode, unlock guard, post-boot check).
- The first week's report-only log is reviewed before reboot mode is switched on.

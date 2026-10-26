# ADR-009: Host OS updates and guarded reboots (owner policy outside the ADR-008 lane)

- **Status:** accepted on merge — owner decision recorded 2026-10-26
- **Date:** 2026-10-26
- **Decision owner:** Magnus (owner host policy); Grimnir system architecture records it
- **Implementing component:** Brokkr (apt policy, patching setup, guarded-reboot job)
- **Approved hosts:** `huginmunin` (Debian/Raspberry Pi OS control node) and `m5` (Ubuntu
  inference node), by their `services.json` node IDs
- **Related:** [ADR-008](adr-008-autonomy-constitution.md) (unchanged),
  [failure-recovery.md](failure-recovery.md), [maintenance-policy-contract.md](maintenance-policy-contract.md),
  [authority.md](authority.md)

## Context

Until now the hosts installed **security updates only** through unattended-upgrades. Brokkr's apt
policy deliberately excluded regular Debian and Raspberry Pi archive packages, including kernel and
firmware, and never rebooted automatically: "the operator schedules reboots when convenient".

That left real exposure in practice:

- The inference node ran a kernel 39 days old while patched kernels had been installed for 18 days;
  installed is not running, and the reboot never came.
- On Raspberry Pi hosts the kernel, boot firmware and `rpi-eeprom` come from the Raspberry Pi
  archive, which is not part of the Debian-Security origin, so kernel fixes there were never
  automatic.
- Network-exposed third-party daemons (Tailscale) and roughly 130 regular updates per host waited
  for a person.

ADR-008 governs agent and controller autonomy (Levels 4 and 5). It rejected "broad unattended
maintenance" inside that lane and lists firmware and reboots among the protected lanes a controller
may never mechanically promote. The Debian maintenance executor built for ADR-008 is disarmed and,
by construction, Debian-only, security/bugfix-only, and never reboots. Arming it cannot provide
regular updates, Raspberry Pi firmware, or reboots.

`maintenance-policy` v1 is the authority for unattended-maintenance policy that an execution
controller consumes. Its closed enums cannot express feature or major-version upgrades, which the
Raspberry Pi archive ships for desktop packages (for example Chromium).

The owner wants regular OS updates and Raspberry Pi firmware to apply automatically on the approved
hosts, with reboots that wait for a safe moment.

## Decision

### 1. Scope and authority

This ADR sets **owner host policy** for the operating system's own deterministic update mechanisms
(unattended-upgrades and the stock `rpi-eeprom-update` boot service) plus one deterministic Brokkr
job that reboots when it is safe, on the approved hosts only.

- No model or agent decides anything in this path. This ADR arms no controller, no ADR-008 coverage row
  changes, and ADR-008's constitution and protected lanes stay exactly as they are. Nothing here is
  a precedent for promoting a protected lane inside ADR-008.
- It is a separate policy that `maintenance-policy` v1 does not express. It does not widen v1's
  enums, and v1 consumers must not relabel anything admitted here (such as a feature upgrade) as a
  v1 class. [authority.md](authority.md) records this policy's row.
- **This ADR grants no agent deployment authority.** Deploying or changing it on a host requires
  the existing exact-revision approval or a bounded release mandate. Agents and ADR-008 controllers
  may not add hosts, origins, firmware mechanisms or reboot conditions, switch a host to reboot mode,
  or clear a latched host (section 4); each of those is an owner decision recorded here or in a
  successor ADR.

### 2. Package origins

Applied daily by the stock apt timers through unattended-upgrades, as Brokkr-managed drop-ins. Every
distribution pattern is bound to the host's **release codename** (`${distro_codename}`), never to a
moving alias such as `stable`, so a release upgrade can never happen automatically.

- **`huginmunin` (Debian / Raspberry Pi OS):** Debian `origin=Debian` for the release codename and
  its `-updates` and `-security` pockets; the Raspberry Pi archive
  (`origin=Raspberry Pi Foundation`, release codename), which carries the kernel, boot firmware
  files and `rpi-eeprom`; the Claude Code repository (`origin=Anthropic`, `stable` channel);
  Tailscale (`origin=Tailscale`); GitHub CLI (`origin=gh`, `stable` channel).
- **`m5` (Ubuntu):** the distribution defaults (release, `-security`, ESM) plus `-updates`
  (`origin=Ubuntu`, `archive=<codename>-updates`); Tailscale; the Claude Code repository. Not
  `-backports` and not `-proposed`.

Phased updates are honoured. Packages that would prompt about a configuration file are skipped by
unattended-upgrades and show up in the maintenance report. Nothing is ever downgraded (package
downgrade stays a protected lane). Changing a channel, adding an origin or upgrading a release is an
owner decision.

### 3. Firmware

Two different things are called firmware here:

- **Package files** — Raspberry Pi boot firmware files on the boot partition (`raspi-firmware`) and
  driver firmware blobs (`linux-firmware`, `firmware-*`) — are ordinary package contents installed
  by apt like any other file. They take effect at the next boot.
- **Flashing non-volatile firmware.** The only flashing this policy allows is the **Raspberry Pi
  bootloader EEPROM on `huginmunin`**: apt installs the updated `rpi-eeprom` package and the stock
  `rpi-eeprom-update` boot service writes it at the next boot (default release channel). The owner
  accepts the power-interruption risk without a UPS; recovery is the bootloader recovery image,
  which needs physical access.
- **Everything else stays detect-and-report only**: UEFI/BIOS, Secure Boot dbx, fwupd devices and
  any other flashing mechanism, including when delivered through an otherwise allowed origin. On
  `m5` a boot-chain change can also break TPM-bound unlock once the root volume is encrypted.

A staged EEPROM update is applied by **any** boot, manual or guarded; the guarded-reboot kill switch
does not cancel it. Suspending firmware means holding the `rpi-eeprom` package and/or disabling the
`rpi-eeprom-update` service.

### 4. Guarded reboot

One Brokkr job per approved host, running as the operator user; its only privileged actions are
fixed `sudo -n` invocations (read-only status probes, appending the audit record, and
`systemctl reboot`).

- **Triggers**, each with a recorded identity: `/var/run/reboot-required` (identity: the set of
  packages that requested it); a running kernel older than the newest installed kernel *of the same
  flavour* (identity: that expected kernel version); a pending EEPROM update (identity: the
  available bootloader version). needrestart's raw kernel status is not a trigger: it compares
  different Raspberry Pi kernel flavours and reports a false positive.
- **Window:** nightly, staggered per host and at least two hours apart, so a host and the host that
  monitors it are never down together.
- **Guards.** Any one defers the reboot to the next night, and a missing, stale or ambiguous guard
  observation counts as a deferral, not as "clear":
  - a configured workload unit has spawned work (for example a running Hugin task);
  - a package transaction or its preparation is running (dpkg, apt, unattended-upgrades);
  - system load above a threshold;
  - an interactive terminal used within the last 60 minutes;
  - the host kill-switch file;
  - an encrypted volume needed at boot that would need interactive unlock;
  - the alert path cannot deliver the pre-reboot notice (alerts route through the control node, so
    this also holds a host while its alert path or peer is down);
  - the host is latched (below).
  All guards and the kill switch are checked again immediately before the reboot. Idle interactive
  sessions may be terminated by a reboot. The remaining race — work admitted in the seconds between
  the last check and the reboot — is accepted until a workload-owned drain hook exists.
- **Latch:** if any trigger identity is still pending after a guarded reboot, or the post-boot check
  reports issues, automatic reboots on that host stay off until the owner clears the latch. New
  triggers do not clear it, and escalation never overrides a guard.
- **Escalation:** after three deferred nights the job alerts (a kill switch is intentional and does
  not escalate).
- **Rollout:** report-only for the first week (it records and alerts what it would do). Reboot mode
  is an owner switch, deployed like any other change.
- **After boot:** a check about ten minutes after boot verifies the kernel, that the trigger
  identities cleared, that no unit failed, and that the services running before the reboot run
  again; any deviation alerts and latches.
- **Failure to come back:** a host that does not report its post-boot check is flagged by an
  independent observer — the off-box dead-man probe for the control node, and the daily maintenance
  report (which also alerts on a reboot record with no matching post-boot record) for the others.

### 5. Regressions without a reboot

Regular updates can regress a service without causing any reboot. A daily health check after the
stock unattended-upgrades window compares the running services with a baseline captured before the
update window and checks for failed units; a regression alerts.

### 6. Audit and reversal

Under [failure-recovery.md](failure-recovery.md), executed reboots, EEPROM applications and the
unattended package transactions are autonomous mutations. While Verdandi is stopped, this policy
uses the narrow exception recorded there:

- **Record:** a durable, append-only local mutation record on each host, carrying target, action,
  outcome and the reversal recipe. It covers each guarded reboot and its post-boot outcome
  (including whether an EEPROM update was applied), each health check that found a regression, and
  refers to `/var/log/apt/history.log` for the package transactions themselves. If the record
  cannot be written, the reboot does not happen.
- **Projections:** a Telegram notice before each reboot and after each post-boot check, and
  projection into Munin `maintenance/os/<host>` by the daily `brokkr-maintenance-os` report.
- **Reversal:** `irreversible` for reboots and EEPROM writes; mitigation is the post-boot check,
  the latch, the kill switch and the previous kernel kept installed for manual boot selection.
  Package upgrades are also `irreversible`; the only undo is a manual, owner-run downgrade (no
  automation downgrades).

### 7. Turning it off

- **Stop reboots now:** create the host's kill-switch file.
- **Stop firmware writes:** hold `rpi-eeprom` and/or disable the `rpi-eeprom-update` service; the
  kill switch alone does not cancel a staged EEPROM update.
- **Back to security-only updates:** remove the Brokkr origin drop-ins.

## Consequences

- Kernels, firmware and network daemons are patched without a person; the gap between "installed"
  and "running" shrinks from weeks to normally one night.
- Regular (non-security) updates now land unattended and can regress a service; the daily health
  check and the post-boot check make that visible the same day instead of preventing it.
- Reboots cause short, windowed downtime of the control node's services and of inference.
- A failed EEPROM write needs physical access to recover.
- A host whose guards never clear stays unpatched in memory; the three-night alert surfaces it.
- Before `m5`'s root volume is encrypted without unattended unlock, this policy must be revisited;
  until then the unlock guard refuses to reboot such a volume.

## Alternatives considered

1. **Arm the ADR-008 maintenance lane.** Rejected: it cannot do this by construction, and its
   protected lanes are not to be loosened for host policy.
2. **Express this as `maintenance-policy` v1.** Rejected: v1 deliberately cannot express feature
   upgrades or vendor channels, and widening it is a separate contract change.
3. **unattended-upgrades `Automatic-Reboot`.** Rejected: no workload guard, no latch, no post-boot
   health check and no audit record.
4. **Keep updates and reboots manual.** Rejected by the owner: the 39-day kernel shows manual
   reboots do not happen in time.
5. **Kernel live patching.** Not chosen now; it would not cover firmware or the Raspberry Pi host.

## Non-goals

- No agent- or model-driven maintenance and no package downgrades.
- No flashing of non-volatile firmware other than the Raspberry Pi bootloader EEPROM on
  `huginmunin`.
- No hosts beyond `huginmunin` and `m5`, and no macOS workstation updates.
- No change to ADR-008, its constitution, coverage registry or protected lanes, and no change to
  `maintenance-policy` v1.

## Verification

- Each host's `unattended-upgrade --dry-run -d` lists exactly the origins in section 2.
- Brokkr's hermetic tests cover the guarded-reboot decision table: triggers and identities, every
  guard, the latch, escalation, report mode, the unlock guard, the post-boot and daily health
  checks, and a blocked reboot when the audit record or the alert cannot be written.
- The first week's report-only record is reviewed before reboot mode is switched on.

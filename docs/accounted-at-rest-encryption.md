# Accounted data at rest: decision brief (GRIM-242)

Status: **decision brief, owner decision pending.** No host, storage or boot-chain change is
authorised by this document. It prepares the choice so the owner can answer in one line.

## Why this exists

The self-hosted Accounted evaluation instance on the M5 inference host holds an imported ledger
and documents, and, since the GRIM-240 live shadow pilot, real customer and invoice drafts in a
separate pilot company. The host's root disk has no at-rest encryption, and the instance's
database dumps and pilot queue copies sit on the same disk. On 2026-11-06 the owner explicitly
accepted that risk for the pilot only (at most 10 invoices, ending 2026-11-27). This brief keeps
that acceptance from becoming permanent by default.

## Threat model

| Threat | Addressed by at-rest encryption? |
|---|---|
| Theft or disposal of the disk or machine | Yes |
| Discarded or re-sold backup media | Yes, if backups are inside the encrypted scope |
| Compromise of the running host (disk is unlocked while it runs) | **No** |
| Malicious or mistaken agent action on the host | **No** |

Do not describe encryption at rest as protection against a compromised running host.

## Options

1. **Encrypt the whole disk.** Needs a reinstall or a risky in-place conversion with a verified full
   backup first. Everything on the host, including the inference gateway, is down during the work.
   A headless host also needs a boot-time unlock design (TPM auto-unlock, remote early-boot
   unlock, or a manual passphrase).
2. **Encrypt Accounted data only (recommended).** Move the Accounted database volume, storage
   volume and its backups into an encrypted container or encrypted directory. No reinstall, the
   inference gateway is untouched, and the downtime is limited to the Accounted instance
   (estimated about one hour). Unlock happens when the Accounted stack starts.

Recommendation: option 2. It closes the stated threat for the data that is actually sensitive at a
fraction of the blast radius. Revisit option 1 only if more sensitive material than Accounted data
lands on the host.

## Preconditions to check before choosing the unlock method

- Whether the host has a TPM 2.0 device usable for sealed auto-unlock. Absent a TPM, the realistic
  choices are a manual passphrase at Accounted start or a key fetched from a separate trusted host.
- Whether the Accounted stack must start unattended after a reboot. If yes, a manual passphrase is
  an availability cost the owner must accept.
- That every copy of Accounted data is inside the encrypted scope: live database, object storage,
  pilot queue copies, `pg_dump`-style backups, and any exported evidence directories.

## Execution outline (after the owner decides)

Any change to host storage or the boot chain is coordinated with Brokkr, which owns the platform
layer, and is a production mutation: it needs just-in-time confirmation of target, immutable
revision, action, verification and rollback under the global authority policy.

1. Take and verify a fresh backup, including a restore readback into a scratch location.
2. Stop the Accounted stack only.
3. Create the encrypted container or directory; record key custody (who holds the recovery key and
   where it is stored, never in git).
4. Migrate data and backups; keep the old plaintext copy until step 6 passes.
5. Start the stack and run the existing tenant-isolation fixture checks.
6. Verify a restore from the encrypted backups, then securely remove the plaintext originals.
7. Document the unlock procedure and the reboot behaviour.

Reversal recipe: stop the stack, restore the plaintext copy retained in step 4, start the stack.
This is only available until step 6 completes, so step 6 is a separate confirmation.

## Acceptance (from GRIM-242)

- The option is decided and recorded on GRIM-242.
- A restore from encrypted backups is verified and the evidence is recorded.
- The unlock procedure and key custody are documented in the private operations repository.
- The decision is re-checked before any use of Accounted beyond the evaluation and before the
  GRIM-240 pilot expands beyond its first stage.

## Decision needed from the owner

1. Option 1 or option 2 (recommended: 2).
2. Whether an unattended reboot must bring Accounted back up (decides the unlock method).
3. Timing relative to the pilot end date, 2026-11-27: before, or accept the existing risk
   acceptance until then and do it immediately after.

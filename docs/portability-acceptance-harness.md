# Portability acceptance harness v1

This is the evidence harness for Grimnir #104. It proves that a portability pilot has a complete,
public-safe acceptance record; it neither connects to a host nor authorizes a mutation.

The hermetic fixtures and validator are
[`tests/fixtures/portability-acceptance`](../tests/fixtures/portability-acceptance) and
[`tests/scripts/validate-portability-acceptance.mjs`](../tests/scripts/validate-portability-acceptance.mjs).
They consume the public authority boundary from [node/substrate contract v1](node-substrate-contract.md).

## Required record

Every scenario binds public-safe, immutable fixture references **and canonical SHA-256 record digests** for
Grimnir, Brokkr, and each participating service owner. Its plan names the target architecture, Wi-Fi requirement, transfer-window verdict, and a
reversal recipe. Fresh observations then attest architecture, Wi-Fi profile, mount and monitoring status.
An operator checkpoint, lifecycle result, and service-owned health/hook verification are mandatory.

Evidence claims are deliberately split into five independent kinds: `transport`, `configuration`, `health`,
`copy_integrity`, and `restore`. A claim can be `recorded` or `not_run`; it cannot be silently promoted to a
current/live success by the harness. Any stale evidence, architecture mismatch, missing Wi-Fi profile, poor
transfer window, absent mount, failed health/hook, monitoring outage, or interrupted apply fails closed.

## Pilot status

The NAS Pi + T7 record incorporates the 2026-07-22 failover/move material as a separately SHA-256-pinned
**historical evidence** record only. It is not a new live observation and does not claim this test executed
the move. The Hugin Pi-to-M5 record is
strictly a **dry run**: its lifecycle outcome is `not_started`, its production approval checkpoint is pending,
and all live evidence claims remain `not_run`. Production Hugin mutation requires separate owner approval.

The external repository paths are identity bindings for immutable shared fixtures. They do not claim that
Brokkr, Hugin, Mimir, Munin Memory, or Heimdall has adopted a consumer yet; each owning repository must add
the matching fixture and consumer before #104 can close.

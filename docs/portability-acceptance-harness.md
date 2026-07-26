# Portability acceptance harness v1

This is a **synthetic, public-safe conformance harness** for Grimnir #104. It proves the validation
rules, not that either portability pilot ran. It neither connects to a host nor authorizes a mutation.

The hermetic fixtures and validator are
[`tests/fixtures/portability-acceptance`](../tests/fixtures/portability-acceptance) and
[`tests/scripts/validate-portability-acceptance.mjs`](../tests/scripts/validate-portability-acceptance.mjs).
They consume the public authority boundary from [node/substrate contract v1](node-substrate-contract.md).

## Required record

Every scenario is explicitly marked `synthetic_public_safe` and uses reserved `example-*` identities.
It binds only the pre-existing Grimnir node/substrate positive fixture and its canonical SHA-256 record
digests. It does not invent cross-repository fixture adoption or historical operational artifacts. Its
plan names a target architecture, Wi-Fi requirement, transfer-window verdict, and reversal recipe.
Synthetic observations exercise architecture, Wi-Fi profile, mount and monitoring rules.
An operator checkpoint, lifecycle result, and service-owned health/hook verification are mandatory.

Evidence claims are deliberately split into five independent kinds: `transport`, `configuration`, `health`,
`copy_integrity`, and `restore`. In this fixture every claim is `not_run`. Operational evidence is explicitly
`absent` or `unverified`; while it is incomplete, lifecycle state must remain `not_started`, and all health,
hook, and claims must remain `not_run`. Any attempted promotion fails closed. The nine negative cases are
mutations of an otherwise-valid synthetic scenario and assert the named diagnostic for stale evidence,
architecture mismatch, missing Wi-Fi profile, poor transfer window, absent mount, failed health/hook,
monitoring outage, interrupted apply, and incomplete-evidence promotion.

## Pilot status

No pre-existing public authoritative NAS move artifact was discovered, so the NAS pilot is marked
`absent`, not retrospectively asserted or hash-pinned. The Hugin-to-M5 example is strictly a **dry run**:
it contains no fresh architecture, mount, or monitoring observation; its lifecycle outcome is `not_started`,
its production approval checkpoint is pending, and all evidence claims remain `not_run`. Production Hugin
mutation requires separate owner approval and owner-produced operational evidence.

Conformance validity and operational evidence completeness are separate: this harness can be green while
both pilots remain unverified. #104 remains open until each owning repository supplies its own authoritative
operational record and consumer validation.

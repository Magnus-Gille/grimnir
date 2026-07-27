# ADR-008 journal conformance v2

Every ADR-008 owning adapter—including W1 (gille-inference), W2 (Brokkr), and
W4 (Hugin)—exports one `autonomous-mutation-journal` envelope per attempted
mutation and validates it with Grimnir's
[`autonomous-mutation-journal-v2.schema.json`](autonomous-mutation-journal-v2.schema.json)
plus `make test-autonomy-contract-v2`. The only v2 phase vocabulary is `prepare`,
`apply`, `verify`, `watch`, `commit`, `unknown`, `revert`, `recover`,
`quarantine`, `disarm`, and `terminally-blocked`.

## Protected timing and the durable watch receipt

All phase timestamps come from protected watchdog time; a caller cannot supply
them. `prepare`, `apply`, candidate readback, `verify`, and the durable `watch`
append must complete within 300 seconds of the `prepare` receipt. The journal
append boundary authenticates the controller identity, writes and fsyncs (or
uses an equivalently durable store), reads the receipt back, and verifies its
binding and receipt-chain digest before returning success. That completed
append is the watch receipt; it follows the verified readback and starts the
post-mutation watch. A controller-generated timestamp or an unacknowledged
write is not a watch receipt.

V2 deliberately removes the prebound `binding.canary.watch_deadline`. The
earliest valid commit instant is derived mechanically as:

```text
watch receipt recorded_at + 3600 seconds
```

Commit is forbidden before that instant and after that instant plus 300
seconds. The immutable attempt deadline may be no later than 4200 seconds
after `prepare`, and every success-path mutation phase must occur by both that
bound deadline and the constitutional total limit. Recovery receipts may occur
later because uncertainty at the deadline must still be recoverable. All
comparisons are millisecond-precise. Equality at 300/3600/300/4200 seconds is
valid; one millisecond outside any bound fails closed.

The 900-second `max_silence_seconds` bound is enforced against a separately
authenticated, out-of-band watchdog heartbeat surface. A normal 3600-second
watch does not add synthetic journal phases. The heartbeat binds the attempt,
watchdog identity, and protected-clock observation, is outside controller write
access, and cannot reset or shorten the watch. Missing, stale, or unverifiable
heartbeat state makes the attempt unknown and enters recovery.

Before either implementation is admissible it must also call
`verify-autonomy-owner-authorization.mjs` with an independently pinned owner
public key, and verify the signed runtime-narrowing ledger. An owner signature
binds the exact constitution, coverage intent, owner-attestation registry, and
recovery-worker registry digests. A recovery receipt is valid only when its
Ed25519 key is bound by that signed recovery registry and it narrows its exact
target from an armed state to `shadow`; it cannot widen, re-arm, or address a
different target. Production remains disarmed until those artifacts are
provisioned by the owner.

The owner-authorization manifest, checkpoint, owner-attestation registry,
recovery-worker registry, and runtime-narrowing ledger retain their existing
`schema_version: v1` envelope formats while binding v2 constitution and
coverage digests. Their format version does not select the contract epoch; the
fixed canonical constitution and coverage schemas do.

The checked-in W0 fixtures provide both R-exact and R-forward examples for
consumer conformance. They are test vectors, not deployed authorization.

The `admission` values used by the reference predicate are **verifier-derived
proofs, never caller-supplied claims**: owner authorization comes from the
external-pin verifier; effective target state is owner intent minus verified
signed narrowing; and evidence, journal health, rate/window, silence, and
trusted watchdog time come from their authoritative stores and clocks. A
consumer must fail closed if it cannot independently derive any one of them.

The current owner-authorization digest/sequence checkpoint and the recovery
ledger tail checkpoint must live in an owner- or recovery-append-only store,
respectively, outside controller write access. Controllers may read them to
verify admission; they may not replace either checkpoint, registry, or ledger.
For a recovery demotion, append and durably verify the signed narrowing entry
first, then advance the protected tail checkpoint. A crash or disagreement
between those steps is fail-closed: retain shadow/disarmed behavior, repair by
replaying the signed append from the recovery store, and only then advance the
checkpoint. Never reconstruct a tail from controller-visible files.

## Epoch migration

V1 remains immutable historical evidence and keeps its original validator and
fixtures. V2 is a breaking successor: its constitution, coverage registry, and
journal all declare `schema_version: v2`, and the v2 coverage/journals bind the
v2 constitution digest. A consumer must pin the complete v2 bundle; mixing a
v1 schema, v1 coverage digest, or v1 journal with the v2 constitution fails
closed.

Do not migrate an attempt in place. An attempt prepared under v1 finishes or
recovers under its historical v1 digest. Only a new attempt may use v2.
Production v2 coverage remains globally disarmed and the checked-in owner
authorization remains unconfigured, so publishing this contract does not arm
any controller. After merge, downstream W1/W2/W4 adapters must repin and prove
v2 before any separate owner arming decision.

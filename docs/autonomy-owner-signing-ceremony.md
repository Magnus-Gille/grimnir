# Owner signing ceremony

This ceremony is owner-run. Codex, Claude, controllers, and deployed services
must never create, read, import, retain, or transmit the owner private key.
Fixture keys under `tests/` are test material only. Keep the real private key,
the independently pinned public key, and both protected checkpoints outside Git
and outside controller write access.

1. Export the owner Ed25519 **public** PEM to an explicit local path.
2. Prepare the complete unsigned manifest mechanically (no hand-hashed digests):

   ```sh
   scripts/prepare-autonomy-owner-authorization.mjs OWNER_PUBLIC.pem \
     docs/autonomy-constitution-v2.json COVERAGE-v2.json \
     docs/autonomy-owner-attestation-registry-v1.json RECOVERY_KEYS.json \
     SEQUENCE PREVIOUS_AUTHORIZATION_DIGEST > authorization.json
   ```

   The constitution and coverage paths above are the current W0.2 epoch and
   must be supplied as one v2 bundle. Before signing, validate the owner-supplied
   `COVERAGE-v2.json` against `autonomy-coverage-registry-v2.schema.json` and
   require its `constitution_digest` to equal the canonical digest in
   `autonomy-constitution-v2.json`. The checked-in
   `autonomy-coverage-registry-v2.json` is the deliberately disarmed reference,
   not future armed intent. `autonomy-constitution-v1.json` and
   `autonomy-coverage-registry-v1.json` are historical-only inputs for
   verifying or recovering an attempt that was already prepared under v1;
   never use them to authorize a new attempt.

3. Sign it locally, with the explicit owner-held private key:

   ```sh
   scripts/sign-autonomy-owner-authorization.sh /explicit/owner-private.pem authorization.json
   ```

   Insert the returned Base64 value into `authorization.json.signature.value_base64`.
4. Derive the canonical authorization checkpoint mechanically, before
   verification (the helper validates shape only; it does not claim signature
   validity):

   ```sh
   scripts/prepare-autonomy-owner-authorization-checkpoint.mjs authorization.json
   ```

   The owner decides whether to install that emitted checkpoint in the
   protected lane. Install the recovery-tail checkpoint in the recovery
   append-only store. Do not hand-hash JSON.
5. Supply the independent public-key pin and protected checkpoints to the
   verifiers. An absent, stale, malformed, or mismatched checkpoint is
   disarmed/fail-closed.

Key rotation is a new signed successor authorization and checkpoint update,
and also requires replacing the independently pinned public key. It is never a
controller-side edit.

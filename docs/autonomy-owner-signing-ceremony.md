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
     docs/autonomy-constitution-v1.json COVERAGE.json \
     docs/autonomy-owner-attestation-registry-v1.json RECOVERY_KEYS.json \
     SEQUENCE PREVIOUS_AUTHORIZATION_DIGEST > authorization.json
   ```

3. Sign it locally, with the explicit owner-held private key:

   ```sh
   scripts/sign-autonomy-owner-authorization.sh /explicit/owner-private.pem authorization.json
   ```

   Insert the returned Base64 value into `authorization.json.signature.value_base64`.
4. Derive the canonical authorization digest mechanically with the verifier's
   successful JSON result; install that digest plus the sequence in the
   owner-protected authorization checkpoint. Install the recovery-tail
   checkpoint in the recovery append-only store. Do not hand-hash JSON.
5. Supply the independent public-key pin and protected checkpoints to the
   verifiers. An absent, stale, malformed, or mismatched checkpoint is
   disarmed/fail-closed.

Key rotation is a new signed successor authorization and checkpoint update,
and also requires replacing the independently pinned public key. It is never a
controller-side edit.

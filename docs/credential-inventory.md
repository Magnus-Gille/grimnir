# Credential inventory and expiry (GRIM-249)

`credentials.example.json` is the public-safe example of a metadata-only registry; the real, dated registry stays private (grimnir-ops) and is selected with `--registry` or `CRED_REGISTRY`. It is a metadata-only registry of every credential in the estate: issuer, consumers,
expiry or last rotation, the runbook that rotates it, a verification step and a reversal. It holds no
values, fingerprints, hashes, hostnames or private paths; `scripts/cred-status.py` rejects unknown
fields and value-shaped strings. Dates marked `confidence: reported` come from owner notes and must
be verified against the issuer.

```bash
python3 scripts/cred-status.py --registry PATH         # table sorted by days remaining; exit 1 if expired/expiring/flagged
python3 scripts/cred-status.py --warn-days 45
python3 scripts/cred-status.py --validate-only
```

Rotation itself stays with the owning repository's tool (Munin `munin-admin`, Hugin
`rotate-m5-gateway-key.sh`, Heimdall `producer-token-ops.py`, `m5 provision`, Brokkr offline rotation).
This registry only points at them. Where a live source exists (Hugin `/health`
`homeserver_credential`) it wins over the registry date.

## Cutover orchestrator

`scripts/rotate-credential.py plan|execute --config CFG <id>` runs preflight, issue, install and verify
for one credential. The secret moves only over one OS pipe from the issuer's stdout to the installer's
stdin (for Munin: `munin-admin ... --token-stdout`, MUNIN-440, piped into a stdin-reading installer),
never argv, env, files, logs or tickets. The command lists live in a private config (hosts and paths
are not in this repo). `plan` (default) runs nothing; `execute` needs an interactive terminal and the
owner typing the credential id, so agents only ever run `plan`. Every run appends a secret-free audit
event (with the reversal recipe) to the config's `audit_log`. Exit 3 means the credential was issued but
the installer failed: reconcile state with the verify probe before issuing again, never retry blindly.

Still open: the stdin-reading installers for each consumer, and OAuth wrap-key rotation (MUNIN-440).

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

Not yet built (tracked in GRIM-249 / MUNIN-440): a plan/execute orchestrator for Munin principal
cutovers and a stdout-only token mode in `munin-admin`. Secrets must only ever move through a single
pipe, never argv, env, temp files or tickets.

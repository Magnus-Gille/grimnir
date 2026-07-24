# Desired-vs-observed placement validation

Grimnir #103 adds a small, read-only reconciliation view. It compares the desired
workload placement in `services.json` with an explicit Brokkr observation; it does
not inspect a host, fetch a health endpoint, or authorize a lifecycle action.

`nodes[].node_id` and `components[].workload_id` are stable public-safe IDs.
Hosted components also carry `target_node_id` and an exact reference to the
`workload-requirement` v1 contract: its owning-repository producer and immutable
SHA-256 digest. A Brokkr capability assessment must echo kind, version, producer,
and digest exactly. The registry therefore declares placement and pins the owner
contract it expects without copying Brokkr's capabilities or an owner's
requirements.

Run it with a captured input and a caller-supplied evaluation instant:

```sh
node scripts/validate-placement.js \
  --registry services.json \
  --observation brokkr-placement-observation.json \
  --now 2026-07-23T10:15:00Z
```

The input shape is documented by
[`placement-validation-v1.schema.json`](placement-validation-v1.schema.json). Its
top-level and each node capability evidence must name `brokkr`, bind their exact
observation timestamp, and carry a recomputable SHA-256 digest. Canonical
serialization recursively sorts object keys, preserves array order, and uses JSON
primitive serialization. The digest covers the complete record after removing
only that record's `evidence.digest`; a top-level digest therefore includes the
already sealed nested node records. The node capabilities are the existing
Node/Substrate v1 records.

Runtime loads both tracked schemas from `docs/`, checks their pinned v1 identities,
rejects JSON Schema keywords outside the dependency-free supported subset, resolves
the placement schema's node/substrate reference, and validates the observation
before semantic reconciliation. Unsupported schema versions or keywords,
malformed provenance, digest mismatch, missing references, or out-of-interval
records fail validation. Freshness expiry is reported as fail-closed drift at the
caller-supplied `--now`.

The JSON result has independent `declared`, `deployed`, `running`, and `healthy`
fields per workload. `declared` is registry intent; the other three are observation
values and never inferred from configuration. Drift items are deterministic and
natural-sort numeric identifier fragments numerically. Categories include
`missing-workload`, `incompatible-capability`, `extra-node`, `extra-workload`,
`extra-assessment`, `extra-live-unit`, `stale-evidence`, and `missing-evidence`,
plus separate deployment/running/health state mismatches.

The fixtures are synthetic and hermetic. They cover current desired placement on
`huginmunin`, `nas`, and `m5`, plus a proposed Hugin-to-M5 target. They neither
claim those fixtures are live state nor authorize that relocation. Brokkr remains
the only producer of observed node and workload facts; component owners remain the
authority for workload requirements.

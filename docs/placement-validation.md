# Desired-vs-observed placement validation

Grimnir #103 adds a small, read-only reconciliation view. It compares the desired
workload placement in `services.json` with an explicit Brokkr observation; it does
not inspect a host, fetch a health endpoint, or authorize a lifecycle action.

`nodes[].node_id` and `components[].workload_id` are stable public-safe IDs.
Hosted components also carry `target_node_id` and an exact reference to the
`workload-requirement` v1 contract. The registry therefore declares placement and
contract version without copying Brokkr's capabilities or an owner's requirements.

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
observation timestamp, and carry a SHA-256 digest. The node capabilities are the
existing Node/Substrate v1 records. A capability assessment additionally binds the
exact workload-requirement v1 digest that Brokkr evaluated. Unsupported schema
versions, malformed provenance, missing records, or expired input fail closed.

The JSON result has independent `declared`, `deployed`, `running`, and `healthy`
fields per workload. `declared` is registry intent; the other three are observation
values and never inferred from configuration. Drift items are deterministic and
natural-sort numeric identifier fragments numerically. Categories include
`missing-workload`, `incompatible-capability`, `extra-live-unit`,
`stale-evidence`, `missing-evidence`, plus separate deployment/running/health state
mismatches.

The fixtures are synthetic and hermetic. They cover current desired placement on
`huginmunin`, `nas`, and `m5`, plus a proposed Hugin-to-M5 target. They neither
claim those fixtures are live state nor authorize that relocation. Brokkr remains
the only producer of observed node and workload facts; component owners remain the
authority for workload requirements.

# Observability and improvement

Grimnir components should improve from measured outcomes rather than assumptions. The shared loop is:

```text
Execute → Trace → Evaluate → Reflect → Change → Verify
```

Reflection does not imply automatic mutation. Changes follow the normal ownership, testing, review,
and reversal rules.

## Trace contract

Every model call or consequential operation should emit a bounded trace.

Required fields:

| Field | Meaning |
|---|---|
| `trace_id` | unique correlation identifier |
| `component` | owning component from the selected registry |
| `tenant_id` | authenticated requesting principal |
| `task_type` | stable category used for aggregation and routing |
| `started_at`, `ended_at`, `duration_ms` | timing |
| `success` | whether the intended postcondition was met |
| `outcome` | bounded machine-readable result category |

Useful optional fields include runtime/model, prompt version, token counts, estimated cost, tool count,
parent trace, policy decision, retry count, and a short input/output summary.

Never store full prompts, retrieved files, secrets, credentials, or model output merely to make
debugging easier. Link to an authorized source record when detail is required.

OpenTelemetry GenAI semantic conventions are a useful vocabulary where they fit, without requiring a
particular telemetry backend.

## Evaluation tiers

### 1. Deterministic checks

Run on every applicable execution: schema validity, required sections, tool arguments, timeout,
postcondition, audit/reversal presence, and retry behavior. These checks are cheap and become ordinary
regression tests when they find a bug.

### 2. Model-assisted evaluation

Use a domain-specific pass/fail rubric with a written reason. Calibrate against a human-labeled sample
before trusting the judge, version the prompt, and monitor disagreement and drift. A judge should not
receive more sensitive content than its provider policy allows.

### 3. Human correction

An explicit human correction is the strongest signal, but it is also user data. Capture it only with a
defined purpose, retention period, and access policy. Preserve the corrected example, not only a score.

## Failure taxonomy

Use stable labels so failures can be compared across components:

- `wrong_tool`
- `bad_args`
- `unsupported_claim`
- `format_error`
- `incomplete`
- `off_topic`
- `timeout`
- `upstream_error`
- `policy_denied`
- `workspace_error`
- `context_stale`
- `identity_missing`

Components may add labels but should not rename shared ones without migration.

## Reflection

A periodic reflection job may aggregate recent failures, regressions, corrections, latency/cost shifts,
and routing outcomes. Its output should contain:

- repeated failure patterns;
- evidence and uncertainty;
- likely owning component;
- a small proposed change;
- a test and rollback plan.

Reflection is read-only by default. It files or proposes work; it does not silently rewrite prompts,
routing, or production configuration.

## Component signals

| Component | Starting signal |
|---|---|
| Munin Memory | retrieval relevance plus correction rate |
| Mimir | authorized retrieval success and bounded-root violations |
| Hugin | postcondition success by task type, policy denial, and workspace failure |
| gille-inference | quality/latency/cost by task type and model |
| Heimdall | alert precision, recovery detection, and collector reliability |
| Brokkr | patch/backup/restore evidence and mean time to detect host failure |

Optional integrations define their own user-value signal rather than optimizing message volume or
other easy proxies.

## Improvement rules

1. Instrument before optimizing.
2. Prefer deterministic checks before model judges.
3. Version prompts, policies, and routing configuration referenced by traces.
4. Turn diagnosed failures into regression cases in the owning repository.
5. Compare changes on a stable evaluation set before deployment.
6. Use rolling evidence with explicit decay; old model performance should not dominate forever.
7. Require normal review and reversal evidence for automatic changes.
8. Apply the data-lifecycle map to traces, evaluations, and corrections.

The storage backend is deployment-specific. Munin can hold low-volume durable summaries, while a
local telemetry store can buffer high-volume traces. Direct database coupling between components is
not part of the contract.

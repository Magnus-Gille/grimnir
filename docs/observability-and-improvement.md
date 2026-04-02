# Grimnir — Observability and the Self-Improving Loop

> Architectural guidance for building components that get better over time.
> Last updated: 2026-04-02.

---

## Purpose

This document defines how Grimnir components should capture execution data, evaluate their own output, and feed that signal back into improving future performance. It is guidance for implementation — individual services own their specifics, but the patterns, schemas, and interfaces described here are the common contract.

This is the engineering answer to the fourth founding principle: *"Every component should have a measurable signal it can optimize toward."*

---

## The Loop

Every Grimnir component participates in the same improvement cycle:

```
Execute → Trace → Score → Reflect → Improve
```

1. **Execute** — The component does its job (generates a briefing, runs a task, routes a message).
2. **Trace** — Structured execution data is captured: what happened, how long it took, what it cost, whether it succeeded.
3. **Score** — The output is evaluated against quality criteria, producing a numeric score and optional failure-mode label.
4. **Reflect** — Periodically, an LLM reads accumulated traces and scores to identify patterns and synthesize insights.
5. **Improve** — Prompts, examples, routing weights, or configuration are updated based on what the reflection found.

Steps 1-2 happen on every invocation. Step 3 can be immediate (heuristic checks) or batched (LLM-as-judge). Steps 4-5 happen on a cadence (weekly) or when failure thresholds are crossed.

The loop is not theoretical. Each step has a concrete implementation path described below.

---

## Trace Capture

### What to capture

Every component that calls an LLM or executes a non-trivial operation should emit a **trace record**. The trace is the atomic unit of the improvement loop — without it, nothing downstream works.

**Required fields:**

| Field | Type | Description |
|-------|------|-------------|
| `trace_id` | TEXT | Unique identifier (UUID v4) |
| `agent` | TEXT | Component name matching `services.json` (e.g., `skuld`, `hugin`, `ratatoskr`) |
| `task_type` | TEXT | What kind of work (e.g., `briefing`, `code-task`, `triage`, `health-check`) |
| `started_at` | INTEGER | Unix timestamp ms |
| `ended_at` | INTEGER | Unix timestamp ms |
| `duration_ms` | INTEGER | Wall-clock time |
| `success` | INTEGER | 1 = completed as intended, 0 = failed or degraded |

**Recommended fields (when applicable):**

| Field | Type | Description |
|-------|------|-------------|
| `model` | TEXT | Model that served the request (e.g., `claude-sonnet-4-6`, `qwen3.5:14b`) |
| `input_tokens` | INTEGER | Prompt tokens consumed |
| `output_tokens` | INTEGER | Completion tokens generated |
| `cost_usd` | REAL | Estimated cost (null for local models) |
| `finish_reason` | TEXT | `stop`, `tool_use`, `length`, `error` |
| `tool_calls` | INTEGER | Number of tool invocations in the trace |
| `parent_trace_id` | TEXT | For sub-tasks / pipeline phases |
| `input_summary` | TEXT | Short description of input (not the full prompt — avoid storing secrets) |
| `output_summary` | TEXT | Short description of output |

**Evaluation fields (attached post-hoc or inline):**

| Field | Type | Description |
|-------|------|-------------|
| `score` | REAL | 0.0-1.0, null if not yet evaluated |
| `score_source` | TEXT | `heuristic`, `llm_judge`, `human` |
| `failure_mode` | TEXT | Categorical label when `success=0` (see taxonomy below) |
| `human_correction` | TEXT | The corrected output, when a human fixed the result |

### Where to store traces

Traces are written to **Munin** using the `traces/<agent>` namespace. This keeps them accessible from all environments (Desktop, Web, Mobile) and queryable via existing Munin search.

For high-frequency components, a local JSONL file (`/var/log/grimnir/<agent>-traces.jsonl`) serves as the write-fast buffer. A daily job syncs notable entries to Munin.

The choice is per-component:
- **Low frequency** (Skuld: 1/day, Hugin: ~10/day): write directly to Munin.
- **High frequency** (Ratatoskr during active use, future parallel Hugin): JSONL buffer → daily sync.

### Schema alignment

Field names follow the [OpenTelemetry GenAI semantic conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/) where applicable. This is not about adopting the full OTel stack — it is about using field names that the ecosystem is converging on, so that future tooling (Langfuse, Phoenix, custom dashboards) can ingest the data without transformation.

---

## Scoring and Evaluation

A trace without a score is just a log. Scores are what turn execution data into improvement signal.

### Three scoring tiers

Components should implement scoring in this order — each tier adds capability, and the earlier tiers are prerequisites for the later ones.

**Tier 1: Heuristic checks (free, instant, no LLM needed)**

Deterministic validations that run inline after every execution:

- Did the output parse as valid JSON/markdown/expected format?
- Did all tool calls use valid tool names and argument schemas?
- Did the task complete within its timeout?
- For Skuld: does the briefing contain the required sections (calendar, projects, action items)?
- For Ratatoskr: did the intent classifier produce a known category?
- For Hugin: did the task produce a result entry in Munin?

Heuristic checks produce `score_source: "heuristic"`. They catch structural failures immediately. A component with only Tier 1 scoring is still vastly better than no scoring.

**Tier 2: LLM-as-judge (cheap via local models, batched)**

An LLM evaluates the output against domain-specific criteria. Key design decisions:

- **Binary pass/fail, not numeric scales.** A pass/fail judgment with a written critique is more actionable than a 3.7/5 score. The critique explains *why* it failed; the score just says it did.
- **Domain-specific judge prompts.** A generic "is this helpful?" judge is nearly useless. Each component needs its own judge prompt calibrated to what "good" means for that component.
- **Run locally.** Ollama on the Pi (Qwen 3.5 14B or similar) is sufficient for structured evaluation. The judge doesn't need to be smarter than the agent — it needs to check specific criteria.
- **Calibrate against human labels.** Before trusting an LLM judge, label ~50 traces manually (Magnus reviews, marks pass/fail with reason). Run the judge on the same set. Iterate the judge prompt until agreement exceeds 85%. This calibration dataset also becomes the first regression test suite.

Judge prompts live in the component's repo (e.g., `prompts/judge.md`) and are versioned alongside the code.

**Tier 3: Human feedback capture**

The highest-quality signal. Two sources:

- **Explicit correction via Ratatoskr.** When Magnus corrects an agent's output in Telegram, the original output + correction are logged as a labeled example. The Ratatoskr interface should make this natural — a reply to a bad result is a correction, not just a message.
- **Review during reflection.** During the weekly reflection step, flagged traces (low scores, uncertain judges) are surfaced for human review. Magnus labels them pass/fail with a note.

Human corrections are gold. Even 10-20 labeled corrections meaningfully improve prompt calibration.

### Failure mode taxonomy

When a trace is scored as failed, label the failure mode. A consistent taxonomy across components enables cross-cutting analysis.

| Failure mode | Description | Typical fix |
|---|---|---|
| `wrong_tool` | Called a tool that wasn't appropriate | Improve tool descriptions or routing logic |
| `bad_args` | Correct tool, malformed arguments | Tighten argument schemas or add examples |
| `hallucination` | Stated facts not supported by context | Add retrieval step or constrain generation |
| `format_error` | Output didn't match expected structure | Add format examples or schema validation |
| `incomplete` | Correct direction but missing required content | Expand prompt coverage or add checklist |
| `off_topic` | Addressed something the user didn't ask for | Clarify intent extraction or add guardrails |
| `timeout` | Ran out of time | Adjust timeout or decompose into subtasks |
| `upstream_error` | External service (API, model) returned an error | Retry logic, fallback, or escalation |
| `context_stale` | Used outdated information from memory/cache | Freshen retrieval or add recency checks |

Components may add their own labels. The taxonomy is a starting vocabulary, not a closed set.

---

## Reflection

Reflection is the step that turns a pile of scored traces into actionable knowledge. It is an LLM reading accumulated execution data and synthesizing patterns — the same thing a senior engineer does when reviewing a week of production logs, but automated.

### How it works

A scheduled job (systemd timer, weekly cadence) runs the following:

1. **Gather** — Read traces from the past week, filtered to `score < 0.7` or `success = 0`. Also read any human corrections from the period.
2. **Analyze** — Pass the traces to an LLM with a reflection prompt:
   - What failure modes appeared more than once?
   - What task types had the lowest scores?
   - Were there any regressions (task types that used to succeed but started failing)?
   - What patterns in the successful traces could be extracted as few-shot examples?
3. **Synthesize** — The LLM produces a structured reflection:
   - Top 3 failure patterns with root cause hypotheses
   - Suggested prompt/config changes
   - Candidate few-shot examples from high-scoring traces
4. **Store** — Write the reflection to Munin at `projects/grimnir/reflections/<date>` and tag it with the components involved.

### Reflection triggers

- **Time-based:** Weekly (default). Runs during the nightly maintenance window.
- **Threshold-based:** If the rolling 24h failure rate for any component exceeds 30%, trigger an immediate reflection for that component. (Heimdall can detect this from trace data.)

### What reflection is not

Reflection does not automatically change prompts or configuration. It produces *recommendations*. In Phase 2 (self-maintaining), some low-risk recommendations may be auto-applied (e.g., adjusting a timeout value). In Phase 1, a human reviews the reflection and decides what to act on.

---

## Improvement Mechanisms

When the loop identifies something to improve, these are the concrete mechanisms.

### Prompt versioning

Every agent prompt that goes through the improvement loop should be versioned:

- Prompts live in the component's repo under `prompts/` (e.g., `prompts/briefing-v3.md`).
- When a prompt is updated based on reflection findings, increment the version and note what changed in the commit message.
- Traces record which prompt version produced them (add a `prompt_version` field if the prompt is under active optimization).
- This enables direct measurement: "Did prompt v3 produce higher scores than v2 on the same task types?"

### Few-shot example curation

The most practical automated improvement: when a trace scores highly (score >= 0.9, source = human or calibrated judge), its input/output pair becomes a candidate few-shot example.

- Store curated examples in Munin at `prompts/<agent>/examples`.
- The agent's prompt template pulls from this set at runtime.
- Cap at 3-5 examples to avoid context bloat. Prefer diverse examples over many similar ones.
- Periodically prune: if a new example covers the same case as an old one, keep the better-scored one.

This is a lightweight version of DSPy's BootstrapFewShot — mining your own execution history for good demonstrations. It works without any framework.

### Failure case regression tests

Every failure that gets diagnosed and fixed should become a regression test:

- The input that caused the failure + the expected (corrected) output are stored as a test case.
- Before deploying a prompt change, run the current test suite against the new prompt.
- Test suites grow organically from production failures. They don't need to be comprehensive upfront.

Store regression test cases in the component's repo under `tests/eval/` or in Munin at `eval/<agent>/cases`.

### Routing table updates (Hugin v2)

For Hugin's multi-runtime routing, the improvement loop feeds the `qualityScores` table:

- After each task completion, the trace's score is attributed to the model that executed it, categorized by task type.
- The routing table (stored in Munin at `meta/routing-table`) maps `(task_type, model) → quality_score`.
- The router uses these scores when selecting a runtime: higher-scoring models for a given task type are preferred (weighted against cost).
- Scores are rolling averages with exponential decay — recent performance matters more than historical.

This creates a closed loop: model selection → execution → scoring → updated model selection.

---

## Per-Component Signals

Each component should optimize toward specific signals. These are the starting points — they will be refined through experience.

| Component | Primary signal | Secondary signals |
|---|---|---|
| **Skuld** | Briefing quality score (section completeness, source coverage, factual recency) | Token efficiency, generation latency |
| **Hugin** | Task completion rate by type | Duration vs timeout ratio, cost per successful task, retry rate |
| **Ratatoskr** | First-response resolution rate (user didn't need to re-ask) | Intent classification accuracy, routing correctness |
| **Heimdall** | Alert accuracy (true positive rate of health warnings) | Collection reliability, dashboard load time |
| **Munin** | Search relevance (target entry in top-3 results) | Query latency, embedding quality, memory staleness rate |
| **Mimir** | Retrieval success rate | Response latency, cache hit rate |

---

## Infrastructure Requirements

### What already exists

- **Heimdall** computes task success rate (`getTaskSuccessRate()`) and collects service health metrics on a 5-minute cadence. It is the natural home for aggregate dashboards over trace data.
- **Munin** provides searchable, cross-environment storage for trace records and reflections.
- **systemd timers** handle all scheduled jobs (collection, validation, briefings).

### What needs to be built

These are the common components. They can live in the grimnir repo (scripts/libraries) or as extensions to existing services.

1. **Trace writer library** — A small shared module that components import to emit traces in the standard schema. Handles Munin writes and optional JSONL buffering. Should be <100 LOC.

2. **Heuristic evaluator framework** — A pattern for defining per-component check functions that run after execution and attach scores to traces. Each component defines its own checks; the framework provides the runner and score-attachment logic.

3. **Reflection job** — A systemd timer + script that reads recent traces from Munin, runs the reflection prompt against a local or API model, and stores the output. Weekly cadence. One script, shared across all components.

4. **Heimdall trace dashboard** — A new card (or extension of existing cards) that shows trace-derived metrics: scores over time, failure mode distribution, cost trends. Reads from Munin trace entries.

### What is explicitly out of scope

- **No new services.** The trace infrastructure is a library + a timer + dashboard extensions, not a new component.
- **No external platforms.** Langfuse, Phoenix, and similar tools are acknowledged as potential future options if the home-grown approach hits limits, but they are not part of the initial design.
- **No automated prompt deployment.** The loop produces recommendations and candidate improvements. A human reviews and deploys. This constraint relaxes in Phase 2+.

---

## Implementation Sequence

This ordering ensures each step is independently useful and builds on the previous one.

| Step | What | Depends on | Delivers |
|------|------|------------|----------|
| 1 | Trace writer library (shared module, Munin + JSONL output) | Nothing | Standard trace emission for all components |
| 2 | Instrument Skuld (first adopter — 1 trace per day, easy to validate) | Step 1 | Real execution data flowing into Munin |
| 3 | Heuristic evaluators for Skuld (section checks, source count, date freshness) | Step 2 | Automated scoring on every briefing |
| 4 | Instrument Hugin task completions | Step 1 | Task-level traces with duration, model, success |
| 5 | Heimdall trace dashboard card | Steps 2-4 | Visible trends and failure rates |
| 6 | LLM judge for Skuld (calibrated against 50 human labels) | Step 3 | Automated quality scoring beyond heuristics |
| 7 | Reflection job (weekly, reads traces, writes insights) | Steps 2-4 | Pattern synthesis and improvement recommendations |
| 8 | Few-shot example curation pipeline | Steps 6-7 | Automated prompt improvement from production data |
| 9 | Hugin routing table fed by real quality scores | Steps 4, 6 | Data-driven model selection |
| 10 | Ratatoskr correction capture | Step 1 | Human feedback as labeled training data |

Steps 1-3 can be done in a single session. Steps 4-5 follow naturally. The rest unfolds over weeks as data accumulates.

---

## Principles

These are the design rules for the improvement loop. When in doubt, refer back here.

1. **Traces are the primitive.** Everything else — scores, reflections, prompt updates, routing — is derived from traces. If it isn't traced, it can't improve.

2. **Start with heuristics, graduate to judges.** A format check that runs on every invocation beats an LLM judge that never gets set up. Get Tier 1 scoring running before investing in Tier 2.

3. **Binary pass/fail over numeric scales.** Forces clarity about what "good" means. A 3.7/5 score is unactionable. "Failed: missing calendar section" is actionable.

4. **Calibrate judges against human labels.** An uncalibrated judge produces noise, not signal. Fifty human labels is the minimum viable calibration set.

5. **Store the correction, not just the score.** When a human fixes an agent's output, the correction is worth more than the failure label. It is a training example.

6. **Reflection is read-only by default.** The reflection job recommends; it does not deploy. Automated deployment of improvements is a Phase 2 capability that requires demonstrated reliability of the recommendation quality.

7. **No new services.** The improvement loop is a property of the system, not a new component. It is implemented as a library, some timer jobs, and dashboard extensions.

8. **Sovereignty applies to traces too.** Trace data stays on Magnus's hardware. It is never sent to third-party observability platforms. The same data-sovereignty principle that governs Munin governs the improvement loop.

---

*This document is a companion to [vision.md](vision.md) and [architecture.md](architecture.md). It operationalizes the "autonomous improvement by design" principle into concrete patterns that components implement.*

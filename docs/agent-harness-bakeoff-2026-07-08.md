# Agent Harness Bake-Off - 2026-07-08

> Evidence note for decoupling Grimnir/Hugin from Claude-shaped harnesses while keeping the
> Grimnir substrate contract: M5/OpenAI-compatible routing, file/shell/test loops, permission
> controls, parseable traces, and room for Munin/Verdandi attribution.

## Summary

The short answer: the gap is no longer primarily model capability. It is harness integration and
policy/audit plumbing.

Two open-source harnesses already completed a real edit-and-test loop through the M5
OpenAI-compatible gateway:

1. **Goose** is the best general worker candidate. It can use an OpenAI-compatible provider,
   run headless with the Developer extension, edit files, run shell commands, and stream JSON.
   It should be spiked first for non-Hugin "agent worker" tasks.
2. **OpenCode** is the closest fit for a Hugin coding-lane adapter. It has explicit build/plan
   agent modes, config-level provider support, configurable permissions, JSON output, and proved
   it can use M5 to run tests, inspect files, patch code, and rerun tests.

**Aider** is useful as a lightweight patch helper, not a full Grimnir agent harness. **OpenHands**
remains interesting for a heavier isolated runtime/SDK path, but it did not reach usable headless
events in this spike window.

The immediate architectural move should be an adapter seam in Hugin, not a new in-house harness:

```
Hugin task -> gate/provenance -> HarnessAdapter -> open harness process -> normalized events
          -> test/result summary -> Munin trace + Verdandi audit event
```

## Test Method

A disposable fixture repo was created at `/tmp/grimnir-harness-bakeoff.ToJKJQ`:

- `math.js` intentionally returned `a - b` from `add(a, b)`.
- `test.js` expected `add(2, 3) === 5`.
- Baseline `npm test` failed with `-1 !== 5`.
- A successful harness needed to make the smallest patch and prove `npm test` passed.

M5 was reached through `http://100.76.72.59:8080/v1` with a token from `m5-auth`. The available
M5 models at test time were `gemma4`, `gpt-oss-120b`, `mellum`, `qwen3-30b-instruct`,
`qwen3-coder-next-80b`, `qwen36-a3b`, and `whisper-1`.

Evidence logs were written under `/tmp/grimnir-harness-bakeoff-results/`.

## Results

| Harness | M5/OpenAI-compatible | File edit | Shell/test loop | Policy/log notes | Verdict |
|---|---:|---:|---:|---|---|
| Goose | Yes | Yes | Yes | Stream JSON is verbose; one odd `read_image` attempt on JSON recovered cleanly | Best general worker candidate |
| OpenCode | Yes | Yes | Yes | Good JSON events and diff metadata; read-only plan run obeyed deny rules but stalled | Best Hugin coding-lane candidate |
| Aider | Yes | Yes | Partial | Applied patch; external test passed; no clear autonomous test execution in this run | Lightweight patch helper |
| OpenHands | Plausible | Not proven | Not proven | CLI detected, but headless JSON run emitted no events for about 90 seconds | Later deeper spike |

### Goose

Goose was installed into a temporary bin dir and configured with:

- `GOOSE_PROVIDER=openai`
- `GOOSE_MODEL=qwen3-coder-next-80b`
- `OPENAI_HOST=http://100.76.72.59:8080`
- `OPENAI_API_KEY=$(m5-auth)`
- `goose run --no-session --no-profile --with-builtin developer --output-format stream-json`

Observed behavior:

- M5 smoke test returned the expected text.
- The Developer extension listed/read files, ran `npm test`, edited `math.js`, reran `npm test`,
  and reported success.
- Final diff was exactly the intended one-line change: `a - b` -> `a + b`.

Risks:

- The stream is very verbose and token-oriented; Hugin would need a normalizer.
- The agent attempted `read_image` on `package.json` before recovering. This is not fatal, but
  it argues for explicit tool allowlists and trace review before production use.
- Auto mode must sit behind Hugin's existing gating. Goose should not receive ambient credentials.

Sources: [Goose provider docs](https://goose-docs.ai/docs/getting-started/providers/).

### OpenCode

OpenCode was already installed locally. A temporary config directory defined an M5 provider with
`@ai-sdk/openai-compatible`, `baseURL: "http://100.76.72.59:8080/v1"`, and env-based API key
loading.

Observed behavior:

- M5 smoke test returned the expected text.
- A read-only config with `edit: "deny"` and `bash: "deny"` made no edits and no shell calls,
  though the plan-agent task stalled on a tiny read-only question.
- Build mode with `qwen3-coder-next-80b` ran `npm test`, inspected files, edited `math.js`,
  reran `npm test`, and returned `ok`.
- Final diff was exactly the intended one-line change.

Risks:

- The plan-agent stall means "read-only analysis worker" needs more cases before trust.
- OpenCode config/permission behavior should be pinned by a regression fixture before Hugin uses
  it for real work.

Sources: [OpenCode providers](https://opencode.ai/docs/providers/),
[agents](https://opencode.ai/docs/agents/), [permissions](https://opencode.ai/docs/permissions/),
and [models](https://opencode.ai/docs/models/).

### Aider

Aider was already installed locally. It needed `OPENAI_API_KEY` plus `--openai-api-base
http://100.76.72.59:8080/v1`; passing the key only via `--openai-api-key` failed under LiteLLM.

Observed behavior:

- Applied the intended one-line patch.
- External `npm test` passed after the run.
- Aider created `.aider*` side effects unless explicitly suppressed.

Risks:

- Better for "apply this patch" than for a full autonomous Grimnir worker.
- Needs strict flags such as `--no-auto-commits`, `--no-gitignore`, and explicit file lists.

Sources: [Aider OpenAI-compatible API docs](https://aider.chat/docs/llms/openai-compat.html).

### OpenHands

OpenHands CLI was reachable via `uvx --from openhands openhands`, and the CLI exposes
`--headless`, `--json`, `--task`, and `--override-with-envs`.

Observed behavior:

- The CLI help path worked and documented `LLM_API_KEY`, `LLM_MODEL`, and `LLM_BASE_URL`.
- A headless JSON run against M5 emitted only SDK import noise for about 90 seconds and was stopped.
- Isolating `HOME` broke `m5-auth` keychain access, so future OpenHands tests need either normal
  user context or a non-keychain token handoff.

Risks:

- Headless mode is always auto-approve, which is a poor first fit for direct Hugin integration.
- The cold-start/runtime surface is heavier than Goose/OpenCode.

Sources: [OpenHands command reference](https://docs.openhands.dev/openhands/usage/cli/command-reference)
and [headless mode docs](https://docs.openhands.dev/openhands/usage/cli/headless).

## Architectural Implications

The harness should be treated as a replaceable tenant, not as Grimnir's trust boundary.

What must be true to decouple from Claude:

- **Model routing:** every harness must be configurable to use M5/OpenAI-compatible, OpenRouter,
  OpenAI, Anthropic, or another provider without rewriting task logic.
- **Tool contract:** shell, file edit, file read, web, and MCP access must be declared and
  constrained per task class.
- **Normalized events:** Hugin should ingest harness events into a common schema: `started`,
  `tool_call`, `tool_result`, `file_diff`, `test_result`, `blocked`, `completed`, `failed`.
- **Gating stays outside the harness:** prompt-injection scanning, egress policy, provenance,
  sensitivity classification, and credentials remain Hugin/Grimnir responsibilities.
- **Audit emission:** consequential actions need Verdandi events under the tenant/harness identity.
- **Reversal recipe:** any autonomous mutation still needs the `failure-recovery.md` undo convention.

This means the main missing piece is a **Hugin HarnessAdapter**, not more Claude-specific prompt
work.

## Recommendation

Implement a narrow Hugin harness adapter spike in this order:

1. **OpenCode adapter for coding tasks**: easiest to constrain and already proved edit/test with
   M5. Start with a disposable repo fixture, JSON events, no credentials, no external directories.
2. **Goose adapter for general worker tasks**: broader tool surface, likely better outside pure code,
   but needs event normalization and tool allowlist hardening.
3. **Aider helper path**: keep available for bounded patch generation when Hugin already knows the
   files and tests.
4. **OpenHands later**: revisit only when isolated runtime needs outweigh cold-start and
   auto-approve risk.

Acceptance for the first adapter should be:

- Runs the bake-off fixture through M5 and produces the one-line fix.
- Emits normalized events into a local JSONL trace.
- Produces a machine-readable diff summary and test result.
- Respects a read-only mode that can read but cannot edit or run shell.
- Leaves no global config or repo side effects.
- Can be wrapped by Hugin's existing gate before receiving real tasks.

## M5 Second Pass

M5 (`qwen3-30b-instruct`) reviewed the evidence and independently ranked Goose first, OpenCode
second, Aider third, and OpenHands fourth. I agree with the Goose ranking for general agent work,
but for Hugin's immediate coding-lane replacement the practical first adapter should be OpenCode
because its build/plan modes and permission config align more directly with Hugin task classes.

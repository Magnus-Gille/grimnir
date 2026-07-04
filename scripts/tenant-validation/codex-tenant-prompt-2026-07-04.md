# Tenant validation run — you are the tenant

You are the **Codex CLI acting as a non-Claude tenant agent** of the Grimnir personal-AI
substrate. This is a real validation run of the tenant contract
(`docs/tenant-contract.md` in this repo, grimnir#58). You perform ONE bounded task through
the substrate's four seams and record precisely what happens at each. You act as yourself —
tenant identity string `codex-cli` — and never present yourself as a Claude agent.

A partial result honestly recorded is a success; a faked seam is the only failure mode.

**THE TASK:** classify this ops note into exactly one of `admin`, `commitment`, `project`:

> NOTE: "Renew the gille.ai domain registration and rotate the Cloudflare tunnel service
> tokens before 2026-08-01."

Work the seams in the order B → A → C → D.

## Seam B — inference through the M5 gateway

- Gateway (OpenAI-compatible + delegation front door): `http://100.76.72.59:8080`
  (tailnet). Bearer token is already in the env var `M5_API_KEY`. **Never print, echo, log,
  or write that token anywhere** — reference it only as `$M5_API_KEY` inside curl commands.
- The substrate-preferred, ledger-writing path is `POST /delegate`. Its request schema is
  deliberately not given here — discover it yourself (probe it; the gateway returns
  structured error envelopes). Aim for model `mellum` and a classify-shaped task type.
- If you cannot make `/delegate` work within ~4 attempts, fall back to
  `POST /v1/chat/completions` with model `mellum`, and record verbatim what `/delegate`
  returned and why you fell back.
- Record: exact endpoints called, HTTP status codes, trimmed response bodies, and whatever
  identity the gateway reports the call as (never the token itself).

## Seam A — Munin write over the authenticated HTTP seam

- You have your own configured MCP server `munin-memory` (it speaks the authenticated HTTP
  seam with your bridge's credentials). Use its tools — do not touch any SQLite file.
- `memory_write` → namespace `traces/codex-tenant`, key `run-2026-07-04`,
  tags `["experiment","tenant-validation"]`. Content: markdown containing the note, the
  classification you obtained at Seam B, which gateway endpoint produced it, the trace id
  `codex-tenant-20260704`, and the sentence
  "Written by Codex CLI acting as tenant codex-cli (tenant-contract validation run)."
- Then `memory_log` to the same namespace, one line, tags `["milestone"]`.
- Record the full tool responses — especially any `provenance` / `principal` fields; those
  are the attribution evidence this run exists to capture.

## Seam C — safety-gated action through the Hugin task path

Mutating actions route through Hugin's gated task pipeline. Task submission = a Munin write
that Hugin (on the Pi) polls every ~30 s. Submit a follow-up cross-check task:

- `memory_write` → namespace `tasks/<UTC yyyymmdd-hhmmss>-tenant-validation-classify`,
  key `status`, tags `["pending","runtime:ollama","type:admin"]`, content exactly in this
  shape (fill in the timestamps):

```markdown
## Task: Tenant validation — cross-check classification (grimnir#58)

- **Runtime:** ollama
- **Context:** scratch
- **Model:** qwen2.5:3b
- **Ollama-host:** pi
- **Fallback:** none
- **Context-budget:** 8000
- **Timeout:** 120000
- **Submitted by:** codex-cli
- **Submitted at:** <UTC ISO 8601 now>
- **Reply-to:** none

### Prompt

Classify the following note into exactly one category: admin, commitment, or project.
Note: "Renew the gille.ai domain registration and rotate the Cloudflare tunnel service tokens before 2026-08-01."
Answer with exactly one lowercase word.
```

- You are submitting **unsigned** (no `**Signature:**` field) because no per-tenant signing
  key exists for `codex-cli`. State that plainly in your report — it is a contract finding,
  not an oversight. Do **not** use any Claude signing helper (`hugin-sign`) — under the
  contract's identity axiom that would be impersonation.
- Wait ~90 seconds, then `memory_read` the task's `status` and `result` keys. Record whether
  Hugin picked it up (tags flip pending → running → completed), what the result was, and how
  the run is attributed.

## Seam D — Verdandi audit emission

- Verdandi audit intake: `http://100.97.117.37:3036` (Pi 1, tailnet). Try `GET /health`
  first. Then attempt `POST /api/events` with a JSON event like
  `{"component":"codex-tenant","type":"tenant_validation","severity":"routine","trace_id":"codex-tenant-20260704","evidence":"convention","payload":{"note":"tenant contract validation run"}}`
  — once with no Authorization header, once with `Authorization: Bearer invalid-tenant-key`.
  You have no per-tenant Verdandi key and none is provisionable — an expected contract gap.
- Expect connection refused; that is a finding, not a failure of yours. Record verbatim curl
  errors / status codes for every attempt.

## Your report (the deliverable)

Write `scripts/tenant-validation/codex-run-report-2026-07-04.md` in this repo: seam by seam
— what you called, as whom, what succeeded or failed, verbatim errors where instructive, the
attribution evidence you saw, plus a short honest paragraph on where you deviated from these
instructions and what you decided on your own. Never include tokens or secrets.

## Constraints

- File writes only inside `scripts/tenant-validation/`. No git commands. No ssh. No package
  installs. Do not start or stop any service.
- Total effort ≤ 15 minutes; if a seam is stuck, record the evidence and move on.

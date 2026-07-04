# The Tenant Contract

> **Spec, 2026-07-04.** The minimal contract any agent must satisfy to act *through* the
> Grimnir substrate. Answers grimnir#45. Companion to `vision.md` (the *why*) and
> `architecture.md` (the *how*). This is the **agent↔substrate** contract; it is distinct
> from the **service↔service** cross-service contracts scoped in `ecosystem-review-plan.md`
> (Step 0) — a tenant *speaks* those contracts at the seams below, it does not replace them.
>
> **This is spec-only. No code ships from this document** — mirroring the ecosystem-review
> Step-0 pattern. Proving the contract with a real non-Claude agent is tracked as validation
> work (§5), not delivered here.

---

## 1. Why this exists

The vision's thesis sentence — *"a sovereign, self-knowing personal-AI substrate that **any
agent** can safely act through"* — currently has no end-to-end supporting evidence. The acting
integrations are Claude-coupled, and no second agent brand has ever been driven through the
substrate's seams:

- `ratatoskr/src/concierge.ts` (~108) and `skuld/src/synthesizer.ts` (~12) instantiate the
  Anthropic SDK directly for their LLM calls — a hardcoded, single-vendor inference path.
- Hugin's agent loop defaults to the **Claude Agent SDK** (`@anthropic-ai/claude-agent-sdk`,
  `sdk-executor.ts`). It *does* already carry a `runtime-registry.ts` / `router.ts` selecting
  between the Agent SDK, Ollama, OpenRouter, and the M5 home-server (`architecture.md`,
  "Multi-runtime") — but that is *intra-Hugin runtime selection*, not a proven tenant seam: no
  non-Claude agent has been driven end-to-end through all four seams below.

Because no second agent brand has ever acted through the substrate, "the agent is a replaceable
tenant" (vision §The thesis) is an assertion, not a demonstrated property. This document turns
the assertion into a checkable contract: **what an agent must do at each substrate seam to be a
conforming tenant**, regardless of which model or harness it is built on.

The substrate is the identity; the agent — loop, channels, model — is the replaceable tenant.
The contract is the seam between them.

---

## 2. The spine: per-tenant identity

The single element the current system most lacks is **per-tenant identity**. Today the seams
are guarded by *shared static tokens*, so — as the 2026-07-03 gap analysis put it (§1.5) — "the
substrate cannot attribute *which* tenant did what." Attribution, quota, safety provenance, and
audit all collapse to a single undifferentiated actor.

> **Contract axiom.** Every tenant presents a **distinct identity credential** at all four
> seams. One tenant ⇒ one key per seam (or one federated identity resolvable to per-seam keys).
> A tenant that borrows another tenant's key is not conforming — it is impersonation, and it
> defeats the substrate's ability to route, meter, gate, and audit per actor.

Everything below is a consequence of this axiom applied to a specific seam.

---

## 3. The four seams

The substrate exposes exactly four seams an acting agent touches. The contract defines, per
seam: what the substrate provides, what the tenant **MUST** / **MUST NOT** do, which parts are
already model-agnostic vs. currently Claude-coupled, and how conformance is checked.

### Seam A — Munin access *(Memory pillar)*

**Substrate provides:** an authenticated MCP/HTTP surface (JSON-RPC 2.0) over the Munin memory
store — `memory_read` / `memory_write` (compare-and-swap) / `memory_read_batch` /
`memory_query` / `memory_log` / `memory_delete` (two-step) — with server-side secret-scan
before persist, and namespace conventions (`projects/*`, `traces/<agent>`, `tasks/*`,
`decisions/*`, …). The **Munin HTTP client contract** (bearer auth, retry/backoff on 429/5xx,
`classification` field rules) is **owned by munin-memory** (it owns the protocol it serves);
`hugin/src/munin-client.ts` is the current best reference implementation to cite, not the owner.

**Tenant MUST:**
- Authenticate with **its own per-tenant bearer token**, behind the edge service token, so
  writes carry the tenant's identity.
- Reach Munin **only through the HTTP/MCP seam** — never open the SQLite file directly. (The
  skuld direct-SQLite read, gap §1.5 / skuld#3, is the anti-pattern this rule forbids.)
- Speak the Munin HTTP client contract: JSON-RPC 2.0, retry/backoff on 429/5xx, compare-and-swap
  on concurrent writes, honor the `classification` field.
- Write only into namespaces it owns or is permitted to (its own `traces/<tenant>`, its task
  results, not another component's private namespace).

**Tenant MUST NOT:** bypass secret-scanning by writing through any non-Munin path; assume its
writes are trusted server-side (Munin re-scans and may reject).

**Model-agnostic already:** the seam is HTTP + JSON-RPC — no Claude assumption. Any runtime that
can make an authenticated HTTP call conforms. **Claude-coupled today:** only that the *sole*
non-laptop writer paths were built for Claude-brand agents; the transport itself is neutral.

**Conformance check:** the tenant reads its inputs and writes its outputs against a live Munin
instance using its own key; the write appears attributed to the tenant; a secret in the payload
is redacted/rejected server-side.

### Seam B — Gateway routing *(Inference pillar)*

**Substrate provides:** the M5 home-server gateway (`:8080`, tailnet + Cloudflare) — an
OpenAI-compatible front door (`POST /v1/chat/completions`), a bounded delegation path
(`POST /delegate`, owner tier), per-key auth, sliding-window quota, owner-preempts-guest GPU
admission, and the **capability ledger** (`GET /ledger`) that accrues per-`(task_type, model)`
verdicts so the substrate *learns what cheaper compute can be trusted with*.

**Tenant MUST:**
- Treat model/runtime selection as **indirectable through the gateway**, not as a hardcoded
  cloud SDK. A conforming tenant's inference path can be pointed at the gateway (or at a model
  the gateway serves) without rewriting the tenant.
- Route inference the substrate should *learn from* through the gateway. Plain inference uses
  `POST /v1/chat/completions`; the **ledger-writing path is `POST /delegate`** — per
  `architecture.md`, nightly local sub-tasks route through `/delegate` "so the ledger keeps
  learning what local models can be trusted with." A tenant that wants its outcome recorded as a
  routing verdict must use `/delegate`. (Hardcoded direct-to-cloud calls generate zero routing
  data — gap §1.2(c) — and starve Pillar 2.)
- Authenticate with its own per-tenant gateway key; respect quota and the owner-preempts-guest
  admission rule.

**Tenant MUST NOT:** hold a single-vendor SDK as the *only* possible inference path; consume
guest-tier admission while claiming owner priority.

**Model-agnostic already:** the gateway is OpenAI-shaped and vendor-neutral by construction — a
*non-Claude* model (a local M5 model, another cloud vendor) is a first-class citizen here. This
seam is where "any agent" is most naturally true. **Claude-coupled today:** ratatoskr and skuld
bypass the gateway entirely with direct `new Anthropic(...)` calls; Hugin's loop assumes the
Claude Agent SDK runtime rather than a pluggable provider.

**Conformance check:** the tenant completes an inference call through the gateway; a `/delegate`
call produces a ledger entry for its `(task_type, model)`; the call is attributed to the tenant's
gateway key.

### Seam C — Safety gating *(Memory pillar — "own")*

**Substrate provides:** Hugin's gating layer, through which every task touching real credentials
or the tailnet must pass — `prompt-injection-scanner.ts`, `exfiltration-scanner.ts`,
`egress-policy.ts`, a `privacy-filter/`, content `sensitivity.ts` classification — plus
`task-signing.ts` / `provenance.ts` for attribution. This is the harness-level analogue of
Verdandi's redact-before-persist and Munin's secret-scan (`architecture.md`, "Safety gating").
The vision assigns this seam as **owned, not reused** (it is what makes tenants safe against
*our* data).

**Tenant MUST:**
- Route any **mutating or egressing action** (writing to external systems, sending mail,
  spending money, touching the tailnet, executing shell) through the gating layer — it does not
  act on credentials directly. Today this means submitting the action through Hugin's task /
  delegation execution path, which applies the gate (there is no standalone gate API yet).
- Carry a **tenant provenance stamp** so a gated action is attributable to the tenant that
  requested it (`task-signing` / `provenance`).
- Accept gate decisions: a blocked action is blocked; the tenant surfaces the block, it does not
  route around it.

**Tenant MUST NOT:** hold ambient, ungated credentials that let it act outside the gate; retry a
gated-and-denied action through a side channel.

**Model-agnostic already:** the gate inspects *actions and content*, not the model — it is
tenant-brand-agnostic by design. **Claude-coupled today:** the only tenant that currently routes
through it is Hugin's Claude-SDK loop, so the gate has never seen a non-Claude requester and
tenant-provenance has never been exercised across brands.

**Conformance check:** a benign mutating action by the tenant passes the gate and is provenance-
stamped with the tenant identity; a planted prompt-injection / exfiltration attempt in the
tenant's task is caught and blocked.

### Seam D — Audit emission *(Verdandi — Memory pillar)*

**Substrate provides:** Verdandi (`:3036`, Pi 1) — a tamper-evident, hash-chained
(SHA-256 / RFC 8785) event log. `POST /api/events` (single) / `POST /api/events/batch` (≤1000),
Bearer **per-component key**, server-authoritative derived fields (timestamp, identity, hash),
redact-before-persist (14-rule pipeline), severity taxonomy (`critical` / `significant` /
`routine` / `debug`), retention classes, and an honesty grade on every event —
`mechanism` (proven/automatic) vs `convention` (self-reported).

**Tenant MUST:**
- **Emit a Verdandi event for every consequential action** it takes (before/after a mutation, a
  spend, an external send, an autonomous decision), correlated by `trace_id`.
- Emit under **its own per-component key**, so audit attribution is per-tenant. (Shared static
  tokens are exactly why audit can't currently say which actor acted — gap §1.3 / §1.5.)
- Report an honest evidence grade: claim `mechanism` only when the event is automatically proven;
  otherwise `convention`.

**Tenant MUST NOT:** fabricate server-authoritative fields (identity, hash, timestamp) — they are
recomputed server-side and client values are advisory only; suppress an audit gap silently
(Verdandi is fail-loud for audit).

**Model-agnostic already:** the intake is plain authenticated HTTP with a documented event shape
— any runtime can emit. **Claude-coupled today:** the only live emitter is the laptop Claude Code
hook (gap §1.3); no sibling-repo or non-Claude emitter exists, so per-tenant audit attribution is
unproven.

**Conformance check:** the tenant's action produces a Verdandi event under its own key;
`GET /api/verify` confirms the hash chain; `GET /api/events?component=<tenant>` returns the
event attributed to the non-Claude tenant.

---

## 4. What today's Claude-specific integrations must change

Three of the four seams are directly reachable today as authenticated HTTP (Munin, gateway,
Verdandi). **Seam C is not a standalone tenant-callable API** — safety gating is Hugin's internal
task-pipeline layer, reached by routing work *through Hugin's task / delegation execution path*,
which applies the gate. A conforming non-Hugin tenant must therefore either submit its mutating
actions through Hugin (inheriting the gate) or wait for the gate to be exposed as its own seam
(a follow-up). What is **not** satisfiable today is *tenant replaceability*, because the acting
integrations are Claude-coupled and the seams share static tokens. Minimal changes:

| Integration | Today | Change to conform |
|---|---|---|
| `ratatoskr/src/concierge.ts` (~108) | `new Anthropic(...)` direct cloud call | Route the triage LLM call through **Seam B** (gateway) behind an injectable provider; emit the routing-outcome verdict (also closes gap §1.2(c) / ratatoskr#27's dataset need). |
| `skuld/src/synthesizer.ts` (~12) | Direct Anthropic SDK for synthesis | Same gateway indirection at Seam B. Independently, skuld's **direct SQLite read** must move to **Seam A** (authenticated Munin HTTP — skuld#3). |
| Hugin dispatcher | Agent loop defaults to the Claude Agent SDK; a `runtime-registry`/`router` already selects Ollama/OpenRouter/M5 per task, but no non-Claude tenant has been proven across the four seams | Finish making the runtime a first-class **tenant provider** (the vision already caps Hugin's loop as a reusable *tenant*), and prove one non-Claude runtime end-to-end. The in-flight `feat/orchestrator-homeserver-provider` work (gap §1.2(a)) is the corrective seam. |
| All four seams | Shared static bearer tokens | Issue **per-tenant keys** (Munin, gateway, Verdandi, gating provenance) so §2's identity axiom holds and attribution/quota/audit become per-actor. |

None of these are landed here — they are the downstream code work this spec unblocks, filed
against their owning repos.

**Companion gap — not in scope here:** a conforming tenant that acts autonomously also needs a
**failure-recovery / undo story** (does the tenant make its mistakes visible or reversible?).
That is tracked as grimnir#46 and is a required *companion* obligation to this contract, not
duplicated in it.

---

## 5. Cheap validation plan — prove the seam once

The point of the contract is to be *demonstrated*, cheaply, once — not built out into a general
non-Claude harness. The validation drives **one bounded, low-blast-radius workflow end-to-end
with a local M5 model as the acting tenant**, exercising all four seams.

**Candidate workflow (pick one bounded task):** a skuld-style "summarize N Munin log entries into
one briefing paragraph," or a ratatoskr-style "classify one inbound message into a task type."
Both are single-shot, read-mostly, and cheap to reverse.

**The non-Claude tenant:** a local model on the M5 (e.g. `mellum` for the classify variant,
`qwen3-coder-next-80b` for a heavier synthesis), driven by a thin script that is *not* built on
the Claude Agent SDK.

**End-to-end, one afternoon, zero frontier tokens:**

1. **Seam A** — the tenant authenticates to Munin with **its own per-tenant key** and reads the
   input entries over HTTP (no SQLite).
2. **Seam B** — the tenant runs the learn-worthy LLM step through the gateway via
   `POST /delegate` against the local model; a **ledger verdict** appears for that
   `(task_type, model)`. (Plain, non-recorded inference would use `POST /v1/chat/completions`.)
3. **Seam C** — the write-back / task-enqueue step passes Hugin's **gating layer** and is
   provenance-stamped with the tenant's identity.
4. **Seam D** — the tenant emits **Verdandi events** under its own key; `GET /api/verify` passes;
   the events are attributed to the M5 tenant.

**Success criterion:** the workflow completes, and each of the four seams shows a record
attributed to the **non-Claude M5 tenant**, not to any Claude key. That single trace is the first
real evidence for the thesis sentence. **Cost:** one local model, no frontier spend, one bounded
session.

**Explicitly out of scope of this ticket:** actually *building and running* that validation, and
any general non-Claude agent runtime. This document is the contract and the plan; execution is
follow-up work (see UNCERTAINTIES in the PR).

---

## 6. Conformance checklist

A future tenant self-checks against these MUSTs (one line per obligation):

- [ ] **Identity** — presents a distinct per-tenant credential at every seam (§2).
- [ ] **A. Munin** — authenticated HTTP/MCP only, no direct SQLite, speaks the client contract,
      writes to owned namespaces.
- [ ] **B. Gateway** — inference indirectable through the gateway; learn-worthy calls route via
      `/delegate` (the ledger-writing path); respects quota/admission.
- [ ] **C. Gating** — all mutating/egressing actions pass the gate, provenance-stamped; accepts
      denials.
- [ ] **D. Audit** — emits a Verdandi event per consequential action, under its own key, with an
      honest evidence grade; never fabricates server-authoritative fields.
- [ ] **Companion (#46)** — has a failure-recovery / undo story for autonomous actions.

A tenant is **conforming** when all four seams check green under its own identity. Grimnir has
zero conforming non-Claude tenants today; the §5 plan produces the first.

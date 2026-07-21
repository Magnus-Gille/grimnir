# Sol Review — Grimnir Vision, Subsystems, and Top Five Priorities

> **Date:** 2026-07-09  
> **Scope:** System-level review of Grimnir's vision, architecture, current evidence, and live backlog.  
> **Mode:** Assessment only. No implementation, deployment, ticket mutation, or production probe was performed.

## Executive conclusion

Grimnir's core idea is strong and increasingly real:

> **Grimnir is a sovereign, self-knowing personal-AI substrate that any agent can safely act through.**

The system is not primarily an agent framework. Its durable value is the substrate that remains when models, harnesses, and channels are replaced:

1. **Sovereign Memory** — personal memory, files, and accountability on Magnus's hardware.
2. **Self-Knowing Inference** — evidence-based routing of work to the cheapest model that has earned trust for that task.

The implementation has advanced beyond the 2026-07-03 gap-analysis baseline. The M5 learning loop is now live, production workloads feed it, the routing table has guarded writers, the CI sweep landed, Ratatoskr is hardened, Hugin's unconditional permission bypass was replaced by scoped profiles, Munin and the gateway gained tenant attribution, and registry validation is green.

The remaining problem is no longer “build the pieces.” It is **finish the guarantees**:

- the audit/provenance path is still incomplete for non-Pi tenants and Hugin mutations;
- the irreplaceable data is not yet covered by a complete, tested recovery and physical-security story;
- five owner decisions block trust, retention, succession, ROI, and the Skuld decision;
- local/open-harness execution works in tests but is not yet a reliable, auditable production lane;
- Phase 2 still has signals that do not trigger action.

The recommended top five are therefore:

1. Close the accountable tenant-and-audit path.
2. Resolve the five owner decisions in one focused session.
3. Prove whole-substrate survivability and recovery.
4. Productionize the open-harness, self-knowing inference lane.
5. Make Phase 2 signals reliably reach a human or an automated response.

## 1. The vision

### 1.1 Identity: substrate, not tenant

The most important architectural choice in vision v0.2 is the separation between **substrate** and **tenant**.

- The **substrate** is Grimnir: memory, files, audit, inference evidence, routing, safety policy, and durable identity.
- A **tenant** is any replaceable agent loop, model, channel, or harness: Claude Agent SDK, Codex, OpenCode, Goose, Telegram, or a future ingress.

That distinction prevents Grimnir from competing with fast-moving agent frameworks. It owns only what compounds personally and cannot be reacquired from a vendor.

### 1.2 The two protected pillars

#### Pillar 1 — Sovereign Memory

**Munin + Mimir + Verdandi** form the personal knowledge and accountability core:

- Munin holds searchable state, history, summaries, task records, and cross-environment orientation.
- Mimir holds full files and artifacts that should not be copied into every model context.
- Verdandi records consequential actions in a tamper-evident chain.

The value proposition is not merely local hosting. It is continuity and control over the personal context that makes an agent useful over time.

#### Pillar 2 — Self-Knowing Inference

**M5 gateway + capability ledger + evaluation/probe system + guarded routing table** form the inference core.

The system does not assume that a local model is good enough. It records outcomes, uses trusted verifiers where possible, detects regressions, and routes based on accumulated evidence. This is Grimnir's most distinctive technical idea.

### 1.3 The build rule

The vision's decision rule is sound:

> Build only what touches Memory or Inference-routing. Reuse open-source in the harness layer, provided it conforms to the substrate contract.

This implies:

- deepen Munin, Verdandi, routing evidence, safety gates, and identity;
- keep Hugin as policy/routing glue, not a bespoke universal agent framework;
- use OpenCode, Goose, Claude Agent SDK, Codex, or successors behind a stable adapter;
- cut channels, dashboards, experiments, and services that do not protect a pillar or show measured use.

### 1.4 The autonomy arc

| Phase | Promise | Honest current state |
|---|---|---|
| 1. Reactive | “Do X and go to sleep.” | Largely complete: memory, files, dispatch, Telegram, monitoring, briefings, local inference. |
| 2. Self-maintaining | Detect and handle upkeep without being asked. | Current phase. Deployment validation and maintenance machinery are real, but several detect→notify→act loops remain open. |
| 3. Proactive collaborator | Identify useful work and do or propose it. | Technically approachable, but premature until identity, audit, recovery, and interactive trust are settled. |
| 4. Trusted autonomous agent | Act independently on meaningful business work. | Aspirational. Requires earned trust, reliable reversal, and accountable identity—not just better models. |

The correct near-term objective is not “more autonomy.” It is making Phase 2 trustworthy enough that Phase 3 becomes a controlled expansion rather than a leap.

## 2. System map

### 2.1 Physical and network substrate

| Node | Role | Important workloads |
|---|---|---|
| `huginmunin` Raspberry Pi | Primary service host | Munin, Hugin, Heimdall, Ratatoskr, Skuld timer, Verdandi, Grimnir validation/security timers |
| `nas` | Storage host | Mimir, artifact storage, Time Machine, backup disk |
| BosGame M5 | Main inference node | OpenAI-compatible gateway, model serving, capability ledger, routing/evaluation jobs |
| Orin Nano | Secondary inference node | Ollama / specialist or overflow capacity |
| MacBook Air | Development + intermittent inference | Claude/Codex, noxctl, local model servers, artifact source |
| `skald` Raspberry Pi | Display | E-paper display endpoint |

Tailscale is the internal mesh. Cloudflare Tunnel/Access fronts selected public services. systemd is the process and schedule manager. `services.json` is the inventory authority for components, hosts, ports, deployment shape, and units.

### 2.2 The main flows

#### Memory and file flow

`agent → Munin search/state` and `laptop artifacts → Mimir → Munin summary/index`.

Munin is the cross-environment discovery layer. Mimir is the content layer. This supports laptop, CLI, desktop, web, mobile, and Telegram without copying full documents into every environment.

#### Task and action flow

`agent or Ratatoskr → Munin task → Hugin claim/gate/route → runtime or harness → result → Munin → optional Telegram reply`.

Hugin owns macro-routing and safety/policy around execution. The chosen runtime may be Claude, Codex, a local executor, an M5 `/delegate` worker, or eventually an OpenCode/Goose adapter. The missing final edge is consistent tenant provenance and Verdandi emission for consequential actions.

#### Inference-learning flow

`production request → M5 gateway → model/verifier outcome → capability ledger → guarded routing-table regeneration → future routing decision`.

Unlike the July 3 baseline, this loop now operates in production. Its current weaknesses are admission/backpressure, verifier quality, promotion safety, and honest ROI calibration—not absence of a loop.

#### Operations flow

`service/system metrics → Heimdall/Brokkr/Grimnir validation → dashboard or alert → operator/automation`.

Collection is comparatively mature. The weak edge is delivery and response: some critical signals are still dashboard-only, and some validation evidence is stored without driving a decision.

## 3. Subsystem overview and current state

| Subsystem | Strategic role | Current evidence | Main remaining gap |
|---|---|---|---|
| **Grimnir repo** | System authority, registry, architecture, deploy/validation/security orchestration | Registry validation reported 7 OK, 0 issues, 0 warnings on 2026-07-08 | Architecture/threat/backlog text now contains stale claims; Phase-2 evidence still needs better consumption |
| **Munin Memory** | Pillar 1 memory and cross-environment state | Mature; per-tenant principal work (#191) closed; large test suite; orientation/search are core daily infrastructure | Correction, supersession, expiry, and ownership-aware forgetting remain open in [#192](https://github.com/Magnus-Gille/munin-memory/issues/192) |
| **Mimir** | Pillar 1 full-file archive | Healthy; encrypted OneDrive off-site leg and byte-identical restore test are live; public-doc scrub current | Heimdall health/push configuration remains ambiguous ([#11](https://github.com/Magnus-Gille/mimir/issues/11), [#12](https://github.com/Magnus-Gille/mimir/issues/12)); recovery coverage must be assessed as part of the whole system |
| **Verdandi** | Pillar 1 tamper-evident accountability | Real hash chain; checkpoint command/timer merged in PR #17 | Checkpoint deploy pending; off-Pi intake and tenant key lifecycle blocked by [#15](https://github.com/Magnus-Gille/verdandi/issues/15); Hugin still does not emit |
| **M5 / gille-inference** | Pillar 2 gateway, ledger, evaluation, routing | Live production delegation, guarded routing-table updates, quality-adjusted savings evidence, Heimdall panels | Policy remains shadow/HOLD; verifier and promotion evidence can be gamed or inflated; audit emission blocked on Verdandi |
| **Hugin** | Policy, safety, macro-routing, task lifecycle | Active; M5 worker attribution deployed; scoped permission profiles replaced unconditional bypass; Claude fallback retained | Tenant signing/provenance [#146](https://github.com/Magnus-Gille/hugin/issues/146), Verdandi emission [#148](https://github.com/Magnus-Gille/hugin/issues/148), and M5 busy retry [#157](https://github.com/Magnus-Gille/hugin/issues/157) |
| **Ratatoskr** | Telegram ingress and task/result routing | Production; gateway-backed triage; `/repo` path and header-injection hardening live-validated | Mostly maintenance/UX; no longer a load-bearing architecture gap |
| **Skuld** | Morning briefing / orientation product | Timer-only deployment is now present and registry validation is green | Value is unproven. [Grimnir #69](https://github.com/Magnus-Gille/grimnir/issues/69) has a stale incident description; the live question is four-week measured trial vs cut |
| **Heimdall** | System visibility and human-facing health | Active; fleet and inference panels are real | Critical alert-engine reds remain display-only in [#112](https://github.com/Magnus-Gille/heimdall/issues/112) |
| **Brokkr** | Hardware, OS, storage, backups, off-box substrate care | Dead-man check merged; maintenance timers and hardware ownership established | Dead-man deploy/drill pending; restore coverage [#39](https://github.com/Magnus-Gille/brokkr/issues/39) and encryption-at-rest decision [#40](https://github.com/Magnus-Gille/brokkr/issues/40) remain open |
| **noxctl** | Fortnox CLI/MCP and controlled accounting access | Mature 0.4.0 release with broad tests and explicit mutation confirmation | Sensitive-data lifecycle belongs in Grimnir's data map; otherwise not a current substrate bottleneck |

## 4. Cross-cutting contracts and trust boundaries

### 4.1 Tenant contract

Any acting tenant must pass four seams:

| Seam | Obligation | Current state |
|---|---|---|
| A — Munin | Authenticated memory/state access with tenant identity | Transport proven with Codex; per-tenant principal ticket closed |
| B — Gateway | Inference through evidence-producing routing with caller attribution | Transport and ledger proven; key-alias attribution ticket closed |
| C — Hugin | Safety-gated task execution with verified provenance | Gate/execution proven; signing and lifecycle attribution still open |
| D — Verdandi | Reachable, tenant-attributed audit emission | Still blocked off-Pi; this prevents end-to-end conformance |

The first Codex validation proved that the transports are genuinely model-agnostic. It did **not** prove that a non-Claude tenant can act with end-to-end accountability. That distinction should remain explicit.

### 4.2 Security posture

The relevant trust boundaries are:

- untrusted email, web pages, documents, Telegram content, dependencies, and model output;
- powerful agents that can combine private data, untrusted content, tools, credentials, and egress;
- a semi-trusted tailnet where per-service auth—not network location—is the real control;
- physical possession of unencrypted media;
- a single trusted operator whose absence is itself a continuity risk.

Hugin's queue path is materially safer after issue #149, but interactive sessions still bypass that gate. Verdandi's hash chain is real, but the actor doing the most consequential autonomous work—Hugin—still does not feed it.

### 4.3 Failure recovery

The convention is well designed: every autonomous mutation must leave both a reversal recipe (`git_revert`, `snapshot`, or `irreversible` plus mitigation) and a Verdandi event. The weakness is adoption, not design. Until Hugin emits and tenant identity is verified, this convention cannot be claimed as a system property.

### 4.4 Self-improvement

The intended cycle is:

`execute → trace → score → reflect → improve`.

Pillar 2 now demonstrates a real version of this cycle. The wider fleet is uneven: several components emit evidence without a consumer, and some scoring signals are structurally easy to satisfy without measuring real task quality. The correct next move is better evidence and closed responses, not a new observability service.

## 5. Evidence reconciliation: what changed after the July 3 baseline

Older documents and some open issue bodies are useful history but not current truth. The following corrections materially change the priority ranking:

1. **Pillar 2 is no longer severed.** Hugin and Ratatoskr feed M5 production traffic; routing-table generation/adoption and regression guards are live. The remaining work is reliability, verifier integrity, and policy maturity.
2. **The “7 repos without CI” program is no longer open.** The July fleet closed the original CI sweep. It should not consume a top-five slot.
3. **Skuld is deployed as a user-scoped timer.** Issue #69's “not installed / never run” body is stale. The unresolved question is whether briefings earn their maintenance cost.
4. **Mimir has encrypted off-site backup and a tested restore.** Brokkr #39 still matters for stores not covered by that mechanism and for a whole-system drill, but the ticket's original “Mimir local-only” premise is stale.
5. **Hugin issue #149 is closed and deployed.** Unconditional `bypassPermissions` is no longer the current permission model. The threat model should be revised after validation evidence is consolidated.
6. **Munin #191 and gille-inference #152 are closed.** Tenant identity is not “missing everywhere” anymore; the remaining structural gaps are Hugin provenance and Verdandi intake/emission.
7. **Verdandi checkpointing and the Brokkr dead-man implementation are merged.** Their remaining value is operational: deploy, drill, and verify.
8. **Grimnir's user-scope validator behavior is fixed in deployed code despite #63 remaining open.** This is backlog hygiene, not a fresh engineering gap.

This review therefore ranks the remaining edges, not the already-shipped July program.

## 6. The five highest-priority/value items

The ranking uses four criteria: vision centrality, risk reduction, unblocking effect, and value relative to effort.

### 1. Close the accountable tenant-and-audit path

**Why it ranks first:** This is the unresolved half of the thesis sentence: “any agent can **safely** act through.” It also closes the accountability inversion in which Hugin performs mutations but Verdandi mostly records laptop activity.

**Scope, in dependency order:**

1. Deliver [verdandi#15](https://github.com/Magnus-Gille/verdandi/issues/15): a reachable off-Pi intake plus mint/list/rotate/revoke for tenant/component credentials.
2. Deliver [hugin#146](https://github.com/Magnus-Gille/hugin/issues/146): verified tenant signing, provenance in structured results, and a path toward requiring signatures.
3. Deliver [hugin#148](https://github.com/Magnus-Gille/hugin/issues/148): emit execution/mutation events with reversal metadata.
4. Unblock [gille-inference#154](https://github.com/Magnus-Gille/gille-inference/issues/154): audit routing-regression alarms without making audit availability a runtime dependency.
5. Deploy Verdandi checkpointing and rerun [grimnir#58](https://github.com/Magnus-Gille/grimnir/issues/58) through all four seams with a distinct non-Claude identity.

**Done means:** A Codex/OpenCode tenant has distinct credentials at all four seams; a consequential action produces a verified provenance chain, a Verdandi event, and a reversal recipe; Seam D passes from off-Pi.

**Effort:** Medium, cross-repo. **Unblocking value:** Very high.

### 2. Resolve the five owner decisions in one focused session

**Why it ranks second:** The analysis is already done in `docs/roadmap-now-decision-brief.md`. A short owner session unlocks several high-risk and high-value paths at far lower cost than another implementation sprint.

Decide:

- [#65](https://github.com/Magnus-Gille/grimnir/issues/65): emergency delegate(s) and `recover` vs `export-and-shutdown` vs temporary operation.
- [#66](https://github.com/Magnus-Gille/grimnir/issues/66): retention defaults for client/accounting data, personal memory, telemetry, and transient task artifacts.
- [#67](https://github.com/Magnus-Gille/grimnir/issues/67): the service/system exit threshold and minimal dormant mode.
- [#69](https://github.com/Magnus-Gille/grimnir/issues/69): four-week measured Skuld trial or cut. The old deployment premise should be corrected first.
- [#70](https://github.com/Magnus-Gille/grimnir/issues/70): interactive-session posture. The safest practical default is to route consequential mutations following untrusted input through Hugin, with a fresh session as the fallback.

Then write only the five already-scoped artifacts: succession checklist, data-lifecycle map, vision ROI/off-ramp paragraph, Skuld decision record, and interactive-session posture. Use the retention decision to shape Munin correction/forgetting [#192](https://github.com/Magnus-Gille/munin-memory/issues/192).

**Done means:** The five choices are explicit, the small documents exist, and each implementation ticket has a policy answer instead of inventing one.

**Effort:** Small owner session plus small documentation follow-up. **Value/effort:** Highest in the backlog.

### 3. Prove whole-substrate survivability and recovery

**Why it ranks third:** Pillar 1 contains assets that cannot be recreated. A sovereign system that cannot be restored—or whose disks disclose everything when stolen—is not yet sovereign in the strong sense.

**Scope:**

- Reframe and complete [brokkr#39](https://github.com/Magnus-Gille/brokkr/issues/39) as a restore matrix across Munin, Mimir, Verdandi, Time Machine, and essential configuration/key manifests. Credit Mimir's existing encrypted off-site leg and restore evidence rather than duplicating it.
- Verify and decide encryption at rest in [brokkr#40](https://github.com/Magnus-Gille/brokkr/issues/40), including boot/recovery/key-custody consequences.
- Deploy the merged off-box dead-man timer on M5 and run the blackhole and recovery drills.
- Deploy Verdandi's checkpoint timer and confirm that the anchor survives compromise of the audited host.
- Tie the technical runbook to the succession decision from priority 2.
- Keep the physical UPS issue [grimnir#4](https://github.com/Magnus-Gille/grimnir/issues/4) visible as the cheap protection against a failure mode already experienced.

**Done means:** A documented drill restores representative data from every critical store into an isolated target; off-site coverage gaps are explicit; encrypted-media status is verified; host loss produces an off-box alert; another named person can follow the recovery entry point.

**Effort:** Medium. **Risk reduction:** Very high.

### 4. Productionize the open-harness, self-knowing inference lane

**Why it ranks fourth:** Pillar 2 is live, and the harness bake-off proved that OpenCode and Goose can execute real local edit/test loops through M5. The gap is now policy, event normalization, backpressure, and evidence quality—not model availability.

**Scope:**

- Fix Hugin busy-lane behavior in [#157](https://github.com/Magnus-Gille/hugin/issues/157): bounded retry, `Retry-After`, a homeserver-specific concurrency cap, and explicit degraded-coverage reporting.
- Create the narrow Hugin `HarnessAdapter` implementation ticket recommended by the bake-off, starting with OpenCode for coding tasks.
- Pin the acceptance fixture: normalized events, machine-readable diff/test evidence, no global side effects, and a read-only mode proven unable to edit or run shell.
- Keep gating, credentials, provenance, audit, and reversal outside the harness.
- Harden model promotion and evidence quality through the currently open gille-inference work, especially [#156](https://github.com/Magnus-Gille/gille-inference/issues/156), [#158](https://github.com/Magnus-Gille/gille-inference/issues/158), and [#176](https://github.com/Magnus-Gille/gille-inference/issues/176).
- Keep delegate policy in shadow until real lane volume, verifier quality, and cost calibration support enforcement.

**Done means:** A production Hugin task can use OpenCode+M5 behind the same gate/audit contract, survives M5 admission pressure without silently dropping workers, and produces trustworthy evidence that can change routing.

**Effort:** Medium. **Strategic value:** Very high, but correctly sequenced after identity/audit foundations.

### 5. Make Phase 2 signals reliably trigger action

**Why it ranks fifth:** Grimnir already collects substantial evidence. Phase 2 becomes real when important changes reliably reach a human or a safe automated response, while routine green state stays quiet.

**Scope:**

- Route Heimdall red alerts through Telegram with deduplication/throttling in [heimdall#112](https://github.com/Magnus-Gille/heimdall/issues/112).
- Deploy and drill the Brokkr dead-man path as the independent host-loss channel.
- Make Grimnir validation deltas drive a decision instead of accumulating unread history ([grimnir#2](https://github.com/Magnus-Gille/grimnir/issues/2), [#23](https://github.com/Magnus-Gille/grimnir/issues/23)).
- Use proven signal quality before enabling documentation auto-remediation in [grimnir#5](https://github.com/Magnus-Gille/grimnir/issues/5).
- Resolve Mimir's false/unknown Heimdall state so operational dashboards distinguish an unreachable probe from an unhealthy service.
- As the first keyboard action when work resumes, close the known credential-containment loose end in [grimnir#9](https://github.com/Magnus-Gille/grimnir/issues/9): verify the previously exposed Anthropic key is revoked. This is tiny, urgent hygiene—not a new program.

**Done means:** Simulated service failure and host loss create one deduplicated off-box notification; a validation regression surfaces once; recovery produces a resolved notification; green runs remain silent; known compromised credentials are confirmed dead.

**Effort:** Small to medium. **Operational value:** High.

## 7. Recommended sequencing

No implementation is started by this review. When work does begin, the lowest-risk sequence is:

1. **Owner/P0:** verify key revocation and make the five owner decisions.
2. **Trust track:** Verdandi #15 → Hugin provenance/emission → tenant-contract rerun.
3. **Resilience track, in parallel:** deploy/drill already-merged controls, then restore/encryption work.
4. **Inference track:** Hugin backpressure first, then the OpenCode adapter and promotion-quality gates.
5. **Phase-2 closure:** wire alert/delta consumers and only then consider automated remediation.

This sequence avoids building more autonomy on top of ambiguous identity, untested recovery, or weak signals.

## 8. What should not take a top-five slot now

- More channels, Telegram media features, or a richer dashboard.
- New in-house agent-loop machinery.
- Skuld phases 4–5 before the measured trial/cut decision.
- More local models before promotion and verifier integrity are trustworthy.
- Large compliance prose before the small data map and retention defaults exist.
- A new observability service; the missing work is wiring and response.
- Reopening the completed July CI, Ratatoskr hardening, registry, or routing-table programs.

## 9. Method and sources

### Claude-shaped orientation completed first

Before analysis, this review inspected:

- root `CLAUDE.md`, `STATUS.md`, `AGENTS.md`, `.claude/settings.local.json`, and `docs/.claude/settings.local.json`;
- the Claude skill catalog and the relevant `issues`, `research-spike`, and `magnus-security-review` skill instructions;
- Claude MCP configuration names relevant to this ecosystem: `munin-memory`, `m5`, `friction-mcp`, and `arxiv`;
- current Munin project status for Grimnir and its major components;
- the installed GitHub connector and live open issues across the component repositories.

Munin and GitHub were used read-only. M5/Hugin delegation, friction triage, production SSH, deployments, and ticket changes were deliberately not used.

### Primary repo sources

- `docs/vision.md`
- `docs/architecture.md`
- `docs/tenant-contract.md`
- `docs/tenant-validation-2026-07-04.md`
- `docs/threat-model.md`
- `docs/gap-analysis-2026-07-03.md`
- `docs/roadmap-now-decision-brief.md`
- `docs/observability-and-improvement.md`
- `docs/failure-recovery.md`
- `docs/agent-harness-bakeoff-2026-07-08.md`
- `docs/authority.md`, `docs/role-separation.md`, `services.json`, and `STATUS.md`

The same-day `fable_review_20260709.md` was used as an independent cross-check, not as authority. Where it conflicted with newer status or live issue state, this review followed the newer evidence and documented the correction in section 5.

---

**Bottom line:** Grimnir has crossed from architecture experiment into a functioning personal substrate. The highest-value work is now to make its strongest claims boringly true under failure: attributable tenants, complete audit, recoverable sovereign data, trustworthy routing evidence, and signals that reliably cause the right response.

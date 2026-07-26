# Fleet seam audit — 2026-07-26

This is a bounded audit advancing [grimnir#79](https://github.com/Magnus-Gille/grimnir/issues/79), not a fleet-wide certification. Source observations were checked against the owning repositories' current remote `main` files on 2026-07-26. The Ratatoskr row also has a bounded, public-safe production receipt; the Verdandi and Munin rows do **not** claim a production write or deployment.

The canonical delivery conventions are already adopted in
[Cross-service contracts](architecture.md#cross-service-contracts), rules 6–7:

1. a producer proves its payload through the consumer's actual acceptance rule;
2. a data-reading feature has a bounded, read-only real-data check before completion;
3. that check includes representative historical rows when prior producer defects or migrations could change their shape, using an identity that survived the defect; and
4. a supported input that cannot be applied is rejected or surfaced as an observable warning, never silently accepted as plausible success.

## Result matrix

| Producer → consumer | Current source evidence | Consumer acceptance / observable result | Evidence status and owner action |
|---|---|---|---|
| Ratatoskr → Heimdall alert ingest | Ratatoskr validates an allowlisted alert and posts the bare object from `src/alert.ts`; its current `tests/heimdall-alert-contract.test.ts` runs accepted/rejected firing and resolution envelopes through a byte-pinned copy of Heimdall's actual ingest/auth exports. | A firing alert needs a title; a resolution needs a `dedup_key`. Heimdall normalizes severity and persists title, body/detail, source, and dedup key. It intentionally does not persist `ts` or `links`. | **Verified.** The pinned consumer fixture covers acceptance, rejection, idempotent resolution, and deliberately non-persisted advisory fields. [Ratatoskr #57](https://github.com/Magnus-Gille/ratatoskr/issues/57) also records a public-safe production receipt: a synthetic firing alert changed matching active count `0 → 1`, then resolution returned it to `0`. No new defect found. |
| Verdandi event intake | Verdandi exposes single, batch, and hook ingest. A read-only search of current `main` in Ratatoskr, Hugin, Munin, Heimdall, gille-inference, Brokkr, and Skuld found no current `/api/events` or `VERDANDI` client integration. | The server validates event type, severity, component identity, redaction, and idempotency before persistence. | **Not an active producer→consumer seam.** No producer contract or real-data evidence is claimed. Re-audit after an emitter is approved, provisioned, and enabled; its owner must use Verdandi's accepted/rejected fixtures and a bounded read-only receipt check. |
| Munin project status → Heimdall projects view | Heimdall's `src/munin-projects.js` selects only `projects/*` state entries whose key is `status`, derives lifecycle from tags, and optionally parses named Markdown headings. The inspected service writers do not establish a distinct, currently active service-owned producer for that document shape. | Entries outside the namespace/key/type filter are omitted; missing headings merely remove optional structured fields. The authoritative write surface remains Munin's `memory_update_status`/`memory_write` contract. | **No grounded service-to-service producer gap found in this bounded audit.** This is a generic shared-document consumer, not evidence that a particular service writes a shape Heimdall fails to accept. A future service-owned status writer needs a consumer fixture plus a read-only check against representative status entries, including older entries lacking optional headings. |

## Evidence boundary

Ratatoskr → Heimdall satisfies the bounded receipt requirement above. Its retained evidence contains only timestamp/count/result metadata and no tokens, URLs, bodies, alert identities, or private locators.

For a future Verdandi emitter, the owner must query a bounded redacted result set by component after the approved emitter runs and confirm accepted event count plus the consumer-visible identity and lifecycle fields. This audit does not authorize enabling Verdandi.

## Residual unaudited seams

- Hugin → Heimdall typed-panel rows and the Hugin ↔ M5 learning-task seam were not re-audited here; their previously routed owner work remains outside this named-seam pass.
- Other Munin namespaces (tasks, maintenance, alerts, and ad-hoc agent documents) were not promoted to producer→consumer seams without a concrete service producer and consumer acceptance rule.
- No production corpus was queried for Verdandi or the generic Munin status shape. The Ratatoskr probe is a bounded lifecycle receipt, not a broad alert-corpus audit.

## Method note

The audit used direct source and fixture inspection, plus the public-safe Ratatoskr receipt above. A bounded M5 `mellum` classification independently labelled Ratatoskr **verified** and Verdandi/Munin **insufficient for a defect**; the source evidence was checked independently before recording that result. No actionable defect or duplicate owning-repo issue was found in this bounded pass.

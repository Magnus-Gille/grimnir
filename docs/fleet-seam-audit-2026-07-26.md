# Fleet seam audit — 2026-07-26

This is a bounded, source-level audit advancing [grimnir#79](https://github.com/Magnus-Gille/grimnir/issues/79). It is not a fleet-wide certification and is **not live-verified**: it does not claim a production write or deployment. Source observations were checked against the owning repositories' current remote `main` files on 2026-07-26; live evidence, where required below, remains outstanding.

## Result matrix

| Producer → consumer | Current source evidence | Consumer acceptance / observable result | Evidence status and owner action |
|---|---|---|---|
| Ratatoskr → Heimdall alert ingest | Ratatoskr validates an allowlisted alert and posts the bare object from `src/alert.ts`; Heimdall accepts it at `/api/alerts` in `src/alert-ingest.js`. | A firing alert needs a title; a resolution needs a `dedup_key`. Heimdall normalizes severity and persists title, body/detail, source, and dedup key. It intentionally does not persist `ts` or `links`. | **Gap: consumer-contract test is absent.** Ratatoskr tests prove the outgoing JSON, not Heimdall's actual validator. [Ratatoskr #57](https://github.com/Magnus-Gille/ratatoskr/issues/57) owns acceptance fixtures and bounded read-only real-data evidence before this seam is called complete. |
| Verdandi event intake | Verdandi exposes single, batch, and hook ingest, but its current status and `docs/multi-env-ingest-design.md` say it has **no live emitter** and remains intentionally inactive. | The server validates event type, severity, action, component identity, redaction, and idempotency before persistence. | **Not an active producer→consumer seam.** No producer contract or real-data evidence is claimed. Re-audit after an emitter is approved, provisioned, and enabled; its owner must use Verdandi's accepted/rejected fixtures and a bounded read-only receipt check. |
| Munin project status → Heimdall projects view | Heimdall's `src/munin-projects.js` selects only `projects/*` state entries whose key is `status`, derives lifecycle from tags, and optionally parses named Markdown headings. The inspected service writers do not establish a distinct, currently active service-owned producer for that document shape. | Entries outside the namespace/key/type filter are omitted; missing headings merely remove optional structured fields. The authoritative write surface remains Munin's `memory_update_status`/`memory_write` contract. | **No grounded service-to-service producer gap found in this bounded audit.** This is a generic shared-document consumer, not evidence that a particular service writes a shape Heimdall fails to accept. A future service-owned status writer needs a consumer fixture plus a read-only check against representative status entries, including older entries lacking optional headings. |

## Required real-data evidence before closure

For Ratatoskr → Heimdall, the owner must perform a read-only, bounded check of existing redacted alert records or a safe authenticated receipt path. It must demonstrate that one firing lifecycle and one resolution lifecycle are accepted and observable, record only timestamp/count/result metadata, and not copy tokens, URLs, bodies, or private locators into an issue or this repository.

For a future Verdandi emitter, the owner must query a bounded redacted result set by component after the approved emitter runs and confirm accepted event count plus the consumer-visible identity and lifecycle fields. This audit does not authorize enabling Verdandi.

## Residual unaudited seams

- Hugin → Heimdall typed-panel rows and the Hugin ↔ M5 learning-task seam were not re-audited here; their previously routed owner work remains outside this named-seam pass.
- Other Munin namespaces (tasks, maintenance, alerts, and ad-hoc agent documents) were not promoted to producer→consumer seams without a concrete service producer and consumer acceptance rule.
- No live production corpus was queried for any seam in this audit.

## Method note

The audit used direct source and fixture inspection only. A bounded M5 `mellum` structural review agreed that the Ratatoskr evidence does not establish a consumer-contract test or real-data evidence; its additional field-mismatch observation was treated as advisory, because intentionally unpersisted fields are not by themselves a defect.

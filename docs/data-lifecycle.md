# Grimnir — Data Lifecycle Map

> **Status:** store map and provisional retention defaults adopted 2026-07-10. Automatic pruning
> remains an owning-repo implementation decision; this document does not create deletion jobs.
>
> This is an operational map, not a general GDPR policy or legal interpretation.

## Default classes

| Data class | Provisional default | Rule |
|---|---|---|
| Client and accounting | Statutory and contractual duties win; otherwise **24 months after the engagement ends** | Confirm the applicable duty before deletion. The 24-month fallback applies only when neither law nor contract requires longer retention. |
| Personal memory | Retain until explicit correction or deletion, with an **annual review** | The annual review identifies stale or unnecessary memory; it does not replace correction/deletion on request. |
| Operational telemetry | **6 months** from collection | Retain enough history for incident and trend review; do not keep payloads merely because they are easy to log. |
| Transient task artifacts | **30 days** after task completion | Promote useful output into an owned durable store before the disposable workspace or rendering copy expires. |

Retention is measured from the last relevant activity unless a row below names a better trigger.
Legal hold, an active incident, or an unresolved financial obligation pauses deletion only for the
affected records. A pause must have an owner and a review date.

## Store map

| Store | Primary data class | Authority | Retention application | Erasure / correction path |
|---|---|---|---|---|
| Munin | Personal memory; task results | `munin-memory` | Namespace owner selects the applicable class. Promoted durable memory follows the personal-memory default; disposable task results follow the transient default. | Correct or delete the owned entry through Munin and retain a minimal erasure audit record. |
| Mimir | Client/accounting files; personal files; generated artifacts | `mimir` | The source folder's class controls. Generated copies must not outlive their source without an explicit reason. | Delete the source object through Mimir; encrypted backup copies age out through backup rotation rather than immediate mutation. |
| Verdandi | Audit and reversal evidence | `verdandi` | Keep evidence for at least as long as the action or retained record it explains. Payload-derived detail should be minimized and may follow the shorter operational window. | Append a tombstone or redaction event; do not rewrite the hash chain. Preserve non-sensitive integrity metadata. |
| Heimdall | Metrics, alerts, rendered status | `heimdall` | Operational-telemetry default, measured from collection time. | Prune through the owning maintenance path; do not edit generated views as if they were source data. |
| Hugin | Task input/output, logs, workspaces | `hugin` | Workspaces and unpromoted outputs use the transient-artifact default. The durable task result in Munin follows its selected class. | Remove the workspace and disposable logs; correct/delete the owned Munin result separately while retaining the action audit. |
| Ratatoskr | Telegram-derived routing context | `ratatoskr` | Local copies use the transient-artifact default. Telegram remains a separate source system. | Delete local transient state; delete source messages through Telegram when required. |
| Skuld | Briefing drafts and generated briefings | `skuld` | Drafts use the transient-artifact default. Only a deliberately promoted briefing or action becomes durable Munin memory. | Delete the Skuld output from its owning store; remove any separately promoted Munin entry through Munin. |
| noxctl / Fortnox exports | Client and accounting | `fortnox-mcp` / Fortnox | Statutory, contractual, and Fortnox source requirements win. Local exports use the client/accounting default when no longer needed for active work. | Delete local exports through their owning path; use Fortnox's supported correction/erasure process for source records. |
| Backups | Copy of source class | Brokkr | Never extend source retention silently. Rotation may delay physical erasure; record the maximum delay in the owning backup configuration. | Delete from live source first, then allow documented backup expiry. Restore procedures must not resurrect an expired record into production. |
| M5 capability ledger | Operational evidence; possibly payload-derived artifacts | `gille-inference` | Verdict and routing evidence use the operational-telemetry default. Payload-derived fixtures use the transient default unless explicitly promoted as an eval asset. | Remove or redact payload-derived artifacts; retain only the minimum aggregate evidence needed to explain a routing decision. |

## Erasure workflow

1. Identify the authoritative store and any derived copies using the map above.
2. Check for a narrow statutory, contractual, incident, or legal-hold exception.
3. Correct or erase at the authoritative source first.
4. Remove derived live copies and record when backup expiry will complete.
5. Emit a minimal audit record containing the request scope, stores acted on, result, and expiry
   date—never the erased content itself.
6. Verify through readback/search that the live record is gone or corrected.

Automatic pruning must be implemented and tested by the owning repo. This map alone does not
authorize a new deletion job. It implements the decision artifact for grimnir#66 and should shape
Munin correction/forgetting work without creating a second lifecycle authority.

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

The last column distinguishes **current** mechanisms from **target** work. A target is not an API,
automation, or compliance claim. Cross-store erasure orchestration does not exist today.

| Store | Primary data class | Authority | Retention application | Current mechanism / unresolved target |
|---|---|---|---|---|
| Munin | Personal memory; task results | `munin-memory` | Namespace owner selects the applicable class. Promoted durable memory follows the personal-memory default; disposable task results follow the transient default. | **Current:** owning Munin mechanisms and operator administration only; there is no system-wide erasure workflow. **Target:** ownership-aware correction/deletion with a minimal audit record. |
| Mimir | Client/accounting files; personal files; generated artifacts | `mimir` | The source folder's class controls. Current backup behavior may outlive the source as described at right. | **Current:** Mimir's HTTP surface is read-only—there is no delete API. An operator must remove a file at its authoritative filesystem/source and verify derived copies. Encrypted off-site history has a configured 30-day rotation; NAS `backup-artifacts` is append-only/no-delete and may preserve removed files indefinitely. **Target:** an authenticated, audited deletion workflow that identifies derived copies and resolves the NAS retention gap. |
| Verdandi | Audit and reversal evidence | `verdandi` | Keep evidence for at least as long as the action or retained record it explains. Payload-derived detail should be minimized and may follow the shorter operational window. | **Current:** secrets are redacted before ingest, but PII in immutable original rows has no implemented erasure mechanism. **Target:** resolve erasure without falsely rewriting hash-chain history. This remains unresolved owning-repo work. |
| Heimdall | Metrics, alerts, rendered status | `heimdall` | Operational-telemetry default, measured from collection time. | **Current:** owning maintenance mechanisms only; the six-month default is not centrally enforced. **Target:** tested six-month pruning without treating generated views as source data. |
| Hugin | Task input/output, logs, workspaces | `hugin` | Workspaces and unpromoted outputs use the transient-artifact default. The durable task result in Munin follows its selected class. | **Current:** operator-managed workspace/log removal; durable Munin results are a separate store. **Target:** tested 30-day cleanup plus explicit handling of the associated Munin result and audit evidence. |
| Ratatoskr | Telegram-derived routing context | `ratatoskr` | Local copies use the transient-artifact default. Telegram remains a separate source system. | **Current:** source-message deletion is Telegram-side and no cross-store lifecycle is enforced. **Target:** tested 30-day expiry for any local transient copies. |
| Skuld | Briefing drafts and generated briefings | `skuld` | Drafts use the transient-artifact default. Only a deliberately promoted briefing or action becomes durable Munin memory. | **Current:** outputs live through their owning store; no Skuld-specific erasure workflow is established. **Target:** expire drafts at 30 days and route promoted Munin entries through Munin's eventual correction/deletion mechanism. |
| noxctl / Fortnox exports | Client and accounting | `fortnox-mcp` / Fortnox | Statutory, contractual, and Fortnox source requirements win. Local exports use the client/accounting default when no longer needed for active work. | **Current:** operator removes local exports; Fortnox remains the source authority. **Target:** inventory and verify local/derived export removal without overriding Fortnox's supported record process. |
| Backups | Copy of source class | Owning service (replication/retention); Brokkr (disk, mount, and storage-health substrate) | Target retention follows the source class, but current configurations differ. | **Current:** encrypted off-site history has configured rotation, while Mimir's NAS artifact backup is append-only/no-delete and may preserve removed files indefinitely; there is no cross-store erasure coordinator. **Target:** add an explicit NAS retention decision, prove expiry timing where expiry exists, and prevent restores from silently resurrecting expired records. |
| M5 capability ledger | Operational evidence; possibly payload-derived artifacts | `gille-inference` | Verdict and routing evidence use the operational-telemetry default. Payload-derived fixtures use the transient default unless explicitly promoted as an eval asset. | **Current:** operator-managed removal/redaction only; the provisional windows are not enforced. **Target:** six-month evidence and 30-day payload-fixture expiry while retaining only the minimum aggregate routing evidence. |

## Erasure workflow

1. Identify the authoritative store and any derived copies using the map above.
2. Check for a narrow statutory, contractual, incident, or legal-hold exception.
3. Use the authoritative store's **current** mechanism first. If no safe mechanism exists, record
   the request as blocked; do not substitute an unimplemented target from the table.
4. Where a safe mechanism exists, remove known derived live copies and record when backup expiry
   will complete.
5. Emit a minimal audit record containing the request scope, stores attempted, completed/blocked
   result, and any expiry date—never the erased content itself.
6. Verify completed actions through readback/search. Keep blocked stores open as unresolved work;
   do not report whole-request erasure as complete.

Automatic pruning and missing erasure mechanisms must be implemented and tested by the owning repo.
This map alone does not authorize a deletion job or claim GDPR erasure is complete. It implements
the decision artifact for grimnir#66 and should shape correction/forgetting work without creating a
second lifecycle authority.

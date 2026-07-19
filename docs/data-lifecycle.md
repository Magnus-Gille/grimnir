# Data lifecycle

This is an engineering checklist, not legal advice. A deployment must choose retention periods based
on its users, contracts, jurisdictions, and recovery needs.

## Store map

| Store | Typical content | Owner | Required lifecycle capability |
|---|---|---|---|
| Munin Memory | durable context, task state, summaries | `munin-memory` | provenance, correction, deletion, namespace retention, backup expiry |
| Mimir | source files and generated artifacts | `mimir` | authoritative deletion, derived-copy discovery, backup expiry |
| Hugin | task input/output, journals, workspaces | `hugin` | short-lived workspace cleanup and explicit result promotion |
| Heimdall | metrics, alerts, status views | `heimdall` | bounded telemetry retention and payload minimization |
| Inference gateway | request metadata, routing ledger | `gille-inference` | prompt minimization, configurable logs, evaluation expiry |
| Audit sink | action and reversal evidence | deployment-specific | payload minimization, integrity verification, defined erasure strategy |
| Backups | encrypted copies of the stores above | `brokkr` plus store owner | rotation, deletion propagation, restore tests, key succession |

Optional chat or briefing adapters also need retention rules for messages, transcripts, drafts, and
cached source content.

## Required questions

For every store, document:

1. What data is collected, and which copy is authoritative?
2. What purpose justifies keeping it?
3. Which principal owns or can access it?
4. When does retention start and end?
5. How can a person inspect, correct, export, or delete it?
6. Which derived views, indexes, logs, and caches must follow a deletion?
7. How long does deleted data remain in encrypted backups?
8. What minimal audit evidence remains, and why?
9. Which legal hold or incident condition can pause deletion, who owns it, and when is it reviewed?

## Design rules

- Do not log full prompts, files, or model responses merely for convenience.
- Promote useful task output intentionally; treat workspaces and renderings as disposable.
- Keep durable memory separate from immutable audit evidence so correction does not require rewriting
  history.
- Minimize personal data in hash chains; immutability and erasure are otherwise in direct tension.
- Test lifecycle operations against backups and derived copies, not only the live primary store.
- Treat a documented target as incomplete until the owning repository has tests and an operator run.

# ADR-006: Improvement scope for the delegation loop

- **Status:** accepted
- **Date:** 2026-07-19
- **Decision owner:** Grimnir system architecture
- **Component reviewers required:** Hugin and `gille-inference`

## Context

“Improve models” has been used for several materially different activities: selecting a better
model, changing the prompt or harness around a model, and training new model weights. The deployed
capability ledger evaluates evidence and informs routing. It does not train, fine-tune, or mutate
model weights, and the current production corpus is neither sufficiently governed nor sufficiently
representative to imply otherwise.

## Decision

LearningTaskContract v1 includes two improvement classes:

1. **Route and roster selection:** use verifier-backed capability evidence to retain, freeze,
   remove, or prefer an existing model/configuration for a bounded task type.
2. **Prompt, harness, and tool-policy optimization:** run matched, one-axis experiments with
   independent verification, product-quality gates, reviewed deployment, and rollback.

**Model-weight training is not in v1.** It is a conditional future program, not a hidden extension
of harvesting and not an automatic use of task content. The capability ledger and harvested labels
remain evaluation/routing evidence unless a separately authorized export is created.

Promotion is deliberately manual. `promotion-ready` means the evidence gate passed; it does not
authorize Hugin or the gateway to edit configuration, deploy code, replace a champion, or train a
model. The owning repository's human operator applies the exact reviewed reference and records the
result.

## Gate for a future weight-training program

A separate ADR and implementation program may bring weight training into scope only after all of
these gates have explicit evidence:

- **Purpose and consent:** each training use is named in `governance.allowed_uses`; operational or
  evaluation permission is not reinterpreted as training permission.
- **Privacy and lifecycle:** sensitivity ceilings, data minimization, subject correction/erasure,
  retention expiry, deletion propagation, and backup expiry are implemented and tested.
- **Dataset construction:** governed export, immutable provenance, license/ownership checks,
  semantic and exact deduplication, contamination checks, and task/source stratification exist.
- **Volume and representativeness:** a predeclared minimum sample size and coverage by task type are
  met; repeated prompts, one operator, or success-only samples are not presented as representative.
- **Splits and leakage:** train/validation/holdout splits are source- and lineage-aware, frozen
  before training, and checked against inference exposure.
- **Training reproducibility:** base artifact, method (for example SFT/LoRA/DPO), code, seed,
  hyperparameters, compute, and output artifact digest are reproducible.
- **Independent evaluation:** the candidate clears task-specific deterministic/product gates,
  safety/privacy regressions, capability regression suites, and a holdout not used for training or
  selection.
- **Deployment and rollback:** canary scope, owner approval, artifact signing, serving config epoch,
  monitoring window, stop conditions, and return to the prior artifact are proven.

Until a future ADR names numeric gates and the owner approves training use, no component may export
task content for weight training or describe a ledger/routing update as model training.

## Consequences

- Hugin may optimize the task-facing prompt, harness, tool policy, and macro-routing through its
  controlled experiment process.
- `gille-inference` may update capability evidence, micro-routing, and the deployed model roster
  through its guarded process.
- Both must preserve exact identities so changes can be attributed to one tested axis.
- Task labels and corrections remain valuable even when no challenger is promoted.
- “The system learned” and “the model was trained” are distinct claims in documentation and UI.

## Revisit trigger

Revisit only when there is a concrete weight-training objective plus evidence that the privacy,
data-volume, split, evaluation, deployment, and rollback gates above can be met. Interest in a new
fine-tuning tool or unused local compute is not by itself a trigger.

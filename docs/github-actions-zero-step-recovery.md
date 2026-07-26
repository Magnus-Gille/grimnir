# GitHub Actions zero-step recovery

`scripts/github-actions-zero-step-preflight.sh` is the read-only diagnostic for
the failure shape in grimnir#138. It differentiates a job that did not start on a
runner from a workflow that reached a test step; it is not a CI bypass and cannot
make a blocked pull request mergeable.

```sh
scripts/github-actions-zero-step-preflight.sh diagnose \
  --repo Magnus-Gille/skuld --run 30180932068 --job 89737176794
```

The command makes exactly two GitHub API GETs (the nominated run and job), emits
one public-safe key/value alert record, and exits without a retry, poll, rerun,
dispatch, comment, or any other GitHub mutation. Consumers deduplicate on the
single `alert_key` field and emit that record once. In particular, they must not
wrap it in a retry loop. `run_id`, `job_id`, and `affected_pr` occur once each so
an owner can act on the exact evidence.

| Exit | Class | Meaning |
| --- | --- | --- |
| 0 | `workflow_succeeded` | The nominated job completed successfully. |
| 10 | `zero_step_runner_startup_or_capacity` | The job completed without any steps; no test failure was observed. |
| 11 | `run_not_completed` | The nominated run/job is still current; wait rather than rerun. |
| 13 | `github_api_unavailable` | Diagnostic evidence could not be retrieved. |
| 14 | `malformed_api_evidence` / `evidence_mismatch` | Do not infer a cause from inconsistent API data. |
| 20 | `workflow_step_failure` | At least one workflow step existed; investigate that workflow failure. |

## Owner recovery action

For exit 10, GitHub’s run/job API establishes only the symptom. It does **not**
expose the account-level Actions billing, spending-limit, payment, or runner
allocation decision that produced it. The authoritative recovery action is for
the GitHub account owner to open the private repository’s **Settings → Billing
and licensing → Plans and usage**, verify that Actions is enabled and that the
account has an active payment method and usable Actions spending/credit limit,
then check the Actions settings for any owner-managed runner/allocation policy.

After the owner has restored capacity, manually rerun the exact blocked revision
once. Merge only when a new Actions run contains real completed steps and passes;
local green tests and this diagnostic are supporting evidence, never a substitute
for the protected GitHub CI gate. If the billing UI is healthy, retain the
diagnostic record and escalate it to GitHub Support as runner allocation evidence.

## Validated evidence

On 2026-07-26, `Magnus-Gille/skuld` PR #15’s run `30180932068` / job
`89737176794` completed in five seconds with `steps: []`, `runner_id: 0`, an
empty runner name, and a 22-byte empty ZIP log archive. The same signature was
recorded for Verdandi PR #25 (run `30045605392`, job `89335895570`, plus one
controlled zero-step rerun) and Ratatoskr PR #53 (run `30065051489`). This is why
the classifier reports runner startup/capacity—not a test failure—while leaving
the authoritative billing/allocation cause for the owner UI.

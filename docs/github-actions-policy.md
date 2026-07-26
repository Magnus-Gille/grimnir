# GitHub Actions provenance and runtime policy

Grimnir owns the read-only fleet policy for GitHub Action pins, release provenance, and runtime
claims. The audit inventories every workflow in the repositories registered by
`services.json.repository_authority`; it never edits an owning repository.

Run the live fleet audit from an authenticated operator checkout:

```bash
node scripts/github-actions-policy.mjs --format text
node scripts/github-actions-policy.mjs --format json
```

The helper uses `GH_TOKEN` or `GITHUB_TOKEN`, falling back to `gh auth token`. The credential needs
read access to every registered private repository that should be audited. It enumerates the exact
default-branch Git tree under `.github/workflows/`, rather than relying on the Actions API's visible
workflow list, so disabled and otherwise non-API-visible workflow files are still included. A
repository or upstream Action that cannot be read is an error, not a silent skip.

## Policy

Every remote `uses:` entry must:

1. use a full 40-hex commit SHA;
2. carry a same-line semantic release tag, for example
   `uses: actions/checkout@<40-hex-sha> # v7.0.1`;
3. have that tag resolve to the exact pinned commit upstream; and
4. expose an exact pinned `action.yml` or `action.yaml` whose `runs.using` is approved.

Approved Action runtimes are `node24`, `composite`, and `docker`. Remote reusable workflows are
verified at their exact pinned path and are runtime-not-applicable. Node 20 is a dedicated policy
error; absent or unrecognized runtimes fail closed as unknown. Repository-local `./...` Actions are
read from the same audited repository snapshot and receive the same runtime check. `docker://`
references fail the GitHub commit-pin policy because they cannot provide the required GitHub
repository SHA and release-tag evidence.

The local `make test` gate runs Grimnir's actual workflow files through the same parser with the
reviewed provenance fixture in
`tests/fixtures/github-actions-policy/grimnir-upstream.json`. That cheap owning-repository check
prevents a PR from casually reintroducing a floating pin, stale comment, or unapproved runtime.
The live fleet audit remains the authority for resolving those recorded tags and manifests against
current upstream GitHub evidence.

## Findings and unavailable evidence

Findings are deterministic and routed to `owner_repo`, the repository that must fix its workflow.
Policy findings describe a proven violation:

- `floating-action-ref`
- `missing-release-provenance`
- `upstream-tag-sha-mismatch`
- `action-runtime-node20`
- `action-runtime-unknown`
- `invalid-local-action`

Evidence findings mean the audit could not prove compliance:

- `workflow-inventory-unavailable`
- `upstream-tag-unavailable`
- `action-manifest-unavailable`
- `local-action-manifest-unavailable`

Evidence findings carry a separate `evidence_reason`: `billing`, `transport`, `authentication`,
`permission`, `rate-limit`, `not-found`, `upstream`, or `unknown`. In particular, a private
repository affected by Actions billing is not mislabeled as a pin or runtime policy violation.
Unknown upstream evidence still makes the audit fail closed.

Exit status is `0` only when both policy and evidence are clean, `1` when findings exist, and `2`
for local usage/configuration errors.

## Disclosure boundary

The implementation reads private workflow bytes only in memory. Output contains aggregate counts
and the minimum routing metadata needed to fix a finding: owning repository, workflow path, line,
normalized Action identity, finding code, and evidence reason. It never prints workflow content,
commands, environment values, API error bodies, raw credentials, or private transport locators.
Hermetic fixtures assert this boundary with sentinel content and also cover floating tags, missing
and stale provenance, tag/SHA mismatch, Node 20, Node 24, unknown runtimes, unavailable upstream
evidence, and distinct billing/transport failures.

## M5 dogfood evidence

A bounded Mellum acceptance-coverage check ran through M5 `/delegate` with verified JSON output
(ledger `9aeb1e3e-8865-4d8a-b156-56e5a8f07f06`). The call itself was fast and mechanically valid,
but its three proposed gaps confused workflow pins with manifest fields, placed owner routing in
upstream manifests, and overlooked the byte-for-byte determinism test. None were adopted. This is
useful routing evidence: M5 handled the requested shape cheaply, but the final policy judgment still
required repository-grounded review.

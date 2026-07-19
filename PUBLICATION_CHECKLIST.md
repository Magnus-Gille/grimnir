# Publication checklist

Use this checklist before changing repository visibility or announcing a release.

## Repository content

- [ ] `README.md` explains purpose, maturity, setup, security boundaries, and relation to the other
      Grimnir repositories.
- [ ] A permissive license, contribution guide, and private vulnerability-reporting path exist.
- [ ] Examples use fictional domains, addresses, accounts, paths, identifiers, and payloads.
- [ ] Live `.env`, local registries, status files, logs, traces, exports, benchmarks based on user data,
      generated snapshots, database files, and recovery material are ignored and untracked.
- [ ] Optional or private integrations are clearly labeled and are not required to understand the
      public core.

## History and metadata

- [ ] Scan the complete git history, every branch, and every tag with a current secret scanner.
- [ ] Search history for private hostnames, network addresses, email addresses, customer/client terms,
      personal paths, operational logs, and generated data—not only credential-shaped strings.
- [ ] Review GitHub issues, pull requests, releases, Actions artifacts/logs, packages, wikis, project
      boards, and repository variables separately; a clean git tree does not cover them.
- [ ] If history must be rewritten, coordinate it as a separate destructive operation, invalidate old
      clones/artifacts, and rotate any exposed credential. Rewriting history does not un-disclose data.

## Verification

- [ ] Install from a clean clone using only documented steps.
- [ ] Run tests, type checks, builds, linters, dependency audit, and a current-tree secret scan.
- [ ] Check all local documentation links and any published examples.
- [ ] Confirm default configuration fails closed and does not expose a service or deploy example data.
- [ ] Obtain an independent security and maintainability review of the final diff.
- [ ] Record known limitations and create owning-repository issues for deferred work.

Repository visibility should change only after this checklist is completed for every repository in the
release set.

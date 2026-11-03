# Stable node discovery and private operational mappings

Grimnir owns intended node/workload identities, ports and unit contracts. Brokkr
owns dated physical observations. The operator owns the permitted transport and
host-local paths. None of these records authorizes a connection or mutation.

## Retrieval order

1. Start with the routed ticket's `node_id` and evidence reference. For the
   BROKKR-136 Pi evaluation the stable identity is `node-huginmunin`; its original
   mandate is Munin Memory's `docs/embeddinggemma-2-testmandat-2026-10-12.md`.
   BROKKR-170 contains the later, dated substrate audit. A historical model/RAM
   statement is not a current physical measurement.
2. Read `services.json` for intent and owning repositories. Its `public-v1`
   profile uses `<node-id>.invalid` and reserved example paths. They are not
   operational addresses. Do not try connecting to them or infer an SSH alias.
3. Consult the explicitly configured `GRIMNIR_OPERATIONAL_MAP`, or the documented
   owner-local index `~/.config/grimnir/operational-map.json`. This is a single
   known configuration location, not permission to search directories, SSH
   credentials, environment files or Brokkr's secret-bearing inspect overlay.
4. Run `node scripts/resolve-node.js node-huginmunin`. Default output contains
   stable identity, configuration status and dated evidence references only.
   `--private` additionally returns the exact configured SSH target and hardware
   evidence for an already-authorized operator action. Capture that machine
   output privately; never paste it into public logs, Git or tickets.

Missing, duplicate, unknown, stale or malformed bindings are explicit nonzero
diagnostics. `MAP_STALE` means the exact public-registry bytes changed; reconcile
the private mappings against the new intent before rebinding. `EVIDENCE_STALE`
means the observation exceeds the discovery reader's 24-hour freshness cap.
An observation more than five minutes in the future is invalid. Refresh evidence
through an existing authorized operator route; do not manufacture a timestamp or
ask the owner for facts already available in the named evidence. Hardware data
does not grant transport or deployment authority.

## Owner-only map contract

The map must be a regular, non-symlink, single-link file owned by the current user,
mode `0600`, at most 1 MiB. Reads use the opened descriptor, check metadata before
and after reading, and reject changed files. Errors contain fixed reason codes,
not file contents or private paths. The map contains operational metadata, never
passwords, API tokens, private keys or recovery material.

- `version`: `1`.
- `public_registry_sha256`: SHA-256 of the exact public `services.json` bytes.
- `deploy_user`: explicit operator POSIX identity; no inferred replacement account.
- `local_node_id`: this operator context's stable identity.
- `nodes`: unique registered `node_id` entries with private `hostname`,
  `ssh_alias` and an explicit `user@host` `ssh_target`. The private hostname is the
  existing runtime consumer's locator; `ssh_target` is the operator transport.
  No automatic alias or account substitution is performed by discovery.
  Optional `hardware`/`notes` preserve legacy metadata for private consumers;
  they are not observed hardware evidence.
- `hardware_evidence`, within a node: `observed_at` (UTC), `source_ref` (owning
  `BROKKR-N` ticket), `model`, `architecture`, and `memory_mib`. The operator must
  bind these to the dated Brokkr observation; the resolver checks structure and
  freshness, not physical hardware. OS `MemTotal` means usable RAM, not an exact
  installed-memory specification.
- `components`: registered names with finite overrides for `deploy_path`,
  `persistent_paths`, `systemd_runtime`, `external_environment_files` and the
  hostname portion of `health_check`. Relative persistence entries and health
  policy remain unchanged. Structure/cardinality of private path lists must
  match public intent.
- `owning_repo_deployments`: registered names with `release_root`,
  `deployed_marker` and the private path portion of `coupled_state`.

The map cannot change repositories, ports, units, deployment enablement,
placement, health boundary/path or coupled-state field selection. Unknown keys,
identifiers and duplicate mappings fail closed. The existing complete registry
validator checks materialized runtime records before operational use.

## Consumer compatibility and migration

`QUERY=nodes`, `nodes-json`, `all`, `json:*`, `scan`, `components`, `systemd`,
`ports` and `repository-authority` keep their public shapes and do not open the
private map by default. Public node metadata deliberately omits physical details
and operator notes. `QUERY=deploy`, `validate` and `owning-deploys` require a
complete matching private map for a `public-v1` source. Deploy targets come from
the explicit SSH mapping, and the deploy user must agree with that mapping.
There is no `.local`-to-bare-name retry for this profile.

`REGISTRY_VIEW=operational` explicitly requests a private projection for other
queries. `QUERY=runtime-json` emits the complete legacy runtime registry shape,
without the public-profile marker, for direct-file consumers. This output is
private configuration. Store it only in a new owner-only file outside Git, check
the command's exit status and validate it before configuring a consumer's
existing `REGISTRY_PATH`. Never overwrite an existing operational configuration
as an incidental export step. An explicit legacy private runtime registry remains
supported; it is not a public projection.

Before upgrading any host-side consumer to a public registry, prepare its private
map/export and prove equivalent runtime fields, then apply that configuration
only under the owning deployment mandate. Do not replace a live registry with
reserved examples. This source change neither deploys those configurations nor
changes any host. Scanner repository discovery and public placement checks do
not need live locators. Placement validation consumes public intent only.

The architecture generator requires an explicit control-node context from the
map and uses its runtime bindings. Generated `snapshot.md`/`full-architecture.md`
remain private, ignored operational artifacts; curated `architecture.md` is the
public design view. A successful config lookup is not a live health result.

## Routed tickets and continuation

Hardware/evaluation tickets carry a stable node ID, owning repository and a safe
source/evidence reference. Munin may retain these retrieval pointers, not another
copy of addresses or an independent topology inventory. A fresh session follows
the ticket → registry → dated evidence → named private map chain before asking
the owner. If a prerequisite is absent, report its fixed reason and missing
evidence precisely. Existing review, exact release binding, credential and
owner-attended recovery gates remain unchanged.

Verification: `make test-operational-registry`, registry/placement/architecture
guards, deploy/systemd/persistence regressions, and the repository's full checks.
Reversal is a reviewed source revert plus separately authorized restoration of
the prior private configuration; no history rewrite or destructive data restore.

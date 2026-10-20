# Specification: `scripts/deploy-search-reader.sh` (mimir repository)

Status: specification for a separate mimir-repository implementation session.
Owner of the script: `mimir`. Owner of the registration and the source-identity
boundary: Grimnir (`services.json` `owning_repo_deployments`
entry `mimir-search-reader`, executed only through `scripts/guarded-deploy.sh`;
see [`../deployment-source-binding.md`](../deployment-source-binding.md)).

This document is a contract, not an authorization. Running the script against
`node-m5` is a production mutation: it needs just-in-time confirmation of the
exact SHA and target, or a bounded release mandate, as defined by the owner-wide
policy. The script grants nothing and must not read, print or copy credentials.

## 1. Scope

In scope: upgrading the already-installed Mimir search **reader** runtime on
`node-m5` (ssh alias `m5`, user `magnus`) to one exact, merged mimir commit, and
updating the Mac client pin in the same rollout.

Out of scope (the script must not touch any of these):

- First installation and bootstrap (units absent on the target are a preflight
  failure; the first-install procedure stays in `docs/artifact-search-operations.md`).
- The NAS publisher (see section 11).
- `runtime.env`, `reader.json`, `heimdall.env`, `handoff.json`, the state
  directory (`~/.local/state/mimir-search`), the vector cache, and any credential,
  edge (Cloudflare) policy, or other service on either host.
- The gateway re-pin (`ops repin-embedding`). It is a separate operator step.
- Deleting old release directories. Retention is manual and needs separate scope.

## 2. Registered contract (Grimnir side)

```json
{
  "name": "mimir-search-reader",
  "repo": "mimir",
  "target_node_id": "node-m5",
  "command": ["./scripts/deploy-search-reader.sh"],
  "revision_argument": "--release",
  "release_root": "/home/magnus/.local/share/mimir-search/releases",
  "deployed_marker": "/home/magnus/.local/share/mimir-search/.deployed-commit",
  "loopback_port": 8791,
  "systemd_units": ["mimir-search (service)", "mimir-search-refresh (timer)", "mimir-search-semantic-check (timer)"],
  "coupled_state": [{"node_id": "node-laptop", "home_relative_path": ".config/mimir-search/client.json", "fields": ["release", "package_sha256"]}]
}
```

The executor therefore runs, from the bound worktree:

```sh
/path/to/grimnir/scripts/guarded-deploy.sh <worktree> <sha> -- \
  ./scripts/deploy-search-reader.sh --release <sha> [optional flags]
```

If the script's path, `--release` option, release root, marker path, port, or unit
set changes, the Grimnir registration must change first (or in the same
reviewed change). Do not let the two drift.

## 3. Interface

```text
scripts/deploy-search-reader.sh --release <40-hex-sha> [options]
```

| Argument | Required | Meaning |
|----------|----------|---------|
| `--release SHA` | yes | Exact 40-char lowercase hex commit (reject 64-char/abbreviated/ref names). Same SHA the guard bound. |
| `--dry-run` | no | Run every preflight, build twice, render units, and print the plan and unit diff. Performs only read-only ssh commands. No remote write, no marker change, no pin change. |
| `--rollback` | no | Restore the pre-deploy state recorded for `--release` (section 9). Requires the journal of that deployment. |
| `--no-auto-rollback` | no | On failure, stop and leave the system as-is for diagnosis (marker stays absent). Default is automatic rollback (section 8). |
| `--host ALIAS` | no | ssh alias of the reader node. Default `m5`. Must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Never a user-supplied command. |
| `--client-pin PATH` | no | Mac client pin. Default `~/.config/mimir-search/client.json`. |
| `--acceptance-config PATH` | no | Independently approved acceptance pins (section 6.3). Default `~/.config/mimir-search/deploy-acceptance.json`. |
| `--state-dir PATH` | no | Local deploy journal root. Default `~/.local/state/mimir-search-deploy`. |

Rules:

- Unknown arguments, a missing `--release`, `--dry-run` combined with
  `--rollback`, or a non-canonical path fail with exit 2 before any work.
- No option may carry a secret. Credentials come only from the private files the
  runtime already uses; the script reads them inside the remote shell or a
  `0600` local file and never places them in argv, environment passed to ssh,
  logs, the journal or `set -x` output. The script must not enable `xtrace`.
- The script runs unchanged by `guarded-deploy.sh` (which `exec`s it). It still
  performs its own source check (6.1), because the guard proves the invocation
  identity but not that the tree is clean or merged.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Deployed and accepted, or already deployed and live-verified (no-op), or rollback accepted. |
| 2 | Usage error. Nothing touched. |
| 3 | Preflight failed. Nothing on the target was changed. |
| 10 | Deploy failed after mutation; automatic rollback restored and verified the previous state (previous marker restored, or absent if none existed). |
| 11 | Deploy failed and the target state is unknown or rollback failed (or `--no-auto-rollback`). Marker is absent. The journal path is printed. |

## 4. Local state and locking

- The journal lives under `--state-dir/<sha>/` (directory `0700`, files `0600`,
  outside the repository and outside any synced tree). It stores: phase log,
  previous release SHA and package SHA-256, copies of the previous unit files
  (with SHA-256 each), the previous client-pin file, the previous marker value
  (or `absent`), the built package SHA-256, the rendered unit SHA-256 set, and
  the health/retrieval receipts used for acceptance. No credential may be
  written to it.
- Locking: an exclusive `flock`-style lock on a local lock file in `--state-dir`
  and an exclusive remote lock on
  `~/.local/state/mimir-search-deploy.lock` on the reader for the full run. A
  held lock is a preflight failure (exit 3), never a wait.
- Temporary build/render directories are created with `mktemp -d` (`0700`),
  outside the worktree, removed on exit by a `trap`, except the journal.

## 5. Exact steps

Phases are named so the journal and tests can refer to them. Each phase begins
by re-checking the live state it depends on; the journal is a hint, never proof.

### Phase A: preflight (read-only; any failure is exit 3)

A1. Source identity (local). Cheap and independent of the Grimnir guard:

- `--release` is a full 40-hex SHA.
- `pwd -P` equals `git rev-parse --show-toplevel` (run from the worktree root).
- `git rev-parse HEAD` equals `--release`.
- The working tree has no tracked modification and no untracked non-ignored
  file (`git status --porcelain=v1 --untracked-files=normal` is empty).
- The SHA is reachable from `origin/main` (`git ls-remote` to read the remote
  tip, then `git merge-base --is-ancestor <sha> <fetched origin/main>`), so only
  merged, reviewed code deploys. Unreachable origin fails closed. There is no
  override flag.
- Print `Expected source: <worktree> @ <sha>` and `Actual source: <root> @ <HEAD>`
  in the same format as the Grimnir guard.

A2. Local toolchain: `python3` runs `-m tools.artifact_search.package_runtime
build --help` and `-m tools.artifact_search.service_units --help` from the
worktree; `ssh`, `scp` or `rsync -e ssh`, `shasum`/`sha256sum`, `flock` or
equivalent, `cmp` exist.

A3. Remote reachability and identity (`ssh -o BatchMode=yes -o
ConnectTimeout=10 <host>`): remote user is `magnus`, `$HOME` is a canonical
absolute path (use it as `--home`; it must equal the registered
`/home/magnus` prefix of `release_root`), `systemctl --user` is reachable
(`XDG_RUNTIME_DIR` present), lingering is enabled (`loginctl show-user magnus
-p Linger` = `yes`), `/usr/bin/python3` exists and is the interpreter the
rendered units invoke.

A4. Installed-state expectations (upgrade-only): `mimir-search.service`,
`mimir-search-refresh.service/.timer`, `mimir-search-semantic-check.service/.timer`
exist under `~/.config/systemd/user`. Parse the currently installed
`Environment=MIMIR_SEARCH_RELEASE=` and package path from `mimir-search.service`
to learn the **previous release**; require it to be a 40-hex SHA whose
`releases/<prev>/search.pyz` exists (`0600`, dir `0700`, owner `magnus`) and
hash it (previous package SHA-256). Missing or unparsable: exit 3 (not an
upgrade; the first-install flow applies).

A5. Private configuration present, with modes checked and contents never read
or printed: `~/.config/mimir-search/runtime.env` (`0600`), `reader.json`
(`0600`), `handoff.json` (exists; the refresher owns it), parent directories not
group- or world-writable.

A6. Client pin (local): `--client-pin` exists, is a regular file (not a symlink),
`0600`, parent directories not group/world-writable, valid JSON object with
string fields `release` (40-hex) and `package_sha256` (64-hex). Record both
values. If they do not equal the previous release and its package hash, record
and print the drift (rollback restores the file exactly as found).

A7. Acceptance config (6.3) present, `0600`, and well formed.

A8. Idempotency probe: if the remote marker equals `--release`, run the
read-only live acceptance subset (section 7, items 1, 3-5 without writing the
marker, plus unit-byte equality and pin equality). If it all passes, print
`already deployed and verified`, exit 0 without mutation (marker untouched). If
anything fails, print the drift and continue as a normal deploy; an old marker
is never trusted over live state.

A9. Release directory: if `releases/<sha>/` exists, it must hold
`search.pyz` (`0600`) whose SHA-256 equals the locally built package (checked
after Phase B) and nothing else unexpected; otherwise exit 3. A release
directory is immutable and is never overwritten.

A10. Baseline capture (informational, recorded in the journal): the
`mimir-search-semantic-check` result, current listeners owned by
`mimir-search.service`, and `systemctl --user is-active` for each unit.

A11. Remote free space on the release filesystem is at least twice the package
size.

### Phase B: build and render (local, no remote writes)

B1. Build the package twice into two different empty `0700` temp paths:

```sh
python3 -m tools.artifact_search.package_runtime build \
  --release <sha> --repo "$PWD" --package "$TMP/build-1/search.pyz"
python3 -m tools.artifact_search.package_runtime build \
  --release <sha> --repo "$PWD" --package "$TMP/build-2/search.pyz"
```

The two files must be byte-identical (`cmp -s`) or exit 3 (not reproducible).
Compute `package_sha256` once. Run the trusted verifier on the artifact:

```sh
python3 -m tools.artifact_search.package_runtime verify \
  --release <sha> --package "$TMP/build-1/search.pyz" --sha256 <package_sha256>
```

B2. Render the reader units (run from the worktree at the SHA):

```sh
python3 -m tools.artifact_search.service_units --role reader \
  --home <remote-home> --release <sha> --output-directory "$TMP/units"
```

The output directory must not pre-exist (the renderer creates it `0700`). Expect
exactly the five files: `mimir-search.service`, `mimir-search-refresh.service`,
`mimir-search-refresh.timer`, `mimir-search-semantic-check.service`,
`mimir-search-semantic-check.timer`. Any other file set is exit 3. Record each
file's SHA-256 and print a unified diff against the installed units.

`--dry-run` stops here after printing the plan (release, package SHA-256, the
unit diff, the pin change, and the exact remote commands it would run).

### Phase C: stage on the target (additive, does not change the running service)

C1. Create `releases/<sha>/` mode `0700` (`umask 077`) if absent; copy the
package to `releases/<sha>/.search.pyz.<pid>` then set `0600` and `mv` it to
`search.pyz` (same-directory rename). If `search.pyz` already exists with the
same SHA-256, skip the copy. Different content: stop (exit 3 if before any
active change, otherwise treat as failure in Phase D+).

C2. Hash the remote file; it must equal `package_sha256`.

C3. Copy the rendered units to a staging directory on the target
(`~/.local/state/mimir-search-deploy/staging/<sha>/`, `0700`) and hash them
remotely. Do not touch `~/.config/systemd/user` yet.

C4. Journal: copy the **currently installed** five unit files and the current
marker value (or `absent`) into the journal. Verify each copy against the
remote hash.

### Phase D: switch (first mutation of active state)

D1. **Invalidate the marker**: remove `.deployed-commit` on the target (atomic
`rm -f`; confirm absent). If the outcome of this step is indeterminate, stop
and report marker state `unknown` with exit 11, taking no further action. Do
not proceed to D2 with an unconfirmed marker.

D2. Stop activity that could race the switch, in this order:
`mimir-search-refresh.timer`, `mimir-search-semantic-check.timer`, then
`mimir-search.service` ("stop the service before switching packages"). Wait for
the units to be `inactive`.

D3. Install the staged unit files into `~/.config/systemd/user`: for each file,
write `name.new.<pid>` in the same directory with mode `0644`, then `mv -f` to
`name`. Compare the installed bytes to the rendered SHA-256 set. Run
`systemctl --user daemon-reload`.

D4. Run the initial refresh to completion before the runtime starts:
`systemctl --user start mimir-search-refresh.service` (oneshot; blocks until
done; non-zero is failure). Confirm `handoff.json` mtime advanced and the unit
result is `success`.

D5. Start: `systemctl --user enable mimir-search.service
mimir-search-refresh.timer mimir-search-semantic-check.timer`, then
`systemctl --user restart mimir-search.service` and
`systemctl --user start mimir-search-refresh.timer
mimir-search-semantic-check.timer`. Wait (bounded, for example 60 seconds) for
`mimir-search.service` to be `active (running)` and the loopback port to
answer.

### Phase E: server-side acceptance (still without changing the client pin)

All checks in section 7 items 1-5. Any failure goes to section 8.

### Phase F: client pin update (coupled state)

F1. Re-read the pin file; if it differs from what Phase A6 recorded, abort to
section 8 (someone edited it mid-run; never clobber).

F2. Write the new pin atomically: preserve every other field, set only
`release` and `package_sha256`, write to a temp file in the same directory with
mode `0600`, `fsync`, `mv -f`. Never follow a symlink. The previous file bytes
are already in the journal.

F3. Client-side acceptance (section 7 items 6-7).

### Phase G: commit the marker

G1. Re-verify source identity (A1 again: HEAD still equals `--release`, tree
still clean). A change since Phase A is a failure.

G2. Write the marker on the target: content is the 40-hex SHA and a newline,
written to a temp file in the same directory (mode `0600`) and `mv -f`'d to
`.deployed-commit`. Read it back over ssh and require byte equality.

G3. Optionally write `~/.local/share/mimir-search/.deployed-receipt.json`
(`0600`, same atomic method) holding `{release, package_sha256,
unit_sha256_set, accepted_at_utc, previous_release}` as an audit aid. The marker
alone is authoritative.

G4. Print the summary (release, package SHA-256, previous release, journal
path, marker path) and exit 0. The marker is the **last** write; no step after it
can fail the deployment.

## 6. Acceptance inputs

### 6.1 Source identity

See A1/G1. The marker is only ever written for the SHA whose tree built the
package and rendered the units in this run.

### 6.2 Credentials

`MIMIR_SEARCH_API_KEY` is read only on the reader inside the remote shell from
`runtime.env` (or by the existing client from its private config) and used to
authenticate the health and `/search` probes. It never appears in an argument,
an exported variable passed through ssh, a log, the journal, a receipt or a
test fixture. Pass multi-line remote scripts on stdin to `ssh <host> bash -s`
rather than building command strings from variables. Quote every
interpolated value; only fixed, validated tokens (SHA, alias, path) may be
interpolated.

### 6.3 Approved acceptance pins

`--acceptance-config` (JSON, `0600`, outside the repository) supplies the
independently approved values, because `package_runtime verify` must compare
against pins that did not come from the system under test:

```json
{
  "schema": "mimir-search-deploy-acceptance-v1",
  "source_id": "<approved source UUID>",
  "snapshot_id": "<approved snapshot pin>",
  "known_hit": { "query": "<query text known to hit>", "expected_path": "<archive path>", "expected_sha256": "<original bytes hash>" },
  "no_hit": { "query": "<query text known to have no answer>" }
}
```

The script fails closed (exit 3) when the file is missing, has other fields, or
any value is empty. Changing the approved source or snapshot is an owner
decision made outside this script.

## 7. Acceptance checks

All must pass. Evidence is saved in the journal. Run in this order.

1. **Package verify with receipts.** On the reader, capture authenticated
   `/health` and a successful `/search` for the known-hit query into private
   files (`0600`), then, locally with the receipts copied to the `0700` temp
   directory:

   ```sh
   python3 -m tools.artifact_search.package_runtime verify \
     --release <sha> --package "$TMP/build-1/search.pyz" --sha256 <package_sha256> \
     --health-json <health.json> --retrieval-json <retrieval.json> \
     --snapshot-id <snapshot_id> --source-id <source_id>
   ```

   The verifier rejects stale (older than 30 seconds) or mismatched receipts,
   so capture immediately before verifying. HTTP 200 or a running process is not
   evidence.
2. **Unit and package integrity on the target.** Installed unit bytes equal the
   rendered set; `releases/<sha>/search.pyz` hash equals `package_sha256`;
   directory `0700`, file `0600`, owner `magnus`.
3. **Unauthenticated denial.** An unauthenticated `POST /search` to
   `http://127.0.0.1:8791/search` (run on the reader) returns HTTP 401. Any
   other status fails.
4. **Single loopback listener.** The set of TCP listeners owned by
   `mimir-search.service` (its cgroup PIDs; use `ss -Hltnp` and filter by those
   PIDs, because other services legitimately listen on the node) is exactly
   `{127.0.0.1:8791}`. A wildcard, IPv6 or other-port listener fails.
5. **Semantic check.** `systemctl --user start
   mimir-search-semantic-check.service` exits 0 and its latest journal result is
   state `pass` (parse the bounded `[mimir-search]` output). `warn` is retried
   once after 30 seconds; a second `warn`, or any `fail`, fails the deploy. A
   pre-existing gateway-drift `fail` blocks acceptance by design; the operator
   runs the re-pin step, then re-runs the deploy (idempotent).
6. **Client known-hit.** With the **new** pin in place, run the existing client
   (`scripts/mimir-search`, via its normal SSH path) for `known_hit.query`:
   success, provenance pins match the new `release` and `package_sha256`, and the
   top result carries `expected_path` and `expected_sha256`.
7. **Client no-hit.** The client runs `no_hit.query`: a well-formed empty/
   abstaining response with matching provenance, not an error, and not a
   result. (An empty result never certifies absence; this only proves the read
   path after the known hit.)

If implementing 6/7 requires a client mode the current client lacks, raise it as
a mimir issue; do not weaken the check.

## 8. Idempotency and partial-failure plan

Principles: reconcile live state before every phase; never repeat an external
mutation with an unknown outcome without reading it back; additive steps first,
active-state changes last; the marker is absent for the whole window in which
live state is not certified.

- **Re-running the same `--release`** is always safe. Phase A re-derives the
  previous release from live units. If the system already runs `--release`
  (units match, pin matches, acceptance passes) it is a no-op (A8). If a prior
  run died partway, the new run sees mixed state: it treats the **recorded
  journal's** previous-state copies as the rollback target if the journal exists
  and the live units still reference `--release` or the journal's previous
  release; otherwise (live state matches neither) it stops with exit 3 and asks
  for operator reconciliation rather than guessing.
- **Release directory and package** are immutable and content-addressed by SHA:
  re-copying is skipped when the hash matches and refused when it differs.
- **Unit installation** uses per-file atomic renames; a crash can leave a mix of
  old and new files. The journal copy of the previous set plus the rendered set
  let either direction be completed; byte comparison, not file presence, decides
  what is installed.
- **Marker**: removed at D1 before any active change; written only at G2. A
  crash anywhere between leaves it absent, which Grimnir validation and humans
  read as "not certified". An unconfirmed removal (D1) halts with `unknown`.
- **Failure handling by phase**
  - Before D1: nothing active changed. Exit 3 (or 2). Staged inert files may
    remain; they are harmless and reused on retry.
  - D1 onwards: default is automatic rollback (section 9, including the Phase F
    pin if already written). Success of the rollback is **proved** by acceptance
    of the previous state (previous package verify, 401, listener, semantic
    check, client queries with the restored pin), then the previous marker is
    restored (or stays absent if none existed) and the script exits 10. A rollback
    that cannot be proved exits 11 with the marker absent.
  - A failure in G (after acceptance) leaves the new state accepted but
    uncertified: do not roll back an accepted deployment merely because the
    marker write failed; retry G2 once (idempotent atomic write plus read-back);
    if it still fails, exit 11 with a precise "accepted but unmarked" message
    so a re-run (A8 path) can finish it.
  - Interruption (SIGINT/SIGTERM/ssh drop): a `trap` records the interruption in
    the journal and, if past D1, follows the same automatic-rollback decision,
    with the one-attempt rule for an indeterminate ssh result: read the live
    state back before repeating any mutation.
- **Transient failure retry**: retry an ssh/scp transport error once, never a
  mutation whose outcome is unknown. After three failed attempts on the same
  condition, stop and report.
- The script never deletes release directories, configuration, state, or
  journals.

## 9. Rollback

Recipe (must be printed in `--dry-run` and at the start of a mutating run):

1. Stop `mimir-search-refresh.timer`, `mimir-search-semantic-check.timer`,
   `mimir-search.service`.
2. Restore the previous unit files from the journal copies (verify each
   SHA-256 against the recorded value before and after). Remove any unit file
   the new render introduced that did not exist before (after disabling it),
   recording it.
3. Restore the client pin from the journal copy **only if** the live pin still
   equals what this deploy wrote (otherwise stop and report the conflict).
4. `systemctl --user daemon-reload`; start `mimir-search-refresh.service` and
   require success; start `mimir-search.service` and the timers.
5. Re-run acceptance against the **previous** release and package hash from the
   journal (section 7, using `package_runtime verify` with the previous values,
   plus 401, listener, semantic check, client known-hit and no-hit).
6. Restore the previous marker value, or leave it absent if none existed.
7. The new `releases/<sha>/` directory and the previous one are kept. Journal
   status becomes `rolled-back`.

`--rollback --release <sha>` performs this from the journal of the deployment of
`<sha>` (the guard binds the worktree to that SHA, so the script is available at
the revision being rolled back). It refuses if no journal exists, if the live
release is neither `<sha>` nor the journal's previous release, or if the
previous release directory is missing or its hash differs from the journal.
Verify during implementation that the trusted verifier accepts a previous
release's package; if it does not, the rollback must obtain a verifier from a
git worktree at the previous SHA instead.

If the journal is lost, a manual rollback is the documented operator procedure
in `docs/artifact-search-operations.md` ("Later upgrades retain a known-good
package/receipt"); add a pointer there.

## 10. Marker and source-identity binding

- **Marker file**: `/home/magnus/.local/share/mimir-search/.deployed-commit` on
  `node-m5`, containing exactly one lowercase 40-hex SHA and a newline, mode
  `0600`, written atomically. It lives outside `releases/` so no release can
  overwrite it.
- **Meaning**: "the units installed, `releases/<sha>/search.pyz` serving, and
  the Mac pin in effect were produced from `<sha>`, and every section 7 check
  passed against exactly that state." It is certification of acceptance, not
  of copied files.
- **Binding chain**: orchestrator-supplied accepted SHA -> Grimnir
  `guarded-deploy.sh` (worktree path and `HEAD` equal the expected values) ->
  the script's A1 (clean tree, reachable from `origin/main`) -> package built
  from `--repo` at that SHA (`--release` is baked into the package and verified)
  -> units rendered with the same `--release` -> acceptance verifies the running
  process reports that release and package SHA-256 -> G1 re-checks `HEAD` ->
  marker = that SHA. No step derives the SHA from the current checkout or the
  remote.
- **Lifecycle**: removed at D1, written at G2, restored (or left absent) by
  rollback. Absence means unknown.
- **Grimnir today** does not read this marker. A follow-up in Grimnir may add a
  read-only check that compares it with the units' `MIMIR_SEARCH_RELEASE`; until
  then the marker is operator evidence only and must not be described as fleet
  validation.

## 11. The NAS publisher (second component, not yet registered)

`mimir-search-publish.service` and `.timer` run on `node-nas`, rendered by the
same renderer with `--role publisher` from the same package family
(`packages/…/releases/<sha>/search.pyz`, publisher config `publisher.json`,
`0600`). It has a different target, acceptance (a publish succeeds and a fresh
30-minute handoff appears) and rollback, and its release should be kept
compatible with the reader. It is **not** covered by this script and has **no**
registry entry; /deploy must treat a publisher rollout as an uncovered contract
and stop. A follow-up mimir session may add `scripts/deploy-search-publisher.sh`
with a spec in the same shape; then Grimnir adds a second
`owning_repo_deployments` entry (`target_node_id: node-nas`).
Reader/publisher ordering for a coordinated release (publisher first when a
snapshot format changes) should be decided in that spec, not improvised here.

## 12. Implementation and test requirements (mimir session)

- Bash with `set -euo pipefail`, no `eval`, no `xtrace`, quoted expansions,
  `shellcheck` clean. Follow existing mimir script conventions
  (`scripts/deploy-nas.sh`).
- Hermetic tests with stubbed `ssh`/`scp`/`systemctl`/`python3` on `PATH`,
  following the style of Grimnir's `scripts/tests/deploy-*.test.sh`, covering at
  least: usage errors; every A1 failure (dirty tree, wrong HEAD, unmerged SHA,
  abbreviated SHA); non-reproducible build; renderer file-set mismatch;
  immutable release-directory conflict; no-op re-run; failure injected after
  each phase with the expected exit code, marker state and rollback result;
  indeterminate marker removal; pin edited mid-run; `--rollback` with and without
  a journal; proof that no credential value or `MIMIR_SEARCH_API_KEY` appears in
  captured argv, logs or the journal.
- Update `docs/artifact-search-operations.md` (upgrade procedure and operator
  rollback pointer), `docs/index.md`, and the mimir `AGENTS.md` deployment
  section to reference the script and the Grimnir-registered invocation.
- Run the mimir repository's normal checks (`npm test`, and the Python tests
  under `tools/artifact_search`).
- Acceptance of the implementation does not include running it against
  production; the first live rollout is a separately authorized deployment.

## 13. Grimnir follow-ups (not part of the mimir change)

1. Register the publisher entry once its entry point exists (section 11).
2. Optionally teach `grimnir-validate` to compare `deployed_marker` with the
   installed units' release (needs read access to `node-m5`; today the
   validator does not probe it).
3. Keep `services.json` and this contract in lockstep when the script path,
   release root, port or unit set changes.

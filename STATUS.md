# Grimnir System — Status

**Last session:** 2026-07-26 (Codex) — autonomous fleet ticket sweep, review, merge, deploy, and publish
**Latest system revision:** grimnir `ba6c5ed` (refreshed cross-service seam evidence)

## Current work

- **Brokkr #51** has a merged restricted storage-probe contract (PR #52), but the persistent
  production SSH identity is not configured and its creation requires explicit owner approval.
  Heimdall's fail-closed code half is also merged but intentionally not deployed.
- **Brokkr #53** owns the newly verified topology gap: Time Machine moved off NAS, so the NAS probe
  can restore disk/Munin/Mimir evidence but cannot prove Time Machine freshness on M5.
- **Skuld #14 / PR #16** is root-Codex + authenticated-M5 approved and passes 104 local tests, build,
  lint, and diff check. It cannot merge under the green-CI rule: GitHub Actions run `30187798237`
  failed twice with **zero executed steps**, including an explicit rerun. This is tracked in
  Grimnir #140.
- **Grimnir #140, #146, and Brokkr #44** need owner decisions: private-repo CI funding/runner
  posture, authoritative Munin unit path, and whether the deploy-profile acceptance may name its
  non-secret private locators.
- **Grimnir #79** remains open for fleet-wide enforcement. PR #166 completed the bounded named-seam
  refresh: Ratatoskr → Heimdall is verified; no active Verdandi emitter or grounded service-owned
  Munin status-shape defect was found, so no owner ticket was fabricated.
- Grimnir #139's central read-only GitHub Actions policy remains implemented. Its live fleet
  findings are routed to owning repositories.

## Autonomous fleet sweep — 2026-07-26

### Accepted, merged, and published

| repo | PR | merge | outcome |
|---|---:|---|---|
| gille-inference | #104 | `be77a8b` | dated fail-closed delegator cost catalogue; deployed and verified |
| gille-inference | #105 | `5dae436` | structural owner-only code-loop MCP contract; deployed and live-probed |
| gille-inference | #106 | `e33926f` | `code-edit` characterized as a measured gap; deployed, guarded route adoption published |
| heimdall | #43 | `fd75348` | readable Telegram task notifications; deployed and live-probed |

Gille's guarded routing publication adopted candidate
`sha256:08b08fe477b2dc567758600afb2b88387f6df7a5fac2a6d4b23112a556740427`.
`code-edit` remains frontier/null with truthful 1/15 evidence; no forced promotion occurred.
The same deterministic artifact moved `classify` and `extract` to Qwen on 9/9 evidence and added six
newly enumerated aliases as fail-safe frontier routes. Watchdog record
`2c5280bd-eb5a-4a5a-8e83-6873fefb0d6a` is pending its observation window; the immediate dry-run had
zero post-adoption samples and took no action.

### Accepted and merged; deployment intentionally withheld

| repo | PR | merge | outcome / deployment gate |
|---|---:|---|---|
| munin-memory | #289 | `b0b8bbf` | delete preview binds the complete lineage |
| munin-memory | #290 | `bba63cc` | idempotent status round-trip + lifecycle preservation |
| munin-memory | #291 | `f563413` | malformed query/list/CAS arguments now fail closed |
| munin-memory | #292 | `3129043` | preview-first, source-grounded manual consolidation |
| heimdall | #44 | `10686f1` | explicit restricted storage identity; #23 remains open for Brokkr #51 |
| grimnir | #166 | `ba6c5ed` | verified named seam evidence; #79 remains open fleet-wide |
| brokkr | #49 | `bd60261` | bounded maintenance controller |
| brokkr | #50 | `d59eaca` | safe library-only Debian mutation/evidence seam; #35 remains open |
| brokkr | #52 | `3681664` | content-bound restricted NAS probe contract; live identity approval pending |

All Munin deployments remain blocked by Grimnir #146's `/home` versus `/srv` unit-path authority
conflict. Heimdall #44 is withheld until Brokkr #51 supplies and verifies its restricted NAS
identity; deploying it earlier would expose a known critical state without restoring backup/storage
visibility. Brokkr #50 performs no live effects and deliberately refuses controller composition
until retry attempt IDs can be bound to immutable mutation journals.

### Evidence-only closure and genuine blockers

- Munin #287 was closed as not reproduced after production commitments/handoff evidence proved
  consistent; no patch was fabricated.
- Ratatoskr #57 closed via PR #59 / `73943d1`: a bounded production alert lifecycle proved
  absent → accepted/visible once → resolved once → absent. The committed record retains only
  timestamp/count/result metadata, so no runtime deployment was needed.
- Brokkr #44 conflicts with repository safety policy: its exact committed profile would contain
  private host/account/token-source locators forbidden in git. Owner must either approve those
  specific non-secret locators or revise acceptance to a committed schema/example plus untracked
  overlay.
- Brokkr #35 still needs the privileged adapter contract, exact apt/dpkg allowlist, workload
  ownership/health hooks, reboot continuation, retry-journal binding, and executable forward
  recovery.
- Brokkr #51's first implementation was rejected because it could install an arbitrary untracked
  “19-section” script and never executed the remote mutation body in tests. Accepted PR #52 instead
  tracks the fixed command, closes the config grammar, pins host keys, binds staged/installed
  digests, and executes apply/reapply/drift/revoke hermetically. The live credential mutation still
  requires owner approval.
- Gille #96 remains open for provider/billing decisions for unpriced models; #98 remains open for
  dedicated key naming/quota plus rotation/revocation evidence.

Every accepted PR in this sweep received exact-diff root Codex review, direct authenticated M5
review, and the repository's full available verification. Claude was unavailable due its monthly
limit, so the user-authorized Codex + M5 fallback was used.

## The headline

Heimdall was the session's centre of gravity and its open alerts went from **9 of unknown truth to 5,
all verified true**, then to a state where every remaining alert is either actionable or a known
miscalibration with a filed ticket. The root cause was not any single bug: **production Heimdall had
been running the committed *demonstration* config since the 2026-07-19 public release**, with RFC 5737
documentation addresses and demo host names. Backup and disk probes were dark for three days.

A second theme ran through the whole session: **the issue tracker is not evidence about the running
system, in either direction.** Four issues were open after their work was done; one (#69) asserted a
service was missing while it was running fine.

## Completed this session

### Merged and deployed

| repo | PR | commit | change |
|---|---|---|---|
| heimdall | #25 | `945847c` | alarm correctness + display reduction; deployed |
| grimnir | #148 | `0e03def` | audit exit semantics + fixed Munin reporting channel; live on Pi |
| grimnir | #150 | `87dfc6f` | deploy refuses a unit whose target contradicts `deploy_path` |
| brokkr | #43 | `99afdb3` | `pipefail` bug that silently aborted `maintenance-os` daily; deployed |
| hugin | #321 | `3be19f7` | Heimdall descriptor 7,754 → ~690 bytes; **not deployed** (see blockers) |
| munin-memory | #260 | `cd80e33` | bounded `memory_orient` in every detail mode |
| munin-memory | #261 | `e8caef0` | exact-anchor retrieval floor |
| munin-memory | #265 | `2eaa4e5` | release v0.6.1; deployed to huginmunin |
| gille-inference | #92 | `125b0f3` | canonicalize task-type identity for authority gates |
| gille-inference | #93 | `7c628ff` | stamped vs defaulted delegator attribution |

Deployed and certified: gille-inference `125b0f3` (owner-run), munin-memory v0.6.1, heimdall
`945847c`, brokkr `99afdb3`, grimnir `0e03def` on the Pi checkout.

### Heimdall — what was actually wrong

- **`commits_behind = -1`** (`drift.js:280`, `else { commitsBehind = -1 }`) produced 6 of the 9 alerts.
  Drift now resolves to `up-to-date | drift | ahead | unknown`, per repo rather than per systemd unit,
  with "not measurable" rendered distinctly from "behind".
- **Zombie alerts** bound to a dead host identity (`huginmunin` stopped reporting 2026-07-23 while the
  same machine reported as `control-node`). Reconciled via `fleet.host_aliases` plus a staleness reaper.
- **Real failures were silent** while false ones were loud: `brokkr-maintenance-os` (exit 1 daily) and
  `grimnir-validate` raised no alert at all.
- **Production ran the demo config.** `HEIMDALL_CONFIG_PATH` and `GRIMNIR_SERVICES_JSON` were both
  unset, so RFC 5737 addresses were live. Fixed with a non-repo overlay at
  `/home/magnus/.heimdall/config.json` (mode 0600) plus `HEIMDALL_STORAGE_SSH_USER=magnus` and
  `HEIMDALL_STORAGE_SSH_HOST`. **Three separate places defaulted to documentation addresses**; all
  three had to be fixed before a single metric flowed. The resulting fresh NAS rows were later shown
  to rely on implicit personal-identity fallback, not a valid restricted probe; Heimdall #23 and
  Brokkr #51 own that correction.

### Deploy safety

`grimnir#150` was written because `make deploy` **took Munin Memory down for ~10 minutes**: it rsynced
code to the registry `deploy_path` and installed a unit pointing at `/srv/grimnir/munin-memory`, a path
that does not exist on the host. Recovery worked only because a March-era `.bak` happened to survive.

The guard immediately found **two more armed instances**: `mimir` (unit says `User=mimir`,
`/home/mimir/mimir-server` — neither exists on the NAS; filed mimir#29) and `brokkr` (unit runs from
`~/.local/lib/brokkr` while the registry says `/home/magnus/repos/brokkr` — a silent no-op deploy).

### Backlog reconciliation

Audited all 35 open grimnir issues: **1 delivered, 11 partial, 23 open**. Corrected #102 (NOT
delivered — `hugin#289` open, so acceptance criterion 4 unmet), #78 (2 of 3 "remaining" repos already
gone), #90 (only `claude-config#11` outstanding). Closed **#69 as invalid** and recorded the trial
dates in `docs/skuld-trial-decision.md` (PR #147) — they were blank placeholders, so the day-28 gate
could never come due.

### Cross-fleet dependency sweep

Issue **#16** was re-audited against each named repository's current `main` lockfile on 2026-07-26.
The original all-dev/build-time premise was false: production audit findings remain in munin-memory,
hugin, and verdandi. Roadmap-linked owning tickets are munin-memory#285, hugin#322, and verdandi#29.
Heimdall's remediation PR #39 merged as `a02420f`, was deployed exactly, and its collector, live
health revision, and remote production audit all verified clean. #16 remains open until the three
remaining owner deliverables land. Mimir, Ratatoskr, Skuld, and Fortnox MCP have no production audit
findings; their remaining findings are dev-only.

## Important incidents and learnings

- **The deploy outage (grimnir#146).** The `/srv/grimnir` relocation is half-done: the owning repo
  declares post-relocation units while the registry and hosts are pre-relocation, and nothing failed
  closed. Finish or revert the relocation; it belongs with Epic C / brokkr#12.
- **#69 nearly cost a working service.** It claimed skuld was never installed; the owner had approved
  cutting it. Skuld runs as a **user-scope** timer — `systemctl list-units` reports zero and reads as
  absence. Verifying against the host is the only reason a live daily briefing was not archived.
  **"Not in `systemctl list-units`" is not evidence a service is absent.**
- **Thresholds encoded assumptions nobody had checked.** Three tickets (heimdall#27, #28, #29) share one
  shape: a constant standing in for a property that should be read from the thing being monitored — a
  demo config assumed real, a 6h backup threshold against a **weekly** schedule
  (`AutoBackupInterval = 604800`), an 80% disk rule against a volume deliberately run near-full by quota.
- **M5 splits by task shape, again.** Bounded structural extraction was reliable and produced a real
  review finding; anything reasoning-shaped failed (it returned an inverted answer on brokkr control
  flow and was discarded). Under four concurrent agents, two independently recovered from "server is
  busy" by **trimming the prompt** rather than waiting — pointing at admission behaviour, not raw
  capacity. Recorded on gille-inference#25.

## Next steps (priority order)

1. **Brokkr #51 / Heimdall #23** — after explicit owner approval, create and roll out the dedicated
   NAS probe credential with merged Brokkr PR #52, verify disk/Munin/Mimir readback, then deploy
   Heimdall PR #44's code.
2. **Brokkr #53** — add M5-local Time Machine telemetry through a least-authority existing
   substrate/fleet path; the NAS probe cannot observe a backup that moved to another node.
3. **Skuld PR #16 / Grimnir #140** — choose private-repo CI funding or an isolated self-hosted
   runner; merge only after a check actually executes and passes.
4. **Grimnir #146** — choose `/home` or `/srv` as the authoritative Munin unit path, then deploy
   merged Munin PRs #289–#292 from exact revisions.
5. **Brokkr #44** — approve the exact non-secret locator policy or revise acceptance to a committed
   schema/example plus untracked host overlay.
6. **Brokkr #35** — finish the privileged adapter, workload/reboot lifecycle, retry-journal binding,
   and executable forward recovery.
7. **Gille #96/#98** — resolve provider pricing/billing and dedicated key/quota/rotation policy;
   continue the #85 watchdog only after its observation window has real samples.
8. **Time-gated trials** — reassess Grimnir #159 after 28 immutable validator runs and Hugin #165
   on 2026-08-22; do not manufacture early conclusions.

## Blockers / owner input

- **Private-repo GitHub Actions** still fails before any step executes. Grimnir #140 is explicitly an
  owner decision; no agent may install a self-hosted runner on M5 without approval.
- **Munin deploy authority** is contradictory (`/home` versus `/srv`); Grimnir #146 needs an owner
  direction before the merged queue can deploy.
- **Brokkr #44** needs owner approval for the exact non-secret locator treatment or a revised
  acceptance contract.
- **Brokkr #51 / Heimdall #23** needs explicit approval to create the persistent dedicated
  production SSH credential. Code and rollback contract are merged; no identity or host mutation
  was performed.
- **Brokkr #53** confirms the NAS probe cannot restore Time Machine visibility after that source
  moved to M5; a separate least-authority M5 producer is required.
- **Time Machine migration** was still incomplete in the prior session and was not re-verified here.
  Do not remove the NAS destination based on this file.

## Verification at close

- Every merged PR had green CI plus independent review with executed verification — regressions
  mutation-tested to confirm they fail without the fix, not merely inspected.
- Heimdall's `test/live-alert-state.test.js` replays the nine real alerts and asserts each corrected
  outcome (8/8 passing), including that an audit reporting 2 findings raises **no** failure alert.
- `grimnir-validate` verified live under systemd: exit **0**, `Result=success`,
  `AUDIT OK: ran to completion — 2 finding(s)`, and `Results written to Munin (findings=2 severity=issues)`
  after months of a silent trailing-slash failure (`validation/` vs `validation`).
- NAS rows did update after being frozen since 2026-07-22, but this session established that the
  collector borrowed an implicit personal SSH identity. Treat that as failure evidence, not restored
  monitoring, until Heimdall #23 / Brokkr #51 complete.
- grimnir `make test` 117 passed / 0 failed plus the new 12-test exit-contract suite; shellcheck clean.

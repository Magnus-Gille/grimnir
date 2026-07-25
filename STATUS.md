# Grimnir System — Status

**Last session:** 2026-07-25/26 (Claude) — monitoring correctness, deploy safety, and a backlog audit
**Latest system revision:** grimnir `87dfc6f` (deploy unit-path guard)

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
  three had to be fixed before a single metric flowed. NAS probes revived after three days dark.

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

1. **grimnir#149** — set `HEIMDALL_HUB_URL`/`HEIMDALL_FLEET_TOKEN` for Hugin **before** deploying it, or
   the capability-evidence panels disappear rather than move.
2. **mimir#29** — armed to take Mimir down on its next deploy. The guard now refuses it, but the
   underlying contradiction stands.
3. **gille-inference#95** — policy reads canonical identity while the ledger writes verbatim, so failures
   cannot degrade a lane. Blocks #85 (first enforced lane).
4. **#85** — then enforce one lane (`reason-hard @ gpt-oss-120b`, `numeric`-verified: 25/25, p90 13,731 ms)
   with pre-registered thresholds and a *tested* rollback.
5. **heimdall#26/#27/#28/#29** — snapshot staleness, non-repo config with a documentation-address
   assertion, and the two threshold miscalibrations.
6. **gille-inference#96** — price the five delegator ids in use; `verified_savings_actual_usd` stays $0.00
   until then, which also blocks grimnir#67.
7. **brokkr#44** — turn the 8-variable deploy incantation into a committed profile.
8. **The `/srv/grimnir` relocation decision** (grimnir#146) — finish or revert.

## Blockers / owner input

- **Time Machine migration in progress.** Destination moved to m5 (4TB, `smb://magnus@m5._smb._tcp.local./TimeMachine`)
  and re-added with encryption; the initial full backup (~786 GiB) was running at session close as
  `Magnus MacBook Air <uuid>.incomplete`. **Do not remove the NAS destination until it completes** — an
  `.incomplete` bundle is not restorable, so the NAS is currently the only usable backup.
- **Hugin deploy blocked** on grimnir#149.
- GitHub Actions billing for private repos remains the standing blocker from prior sessions.

## Verification at close

- Every merged PR had green CI plus independent review with executed verification — regressions
  mutation-tested to confirm they fail without the fix, not merely inspected.
- Heimdall's `test/live-alert-state.test.js` replays the nine real alerts and asserts each corrected
  outcome (8/8 passing), including that an audit reporting 2 findings raises **no** failure alert.
- `grimnir-validate` verified live under systemd: exit **0**, `Result=success`,
  `AUDIT OK: ran to completion — 2 finding(s)`, and `Results written to Munin (findings=2 severity=issues)`
  after months of a silent trailing-slash failure (`validation/` vs `validation`).
- NAS probes confirmed revived: `disk_used_pct_nas`, `tm_last_backup`, `munin_backup_latest/count` all
  updated after being frozen since 2026-07-22.
- grimnir `make test` 117 passed / 0 failed plus the new 12-test exit-contract suite; shellcheck clean.

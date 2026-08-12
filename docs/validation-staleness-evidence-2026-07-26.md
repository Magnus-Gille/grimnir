# Registry-validation staleness evidence — 2026-07-26

**Decision:** Do not add an unattended Git pull cadence from the evidence collected for
Grimnir #2. Keep the existing read-only daily validator. A later proposal must collect
immutable per-run freshness observations before it can justify an automatic mutation.

## What was measured

The live `grimnir-validate.timer` is persistent, scheduled daily at 04:30
Europe/Stockholm with a randomized delay of at most 120 seconds. Its service runs
`scripts/generate-architecture.sh --validate` from the canonical checkout; it does
not run `git pull`.

Munin audit history for `validation/registry/latest` contains one timer-shaped update
on every calendar day from 2026-04-02 through 2026-07-25: **115 expected days, 115
observed daily updates, and zero missing dates**. Those scheduled writes occurred at
02:30--02:32 UTC (04:30--04:32 CEST during this window). There are also manual
validation writes during incident work; they are not treated as timer samples.

The current live checkout is clean, on `main`, and exactly equal to live
`origin/main`. That is a present-state observation, not evidence of an appropriate
sync cadence.

## Why this cannot select a cadence

The validator's freshness check compares local `HEAD` with `git ls-remote
origin/main` and emits only `current`, `mismatch`, or `unreachable`. It does not
fetch or mutate the checkout. Its historical output was overwritten in the single
`validation/registry/latest` state entry, so old result bodies cannot be recovered
as of their run times. Durable `validation` log events began only on 2026-07-25 after
the reporting repair.

Consequently, the retained record has no historical per-run local SHA, remote SHA,
commit distance, transition time, or outcome classification. It cannot quantify how
long the checkout was behind origin or distinguish a successful timer run from an
overwritten/manual write. The live journal likewise retained the 2026-07-25 scheduled
exit-1 but not an April--July run history; a 21:12 CEST manual rerun then reported
15 OK / 2 findings successfully.

Choosing hourly, daily, or any other automatic pull interval from these records would
be false precision. In particular, a clean current checkout does not establish that
unattended pulls are safe.

## Required evidence before reconsideration

Any future sync-cadence proposal must first retain one immutable record for each
scheduled validation with:

1. scheduled and observed UTC timestamps;
2. local and remote `main` SHAs plus an unambiguous freshness state;
3. ahead/behind/diverged classification when the repository graph is available;
4. audit completion/reporting outcome, separate from fleet findings; and
5. whether the run was timer-triggered or manual.

After at least 28 consecutive scheduled runs with those fields, a proposal may
quantify stale intervals and consider a reversible, explicitly bounded sync action.
It must still be reviewed as a mutation policy, rather than being inferred from
validation green-ness.

## Evidence capture implementation (issue #159)

The validator now appends one immutable `validation-run-evidence/v1` JSON event
to Munin's `validation` log for each completed invocation. It contains the
scheduled and observed UTC times (scheduled time is null only for an explicit
manual run), explicit `timer` or `manual` origin, local and remote `main` SHA,
and a read-only graph classification of `current`, `ahead`, `behind`,
`diverged`, or `unreachable`. It also keeps audit completion/error and reporting
outcome separate from the fleet finding counts.

When the live remote SHA is not present in the canonical checkout, the
validator fetches it into a disposable bare repository and uses the canonical
object store only as a read-only alternate. This resolves `behind` and
`diverged` without changing canonical refs or objects; `unreachable` is retained
for transport/object-resolution failures where the graph cannot be proved.

`grimnir-validate.timer` invokes a dedicated timer-origin service. Direct runs
default to manual; unknown origins and unavailable scheduled timestamps fail
closed rather than being labelled as timer evidence. The immutable log write is
part of the reporting gate: a mutable `validation/registry/latest` update alone
does not make the audit succeed.

This implementation does not retrospectively validate the eight legacy summary
logs or change the daily schedule. The 28-run window starts only after the
updated units are deployed and successful timer-origin v1 records accumulate.

## Sources

- Live systemd unit and timer inspection on `huginmunin`, 2026-07-26.
- Munin `validation/registry` audit history, queried 2026-07-26.
- [`scripts/lib/registry-checkout.sh`](../scripts/lib/registry-checkout.sh) and
  [`scripts/generate-architecture.sh`](../scripts/generate-architecture.sh).

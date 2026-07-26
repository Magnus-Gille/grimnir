# Skuld — 28-Day Revive-or-Cut Trial

> **Decision:** run Skuld for 28 days, then explicitly keep or cut it from the deployed component
> inventory. The trial starts with the first successfully delivered briefing after this record is
> adopted; record that date below rather than assuming a calendar start.

## Trial record

- **First successful briefing:** 2026-07-11 06:00 CEST
- **Day-28 review due:** 2026-08-08
- **Owner:** Magnus
- **Outcome:** _pending — keep or cut_

> **Verified live 2026-07-25.** Skuld is deployed and running: `skuld.timer` is active in **user
> scope** on `huginmunin` (`systemctl --user`), last run 2026-07-25 06:01:36 CEST with
> `Result=success`, `ExecMainStatus=0`, next run 06:03 the following day. `services.json` describes
> it accurately, including `scope: user`. Dates above are sourced from the component-side ledger at
> `skuld/docs/TRIAL-EVIDENCE.md`, which is the authoritative record of delivery; this file remains
> authoritative for the keep/cut decision itself.
>
> A system-scope `systemctl` check reports zero units for Skuld and looks like absence. It is not —
> see grimnir#69, which was filed on exactly that false negative.

For each scheduled day, capture only:

| Field | Values |
|---|---|
| Delivery | delivered / failed / intentionally skipped |
| Usefulness | useful / not useful / not reviewed |
| Concrete action | short action reference, or none |
| Evidence | Munin/trace identifier; no duplicated briefing body |

A briefing marked useful should name at least one concrete decision or action it caused. Orientation
that changed a plan counts; vague interest does not. Do not add new Skuld features during the trial
unless they are required to keep the existing producer running—the point is to measure the current
service, not a moving target.

## Day-28 decision

- **Keep** only with owner-reviewed evidence that the briefings changed decisions or actions often
  enough to justify their operating and maintenance surface. Record what signal will continue to be
  reviewed in the monthly system ROI ledger.
- **Cut** if no briefing produced concrete value, delivery was too unreliable to evaluate, or the
  owner does not choose a specific reason to keep it. Remove Skuld from `services.json`, disable its
  units, and preserve only the evidence needed to explain the decision.

The review must end in `keep` or `cut`; extending the trial requires a dated owner decision and a
specific unresolved question. This is the decision record for grimnir#69, not a permanent Skuld
product roadmap.

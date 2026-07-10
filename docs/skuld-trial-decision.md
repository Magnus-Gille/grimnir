# Skuld — 28-Day Revive-or-Cut Trial

> **Decision:** run Skuld for 28 days, then explicitly keep or cut it from the deployed component
> inventory. The trial starts with the first successfully delivered briefing after this record is
> adopted; record that date below rather than assuming a calendar start.

## Trial record

- **First successful briefing:** _record when observed_
- **Day-28 review due:** _first successful briefing + 28 days_
- **Owner:** Magnus
- **Outcome:** _pending — keep or cut_

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

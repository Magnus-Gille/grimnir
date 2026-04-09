# Debate Summary: Multi-User Grimnir

**Date:** 2026-03-31
**Participants:** Claude Opus 4.6 vs Codex (gpt-5.4)
**Rounds:** 2
**Topic:** Multi-user security and collaboration for Grimnir infrastructure

---

## Key Outcome

The original "multi-user Grimnir" proposal was narrowed to **"multi-principal Munin"** — a more honest and safer scope. Codex's central critique: the draft treated authorization as HTTP middleware when Munin's real leak surface is inside the tool layer. Every tool handler must be authorization-aware, deny-by-default.

**Verdict: Phase 1 approved as "multi-principal Munin for Magnus + Sara."** Not approved as "multi-user Grimnir" — Mimir, Hugin, and third-party onboarding are explicitly deferred.

## Critical security decisions

1. **AccessContext plumbed through every tool** — not just HTTP middleware. memory_orient, memory_attention, memory_history, memory_get all need filtering.
2. **Full cutover before onboarding Sara** — no grace period, no unauthenticated window alongside new users.
3. **Hashed token storage** — follow existing OAuth pattern.
4. **Namespace isolation** — `users/<id>/*` for private, `shared/<group>/*` for shared, `orgs/<id>/*` for orgs.
5. **Invisible by default** — non-owner users see "not found" (not 403) for unauthorized namespaces. But agent gets machine-readable denial signal to prevent false-success bugs.
6. **Per-principal rate limiting and audit** — not global bucket.
7. **Direct-SQLite readers (Skuld, Heimdall) remain strictly owner-only** in Phase 1.

## Concessions accepted by both sides

1. Tool-level AccessContext is the correct enforcement point (both agree)
2. Munin is the right collaboration medium (both agree)
3. Phased rollout with narrower Phase 1 scope (both agree)
4. No Mimir access for Sara in Phase 1 (Claude conceded)
5. Opaque inbox-based collab, not global conversations bucket (Claude conceded)
6. Admin CLI is essential (Claude conceded)

## Unresolved issues (from Round 2)

1. **Complete tool-by-tool authorization matrix** not yet written — Codex's #1 demand before building
2. **Denial semantics dual contract** — non-scary for humans, machine-readable for agents. Exact shape TBD.
3. **Principal-specific entry experience** — what does Sara's memory_orient show? Empty dashboard? Curated home?
4. **Inbox collaboration semantics** — unread state, pickup, duplicate prevention, expiry rules
5. **Audit model** — principal-aware records needed, current agent_id is "default"

## Phase 1 scope (approved)

**Build:**
- Principal model in Munin (authenticate → resolve → load policy → AccessContext)
- Tool-level enforcement (deny-by-default, every tool)
- `users/<id>/*` namespace convention
- Hashed tokens with optional expiry and revocation
- Admin CLI for token/principal management
- Inbox-based `/collab` skill
- Full service cutover (all 6+ clients get tokens)

**Do NOT build yet:**
- Mimir multi-user (Phase 2)
- Sara's Hugin access (backlog)
- Third-party user onboarding
- Telegram notifications for collab
- System-wide "multi-user Grimnir" claims

**Before building:**
- Write the complete authorization matrix (every Munin tool + derived query)
- Implement as fail-closed tests
- Classify all direct-SQLite readers as owner-only
- Define denial semantics contract

## Critique statistics

- Total critique points: 20
- Valid: 20 (100%)
- Severity: 5 critical, 12 major, 3 minor
- Self-review catch rate: 4/20 (20%)
- Impact: 11 changed, 2 partially changed, 7 acknowledged

## Costs

| Invocation | Wall-clock time | Model version |
|------------|-----------------|---------------|
| Codex R1   | ~5m             | gpt-5.4       |
| Codex R2   | ~4m             | gpt-5.4       |

## All debate files

- [Draft](multi-user-grimnir-claude-draft.md)
- [Self-review](multi-user-grimnir-claude-self-review.md)
- [Codex critique R1](multi-user-grimnir-codex-critique.md)
- [Claude response R1](multi-user-grimnir-claude-response-1.md)
- [Codex rebuttal R2](multi-user-grimnir-codex-rebuttal-1.md)
- [Critique log](multi-user-grimnir-critique-log.json)
- [Summary](multi-user-grimnir-summary.md) (this file)

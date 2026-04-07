# Grimnir System — Status

**Last session:** 2026-04-07
**Branch:** main

## Completed This Session

### Architecture doc update
- Added Verdandi (tamper-evident audit log, :3036) to `docs/architecture.md` — component table, topology diagram, hardware row, access matrix, and dedicated section
- Updated "last updated" date to 2026-04-07
- Commit: 6cee9c9

## Next Steps

1. **UPS for both Pis** — grimnir#4 (hardware purchase, ~300-500 SEK each)
2. **Heimdall boot health check** — heimdall#7 (post-boot service verification + Telegram alert)
3. **Clean up stale systemd units** on huginmunin (hugin-munin-discord, hugin-munin-rituals)
4. **Hugin security hardening** — issues #7–#13
5. **Heimdall registry alignment** — have Heimdall read from `services.json`
6. Multi-principal Munin Phase 1

## Blockers
- None

# Grimnir System — Status

**Last session:** 2026-04-06
**Branch:** main

## Completed This Session

### Power outage recovery and infrastructure hardening
- Both Pis (huginmunin.local + nas.local) came back up after power outage — all services were running but most lacked systemd management
- Created and enabled systemd user units for **munin-memory**, **hugin**, **heimdall**, **ratatoskr** on huginmunin (with `Restart=always`, security hardening, proper dependency ordering on munin-memory)
- Installed **smartmontools** on nas.local — SMART daemon active, drive healthy (Samsung T7 2TB, 0% wear, 0 integrity errors, 3 unsafe shutdowns from outages)
- Created **Avahi Time Machine service file** on nas.local for proper macOS mDNS discovery
- Enabled **periodic fsck** on NAS HDD (every 30 mounts or 3 months, next check 2026-05-04)
- Filed grimnir#4 (UPS for both Pis) and heimdall#7 (boot health check + Telegram alerting) on roadmap

### Findings
- huginmunin: verdandi + skuld were the only services with systemd units; the rest ran as bare processes with no crash recovery
- nas: mimir runs as a system-level service (auto-starts fine); Samba/Time Machine share was configured but not advertised via Avahi
- nas: HDD had `Maximum mount count: -1` and `Check interval: 0` — no periodic fsck was scheduled
- Registry in services.json was accurate for what *should* exist — now matches reality for huginmunin services

## Next Steps

1. **UPS for both Pis** — grimnir#4 (hardware purchase, ~300-500 SEK each)
2. **Heimdall boot health check** — heimdall#7 (post-boot service verification + Telegram alert)
3. **Clean up stale systemd units** on huginmunin (hugin-munin-discord, hugin-munin-rituals)
4. **Hugin security hardening** — issues #7–#13
5. **Heimdall registry alignment** — have Heimdall read from `services.json`
6. Multi-principal Munin Phase 1

## Blockers
- None

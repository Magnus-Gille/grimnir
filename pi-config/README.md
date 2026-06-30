# Pi Config

Version-controlled snapshot of host-level config files on `huginmunin` that aren't owned by any individual Grimnir service. Source of truth lives on the Pi; these copies exist so the config is reproducible and reviewable.

> **cloudflared config** has moved to `brokkr/network/cloudflared/config.yml`. See
> `brokkr/network/README.md` for the apply procedure.

## Files

| Repo path | Pi path | Owner |
|---|---|---|
| `systemd/mimir-reading-sync.service` | `~magnus/.config/systemd/user/mimir-reading-sync.service` | magnus (user unit) |
| `systemd/mimir-reading-sync.timer` | `~magnus/.config/systemd/user/mimir-reading-sync.timer` | magnus (user unit) |

## Apply

These are intentionally not auto-deployed by `scripts/deploy.sh` — they touch host config, not service code, and changes should be deliberate.

```bash
# mimir-reading-sync (user unit)
scp pi-config/systemd/mimir-reading-sync.{service,timer} \
  magnus@huginmunin:.config/systemd/user/
ssh magnus@huginmunin 'systemctl --user daemon-reload \
  && systemctl --user enable --now mimir-reading-sync.timer'
```

## Verify after change

```bash
ssh magnus@huginmunin 'systemctl --user list-timers mimir-reading-sync.timer'
```

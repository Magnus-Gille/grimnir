# Pi Config

Version-controlled snapshot of host-level config files on `huginmunin` that aren't owned by any individual Grimnir service. Source of truth lives on the Pi; these copies exist so the config is reproducible and reviewable.

## Files

| Repo path | Pi path | Owner |
|---|---|---|
| `cloudflared/config.yml` | `/etc/cloudflared/config.yml` | root |
| `systemd/mimir-reading-sync.service` | `~magnus/.config/systemd/user/mimir-reading-sync.service` | magnus (user unit) |
| `systemd/mimir-reading-sync.timer` | `~magnus/.config/systemd/user/mimir-reading-sync.timer` | magnus (user unit) |
| `caddy/tallriksvis.Caddyfile` | merge into `/etc/caddy/Caddyfile` | root |
| `systemd/tallriksvis.service` | `/etc/systemd/system/tallriksvis.service` | root (only if backend process; skip for static-only) |
| `nftables/tallriksvis-egress.nft` | `/etc/nftables.d/tallriksvis-egress.nft` | root |

The cloudflared tunnel credentials file (`/etc/cloudflared/<tunnel-uuid>.json`) is a secret and is NOT tracked here.

## Apply

These are intentionally not auto-deployed by `scripts/deploy.sh` — they touch host config, not service code, and changes should be deliberate.

```bash
# cloudflared (root, system-wide)
scp pi-config/cloudflared/config.yml magnus@huginmunin:/tmp/cloudflared.yml
ssh magnus@huginmunin 'sudo install -m 644 /tmp/cloudflared.yml /etc/cloudflared/config.yml \
  && sudo systemctl restart cloudflared'

# mimir-reading-sync (user unit)
scp pi-config/systemd/mimir-reading-sync.{service,timer} \
  magnus@huginmunin:.config/systemd/user/
ssh magnus@huginmunin 'systemctl --user daemon-reload \
  && systemctl --user enable --now mimir-reading-sync.timer'
```

### tallriksvis sandboxing (Issue #14, Option A)

Goal: remove LAN-anonymous access to tallriksvis, route external access through
Cloudflare Tunnel + Cloudflare Access, and confine the process if it's a backend.
Apply in this order — each step is reversible on its own.

**Pre-flight (read first):**

1. SSH to `huginmunin`, read `/etc/caddy/Caddyfile`, identify the existing
   tallriksvis stanza. Decide: static files (`root` + `file_server`) or backend
   process (`reverse_proxy` to a port)?
2. If backend: confirm the runtime user, deploy path, and command line. The
   systemd unit assumes Node + `/opt/tallriksvis/server.js` — adjust as needed.
3. Tell anyone else who uses tallriksvis (wife) that the URL changes from the
   LAN IP to `tallriksvis.gille.ai`.

**1. Cloudflare Tunnel ingress** (add `tallriksvis.gille.ai` to the existing
tunnel — edit `pi-config/cloudflared/config.yml` to add the entry, then apply
via the cloudflared block above). Also create a Cloudflare Access policy for
the hostname before flipping DNS.

**2. Caddy site** — merge `caddy/tallriksvis.Caddyfile` into the existing
`/etc/caddy/Caddyfile` (do NOT overwrite). The block binds to `127.0.0.1:8080`
so the only path in is via the tunnel.

```bash
ssh magnus@huginmunin 'sudo nano /etc/caddy/Caddyfile'   # merge by hand
ssh magnus@huginmunin 'sudo caddy validate --config /etc/caddy/Caddyfile \
  && sudo systemctl reload caddy'
```

**3. systemd unit** (only if tallriksvis is a backend process; skip for
static-only deploys — Caddy is already the only process in that case):

```bash
ssh magnus@huginmunin 'sudo useradd --system --no-create-home \
  --shell /usr/sbin/nologin tallriksvis || true'
ssh magnus@huginmunin 'sudo chown -R tallriksvis:tallriksvis /opt/tallriksvis'
scp pi-config/systemd/tallriksvis.service magnus@huginmunin:/tmp/
ssh magnus@huginmunin 'sudo install -m 644 /tmp/tallriksvis.service \
    /etc/systemd/system/tallriksvis.service \
  && sudo systemctl daemon-reload \
  && sudo systemctl enable --now tallriksvis.service'
```

**4. nftables egress** — restrict the `tallriksvis` user to tcp/443 + DNS.

```bash
scp pi-config/nftables/tallriksvis-egress.nft magnus@huginmunin:/tmp/
ssh magnus@huginmunin 'sudo install -m 644 /tmp/tallriksvis-egress.nft \
    /etc/nftables.d/tallriksvis-egress.nft'
# Confirm /etc/nftables.conf includes /etc/nftables.d/*.nft, then:
ssh magnus@huginmunin 'sudo nft -f /etc/nftables.d/tallriksvis-egress.nft \
  && sudo nft list chain inet filter output_tallriksvis'
```

**Rollback:** any step can be reverted independently — remove the include /
disable the unit / drop the chain — but check the others still make sense
without it.

## Verify after change

```bash
ssh magnus@huginmunin 'systemctl status cloudflared --no-pager | head'
ssh magnus@huginmunin 'systemctl --user list-timers mimir-reading-sync.timer'
ssh magnus@huginmunin 'systemctl status tallriksvis --no-pager | head'
ssh magnus@huginmunin 'sudo nft list chain inet filter output_tallriksvis'
ssh magnus@huginmunin 'curl -sv http://192.168.0.139:8080 || echo "good — LAN access blocked"'
ssh magnus@huginmunin 'curl -sv http://127.0.0.1:8080 | head'
```

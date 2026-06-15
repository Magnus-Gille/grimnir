#!/usr/bin/env bash
#
# grimnir-brew-update.sh — weekly Homebrew maintenance on Magnus's laptop.
#
# Auto-upgrades FORMULAE (CLI tools). Casks (GUI apps) are NOT auto-upgraded —
# they are reported for deliberate manual upgrade, so apps never restart/change
# under you unexpectedly. Status → Munin, action-needed (casks/failure) →
# Telegram, both via an SSH-hop into huginmunin (no secrets stored on the laptop).
#
# Installed to ~/.local/bin and driven by the com.magnusgille.brew-update
# LaunchAgent (weekly). Run by hand any time: ~/.local/bin/grimnir-brew-update.sh
set -uo pipefail

# launchd runs with a minimal environment — set PATH explicitly.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
BREW="/opt/homebrew/bin/brew"
HOP="magnus@huginmunin.local"
LOGDIR="$HOME/.local/share/grimnir-maintenance/logs"
mkdir -p "$LOGDIR"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== grimnir-brew-update $ts ==="

[[ -x "$BREW" ]] || { echo "brew not found at $BREW"; exit 1; }

"$BREW" update >/dev/null 2>&1 || echo "warn: brew update failed"

# Formulae — auto-upgrade.
n_formulae="$("$BREW" outdated --formula --quiet 2>/dev/null | grep -c . || true)"
echo "upgrading $n_formulae outdated formula(e)…"
"$BREW" upgrade --formula 2>&1 | tail -8
"$BREW" cleanup -s >/dev/null 2>&1 || true

# Casks — report only.
casks="$("$BREW" outdated --cask --quiet 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
n_casks="$(printf '%s' "$casks" | wc -w | tr -d ' ')"

summary="brew (laptop) @ $ts: upgraded ${n_formulae} formula(e); ${n_casks} cask(s) need manual upgrade${casks:+: $casks}"
echo "$summary"

# ── Report to Munin + Telegram via SSH-hop into huginmunin (best-effort) ──
# base64 the message to sidestep all remote-shell quoting issues.
b64="$(printf '%s' "$summary" | base64)"
ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOP" "N_CASKS=${n_casks} bash -s" <<REMOTE 2>/dev/null || echo "warn: report hop failed (offline?)"
set -u
MSG="\$(printf '%s' '$b64' | base64 -d)"
source /home/magnus/repos/grimnir/scripts/lib/munin.sh
source /home/magnus/repos/grimnir/scripts/lib/notify.sh
munin_discover_token /home/magnus/repos || true
ARGS="\$(NS='maintenance/brew/laptop' K='latest' C="\$MSG" T='["maintenance","brew","laptop","automated"]' node --input-type=commonjs -e 'console.log(JSON.stringify({namespace:process.env.NS,key:process.env.K,content:process.env.C,tags:JSON.parse(process.env.T)}))')"
munin_tool_call memory_write "\$ARGS" >/dev/null 2>&1 || true
if [ "\${N_CASKS:-0}" -gt 0 ]; then notify_telegram "🍺 \$MSG"; fi
REMOTE

echo "done."

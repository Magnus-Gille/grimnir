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
# Reporting hop targets, tried in order. .local (mDNS) is flaky under launchd
# ("No route to host"), so fall back to the bare name over Tailscale MagicDNS —
# same strategy as deploy.sh's resolve_host.
HOPS="magnus@huginmunin.local magnus@huginmunin"
LOGDIR="$HOME/.local/share/grimnir-maintenance/logs"
mkdir -p "$LOGDIR"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=== grimnir-brew-update $ts ==="

[[ -x "$BREW" ]] || { echo "brew not found at $BREW"; exit 1; }

# Track failures so a broken update/upgrade is surfaced (not logged as healthy).
fail=0
"$BREW" update >/dev/null 2>&1 || { echo "warn: brew update failed"; fail=1; }

# Formulae — auto-upgrade.
n_formulae="$("$BREW" outdated --formula --quiet 2>/dev/null | grep -c . || true)"
echo "upgrading $n_formulae outdated formula(e)…"
if ! "$BREW" upgrade --formula 2>&1 | tail -8; then echo "warn: brew upgrade --formula had failures"; fail=1; fi
"$BREW" cleanup -s >/dev/null 2>&1 || true

# Casks — report only.
casks="$("$BREW" outdated --cask --quiet 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
n_casks="$(printf '%s' "$casks" | wc -w | tr -d ' ')"

fail_note=""; [ "$fail" -eq 1 ] && fail_note=" [UPGRADE ERRORS — see log]"
summary="brew (laptop) @ $ts: upgraded ${n_formulae} formula(e); ${n_casks} cask(s) need manual upgrade${casks:+: $casks}${fail_note}"
echo "$summary"

# ── Report to Munin + Telegram via a SINGLE heredoc-free SSH command into
# huginmunin, which runs the deployed reporter's `brew` mode. A single ssh
# command (no heredoc on stdin) is robust under launchd; base64 sidesteps all
# remote-shell quoting. Best-effort: stderr captured to the log, never fatal.
b64="$(printf '%s' "$summary" | base64 | tr -d '\n')"
reported=""
for hop in $HOPS; do
  if ssh -o ConnectTimeout=10 -o BatchMode=yes "$hop" \
       "BREW_SUMMARY_B64='$b64' BREW_NCASKS='$n_casks' BREW_ALERT='$fail' bash /home/magnus/repos/grimnir/scripts/maintenance-report.sh brew"; then
    reported="$hop"; break
  fi
  echo "  report hop to $hop failed; trying next…"
done
[[ -n "$reported" ]] && echo "reported to Munin/Telegram via $reported" \
  || echo "warn: report hop failed on all targets — formulae were still upgraded"

echo "done."

#!/usr/bin/env bash
#
# maintenance-report.sh — Grimnir software-update visibility layer.
#
# Two modes (run as separate oneshot timers on huginmunin):
#
#   os    Daily. For EVERY Pi host in services.json (local + SSH to the rest),
#         report: pending security updates, reboot-required, disk usage, and
#         whether unattended-upgrades is installed/healthy. The actual patching
#         is done autonomously by unattended-upgrades (see setup-host-patching.sh);
#         this mode is the detect-and-surface half. Pushes an action-needed
#         Telegram alert when a reboot is pending, security updates are still
#         outstanding, disk is tight, or a host lacks the patcher.
#
#   deps  Weekly. Run `npm outdated` across every service repo checked out under
#         ~/repos and report counts (total + major bumps) to Munin. DETECT +
#         REPORT ONLY — never auto-applies (per the auto-ops debate verdict).
#
# Results go to Munin (maintenance/* namespace) and Heimdall; alerts go to
# Telegram via Ratatoskr. Mirrors security-scan.sh conventions and reuses the
# shared lib/munin.sh + lib/notify.sh helpers. Compatible with bash 3.2+.
#
# Usage:
#   scripts/maintenance-report.sh os    [--dry-run] [--verbose] [--munin-token T]
#   scripts/maintenance-report.sh deps  [--dry-run] [--verbose] [--munin-token T]
set -euo pipefail

REPORT_VERSION="1.0.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY="$GRIMNIR_DIR/services.json"
REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"
DEPLOY_USER="${DEPLOY_USER:-magnus}"

# shellcheck source=scripts/lib/munin.sh
source "$SCRIPT_DIR/lib/munin.sh"
# shellcheck source=scripts/lib/notify.sh
source "$SCRIPT_DIR/lib/notify.sh"

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_DATE="$(date -u +%Y-%m-%d)"
LOCAL_HOST="$(hostname -s)"
DISK_WARN_PCT=85

# ─── Args ────────────────────────────────────────────────────────────────────
MODE="${1:-}"; shift || true
DRY_RUN=false; VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --verbose) VERBOSE=true; shift ;;
    --munin-token) MUNIN_TOKEN="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
case "$MODE" in
  os|deps|brew) ;;
  *) echo "Usage: $0 {os|deps|brew} [--dry-run] [--verbose] [--munin-token T]" >&2; exit 1 ;;
esac

log_verbose() { $VERBOSE && echo "  $*" >&2 || true; }

munin_discover_token "$REPOS_DIR" || true
if [[ -z "${MUNIN_TOKEN:-}" ]]; then
  echo "WARNING: no Munin token found — Munin writes will be skipped" >&2
fi

# memory_write/memory_log wrappers honouring --dry-run and missing token.
report_write() {  # namespace key content tags_json
  $DRY_RUN && { log_verbose "[dry-run] memory_write $1/$2"; return 0; }
  [[ -z "${MUNIN_TOKEN:-}" ]] && return 0
  local args
  args=$(NS="$1" K="$2" C="$3" T="$4" node --input-type=commonjs -e '
    console.log(JSON.stringify({namespace:process.env.NS,key:process.env.K,content:process.env.C,tags:JSON.parse(process.env.T)}))') \
    || { echo "WARNING: Munin payload build failed ($1/$2)" >&2; return 0; }
  munin_tool_call memory_write "$args" >/dev/null || echo "WARNING: Munin write failed ($1/$2)" >&2
}
report_log() {    # namespace content tags_json
  $DRY_RUN && { log_verbose "[dry-run] memory_log $1"; return 0; }
  [[ -z "${MUNIN_TOKEN:-}" ]] && return 0
  local args
  args=$(NS="$1" C="$2" T="$3" node --input-type=commonjs -e '
    console.log(JSON.stringify({namespace:process.env.NS,content:process.env.C,tags:JSON.parse(process.env.T)}))') \
    || { echo "WARNING: Munin payload build failed ($1)" >&2; return 0; }
  munin_tool_call memory_log "$args" >/dev/null || echo "WARNING: Munin log failed ($1)" >&2
}
alert() { $DRY_RUN && { echo "  [dry-run] telegram: $1"; return 0; }; notify_telegram "$1"; }

# ═════════════════════════════════════════════════════════════════════════════
# OS MODE
# ═════════════════════════════════════════════════════════════════════════════
os_probe_cmd() {
cat <<'PROBE'
RR=no; [ -e /var/run/reboot-required ] && RR=yes
# Backup signal (Debian 13): needrestart kernel status >=2 means the running
# kernel is older than the installed one — a reboot is recommended.
if [ "$RR" = no ] && command -v needrestart >/dev/null 2>&1; then
  KSTA=$(needrestart -b 2>/dev/null | awk -F: '/NEEDRESTART-KSTA/{print $2+0}')
  [ "${KSTA:-0}" -ge 2 ] 2>/dev/null && RR=yes
fi
RRPKGS=0; [ -f /var/run/reboot-required.pkgs ] && RRPKGS=$(wc -l < /var/run/reboot-required.pkgs | tr -d ' ')
UU=$(dpkg -l unattended-upgrades 2>/dev/null | grep -c '^ii' || true)
if [ -x /usr/lib/update-notifier/apt-check ]; then
  AC=$(/usr/lib/update-notifier/apt-check 2>&1); ALLUP=${AC%;*}; SEC=${AC#*;}
else
  ALLUP=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || true)
  SEC=$(apt-get -s upgrade 2>/dev/null | awk '/^Inst/ && /security/{c++} END{print c+0}')
fi
DISK=$(df -P / | awk 'NR==2{gsub(/%/,"",$5); print $5}')
echo "REBOOT=$RR"; echo "REBOOT_PKGS=$RRPKGS"; echo "UU_INSTALLED=$UU"
echo "SEC_PENDING=${SEC:-0}"; echo "ALL_PENDING=${ALLUP:-0}"; echo "DISK=${DISK:-0}"; echo "KERNEL=$(uname -r)"
PROBE
}

# Resolve a host to a usable SSH target, mirroring deploy.sh/setup-host-patching:
# "LOCAL" if it's this machine, else user@.local, else user@bare (Tailscale),
# else empty (unreachable). Avoids a transient mDNS blip false-flagging a host.
resolve_remote() {
  local host="$1" short="${1%%.*}" bare="${1%.local}"
  if [[ "$short" == "$LOCAL_HOST" ]]; then echo "LOCAL"; return 0; fi
  if ssh -o ConnectTimeout=6 -o BatchMode=yes "$DEPLOY_USER@$host" true 2>/dev/null; then
    echo "$DEPLOY_USER@$host"; return 0; fi
  if [[ "$bare" != "$host" ]] && ssh -o ConnectTimeout=6 -o BatchMode=yes "$DEPLOY_USER@$bare" true 2>/dev/null; then
    echo "$DEPLOY_USER@$bare"; return 0; fi
  return 1
}

run_os() {
  echo "Grimnir OS maintenance report — $TIMESTAMP (v$REPORT_VERSION)"
  echo

  local HOSTS=()
  while IFS= read -r h; do
    [[ -n "$h" ]] && HOSTS+=("$h")
  done < <(REGISTRY_PATH="$REGISTRY" QUERY=deploy \
    node --input-type=commonjs "$REGISTRY_JS" | cut -d'|' -f3 | grep -v '^$' | sort -u)
  [[ ${#HOSTS[@]} -gt 0 ]] || { echo "No deploy hosts found in $REGISTRY" >&2; exit 1; }

  local probe; probe="$(os_probe_cmd)"
  local summary="OS patch status ($RUN_DATE):" alerts="" any_action=false

  for host in "${HOSTS[@]}"; do
    local short="${host%%.*}" blob target
    echo "▶ $host"
    if target="$(resolve_remote "$host")"; then
      if [[ "$target" == "LOCAL" ]]; then
        blob="$(bash -c "$probe" 2>/dev/null || true)"
      else
        blob="$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$target" "$probe" 2>/dev/null || true)"
      fi
    else
      target=""; blob=""
    fi
    if [[ -z "$blob" ]]; then
      echo "  unreachable"
      summary+=$'\n'"  $short: UNREACHABLE"
      alerts+=$'\n'"⚠️ $short unreachable for OS maintenance check"
      any_action=true
      # Overwrite the per-host latest so consumers don't keep seeing a stale
      # "healthy" value while the host is actually unreachable.
      report_write "maintenance/os/$short" "latest" \
        "$short OS status @ $TIMESTAMP"$'\n'"  $short: UNREACHABLE" \
        "[\"maintenance\",\"os\",\"$short\",\"automated\",\"error\"]"
      continue
    fi
    local rr rrpkgs uu sec all disk kern
    rr=$(grep '^REBOOT=' <<<"$blob" | cut -d= -f2)
    rrpkgs=$(grep '^REBOOT_PKGS=' <<<"$blob" | cut -d= -f2)
    uu=$(grep '^UU_INSTALLED=' <<<"$blob" | cut -d= -f2)
    sec=$(grep '^SEC_PENDING=' <<<"$blob" | cut -d= -f2)
    all=$(grep '^ALL_PENDING=' <<<"$blob" | cut -d= -f2)
    disk=$(grep '^DISK=' <<<"$blob" | cut -d= -f2)
    kern=$(grep '^KERNEL=' <<<"$blob" | cut -d= -f2)

    # Sanitize numeric fields — apt-check writes to stderr and can emit a
    # non-numeric error (e.g. apt-lock contention); a non-numeric value would
    # make the `[[ x -gt 0 ]]` tests below return 2 and abort under set -e.
    local v
    for v in rrpkgs uu sec all disk; do
      case "${!v}" in *[!0-9]*|'') printf -v "$v" '%s' 0 ;; esac
    done

    printf "  reboot=%s(%s) security_pending=%s all_pending=%s uu=%s disk=%s%% kernel=%s\n" \
      "$rr" "$rrpkgs" "$sec" "$all" "$uu" "$disk" "$kern"

    local line="  $short: security_pending=$sec, all_pending=$all, reboot=$rr, disk=${disk}%, uu_installed=$uu, kernel=$kern"
    summary+=$'\n'"$line"

    # Per-host Munin state
    report_write "maintenance/os/$short" "latest" \
      "$short OS status @ $TIMESTAMP"$'\n'"$line" \
      "[\"maintenance\",\"os\",\"$short\",\"automated\"]"

    # Action-needed conditions
    [[ "$rr" == "yes" ]] && { alerts+=$'\n'"🔁 $short needs a REBOOT ($rrpkgs pkg(s)): $(ssh_pkglist "$target")"; any_action=true; }
    [[ "${sec:-0}" -gt 0 ]] 2>/dev/null && { alerts+=$'\n'"🔒 $short has $sec security update(s) still pending"; any_action=true; }
    [[ "${uu:-0}" -eq 0 ]] 2>/dev/null && { alerts+=$'\n'"❗ $short: unattended-upgrades NOT installed"; any_action=true; }
    [[ "${disk:-0}" -ge "$DISK_WARN_PCT" ]] 2>/dev/null && { alerts+=$'\n'"💾 $short disk at ${disk}%"; any_action=true; }
  done

  echo
  echo "$summary"

  report_write "maintenance/os/$RUN_DATE" "summary" "$summary" \
    "[\"maintenance\",\"os\",\"automated\"]"
  report_log "maintenance/" "OS maintenance report run @ $TIMESTAMP — action_needed=$any_action" \
    "[\"maintenance\",\"os-event\",\"automated\"]"

  if $any_action && [[ -n "$alerts" ]]; then
    alert "🛠️ Grimnir OS maintenance ($RUN_DATE)${alerts}"
  fi
  echo
  $any_action && echo "Action needed (alert sent)." || echo "All hosts patched & healthy."
}

# Best-effort fetch of the reboot-required package list for the alert.
# Arg is a resolved target from resolve_remote ("LOCAL" or user@host).
ssh_pkglist() {  # target
  local target="$1" cmd='head -3 /var/run/reboot-required.pkgs 2>/dev/null | tr "\n" "," | sed "s/,$//"'
  if [[ "$target" == "LOCAL" ]]; then bash -c "$cmd" 2>/dev/null || true
  else ssh -o ConnectTimeout=6 -o BatchMode=yes "$target" "$cmd" 2>/dev/null || true; fi
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPS MODE
# ═════════════════════════════════════════════════════════════════════════════
run_deps() {
  echo "Grimnir npm dependency report — $TIMESTAMP (v$REPORT_VERSION)"
  echo

  local repos; repos="$(REGISTRY_PATH="$REGISTRY" QUERY=scan node --input-type=commonjs "$REGISTRY_JS")"
  local summary="npm outdated ($RUN_DATE):" grand_total=0 grand_major=0 checked=0 errors=0

  for repo in $repos; do
    local dir="$REPOS_DIR/$repo"
    if [[ ! -f "$dir/package.json" ]]; then
      log_verbose "skip $repo (no package.json under $dir)"; continue
    fi
    checked=$((checked + 1))
    local out rc counts total major
    # npm outdated exits 0 when up to date, 1 when packages ARE outdated, and
    # nonzero with empty/invalid stdout on a real error (network/registry).
    # Capture both stdout and exit code so a failed check isn't read as "0".
    set +e
    out="$(cd "$dir" && npm_config_cache="${npm_config_cache:-/tmp/npm-cache}" npm outdated --json 2>/dev/null)"
    rc=$?
    set -e
    counts="$(OUT="$out" RC="$rc" node --input-type=commonjs -e '
      const out=(process.env.OUT||"").trim(), rc=process.env.RC||"0";
      let o;
      try { o = out === "" ? {} : JSON.parse(out); }
      catch (e) { process.stdout.write("ERR"); process.exit(0); }
      // Error states (only when rc!=0): empty output, or npm error envelope
      // {"error":{code,summary,...}}. Distinguish that from a real dependency
      // literally named "error" (which has current/wanted/latest fields).
      const errEnv = o && o.error && typeof o.error === "object" &&
        !("latest" in o.error || "current" in o.error || "wanted" in o.error);
      if (rc !== "0" && (out === "" || errEnv)) { process.stdout.write("ERR"); process.exit(0); }
      let total=0, major=0;
      for (const k of Object.keys(o)) {
        const e = o[k];
        if (!e || typeof e !== "object") continue;   // skip non-dependency entries
        total++;
        const cur=(e.current||e.wanted||"0").split(".")[0];
        const lat=(e.latest||"0").split(".")[0];
        if (Number(lat) > Number(cur)) major++;
      }
      process.stdout.write(total+" "+major);
    ')"
    if [[ "$counts" == "ERR" ]]; then
      errors=$((errors + 1))
      printf "  %-16s CHECK FAILED (npm rc=%s)\n" "$repo" "$rc"
      summary+=$'\n'"  $repo: CHECK FAILED"
      report_write "maintenance/deps/$repo" "latest" \
        "$repo dependency check FAILED @ $TIMESTAMP (npm outdated rc=$rc)" \
        "[\"maintenance\",\"deps\",\"$repo\",\"automated\",\"error\"]"
      continue
    fi
    total="${counts%% *}"; major="${counts##* }"
    grand_total=$((grand_total + total)); grand_major=$((grand_major + major))

    printf "  %-16s outdated=%s (major=%s)\n" "$repo" "$total" "$major"
    summary+=$'\n'"  $repo: outdated=$total, major=$major"
    report_write "maintenance/deps/$repo" "latest" \
      "$repo outdated deps @ $TIMESTAMP: total=$total, major=$major" \
      "[\"maintenance\",\"deps\",\"$repo\",\"automated\"]"
  done

  summary+=$'\n'"TOTAL: $grand_total outdated across $checked repos ($grand_major major); $errors check error(s)"
  echo
  echo "$summary"

  report_write "maintenance/deps/$RUN_DATE" "summary" "$summary" \
    "[\"maintenance\",\"deps\",\"automated\"]"
  report_log "maintenance/" "npm dependency report run @ $TIMESTAMP — $grand_total outdated ($grand_major major) across $checked repos, $errors error(s)" \
    "[\"maintenance\",\"deps-event\",\"automated\"]"

  if [[ "$grand_total" -gt 0 || "$errors" -gt 0 ]]; then
    alert "📦 Grimnir deps ($RUN_DATE): $grand_total outdated across $checked repos ($grand_major major bump(s)), $errors check error(s). Review & bump deliberately.${summary#npm outdated ($RUN_DATE):}"
  fi
  echo
  echo "Done — detect+report only, nothing auto-applied."
}

# ═════════════════════════════════════════════════════════════════════════════
# BREW MODE — reports a laptop Homebrew run forwarded over SSH from the laptop.
# Data arrives via env (heredoc-free single ssh command, robust under launchd):
#   BREW_SUMMARY_B64  base64 of the one-line summary
#   BREW_NCASKS       count of casks needing manual upgrade (>0 ⇒ Telegram)
#   BREW_ALERT        "1" if the laptop run had update/upgrade failures (⇒ Telegram)
# ═════════════════════════════════════════════════════════════════════════════
run_brew() {
  local summary ncasks balert
  summary="$(printf '%s' "${BREW_SUMMARY_B64:-}" | base64 -d 2>/dev/null || true)"
  [[ -n "$summary" ]] || summary="brew (laptop) @ $TIMESTAMP: (no summary provided)"
  ncasks="${BREW_NCASKS:-0}"
  case "$ncasks" in *[!0-9]*|'') ncasks=0 ;; esac
  balert="${BREW_ALERT:-0}"
  echo "$summary"

  report_write "maintenance/brew/laptop" "latest" "$summary" \
    "[\"maintenance\",\"brew\",\"laptop\",\"automated\"]"
  report_log "maintenance/" "brew laptop report @ $TIMESTAMP — $ncasks cask(s) need manual upgrade, alert=$balert" \
    "[\"maintenance\",\"brew-event\",\"automated\"]"

  { [[ "$ncasks" -gt 0 ]] || [[ "$balert" == "1" ]]; } && alert "🍺 $summary"
  echo "Done."
}

case "$MODE" in
  os) run_os ;;
  deps) run_deps ;;
  brew) run_brew ;;
esac

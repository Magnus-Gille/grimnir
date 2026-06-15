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
  os|deps) ;;
  *) echo "Usage: $0 {os|deps} [--dry-run] [--verbose] [--munin-token T]" >&2; exit 1 ;;
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
RRPKGS=0; [ -f /var/run/reboot-required.pkgs ] && RRPKGS=$(wc -l < /var/run/reboot-required.pkgs)
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
    local short="${host%%.*}" blob
    echo "▶ $host"
    if [[ "$short" == "$LOCAL_HOST" ]]; then
      blob="$(bash -c "$probe" 2>/dev/null || true)"
    else
      blob="$(ssh -o ConnectTimeout=8 -o BatchMode=yes "$DEPLOY_USER@$host" "$probe" 2>/dev/null || true)"
    fi
    if [[ -z "$blob" ]]; then
      echo "  unreachable"
      summary+=$'\n'"  $short: UNREACHABLE"
      alerts+=$'\n'"⚠️ $short unreachable for OS maintenance check"
      any_action=true
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
    [[ "$rr" == "yes" ]] && { alerts+=$'\n'"🔁 $short needs a REBOOT ($rrpkgs pkg(s)): $(ssh_pkglist "$host" "$short")"; any_action=true; }
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

# Best-effort fetch of the reboot-required package list (short) for the alert.
ssh_pkglist() {  # host short
  local host="$1" short="$2" cmd='head -3 /var/run/reboot-required.pkgs 2>/dev/null | tr "\n" "," | sed "s/,$//"'
  if [[ "$short" == "$LOCAL_HOST" ]]; then bash -c "$cmd" 2>/dev/null || true
  else ssh -o ConnectTimeout=6 -o BatchMode=yes "$DEPLOY_USER@$host" "$cmd" 2>/dev/null || true; fi
}

# ═════════════════════════════════════════════════════════════════════════════
# DEPS MODE
# ═════════════════════════════════════════════════════════════════════════════
run_deps() {
  echo "Grimnir npm dependency report — $TIMESTAMP (v$REPORT_VERSION)"
  echo

  local repos; repos="$(REGISTRY_PATH="$REGISTRY" QUERY=scan node --input-type=commonjs "$REGISTRY_JS")"
  local summary="npm outdated ($RUN_DATE):" grand_total=0 grand_major=0 checked=0

  for repo in $repos; do
    local dir="$REPOS_DIR/$repo"
    if [[ ! -f "$dir/package.json" ]]; then
      log_verbose "skip $repo (no package.json under $dir)"; continue
    fi
    checked=$((checked + 1))
    local out counts total major
    out="$(cd "$dir" && npm_config_cache="${npm_config_cache:-/tmp/npm-cache}" npm outdated --json 2>/dev/null || true)"
    counts="$(OUT="$out" node --input-type=commonjs -e '
      let o={}; try{o=JSON.parse(process.env.OUT||"{}")}catch(e){}
      let total=0, major=0;
      for (const k of Object.keys(o)) {
        total++;
        const cur=(o[k].current||o[k].wanted||"0").split(".")[0];
        const lat=(o[k].latest||"0").split(".")[0];
        if (Number(lat) > Number(cur)) major++;
      }
      process.stdout.write(total+" "+major);
    ')"
    total="${counts%% *}"; major="${counts##* }"
    grand_total=$((grand_total + total)); grand_major=$((grand_major + major))

    printf "  %-16s outdated=%s (major=%s)\n" "$repo" "$total" "$major"
    summary+=$'\n'"  $repo: outdated=$total, major=$major"
    report_write "maintenance/deps/$repo" "latest" \
      "$repo outdated deps @ $TIMESTAMP: total=$total, major=$major" \
      "[\"maintenance\",\"deps\",\"$repo\",\"automated\"]"
  done

  summary+=$'\n'"TOTAL: $grand_total outdated across $checked repos ($grand_major major)"
  echo
  echo "$summary"

  report_write "maintenance/deps/$RUN_DATE" "summary" "$summary" \
    "[\"maintenance\",\"deps\",\"automated\"]"
  report_log "maintenance/" "npm dependency report run @ $TIMESTAMP — $grand_total outdated ($grand_major major) across $checked repos" \
    "[\"maintenance\",\"deps-event\",\"automated\"]"

  if [[ "$grand_total" -gt 0 ]]; then
    alert "📦 Grimnir deps ($RUN_DATE): $grand_total outdated across $checked repos ($grand_major major bump(s)). Review & bump deliberately.${summary#npm outdated ($RUN_DATE):}"
  fi
  echo
  echo "Done — detect+report only, nothing auto-applied."
}

case "$MODE" in
  os) run_os ;;
  deps) run_deps ;;
esac

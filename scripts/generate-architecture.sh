#!/usr/bin/env bash
# generate-architecture.sh — Assemble the full architecture reference
#
# Reads curated content from docs/architecture.md (never modified),
# generates a live deployment snapshot into docs/snapshot.md,
# and concatenates both into docs/full-architecture.md.
#
# Usage:
#   ./scripts/generate-architecture.sh [--munin-token TOKEN | --munin-token-file FILE]
#
# Idempotent, safe to run repeatedly. Completes in <60s.
# NEVER includes secret values — env var names only.
#
# Authority boundary (see docs/authority.md):
#   architecture.md owns: topology, roles, ports, security, deployment, roadmap
#   snapshot.md owns: timestamped service state, health, commits, Munin excerpts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
CURATED="$GRIMNIR_DIR/docs/architecture.md"
SNAPSHOT="$GRIMNIR_DIR/docs/snapshot.md"
OUT="$GRIMNIR_DIR/docs/full-architecture.md"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
HOSTNAME_VAL="$(hostname)"
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"

# Read component lists from the service registry (single source of truth)
if [[ -n "${REGISTRY_PATH:-}" ]]; then
  REGISTRY="$REGISTRY_PATH"
elif [[ -f "$GRIMNIR_DIR/services.local.json" ]]; then
  REGISTRY="$GRIMNIR_DIR/services.local.json"
else
  REGISTRY="$GRIMNIR_DIR/services.json"
fi
REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"

# shellcheck source=scripts/lib/systemd-status.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/systemd-status.sh"
# shellcheck source=scripts/lib/munin-rpc.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/munin-rpc.sh"
# shellcheck source=scripts/lib/credentials.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/credentials.sh"

read -ra COMPONENTS <<< "$(REGISTRY_PATH="$REGISTRY" QUERY=components node --input-type=commonjs "$REGISTRY_JS")"

# ─── CLI args ───────────────────────────────────────────────
MUNIN_TOKEN=""
MUNIN_TOKEN_FILE="${MUNIN_TOKEN_FILE:-}"
VALIDATE_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --munin-token) MUNIN_TOKEN="$2"; shift 2 ;;
    --munin-token-file) MUNIN_TOKEN_FILE="$2"; shift 2 ;;
    --validate) VALIDATE_MODE=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$MUNIN_TOKEN" && -n "$MUNIN_TOKEN_FILE" ]]; then
  MUNIN_TOKEN="$(read_credential_file "$MUNIN_TOKEN_FILE" munin-api-key)" || exit 1
fi

unit_rows_from_json() {
  local units_json=$1
  UNITS_JSON="$units_json" node --input-type=commonjs -e '
    var units = [];
    try {
      units = JSON.parse(process.env.UNITS_JSON || "[]");
    } catch (_) {
      units = [];
    }
    if (!Array.isArray(units)) units = [];
    units.forEach(function (u) {
      process.stdout.write([
        u.name,
        u.type || "service",
        u.scope || "system"
      ].join("|") + "\n");
    });
  '
}

health_status_local() {
  local port=$1 target path code last
  last="000"
  for target in localhost 127.0.0.1 $(hostname -I 2>/dev/null || true); do
    [[ -n "$target" ]] || continue
    [[ "$target" == *:* ]] && continue
    for path in /health /api/health; do
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://${target}:${port}${path}" 2>/dev/null || true)"
      if [[ "$code" == "200" ]]; then
        echo "200"
        return
      fi
      [[ -n "$code" ]] && last="$code"
    done
  done
  echo "$last"
}

health_status_remote() {
  local host=$1 port=$2 user=${SYSTEMD_USER:-grimnir}
  ssh -o ConnectTimeout=5 -o BatchMode=yes "${user}@${host}" "port='$port'; last=000; for target in localhost 127.0.0.1 \$(hostname -I 2>/dev/null || true); do [ -n \"\$target\" ] || continue; case \"\$target\" in *:*) continue ;; esac; for path in /health /api/health; do code=\$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 \"http://\${target}:\${port}\${path}\" 2>/dev/null || true); if [ \"\$code\" = 200 ]; then echo 200; exit 0; fi; [ -n \"\$code\" ] && last=\"\$code\"; done; done; echo \"\$last\"" 2>/dev/null || echo '000'
}

remote_git_checkout_freshness() {
  local host=$1 checkout=$2 branch=${3:-main} user=${SYSTEMD_USER:-grimnir}
  local q_checkout q_ref command output local_sha remote_sha
  q_checkout="$(posix_shell_quote "$checkout")"
  q_ref="$(posix_shell_quote "refs/heads/${branch}")"
  command="local_sha=\$(git -C ${q_checkout} rev-parse HEAD 2>/dev/null) || { printf '%s\\n' missing; exit 0; }; "
  command+="remote_line=\$(git -C ${q_checkout} ls-remote --exit-code origin ${q_ref} 2>/dev/null) || { printf '%s\\n' unreachable; exit 0; }; "
  # shellcheck disable=SC2016 # these variables expand on the remote host
  command+='remote_sha=${remote_line%%[[:space:]]*}; printf '\''%s|%s\n'\'' "$local_sha" "$remote_sha"'
  output="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "${user}@${host}" "$command" 2>/dev/null)" || {
    echo "unreachable"
    return 0
  }
  case "$output" in
    missing|unreachable) echo "$output" ;;
    *)
      IFS='|' read -r local_sha remote_sha <<< "$output"
      classify_registry_freshness "${local_sha:-}" "${remote_sha:-}" ok
      ;;
  esac
}

is_local_host() {
  local candidate=${1:-} short fqdn
  short="$(hostname -s 2>/dev/null || hostname)"
  fqdn="$(hostname -f 2>/dev/null || hostname)"
  [[ -n "$candidate" ]] && {
    [[ "$candidate" == "$HOSTNAME_VAL" ]] ||
    [[ "$candidate" == "$short" ]] ||
    [[ "$candidate" == "$fqdn" ]] ||
    [[ "${candidate%%.*}" == "$short" ]]
  }
}

# ─── Validate mode ────────────────────────────────────────
# Read-only comparison of registry vs live state.
# Uses SSH for cross-host checks. Writes results to Munin when configured.

if [[ "$VALIDATE_MODE" == "true" ]]; then
  # Integrity check + alert helpers for the canonical registry checkout (#47).
  # shellcheck source=scripts/lib/registry-checkout.sh
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/registry-checkout.sh"
  # shellcheck source=scripts/lib/notify.sh
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/lib/notify.sh"

  # Find Munin token (same logic as main mode)
  if [[ -z "$MUNIN_TOKEN" ]]; then
    for envfile in "$REPOS_DIR/hugin/.env" "$REPOS_DIR/ratatoskr/.env" "$REPOS_DIR/heimdall/.env"; do
      if [[ -f "$envfile" ]]; then
        val="$(grep -E '^MUNIN_API_KEY=' "$envfile" 2>/dev/null | head -1 | cut -d= -f2-)"
        if [[ -n "$val" ]]; then
          MUNIN_TOKEN="$val"
          break
        fi
      fi
    done
  fi

  echo ""
  echo "Registry Validation — $TIMESTAMP"
  echo "================================"
  echo ""

  PASS=0
  WARN=0
  FAIL=0
  RESULTS=""

  # Read host-aware registry data
  while IFS='|' read -r v_name v_host v_port v_repo v_deploy_path v_deploy_mode v_units_json; do
    [[ -z "$v_name" ]] && continue

    # Skip components with no configured host.
    if [[ -z "$v_host" ]]; then
      RESULTS+="⏭  $v_name: skipped (no host — laptop-only component)\n"
      continue
    fi

    STATUS_LINE=""
    COMPONENT_OK=true
    COMPONENT_WARN=false

    # Determine if host is local or remote
    if is_local_host "$v_host"; then
      IS_LOCAL=true
    else
      IS_LOCAL=false
    fi

    # Check systemd units
    if [[ "$v_units_json" != "[]" ]] && [[ -n "$v_units_json" ]]; then
      unit_rows="$(unit_rows_from_json "$v_units_json")"

      while IFS='|' read -r unit_name unit_kind unit_scope; do
        [[ -z "$unit_name" ]] && continue
        unit="${unit_name}.${unit_kind}"
        if [[ "$IS_LOCAL" == "true" ]]; then
          active="$(local_systemctl_status "$unit_scope" is-active "$unit")"
        else
          active="$(remote_systemctl_status "$v_host" "$unit_scope" is-active "$unit")"
        fi

        case "$(systemctl_status_severity "$active" "$unit_scope")" in
          pass)
            STATUS_LINE+=" unit:$unit($unit_scope)=active"
            ;;
          warn)
            STATUS_LINE+=" unit:$unit($unit_scope)=unreachable"
            COMPONENT_WARN=true
            ;;
          fail)
            STATUS_LINE+=" unit:$unit($unit_scope)=$active"
            COMPONENT_OK=false
            ;;
        esac
      done <<< "$unit_rows"
    fi

    # Check port / health endpoint
    if [[ -n "$v_port" ]]; then
      if [[ "$IS_LOCAL" == "true" ]]; then
        health_status="$(health_status_local "$v_port")"
      else
        health_status="$(health_status_remote "$v_host" "$v_port")"
      fi

      if [[ "$health_status" == "200" ]]; then
        STATUS_LINE+=" health:$v_port=ok"
      else
        STATUS_LINE+=" health:$v_port=http$health_status"
        COMPONENT_OK=false
      fi
    fi

    # Check deployment freshness. git-pull components are live git checkouts;
    # rsync components are stamped by deploy.sh because rsync excludes .git/.
    if [[ -n "$v_repo" ]]; then
      repo_path="${v_deploy_path:-/srv/grimnir/$v_repo}"
      if [[ "$IS_LOCAL" == "true" ]]; then
        if [[ "$v_deploy_mode" == "git-pull" ]]; then
          if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            STATUS_LINE+=" repo:not-found"
            COMPONENT_OK=false
          else
            repo_freshness="$(check_registry_freshness "$repo_path" main)"
            case "$repo_freshness" in
              current) STATUS_LINE+=" repo:current" ;;
              mismatch)
                STATUS_LINE+=" repo:remote-mismatch"
                COMPONENT_OK=false
                ;;
              *)
                STATUS_LINE+=" repo:origin-unreachable"
                COMPONENT_WARN=true
                ;;
            esac
          fi
        else
          if [[ -L "$repo_path/.deployed-commit" ]]; then
            STATUS_LINE+=" deploy:marker-symlink"
            COMPONENT_OK=false
          elif [[ -f "$repo_path/.deployed-commit" ]]; then
            marker="$(tr -d '\r\n' < "$repo_path/.deployed-commit" 2>/dev/null || true)"
            if [[ "$(classify_deploy_marker "$marker" regular)" == "valid" ]]; then
              STATUS_LINE+=" deploy:stamped:${marker:0:12}"
            else
              STATUS_LINE+=" deploy:marker-invalid"
              COMPONENT_OK=false
            fi
          else
            STATUS_LINE+=" deploy:marker-missing"
            COMPONENT_OK=false
          fi
        fi
      else
        if [[ "$v_deploy_mode" == "git-pull" ]]; then
          remote_check="$(remote_git_checkout_freshness "$v_host" "$repo_path" main)"
          case "$remote_check" in
            current) STATUS_LINE+=" repo:current" ;;
            mismatch)
              STATUS_LINE+=" repo:remote-mismatch"
              COMPONENT_OK=false
              ;;
            missing)
              STATUS_LINE+=" repo:not-found"
              COMPONENT_OK=false
              ;;
            *)
              STATUS_LINE+=" repo:origin-unreachable"
              COMPONENT_WARN=true
              ;;
          esac
        else
          q_marker="$(posix_shell_quote "$repo_path/.deployed-commit")"
          remote_check="$(ssh -o ConnectTimeout=5 -o BatchMode=yes "${SYSTEMD_USER:-grimnir}@${v_host}" "if [ -L ${q_marker} ]; then echo marker-symlink; elif [ -f ${q_marker} ]; then printf 'stamped:%s' \"\$(tr -d '\\r\\n' < ${q_marker})\"; else echo marker-missing; fi" 2>/dev/null || echo 'ssh-failed')"
          if [[ "$remote_check" == "ssh-failed" ]]; then
            STATUS_LINE+=" deploy:ssh-failed"
            COMPONENT_OK=false
          elif [[ "$remote_check" == "marker-missing" ]]; then
            STATUS_LINE+=" deploy:marker-missing"
            COMPONENT_OK=false
          elif [[ "$remote_check" == "marker-symlink" ]]; then
            STATUS_LINE+=" deploy:marker-symlink"
            COMPONENT_OK=false
          elif [[ "$remote_check" == stamped:* ]] &&
               [[ "$(classify_deploy_marker "${remote_check#stamped:}" regular)" == "valid" ]]; then
            marker="${remote_check#stamped:}"
            STATUS_LINE+=" deploy:stamped:${marker:0:12}"
          else
            STATUS_LINE+=" deploy:marker-invalid"
            COMPONENT_OK=false
          fi
        fi
      fi
    fi

    # Emit result line
    if [[ "$COMPONENT_OK" != "true" ]]; then
      RESULTS+="❌ $v_name:$STATUS_LINE\n"
      FAIL=$((FAIL + 1))
    elif [[ "$COMPONENT_WARN" == "true" ]]; then
      RESULTS+="⚠️  $v_name:$STATUS_LINE\n"
      WARN=$((WARN + 1))
    else
      RESULTS+="✅ $v_name:$STATUS_LINE\n"
      PASS=$((PASS + 1))
    fi
  done < <(REGISTRY_PATH="$REGISTRY" QUERY=validate node --input-type=commonjs "$REGISTRY_JS")

  # ─── Registry checkout integrity (#47) ───────────────────
  # The canonical Grimnir checkout is the source every registry
  # consumer reads services.json from. If a hugin task strands it on a feature
  # branch, or a deploy leaves the tree dirty, consumers silently read a
  # poisoned registry — the class of the #33 and #44 incidents. Make that
  # alert-worthy. Read-only; overridable via env for a relocated checkout.
  REGISTRY_CHECKOUT="${GRIMNIR_REGISTRY_CHECKOUT:-$GRIMNIR_DIR}"
  REGISTRY_DEFAULT_BRANCH="${GRIMNIR_DEFAULT_BRANCH:-main}"
  checkout_verdict="$(check_registry_checkout "$REGISTRY_CHECKOUT" "$REGISTRY_DEFAULT_BRANCH")"
  checkout_detail="$(registry_checkout_detail "$checkout_verdict" "$REGISTRY_DEFAULT_BRANCH")"
  checkout_freshness="$(check_registry_freshness "$REGISTRY_CHECKOUT" "$REGISTRY_DEFAULT_BRANCH")"
  freshness_detail="$(registry_freshness_detail "$checkout_freshness")"
  if [[ "$(registry_checkout_is_alert "$checkout_verdict")" == "yes" ]]; then
    RESULTS+="❌ registry-checkout: ${checkout_detail} ($REGISTRY_CHECKOUT)\n"
    FAIL=$((FAIL + 1))
    # Best-effort Telegram alert (never fails this script — notify.sh is safe
    # under set -euo pipefail). This is the poisoned-registry early warning.
    notify_telegram "⚠️ grimnir registry checkout poisoned: ${checkout_detail} at ${REGISTRY_CHECKOUT} on $(hostname). Registry consumers may read a stale/wrong services.json until reconciled to ${REGISTRY_DEFAULT_BRANCH}." || true
  elif [[ "$checkout_freshness" == "mismatch" ]]; then
    RESULTS+="❌ registry-checkout: ${checkout_detail}, ${freshness_detail} ($REGISTRY_CHECKOUT)\n"
    FAIL=$((FAIL + 1))
    notify_telegram "⚠️ grimnir registry checkout differs from live origin/main at ${REGISTRY_CHECKOUT} on $(hostname). Refusing to re-stamp the deployment marker." || true
  elif [[ "$checkout_freshness" == "unreachable" ]]; then
    RESULTS+="⚠️  registry-checkout: ${checkout_detail}, ${freshness_detail} ($REGISTRY_CHECKOUT)\n"
    WARN=$((WARN + 1))
  else
    RESULTS+="✅ registry-checkout: ${checkout_detail}, ${freshness_detail} ($REGISTRY_CHECKOUT)\n"
    PASS=$((PASS + 1))
    # Self-heal the git-pull deploy marker (#33). Sessions pull this canonical
    # checkout forward OUTSIDE a deploy, leaving .deployed-commit — what Heimdall's
    # drift detector reads — stale, so Heimdall false-flags every grimnir unit as
    # behind origin. restamp_deploy_marker only writes because we reached this
    # branch (checkout verified clean AND on the default branch) and a marker
    # already exists. A non-zero return means the marker is stale but the write was
    # refused (e.g. this service's read-only sandbox — see ReadWritePaths in
    # grimnir-validate.service); surface it instead of letting the drift silently
    # persist.
    if ! restamp_deploy_marker "$REGISTRY_CHECKOUT" "$checkout_verdict" "$checkout_freshness"; then
      RESULTS+="⚠️  deploy-marker: .deployed-commit not safely writable (read-only mount or symlink) — Heimdall drift may false-flag\n"
      WARN=$((WARN + 1))
    fi
  fi

  # Print results
  echo -e "$RESULTS"
  echo ""
  echo "Summary: $PASS ok, $FAIL issues, $WARN warnings"
  echo ""

  # Write to Munin if token available
  VALIDATION_PERSISTED=false
  if [[ -n "$MUNIN_TOKEN" ]]; then
    # Munin helpers (inline — validation mode is self-contained)
    _munin_call() {
      munin_http_jsonrpc "$MUNIN_TOKEN" "$1"
    }

    validation_content="## Registry Validation — $TIMESTAMP

$PASS ok, $FAIL issues, $WARN warnings

$(echo -e "$RESULTS")"

    write_payload="$(CONTENT_VAL="$validation_content" node --input-type=commonjs -e '
      console.log(JSON.stringify({
        jsonrpc: "2.0", id: 1, method: "tools/call",
        params: {
          name: "memory_write",
          arguments: {
            namespace: "validation/registry",
            key: "latest",
            content: process.env.CONTENT_VAL,
            tags: ["validation", "registry", "automated"]
          }
        }
      }))
    ')"
    if _munin_call "$write_payload" > /dev/null 2>&1; then
      VALIDATION_PERSISTED=true
    else
      echo "⚠ Failed to write validation results to Munin"
    fi

    # Also log the event
    log_payload="$(CONTENT_VAL="Registry validation: $PASS ok, $FAIL issues at $TIMESTAMP" node --input-type=commonjs -e '
      console.log(JSON.stringify({
        jsonrpc: "2.0", id: 1, method: "tools/call",
        params: {
          name: "memory_log",
          arguments: {
            namespace: "validation/",
            content: process.env.CONTENT_VAL,
            tags: ["validation", "registry", "automated"]
          }
        }
      }))
    ')"
    if ! _munin_call "$log_payload" > /dev/null 2>&1; then
      echo "⚠ Failed to append validation event to Munin"
      VALIDATION_PERSISTED=false
    fi

    if [[ "$VALIDATION_PERSISTED" == "true" ]]; then
      echo "📡 Results written to Munin (validation/registry/latest)"
    fi
  else
    echo "⚠ No Munin token — results printed to stdout only"
  fi

  # A systemd-successful run means both the live checks and their durable
  # operator-facing record succeeded. Findings remain in stdout/Munin first.
  if [[ "$FAIL" -gt 0 ]] || [[ "$VALIDATION_PERSISTED" != "true" ]]; then
    exit 1
  fi
  exit 0
fi

# ─── Verify curated source exists ─────────────────────────
if [[ ! -f "$CURATED" ]]; then
  echo "❌ Curated source not found: $CURATED"
  exit 1
fi

# ─── Find Munin bearer token ──────────────────────────────
if [[ -z "$MUNIN_TOKEN" ]]; then
  for envfile in "$REPOS_DIR/hugin/.env" "$REPOS_DIR/ratatoskr/.env" "$REPOS_DIR/heimdall/.env"; do
    if [[ -f "$envfile" ]]; then
      val="$(grep -E '^MUNIN_API_KEY=' "$envfile" 2>/dev/null | head -1 | cut -d= -f2-)"
      if [[ -n "$val" ]]; then
        MUNIN_TOKEN="$val"
        break
      fi
    fi
  done
fi

# ─── Helper functions ─────────────────────────────────────

munin_call() {
  local payload="$1"
  if [[ -z "$MUNIN_TOKEN" ]]; then
    echo "(Munin token not available)"
    return 1
  fi
  munin_http_jsonrpc "$MUNIN_TOKEN" "$payload"
}

munin_tool_call() {
  local tool_name="$1" args_json="$2"
  local payload
  payload=$(TOOL_NAME="$tool_name" ARGS_JSON="$args_json" node -e "
    console.log(JSON.stringify({
      jsonrpc: '2.0', id: 1, method: 'tools/call',
      params: { name: process.env.TOOL_NAME, arguments: JSON.parse(process.env.ARGS_JSON) }
    }))
  ")
  munin_call "$payload"
}

service_status_row() {
  local unit_name="$1" unit_kind="$2" unit_scope="$3"
  local unit="${unit_name}.${unit_kind}"
  local active enabled pid mem mem_mb started
  local -a systemctl_prefix
  if [[ "$unit_scope" == "user" ]]; then
    active="$(local_systemctl_status user is-active "$unit")"
    enabled="$(local_systemctl_status user is-enabled "$unit")"
  else
    systemctl_prefix=(systemctl)
    active="$("${systemctl_prefix[@]}" is-active "$unit" 2>/dev/null || echo 'unknown')"
    enabled="$("${systemctl_prefix[@]}" is-enabled "$unit" 2>/dev/null || echo 'unknown')"
  fi
  if [[ "$active" == "active" && "$unit_kind" == "service" ]]; then
    if [[ "$unit_scope" == "user" ]]; then
      pid="$(systemctl_user show "$unit" --property=MainPID | cut -d= -f2)"
      mem="$(systemctl_user show "$unit" --property=MemoryCurrent | cut -d= -f2)"
      started="$(systemctl_user show "$unit" --property=ExecMainStartTimestamp | cut -d= -f2-)"
    else
      pid="$("${systemctl_prefix[@]}" show "$unit" --property=MainPID 2>/dev/null | cut -d= -f2)"
      mem="$("${systemctl_prefix[@]}" show "$unit" --property=MemoryCurrent 2>/dev/null | cut -d= -f2)"
      started="$("${systemctl_prefix[@]}" show "$unit" --property=ExecMainStartTimestamp 2>/dev/null | cut -d= -f2-)"
    fi
    if [[ "$mem" =~ ^[0-9]+$ ]] && [[ "$mem" -gt 0 ]]; then
      mem_mb="$((mem / 1024 / 1024))MB"
    else
      mem_mb="n/a"
    fi
    echo "| $unit | $unit_scope | ✅ $active | $enabled | $pid | $mem_mb | $started |"
  elif [[ "$active" == "active" ]]; then
    echo "| $unit | $unit_scope | ✅ $active | $enabled | — | — | — |"
  else
    echo "| $unit | $unit_scope | ❌ $active | $enabled | — | — | — |"
  fi
}

# ─── Begin snapshot generation ─────────────────────────────

echo "🔨 Generating deployment snapshot..."
echo "   Timestamp: $TIMESTAMP"
echo "   Host: $HOSTNAME_VAL"
echo ""

# ─── Service status ───────────────────────────────────────

echo "🔍 Collecting service status..."
DEPLOYMENT_TABLE=""
while IFS='|' read -r _s_name _s_host _s_port _s_repo _s_deploy_path _s_deploy_mode s_units_json; do
  [[ -n "$s_units_json" && "$s_units_json" != "[]" ]] || continue
  s_unit_rows="$(unit_rows_from_json "$s_units_json")"
  while IFS='|' read -r s_unit_name s_unit_kind s_unit_scope; do
    [[ -n "$s_unit_name" ]] || continue
    DEPLOYMENT_TABLE+="$(service_status_row "$s_unit_name" "$s_unit_kind" "$s_unit_scope")\n"
  done <<< "$s_unit_rows"
done < <(REGISTRY_PATH="$REGISTRY" QUERY=validate node --input-type=commonjs "$REGISTRY_JS")

# ─── Git versions ─────────────────────────────────────────

echo "🔍 Collecting git versions..."
GIT_VERSIONS=""
for comp in "${COMPONENTS[@]}"; do
  dir="$REPOS_DIR/$comp"
  if [[ -d "$dir/.git" ]]; then
    # shellcheck disable=SC2016 # single-quoted --format is a literal git format string, not shell expansion
    info="$(git -C "$dir" log -1 --format='`%h` %s (%ar)' 2>/dev/null || echo '(unknown)')"
    branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    dirty=""
    if [[ -n "$(git -C "$dir" status --porcelain 2>/dev/null)" ]]; then
      dirty=" ⚠️ dirty"
    fi
    GIT_VERSIONS+="| $comp | $branch | $info |$dirty\n"
  else
    GIT_VERSIONS+="| $comp | — | (not a git repo) |\n"
  fi
done

# ─── Health checks ────────────────────────────────────────

echo "🔍 Running health checks..."
HEALTH_RESULTS=""
while IFS='|' read -r h_name h_host h_port _h_repo _h_deploy_path _h_deploy_mode _h_units_json; do
  [[ -n "$h_name" && -n "$h_port" ]] || continue

  if is_local_host "$h_host"; then
    status="$(health_status_local "$h_port")"
  else
    status="$(health_status_remote "$h_host" "$h_port")"
  fi

  if [[ "$status" == "200" ]]; then
    HEALTH_RESULTS+="- ✅ **$h_name** (:$h_port) — HTTP $status\n"
  elif [[ "$status" == "000" ]]; then
    HEALTH_RESULTS+="- ❌ **$h_name** (:$h_port) — unreachable\n"
  else
    HEALTH_RESULTS+="- ⚠️ **$h_name** (:$h_port) — HTTP $status\n"
  fi
done < <(REGISTRY_PATH="$REGISTRY" QUERY=validate node --input-type=commonjs "$REGISTRY_JS")

# ─── Munin project statuses ──────────────────────────────

echo "📡 Querying Munin for project statuses..."
MUNIN_STATUSES=""
SEEN_NS=""

for ns_source in "${COMPONENTS[@]}" "grimnir" "grimnir-system"; do
  ns="projects/$ns_source"
  # Skip duplicates
  if echo "$SEEN_NS" | grep -qF "$ns"; then
    continue
  fi
  SEEN_NS+="$ns "

  result="$(munin_tool_call "memory_read" "{\"namespace\":\"$ns\",\"key\":\"status\"}" 2>/dev/null || echo "")"
  if [[ -n "$result" ]]; then
    content="$(echo "$result" | node -e "
      const d=JSON.parse(require('fs').readFileSync('/dev/stdin','utf8'));
      const c=JSON.parse(d?.result?.content?.[0]?.text || '{}');
      if(c.found) console.log(c.content||'');
    " 2>/dev/null || echo "")"
    if [[ -n "$content" ]]; then
      MUNIN_STATUSES+="### $ns\n\n$content\n\n---\n\n"
    fi
  fi
done

# ─── Write snapshot.md ────────────────────────────────────

echo "📝 Writing $SNAPSHOT..."

cat > "$SNAPSHOT" << EOF

---

## Deployment Snapshot

> Captured at $TIMESTAMP on \`$HOSTNAME_VAL\`
>
> This section is auto-generated by \`scripts/generate-architecture.sh\`.
> Do not edit — changes will be overwritten. Edit \`docs/architecture.md\` for curated content.

### Service Status

| Unit | Scope | State | Enabled | PID | Memory | Started |
|------|-------|-------|---------|-----|--------|---------|
$(echo -e "$DEPLOYMENT_TABLE")

### Repository Versions

| Repo | Branch | Last Commit |
|------|--------|-------------|
$(echo -e "$GIT_VERSIONS")

### Health Checks

$(echo -e "$HEALTH_RESULTS")
EOF

# Munin project statuses
if [[ -n "$MUNIN_STATUSES" ]]; then
  cat >> "$SNAPSHOT" << EOF

---

## Project Statuses (from Munin)

> Live project state from Munin memory. Authoritative for current work and blockers.
> Architecture facts (roles, ports, topology) are owned by the sections above.

$(echo -e "$MUNIN_STATUSES")
EOF
fi

# Footer
cat >> "$SNAPSHOT" << EOF

---

*Snapshot generated at $TIMESTAMP on \`$HOSTNAME_VAL\` by \`scripts/generate-architecture.sh\`*
EOF

# ─── Assemble full-architecture.md ─────────────────────────

echo "📝 Assembling $OUT..."
cat "$CURATED" "$SNAPSHOT" > "$OUT"

# ─── Verify no secrets leaked ─────────────────────────────

SECRET_CHECK="$(grep -E '(Bearer [A-Za-z0-9_/+=-]{10,}|eyJ[A-Za-z0-9_-]{20,}|sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{30,}|gho_[a-zA-Z0-9]{30,}|glpat-[a-zA-Z0-9-]{20,}|xox[bpas]-[a-zA-Z0-9-]{20,}|AKIA[A-Z0-9]{16}|[a-f0-9]{32,})' "$OUT" | grep -v '\*\*\*\|<TOKEN>\|<key>\|<same key' | grep -v 'sha256\|Source hash\|SOURCE_HASH\|commit hash' || true)"
if [[ -n "$SECRET_CHECK" ]]; then
  echo "⚠️  WARNING: Possible secret detected in output! Review before committing:"
  echo "$SECRET_CHECK"
else
  echo "   ✅ No secrets detected in output"
fi

echo ""
echo "✅ Done:"
echo "   Curated: $CURATED ($(wc -l < "$CURATED") lines)"
echo "   Snapshot: $SNAPSHOT ($(wc -l < "$SNAPSHOT") lines)"
echo "   Combined: $OUT ($(wc -l < "$OUT") lines)"

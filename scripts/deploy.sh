#!/usr/bin/env bash
set -euo pipefail

# Grimnir deploy script — deploys services to Pi hosts via SSH.
# Usage: ./scripts/deploy.sh [service[=/abs/path/to/worktree] ...]
# No args = deploy all services. Pass one or more names to deploy selectively.
# Use name=/path to deploy from a specific local worktree instead of $HOME/repos/<repo>.
#
# Service list is read from services.json (the single source of truth).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
REGISTRY="${REGISTRY_PATH:-$GRIMNIR_DIR/services.json}"
REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"
REGISTRY_VALIDATOR="$SCRIPT_DIR/lib/validate-registry.js"

# Read deployable services from registry:
# name|repo|host|deploy_path|unit_type|needs_build|unit_scope|deploy_mode|units_json|rsync_excludes_json
if ! REGISTRY_PATH="$REGISTRY" node --input-type=commonjs "$REGISTRY_VALIDATOR"; then
  echo "ERROR: Refusing deploy because registry validation failed" >&2
  exit 1
fi

SERVICES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SERVICES+=("$line")
done < <(REGISTRY_PATH="$REGISTRY" QUERY=deploy node --input-type=commonjs "$REGISTRY_JS")

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  echo "ERROR: No deployable services found in $REGISTRY" >&2
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

pass=0
fail=0
skip=0
results=()
DEPLOY_USER="${DEPLOY_USER:-magnus}"
LOCAL_REPOS_ROOT="${LOCAL_REPOS_ROOT:-$HOME/repos}"

resolve_host() {
  local input=$1

  if [[ "$input" != *.local ]]; then
    echo "$input"
    return
  fi

  if ssh -o ConnectTimeout=2 -o BatchMode=yes "${DEPLOY_USER}@${input}" true &>/dev/null; then
    echo "$input"
    return
  fi

  local bare="${input%.local}"
  if ssh -o ConnectTimeout=5 -o BatchMode=yes "${DEPLOY_USER}@${bare}" true &>/dev/null; then
    echo >&2 "Note: $input not reachable, using Tailscale ($bare)"
    echo "$bare"
    return
  fi

  echo >&2 "ERROR: Cannot reach $input or $bare"
  return 1
}

build_locally() {
  local repo_path=$1

  if [[ ! -f "$repo_path/package.json" ]]; then
    echo "ERROR: $repo_path has no package.json but is marked needs_build=true" >&2
    return 1
  fi

  (
    cd "$repo_path"
    if [[ -f package-lock.json ]]; then
      npm ci
    else
      npm install
    fi
    npm run build
  )
}

resolve_local_path() {
  local service_name=$1 repo=$2
  local req

  # ${arr[@]+...} idiom: bash 3.2 (macOS) treats an empty array's "${arr[@]}"
  # as unbound under set -u — this crashed every no-args `make deploy`.
  for req in ${requested[@]+"${requested[@]}"}; do
    if [[ "$req" == "${service_name}="* ]]; then
      echo "${req#*=}"
      return
    fi
  done

  echo "${LOCAL_REPOS_ROOT}/${repo}"
}

unit_rows() {
  local units_json=$1 fallback_name=$2 fallback_type=$3 fallback_scope=$4
  UNITS_JSON="$units_json" FALLBACK_NAME="$fallback_name" FALLBACK_TYPE="$fallback_type" FALLBACK_SCOPE="$fallback_scope" \
    node --input-type=commonjs -e '
      var units = [];
      try {
        units = JSON.parse(process.env.UNITS_JSON || "[]");
      } catch (_) {
        units = [];
      }
      if (!Array.isArray(units) || units.length === 0) {
        units = [{
          name: process.env.FALLBACK_NAME,
          type: process.env.FALLBACK_TYPE || "service",
          scope: process.env.FALLBACK_SCOPE || "system"
        }];
      }
      units.forEach(function (u) {
        process.stdout.write([
          u.name,
          u.type || "service",
          u.scope || "system"
        ].join("|") + "\n");
      });
    '
}

rsync_exclude_rows() {
  local excludes_json=$1
  RSYNC_EXCLUDES_JSON="$excludes_json" node --input-type=commonjs -e '
    var excludes = JSON.parse(process.env.RSYNC_EXCLUDES_JSON || "[]");
    excludes.forEach(function (exclude) { process.stdout.write(exclude + "\n"); });
  '
}

deploy_service() {
  local name=$1 repo=$2 host=$3 deploy_path=$4 unit_type=$5 needs_build=$6 unit_scope=${7:-system} deploy_mode=${8:-rsync} units_json=${9:-[]}
  local rsync_excludes_json=${10:-[]}
  local local_path
  local remote_host
  local remote
  local branch
  local commit
  local dirty_state

  echo -e "\n${BOLD}=== ${name} (${host}) ===${NC}"

  local_path=$(resolve_local_path "$name" "$repo")

  if [[ ! -d "$local_path" ]]; then
    echo "ERROR: Local repo not found: $local_path" >&2
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi

  branch=$(git -C "$local_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  commit=$(git -C "$local_path" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  commit_full=$(git -C "$local_path" rev-parse HEAD 2>/dev/null || echo "$commit")
  if [[ "$deploy_mode" == "git-pull" ]]; then
    # git-pull mode ships origin/main on the remote — the local tree is not
    # the source, so its branch/dirtiness is informational only.
    echo "Source: origin/main (deploy_mode=git-pull — local tree not shipped; local: ${branch} @ ${commit})"
  else
    if [[ -n "$(git -C "$local_path" status --porcelain 2>/dev/null)" ]]; then
      dirty_state="dirty"
      echo -e "${YELLOW}WARN${NC} Deploying local working tree with uncommitted changes"
    else
      dirty_state="clean"
    fi
    echo "Source: ${local_path} (${branch} @ ${commit}, ${dirty_state})"
  fi

  if ! remote_host=$(resolve_host "$host"); then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi
  remote="${DEPLOY_USER}@${remote_host}"

  # Build locally before syncing if runtime expects generated artifacts like dist/
  # (irrelevant in git-pull mode — nothing local is shipped)
  if [[ "$needs_build" == "true" && "$deploy_mode" != "git-pull" ]]; then
    echo "==> Building locally..."
    if ! build_locally "$local_path"; then
      echo -e "${RED}FAILED${NC}"
      results+=("${RED}✗${NC} ${name}")
      fail=$((fail + 1))
      return
    fi
  fi

  if [[ "$deploy_mode" == "git-pull" ]]; then
    # git-pull mode (Option A, docs/role-separation.md): the checkout IS the
    # deployment. Fast-forward it to origin/main — never force, never rsync —
    # so checkout == HEAD == origin/main by construction. A dirty tree or
    # diverged branch fails loudly here and trips the registry-checkout alarm.
    echo "==> Updating ${remote}:${deploy_path} via git pull --ff-only..."
    # Post-conditions are checked explicitly because `pull --ff-only` exits 0
    # in two bad states (codex review, PR #54): a local main AHEAD of origin
    # (stray commit — the #44 incident class) and unrelated dirty tracked
    # files. Either would let the stamp certify a non-canonical tree, so both
    # fail the deploy loudly instead.
    local pull_cmd
    pull_cmd="git -C '$deploy_path' fetch --quiet origin && "
    pull_cmd+="git -C '$deploy_path' checkout --quiet main && "
    pull_cmd+="git -C '$deploy_path' pull --ff-only --quiet origin main && "
    pull_cmd+="if [ -n \"\$(git -C '$deploy_path' status --porcelain)\" ]; then echo 'ERROR: checkout dirty after pull' >&2; exit 1; fi && "
    pull_cmd+="if [ \"\$(git -C '$deploy_path' rev-parse HEAD)\" != \"\$(git -C '$deploy_path' rev-parse origin/main)\" ]; then echo 'ERROR: HEAD != origin/main after pull (stray local commits?)' >&2; exit 1; fi"
    # shellcheck disable=SC2029 # deploy_path is a local var; intentional client-side expansion
    if ! ssh -o ConnectTimeout=10 "$remote" "$pull_cmd"; then
      echo -e "${RED}FAILED${NC}"
      results+=("${RED}✗${NC} ${name}")
      fail=$((fail + 1))
      return
    fi
  else

  echo "==> Syncing to ${remote}:${deploy_path}..."
  # shellcheck disable=SC2029 # deploy_path is a local var; intentional client-side expansion
  if ! ssh "$remote" "mkdir -p '$deploy_path'"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi
  local rsync_exclude rsync_args
  rsync_args=(-az --delete
    --exclude='node_modules/'
    --exclude='.git'
    --exclude='.git/'
    --exclude='.env'
    --exclude='tests/'
    --exclude='.DS_Store'
    --exclude='.deployed-commit')
  while IFS= read -r rsync_exclude; do
    [[ -n "$rsync_exclude" ]] && rsync_args+=("--exclude=${rsync_exclude}")
  done < <(rsync_exclude_rows "$rsync_excludes_json")
  if ! rsync "${rsync_args[@]}" "$local_path/" "$remote:$deploy_path/"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi

  echo "==> Installing production dependencies on ${remote_host}..."
  # shellcheck disable=SC2029 # deploy_path is a local var; intentional client-side expansion
  if ! ssh "$remote" "cd '$deploy_path' && if [ -f package.json ]; then npm install --omit=dev; fi"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi

  fi # end rsync-mode block (deploy_mode != git-pull)

  local cmd="cd '$deploy_path' && "
  local rows unit_name unit_kind unit_actual_scope unit_file companion_file
  local user_needs_reload=false system_needs_reload=false
  local user_services=() system_services=() user_timers=() system_timers=()

  rows="$(unit_rows "$units_json" "$name" "$unit_type" "$unit_scope")"
  while IFS='|' read -r unit_name unit_kind unit_actual_scope; do
    [[ -n "$unit_name" ]] || continue
    unit_file="${unit_name}.${unit_kind}"

    if [[ "$unit_actual_scope" == "user" ]]; then
      cmd+="unit_src=''; for f in systemd/${unit_file} ${unit_file}; do [ -f \"\$f\" ] && unit_src=\"\$f\" && break; done; "
      cmd+="[ -n \"\$unit_src\" ] || { echo 'ERROR: unit file missing: ${unit_file}' >&2; exit 1; }; "
      cmd+="install -D -m644 \"\$unit_src\" \"\$HOME/.config/systemd/user/${unit_file}\" && "
      user_needs_reload=true
      if [[ "$unit_kind" == "service" ]]; then
        user_services+=("$unit_name")
      elif [[ "$unit_kind" == "timer" ]]; then
        companion_file="${unit_name}.service"
        cmd+="companion_src=''; for f in systemd/${companion_file} ${companion_file}; do [ -f \"\$f\" ] && companion_src=\"\$f\" && break; done; "
        cmd+="if [ -n \"\$companion_src\" ]; then install -D -m644 \"\$companion_src\" \"\$HOME/.config/systemd/user/${companion_file}\"; fi && "
        user_timers+=("$unit_name")
      fi
    else
      cmd+="unit_src=''; for f in systemd/${unit_file} ${unit_file}; do [ -f \"\$f\" ] && unit_src=\"\$f\" && break; done; "
      cmd+="[ -n \"\$unit_src\" ] || { echo 'ERROR: unit file missing: ${unit_file}' >&2; exit 1; }; "
      cmd+="sudo install -D -m644 \"\$unit_src\" \"/etc/systemd/system/${unit_file}\" && "
      system_needs_reload=true
      if [[ "$unit_kind" == "service" ]]; then
        system_services+=("$unit_name")
      elif [[ "$unit_kind" == "timer" ]]; then
        companion_file="${unit_name}.service"
        cmd+="companion_src=''; for f in systemd/${companion_file} ${companion_file}; do [ -f \"\$f\" ] && companion_src=\"\$f\" && break; done; "
        cmd+="if [ -n \"\$companion_src\" ]; then sudo install -D -m644 \"\$companion_src\" \"/etc/systemd/system/${companion_file}\"; fi && "
        system_timers+=("$unit_name")
      fi
    fi
  done <<< "$rows"

  if [[ "$user_needs_reload" == "true" ]]; then
    cmd+="systemctl --user daemon-reload && "
  fi
  if [[ "$system_needs_reload" == "true" ]]; then
    cmd+="sudo systemctl daemon-reload && "
  fi
  for unit_name in ${user_services[@]+"${user_services[@]}"}; do
    cmd+="systemctl --user restart ${unit_name}.service && "
  done
  for unit_name in ${system_services[@]+"${system_services[@]}"}; do
    # Kill any leftover user-unit instance holding the port before the system unit restarts.
    cmd+="{ systemctl --user stop ${unit_name}.service 2>/dev/null || true; } && "
    cmd+="{ systemctl --user disable ${unit_name}.service 2>/dev/null || true; } && "
    cmd+="sudo systemctl restart ${unit_name}.service && "
  done
  for unit_name in ${user_timers[@]+"${user_timers[@]}"}; do
    cmd+="systemctl --user enable --now ${unit_name}.timer && "
  done
  for unit_name in ${system_timers[@]+"${system_timers[@]}"}; do
    cmd+="sudo systemctl enable --now ${unit_name}.timer && "
  done
  # Stamp the deployed commit so Heimdall's drift detector has an authoritative
  # source (excluded from rsync above so --delete won't clobber it). Heimdall
  # reads <deploy_path>/.deployed-commit instead of trusting /health (often no
  # commit) or the on-Pi .git (stale — rsync excludes it).
  if [[ "$deploy_mode" == "git-pull" ]]; then
    # In git-pull mode the remote HEAD is the ground truth (origin/main was
    # just pulled) — stamp that, not the local checkout's commit.
    cmd+="git rev-parse HEAD > .deployed-commit && "
  else
    cmd+="printf '%s\\n' '${commit_full}' > .deployed-commit && "
  fi
  cmd+="echo 'DEPLOY_OK'"

  local output
  if output=$(ssh -o ConnectTimeout=10 "$remote" "$cmd" 2>&1); then
    if echo "$output" | grep -q "DEPLOY_OK"; then
      echo -e "${GREEN}OK${NC}"
      results+=("${GREEN}✓${NC} ${name}")
      pass=$((pass + 1))
    else
      echo "$output"
      echo -e "${YELLOW}WARN — completed but no OK marker${NC}"
      results+=("${YELLOW}?${NC} ${name}")
      skip=$((skip + 1))
    fi
  else
    echo "$output"
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
  fi
}

# Filter to requested services, or deploy all
requested=("$@")

for entry in "${SERVICES[@]}"; do
  IFS='|' read -r name repo host deploy_path unit_type needs_build unit_scope deploy_mode units_json rsync_excludes_json <<< "$entry"

  if [[ ${#requested[@]} -gt 0 ]]; then
    match=false
    for req in ${requested[@]+"${requested[@]}"}; do
      [[ "$req" == "$name" || "$req" == "${name}="* ]] && match=true && break
    done
    $match || continue
  fi

  deploy_service "$name" "$repo" "$host" "$deploy_path" "$unit_type" "$needs_build" "${unit_scope:-system}" "${deploy_mode:-rsync}" "${units_json:-[]}" "${rsync_excludes_json:-[]}"
done

# Summary
echo -e "\n${BOLD}--- Summary ---${NC}"
for r in "${results[@]}"; do
  echo -e "  $r"
done
echo ""
echo -e "  ${GREEN}${pass} passed${NC}  ${RED}${fail} failed${NC}  ${YELLOW}${skip} warnings${NC}"

[[ $fail -eq 0 ]] || exit 1

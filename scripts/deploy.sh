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
REGISTRY="$GRIMNIR_DIR/services.json"
REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"

# Read deployable services from registry: name|repo|host|deploy_path|unit_type|needs_build
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

  for req in "${requested[@]}"; do
    if [[ "$req" == "${service_name}="* ]]; then
      echo "${req#*=}"
      return
    fi
  done

  echo "${LOCAL_REPOS_ROOT}/${repo}"
}

deploy_service() {
  local name=$1 repo=$2 host=$3 deploy_path=$4 unit_type=$5 needs_build=$6
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
  if [[ -n "$(git -C "$local_path" status --porcelain 2>/dev/null)" ]]; then
    dirty_state="dirty"
    echo -e "${YELLOW}WARN${NC} Deploying local working tree with uncommitted changes"
  else
    dirty_state="clean"
  fi
  echo "Source: ${local_path} (${branch} @ ${commit}, ${dirty_state})"

  if ! remote_host=$(resolve_host "$host"); then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi
  remote="${DEPLOY_USER}@${remote_host}"

  # Build locally before syncing if runtime expects generated artifacts like dist/
  if [[ "$needs_build" == "true" ]]; then
    echo "==> Building locally..."
    if ! build_locally "$local_path"; then
      echo -e "${RED}FAILED${NC}"
      results+=("${RED}✗${NC} ${name}")
      fail=$((fail + 1))
      return
    fi
  fi

  echo "==> Syncing to ${remote}:${deploy_path}..."
  if ! ssh "$remote" "mkdir -p '$deploy_path'"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi
  if ! rsync -az --delete \
    --exclude='node_modules/' \
    --exclude='.git/' \
    --exclude='.env' \
    --exclude='tests/' \
    --exclude='.DS_Store' \
    "$local_path/" "$remote:$deploy_path/"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi

  echo "==> Installing production dependencies on ${remote_host}..."
  if ! ssh "$remote" "cd '$deploy_path' && if [ -f package.json ]; then npm install --omit=dev; fi"; then
    echo -e "${RED}FAILED${NC}"
    results+=("${RED}✗${NC} ${name}")
    fail=$((fail + 1))
    return
  fi

  local cmd="cd '$deploy_path' && "
  if [[ "$unit_type" == "service" ]]; then
    cmd+="sudo systemctl restart ${name} && "
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
  IFS='|' read -r name repo host deploy_path unit_type needs_build <<< "$entry"

  if [[ ${#requested[@]} -gt 0 ]]; then
    match=false
    for req in "${requested[@]}"; do
      [[ "$req" == "$name" || "$req" == "${name}="* ]] && match=true && break
    done
    $match || continue
  fi

  deploy_service "$name" "$repo" "$host" "$deploy_path" "$unit_type" "$needs_build"
done

# Summary
echo -e "\n${BOLD}--- Summary ---${NC}"
for r in "${results[@]}"; do
  echo -e "  $r"
done
echo ""
echo -e "  ${GREEN}${pass} passed${NC}  ${RED}${fail} failed${NC}  ${YELLOW}${skip} warnings${NC}"

[[ $fail -eq 0 ]] || exit 1

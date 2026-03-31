#!/usr/bin/env bash
set -euo pipefail

# Grimnir deploy script — deploys services to Pi hosts via SSH.
# Usage: ./scripts/deploy.sh [service...]
# No args = deploy all services. Pass one or more names to deploy selectively.

# Service registry: name|host|path|unit_type|needs_build
SERVICES=(
  "munin-memory|huginmunin.local|~/repos/munin-memory|service|false"
  "hugin|huginmunin.local|~/repos/hugin|service|false"
  "heimdall|huginmunin.local|~/repos/heimdall|service|false"
  "ratatoskr|huginmunin.local|~/repos/ratatoskr|service|false"
  "skuld|huginmunin.local|~/repos/skuld|timer|false"
  "mimir|nas.local|~/repos/mimir|service|true"
)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

pass=0
fail=0
skip=0
results=()

deploy_service() {
  local name=$1 host=$2 path=$3 unit_type=$4 needs_build=$5

  echo -e "\n${BOLD}=== ${name} (${host}) ===${NC}"

  # Build remote command sequence
  local cmd="cd ${path} || exit 1"

  # Stash local changes, pull, install
  cmd+=" && git stash -q 2>/dev/null; git pull --ff-only"
  cmd+=" && npm ci --omit=dev 2>&1 | tail -1"

  # Build step for TypeScript services that serve from dist/
  if [[ "$needs_build" == "true" ]]; then
    cmd+=" && npm ci 2>&1 | tail -1 && npx tsc && npm prune --omit=dev 2>&1 | tail -1"
  fi

  # Restart
  if [[ "$unit_type" == "service" ]]; then
    cmd+=" && sudo systemctl restart ${name} && echo 'DEPLOY_OK'"
  else
    # Timers don't need restart — just pull + install is enough
    cmd+="&& echo 'DEPLOY_OK'"
  fi

  local output
  if output=$(ssh -o ConnectTimeout=10 "magnus@${host}" "$cmd" 2>&1); then
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
  IFS='|' read -r name host path unit_type needs_build <<< "$entry"

  if [[ ${#requested[@]} -gt 0 ]]; then
    match=false
    for req in "${requested[@]}"; do
      [[ "$req" == "$name" ]] && match=true && break
    done
    $match || continue
  fi

  deploy_service "$name" "$host" "$path" "$unit_type" "$needs_build"
done

# Summary
echo -e "\n${BOLD}--- Summary ---${NC}"
for r in "${results[@]}"; do
  echo -e "  $r"
done
echo ""
echo -e "  ${GREEN}${pass} passed${NC}  ${RED}${fail} failed${NC}  ${YELLOW}${skip} warnings${NC}"

[[ $fail -eq 0 ]] || exit 1

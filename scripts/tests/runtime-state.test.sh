#!/usr/bin/env bash
# runtime-state.test.sh — desired runtime/deployment state regressions (#109)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/runtime-state.sh
source "$SCRIPT_DIR/../lib/runtime-state.sh"

PASS=0
FAIL=0

assert_eq() {
  local desc=$1 expected=$2 actual=$3
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

echo "desired runtime/deployment state tests"
echo "======================================"

# Active remains the strict default: anything except active is a failure (or
# the existing bounded user-manager transport warning).
assert_eq "active desired + active observed" pass \
  "$(runtime_observation_severity active active system)"
assert_eq "active desired + inactive observed" fail \
  "$(runtime_observation_severity active inactive system)"
assert_eq "active desired + unreachable user manager" warn \
  "$(runtime_observation_severity active unreachable user)"

# Intentionally stopped means cleanly inactive, never merely "not active".
assert_eq "stopped desired + inactive observed" pass \
  "$(runtime_observation_severity stopped inactive user)"
assert_eq "stopped desired + active observed" fail \
  "$(runtime_observation_severity stopped active user)"
assert_eq "stopped desired + failed observed" fail \
  "$(runtime_observation_severity stopped failed user)"

assert_eq "not-applicable runtime skips unit checks" skip \
  "$(runtime_observation_severity not-applicable active system)"

# Runtime, health, and deployment are orthogonal. A non-deployed platform peer
# can still have active timers, but it must never require a deploy marker.
assert_eq "active runtime has unit checks" yes \
  "$(runtime_checks_applicable active)"
assert_eq "stopped runtime has unit checks" yes \
  "$(runtime_checks_applicable stopped)"
assert_eq "not-applicable runtime has no unit checks" no \
  "$(runtime_checks_applicable not-applicable)"
assert_eq "active runtime with a port has health checks" yes \
  "$(health_check_applicable active 3030)"
assert_eq "stopped runtime skips HTTP health" no \
  "$(health_check_applicable stopped 3030)"
assert_eq "active runtime without a port skips HTTP health" no \
  "$(health_check_applicable active '')"
assert_eq "deployed component requires marker validation" yes \
  "$(deployment_check_applicable true)"
assert_eq "non-deployed peer skips marker validation" no \
  "$(deployment_check_applicable false)"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

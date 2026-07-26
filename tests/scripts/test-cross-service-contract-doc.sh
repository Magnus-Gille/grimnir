#!/usr/bin/env bash
# Regression test for grimnir#7: the architecture must retain the named
# cross-service owners, required regression matrix, and safe evolution rules.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOC="$REPO_ROOT/docs/architecture.md"

failures=0

assert_contains() {
  local description="$1"
  local pattern="$2"
  if ! grep -Eqi "$pattern" "$DOC"; then
    echo "FAIL: $description" >&2
    failures=$((failures + 1))
  fi
}

assert_contains "has Cross-service contracts section" '^### Cross-service contracts$'
assert_contains "names Munin HTTP client owner" 'Munin HTTP client contract.*\*\*munin-memory\*\*'
assert_contains "names Hugin task submission owner" 'Hugin task submission contract.*\*\*hugin\*\*'
assert_contains "names Skuld fast-path owner" 'Skuld fast-path versus fallback contract.*\*\*munin-memory\*\*'
assert_contains "names Heimdall self-heal owner" 'Heimdall.*Hugin self-heal contract.*\*\*hugin\*\*'
assert_contains "names Verdandi intake owner" 'Verdandi event intake contract.*\*\*verdandi\*\*'
assert_contains "requires Munin round-trip coverage" 'authenticated local-server round trip'
assert_contains "requires Skuld path equivalence" 'SQLite path and HTTP fallback'
assert_contains "requires Hugin self-heal regression" 'exact Heimdall self-heal fixture'
assert_contains "requires Verdandi intake coverage" 'authenticated intake with valid, malformed, duplicate'
assert_contains "has owner-first evolution rule" 'Owner-first, versioned change'
assert_contains "has explicit consumer migration rule" 'Consumers migrate explicitly'
assert_contains "requires proof before removal" 'Compatibility is proved before removal'
assert_contains "fails closed for incompatible inputs" 'Fail closed at decision boundaries'

if [[ "$failures" -gt 0 ]]; then
  exit 1
fi

echo "PASS: cross-service contract documentation guard"

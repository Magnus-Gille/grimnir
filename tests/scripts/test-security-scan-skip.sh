#!/usr/bin/env bash
# tests/scripts/test-security-scan-skip.sh
#
# Regression test for security-scan.sh Phase-2 test-file exclusion.
#
# Issue #22: test files containing intentional secret-like fixtures were
# being flagged by the secret scan despite the case-based skip.  This test
# creates a minimal fake git repo containing:
#   - tests/foo.test.ts          (a *.test.ts file with a fake secret)
#   - tests/nested/bar.test.ts   (nested under tests/)
#   - eval/fixtures/pii.jsonl    (evaluation fixture with fake patterns — SKIPPED)
#   - eval/runner.ts             (non-fixture eval file — should be SCANNED, not skipped)
#   - src/real.ts                (a non-test file WITHOUT secrets)
#
# It then runs the Phase-2 scan logic directly (without npm audit) and asserts
# that secrets_found == 0 and that non-test files are still scanned.
#
# Usage:
#   bash tests/scripts/test-security-scan-skip.sh
#
# Exit codes:  0 = all assertions passed, 1 = at least one assertion failed.

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS+1))
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL+1))
  fi
}

# ── Create a temp fake git repo ────────────────────────────────────────────
TMP_REPO="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO"' EXIT

git -C "$TMP_REPO" init -q
git -C "$TMP_REPO" config user.email "test@example.com"
git -C "$TMP_REPO" config user.name "Test"

# Test file: *.test.ts at top level of tests/
mkdir -p "$TMP_REPO/tests/nested"
cat > "$TMP_REPO/tests/foo.test.ts" << 'EOF'
// Intentional fake key for testing the sensitivity scanner
const fakeKey = 'sk-ant-api03-FakeAnthropicTestKey1234567890ABCDEFGHIJKLMNOPQRST';
EOF

# Test file: nested under tests/
cat > "$TMP_REPO/tests/nested/bar.test.ts" << 'EOF'
const fakeGHToken = 'ghp_FakeGitHubTokenABCDEFGHIJKLMNOPQRSTUVWX';
EOF

# Evaluation fixture (should be skipped via eval/fixtures/* pattern)
mkdir -p "$TMP_REPO/eval/fixtures"
cat > "$TMP_REPO/eval/fixtures/pii.jsonl" << 'EOF'
{"text":"CI echoed GH_TOKEN=ghp_FakeGitHubTokenABCDEFGHIJKLMNOPQRSTUVWX","spans":{}}
EOF

# Non-fixture eval file — NOT a fixture, must be scanned (no secrets in it)
cat > "$TMP_REPO/eval/runner.ts" << 'EOF'
export function runEval() { return "ok"; }
EOF

# Real source file WITHOUT secrets (should be scanned but produce 0 findings)
mkdir -p "$TMP_REPO/src"
cat > "$TMP_REPO/src/real.ts" << 'EOF'
export function hello() { return "hello"; }
EOF

# Track everything
git -C "$TMP_REPO" add .
git -C "$TMP_REPO" commit -q -m "test fixture"

# ── Replicate the Phase-2 loop logic ──────────────────────────────────────
SCAN_TMP2="$(mktemp -d)"
trap 'rm -rf "$TMP_REPO" "$SCAN_TMP2"' EXIT

SECRET_PATTERNS_FILE="$SCAN_TMP2/patterns.txt"
cat > "$SECRET_PATTERNS_FILE" << 'PATTERNS'
Bearer [A-Za-z0-9_/+=-]{20,}	bearer-token
sk-ant-[a-zA-Z0-9_-]{20,}	anthropic-key
sk-[a-zA-Z0-9]{20,}	openai-key
ghp_[a-zA-Z0-9]{36}	github-pat
AKIA[A-Z0-9]{16}	aws-access-key
PATTERNS

ALLOWLIST_PATTERN='\*\*\*|<TOKEN>|<key>|example|EXAMPLE|sample|your[-_]|YOUR_'

finding_count=0
processed_count=0
skipped_count=0

tracked_files="$(git -C "$TMP_REPO" ls-files 2>/dev/null)" || true

while IFS= read -r relfile; do
  absfile="$TMP_REPO/$relfile"
  [[ -f "$absfile" ]] || continue

  basename_file="$(basename "$relfile")"
  if [[ "$relfile" == *".env.example"* ]] || [[ "$basename_file" == ".env.example" ]]; then
    continue
  fi

  # ── This is the block under test ──────────────────────────────────────
  case "$relfile" in
    tests/*|test/*|*/tests/*|*/test/*|\
    __tests__/*|*/__tests__/*|*/__mocks__/*|\
    eval/fixtures/*|eval/*/fixtures/*|*/eval/fixtures/*|*/eval/*/fixtures/*|\
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.test.mjs|*.test.cjs|\
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*.spec.mjs|*.spec.cjs|\
    *_test.py|*_test.go)
      skipped_count=$((skipped_count+1))
      continue
      ;;
  esac
  # ──────────────────────────────────────────────────────────────────────

  processed_count=$((processed_count+1))

  while IFS='	' read -r pattern category; do
    [[ -z "$pattern" ]] && continue
    matched_lines="$(grep -nE "$pattern" "$absfile" 2>/dev/null)" || true
    [[ -z "$matched_lines" ]] && continue
    real_matches="$(echo "$matched_lines" | grep -vE "$ALLOWLIST_PATTERN" 2>/dev/null)" || true
    [[ -z "$real_matches" ]] && continue
    while IFS= read -r _match_line; do
      finding_count=$((finding_count+1))
    done <<< "$real_matches"
  done < "$SECRET_PATTERNS_FILE"

done <<< "$tracked_files"

# ── Assertions ────────────────────────────────────────────────────────────
echo ""
echo "Running assertions..."

# 1. test files (tests/foo.test.ts, tests/nested/bar.test.ts) and
#    eval fixture (eval/fixtures/pii.jsonl) must all be skipped — 3 files.
#    eval/runner.ts is NOT a fixture and must NOT be skipped.
assert_eq "skipped_count == 3 (tests/ + nested tests/ + eval/fixtures/)" "3" "$skipped_count"

# 2. No secrets must be reported (even though test files contain fake keys)
assert_eq "finding_count == 0 (no secrets from test/eval files)" "0" "$finding_count"

# 3. Both src/real.ts and eval/runner.ts (non-fixture eval) were scanned
assert_eq "processed_count == 2 (src/real.ts and eval/runner.ts are scanned)" "2" "$processed_count"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
else
  echo "$FAIL of $((PASS+FAIL)) assertion(s) FAILED."
  exit 1
fi

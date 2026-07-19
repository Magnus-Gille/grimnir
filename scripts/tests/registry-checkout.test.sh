#!/usr/bin/env bash
# registry-checkout.test.sh — unit tests for the registry-checkout integrity
# helpers (issue #47: the canonical Grimnir checkout is the source
# registry consumers read services.json from; if it drifts off the default
# branch or goes dirty it silently poisons every consumer — this check makes
# that state alert-worthy).
#
# Sources the REAL classify_registry_checkout / check_registry_checkout from
# lib/registry-checkout.sh (no duplicated copy) so the test can never silently
# drift from the production logic.
#
# Two layers:
#   1. classify_registry_checkout — pure verdict function, exhaustive truth table
#      (no git, no filesystem).
#   2. check_registry_checkout — gatherer over a real fixture git repo, so the
#      git-plumbing wiring is exercised end to end.
#
# Usage:
#   bash scripts/tests/registry-checkout.test.sh
# Exit codes: 0 = all assertions passed, 1 = at least one failed.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

PASS=0
FAIL=0

# Source the production functions under test.
# shellcheck source=scripts/lib/registry-checkout.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/registry-checkout.sh"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected '$expected', got '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

echo "registry-checkout classify tests"
echo "================================"

# ── Pure verdict truth table (git_ok, branch, default_branch, dirty) ──────────
assert_eq "on default + clean -> ok" \
  "ok" "$(classify_registry_checkout yes main main no)"
assert_eq "on default + dirty -> alert-dirty" \
  "alert-dirty" "$(classify_registry_checkout yes main main yes)"
assert_eq "off default + clean -> alert-branch" \
  "alert-branch" "$(classify_registry_checkout yes feature/x main no)"
assert_eq "off default + dirty -> alert-branch-dirty" \
  "alert-branch-dirty" "$(classify_registry_checkout yes feature/x main yes)"
assert_eq "detached HEAD (clean) -> alert-branch" \
  "alert-branch" "$(classify_registry_checkout yes HEAD main no)"
assert_eq "not a git checkout -> alert-no-git" \
  "alert-no-git" "$(classify_registry_checkout no '' main no)"
assert_eq "not a git checkout wins over dirty/branch inputs" \
  "alert-no-git" "$(classify_registry_checkout no feature/x main yes)"

# Default branch is a parameter, not hardcoded to "main".
assert_eq "master as default + clean -> ok" \
  "ok" "$(classify_registry_checkout yes master master no)"
assert_eq "on main when default is master -> alert-branch" \
  "alert-branch" "$(classify_registry_checkout yes main master no)"

# is_alert helper: ok -> not alert, everything else -> alert.
assert_eq "is_alert ok -> no"                "no"  "$(registry_checkout_is_alert ok)"
assert_eq "is_alert alert-dirty -> yes"      "yes" "$(registry_checkout_is_alert alert-dirty)"
assert_eq "is_alert alert-branch -> yes"     "yes" "$(registry_checkout_is_alert alert-branch)"
assert_eq "is_alert alert-no-git -> yes"     "yes" "$(registry_checkout_is_alert alert-no-git)"

# Strict-mode contract: the library must never abort a set -u caller, even when
# a public helper is invoked with no arguments (this test script runs under
# `set -euo pipefail`, so a nounset abort would kill the whole run here).
assert_eq "no-arg check_registry_checkout -> alert-no-git" \
  "alert-no-git" "$(check_registry_checkout)"
assert_eq "no-arg classify_registry_checkout -> alert-no-git" \
  "alert-no-git" "$(classify_registry_checkout)"
assert_eq "no-arg registry_checkout_is_alert -> yes" \
  "yes" "$(registry_checkout_is_alert)"

# Exact remote-freshness classifier: lookup uncertainty must never become green.
assert_eq "freshness exact SHA -> current" "current" \
  "$(classify_registry_freshness 1111111111111111111111111111111111111111 1111111111111111111111111111111111111111 ok)"
assert_eq "freshness differing SHA -> mismatch" "mismatch" \
  "$(classify_registry_freshness 1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 ok)"
assert_eq "freshness failed lookup -> unreachable" "unreachable" \
  "$(classify_registry_freshness 1111111111111111111111111111111111111111 '' unreachable)"
assert_eq "freshness malformed SHA -> unreachable" "unreachable" \
  "$(classify_registry_freshness not-a-sha 2222222222222222222222222222222222222222 ok)"
assert_eq "no-arg freshness gatherer -> unreachable" "unreachable" \
  "$(check_registry_freshness)"
assert_eq "freshness detail mismatch is explicit" \
  "HEAD differs from live origin (ahead, behind, or diverged)" \
  "$(registry_freshness_detail mismatch)"
assert_eq "full SHA deploy marker is valid" "valid" \
  "$(classify_deploy_marker 1111111111111111111111111111111111111111 regular)"
assert_eq "truncated deploy marker is invalid" "invalid" \
  "$(classify_deploy_marker deadbeef regular)"
assert_eq "text deploy marker is invalid" "invalid" \
  "$(classify_deploy_marker ok regular)"
assert_eq "symlink deploy marker is explicit" "symlink" \
  "$(classify_deploy_marker '' symlink)"

# registry_checkout_detail: verdict + default-branch -> human line. Shared with
# generate-architecture.sh so the validate wiring's messages are unit-tested and
# the ok branch is never left referencing an unset detail var.
assert_eq "detail ok" \
  "on main, clean" "$(registry_checkout_detail ok main)"
assert_eq "detail alert-dirty" \
  "working tree dirty on main" "$(registry_checkout_detail alert-dirty main)"
assert_eq "detail alert-branch" \
  "off default branch (main)" "$(registry_checkout_detail alert-branch main)"
assert_eq "detail alert-branch-dirty" \
  "off default branch (main) AND dirty" "$(registry_checkout_detail alert-branch-dirty main)"
assert_eq "detail alert-no-git" \
  "not a usable git checkout" "$(registry_checkout_detail alert-no-git main)"
assert_eq "detail unknown verdict" \
  "unknown verdict: weird" "$(registry_checkout_detail weird main)"
assert_eq "detail honours default branch param" \
  "off default branch (master)" "$(registry_checkout_detail alert-branch master)"

echo ""
echo "registry-checkout gatherer tests (real fixture repos)"
echo "====================================================="

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Build a fixture git repo on branch $2 with one commit. No global git config is
# assumed — author/committer identity is passed via env so this runs on a bare CI.
mk_repo() {  # $1 = dir, $2 = branch
  local dir="$1" branch="$2"
  git init -q -b "$branch" "$dir"
  echo "seed" > "$dir/file.txt"
  git -C "$dir" add file.txt
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$dir" commit -q -m "seed"
}

# clean on default branch
mk_repo "$TMP_DIR/clean" main
assert_eq "fixture: clean on main -> ok" \
  "ok" "$(check_registry_checkout "$TMP_DIR/clean" main)"

# dirty on default branch (an untracked file — what a deploy rsync or a hugin
# scratch write leaves behind)
mk_repo "$TMP_DIR/dirty" main
echo "stray" > "$TMP_DIR/dirty/leftover.tmp"
assert_eq "fixture: untracked file on main -> alert-dirty" \
  "alert-dirty" "$(check_registry_checkout "$TMP_DIR/dirty" main)"

# modified tracked file on default branch
mk_repo "$TMP_DIR/modified" main
echo "changed" > "$TMP_DIR/modified/file.txt"
assert_eq "fixture: modified tracked file on main -> alert-dirty" \
  "alert-dirty" "$(check_registry_checkout "$TMP_DIR/modified" main)"

# off the default branch, clean (the June-15 hugin-task-branch incident)
mk_repo "$TMP_DIR/branch" main
git -C "$TMP_DIR/branch" checkout -q -b task/some-hugin-job
assert_eq "fixture: clean on a feature branch -> alert-branch" \
  "alert-branch" "$(check_registry_checkout "$TMP_DIR/branch" main)"

# off branch AND dirty
mk_repo "$TMP_DIR/both" main
git -C "$TMP_DIR/both" checkout -q -b task/other
echo "stray" > "$TMP_DIR/both/leftover.tmp"
assert_eq "fixture: dirty on a feature branch -> alert-branch-dirty" \
  "alert-branch-dirty" "$(check_registry_checkout "$TMP_DIR/both" main)"

# a non-git directory
mkdir -p "$TMP_DIR/plain"
assert_eq "fixture: non-git directory -> alert-no-git" \
  "alert-no-git" "$(check_registry_checkout "$TMP_DIR/plain" main)"

# a path that does not exist at all
assert_eq "fixture: missing path -> alert-no-git" \
  "alert-no-git" "$(check_registry_checkout "$TMP_DIR/does-not-exist" main)"

# empty path argument must not crash under set -euo pipefail
assert_eq "fixture: empty path arg -> alert-no-git" \
  "alert-no-git" "$(check_registry_checkout "" main)"

# Exact comparison against a real local bare origin: no network and no local
# remote-ref mutation are needed to distinguish current from ahead/behind.
git init -q --bare "$TMP_DIR/origin.git"
git clone -q "$TMP_DIR/origin.git" "$TMP_DIR/fresh"
git -C "$TMP_DIR/fresh" checkout -q -b main
echo "seed" > "$TMP_DIR/fresh/file.txt"
git -C "$TMP_DIR/fresh" add file.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/fresh" commit -q -m seed
git -C "$TMP_DIR/fresh" push -q -u origin main
assert_eq "freshness fixture: exact origin/main -> current" "current" \
  "$(check_registry_freshness "$TMP_DIR/fresh" main)"

echo "local ahead" >> "$TMP_DIR/fresh/file.txt"
git -C "$TMP_DIR/fresh" add file.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/fresh" commit -q -m ahead
assert_eq "freshness fixture: clean local-ahead main -> mismatch" "mismatch" \
  "$(check_registry_freshness "$TMP_DIR/fresh" main)"

git clone -q "$TMP_DIR/origin.git" "$TMP_DIR/remote-writer"
git -C "$TMP_DIR/remote-writer" checkout -q main
echo "remote ahead" >> "$TMP_DIR/remote-writer/file.txt"
git -C "$TMP_DIR/remote-writer" add file.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/remote-writer" commit -q -m remote-ahead
git -C "$TMP_DIR/remote-writer" push -q origin main
assert_eq "freshness fixture: local differs after remote advances -> mismatch" "mismatch" \
  "$(check_registry_freshness "$TMP_DIR/fresh" main)"

git -C "$TMP_DIR/fresh" remote set-url origin "$TMP_DIR/missing-origin.git"
assert_eq "freshness fixture: origin failure -> unreachable" "unreachable" \
  "$(check_registry_freshness "$TMP_DIR/fresh" main)"

echo ""
echo "restamp_deploy_marker tests (#33 deploy-marker self-heal)"
echo "========================================================"

mk_repo "$TMP_DIR/marker" main
MARKER_HEAD="$(git -C "$TMP_DIR/marker" rev-parse HEAD)"
MARKER_FILE="$TMP_DIR/marker/.deployed-commit"

# ok verdict + existing (stale) marker -> rewritten to HEAD, returns 0.
printf 'deadbeef\n' > "$MARKER_FILE"
rc=0; restamp_deploy_marker "$TMP_DIR/marker" ok current || rc=$?
assert_eq "ok + stale marker -> returns 0" "0" "$rc"
assert_eq "ok + stale marker -> healed to HEAD" "$MARKER_HEAD" "$(cat "$MARKER_FILE")"

# ok verdict + NO marker -> must not fabricate one (non-deploy checkout), returns 0.
rm -f "$MARKER_FILE"
rc=0; restamp_deploy_marker "$TMP_DIR/marker" ok current || rc=$?
assert_eq "ok + no marker -> returns 0" "0" "$rc"
assert_eq "ok + no marker -> no marker created" "no" \
  "$([[ -f "$MARKER_FILE" ]] && echo yes || echo no)"

# non-ok verdict must NEVER stamp, even with a marker present (don't bless a
# dirty/branch-stranded tree).
printf 'deadbeef\n' > "$MARKER_FILE"
rc=0; restamp_deploy_marker "$TMP_DIR/marker" alert-dirty || rc=$?
assert_eq "alert-dirty + marker -> returns 0 (skip)" "0" "$rc"
assert_eq "alert-dirty + marker -> left untouched" "deadbeef" "$(cat "$MARKER_FILE")"

# Clean main but not equal to live origin must never be certified.
rc=0; restamp_deploy_marker "$TMP_DIR/marker" ok mismatch || rc=$?
assert_eq "clean main + remote mismatch -> returns 0 (skip)" "0" "$rc"
assert_eq "clean main + remote mismatch -> marker left untouched" "deadbeef" "$(cat "$MARKER_FILE")"

# no-arg call must not crash under set -euo pipefail (strict-mode contract).
rc=0; restamp_deploy_marker || rc=$?
assert_eq "no-arg restamp -> returns 0 (skip, no crash)" "0" "$rc"

# ok verdict + marker present but UNWRITABLE -> returns 1 so the caller can warn
# (this is the grimnir-validate.service read-only-sandbox case). Skipped as root,
# where file permission bits don't block writes.
if [[ "$(id -u)" != "0" ]]; then
  printf 'deadbeef\n' > "$MARKER_FILE"
  chmod 000 "$MARKER_FILE"
  rc=0; restamp_deploy_marker "$TMP_DIR/marker" ok current || rc=$?
  chmod 644 "$MARKER_FILE"
  assert_eq "ok + unwritable marker -> returns 1 (surfaced)" "1" "$rc"
  assert_eq "ok + unwritable marker -> content unchanged" "deadbeef" "$(cat "$MARKER_FILE")"
fi

# A symlinked marker must be REFUSED, never followed — otherwise this write (and
# the validate service's ReadWritePaths exception, which also resolves symlinks)
# could clobber an arbitrary target. Return 1, leave the target untouched.
rm -f "$MARKER_FILE"
echo "target-untouched" > "$TMP_DIR/marker/real-target"
ln -s "$TMP_DIR/marker/real-target" "$MARKER_FILE"
rc=0; restamp_deploy_marker "$TMP_DIR/marker" ok current || rc=$?
assert_eq "ok + symlink marker -> returns 1 (refused)" "1" "$rc"
assert_eq "ok + symlink marker -> target left untouched" \
  "target-untouched" "$(cat "$TMP_DIR/marker/real-target")"
rm -f "$MARKER_FILE"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

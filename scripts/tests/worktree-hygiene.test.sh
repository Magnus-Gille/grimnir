#!/usr/bin/env bash
# worktree-hygiene.test.sh — unit + fixture tests for the worktree-hygiene
# audit helpers (issue #87: audit and harden multi-agent worktree and
# deployment hygiene).
#
# Mirrors the layered approach of registry-checkout.test.sh:
#   1. Pure classifiers — exhaustive truth table, no git/filesystem.
#   2. Gatherers — exercised against real fixture git repos (mktemp), so the
#      git-plumbing wiring (worktree list --porcelain parsing, merge-base,
#      upstream tracking) is proven end to end, never against live repos.
#   3. The standalone CLI (scripts/worktree-hygiene-audit.sh) run against a
#      constructed repos-root fixture, asserting it flags every seeded
#      problem (stale, dirty, canonical-violation, deploy-drift), reports
#      clean when clean, and never emits an auto-executed destructive action.
#
# Usage: bash scripts/tests/worktree-hygiene.test.sh
# Exit codes: 0 = all assertions passed, 1 = at least one failed.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

PASS=0
FAIL=0

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_DIR="$(dirname "$TEST_DIR")"
RUNBOOK_DOC="$SCRIPTS_DIR/../docs/worktree-hygiene.md"

# shellcheck source=scripts/lib/worktree-hygiene.sh
# shellcheck disable=SC1091
source "$SCRIPTS_DIR/lib/worktree-hygiene.sh"

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

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — expected to find '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — unexpectedly found '$needle'"
    FAIL=$((FAIL + 1))
  fi
}

echo "worktree-hygiene classify tests"
echo "==============================="

# ── classify_linked_worktree truth table ──────────────────────────────────
assert_eq "clean, not merged, upstream ok, not prunable -> ok" \
  "ok" "$(classify_linked_worktree no no no no)"
assert_eq "dirty only -> dirty" \
  "dirty" "$(classify_linked_worktree yes no no no)"
assert_eq "merged only -> stale" \
  "stale" "$(classify_linked_worktree no yes no no)"
assert_eq "upstream gone only -> stale" \
  "stale" "$(classify_linked_worktree no no yes no)"
assert_eq "merged AND upstream gone -> stale (no duplicate tag)" \
  "stale" "$(classify_linked_worktree no yes yes no)"
assert_eq "dirty AND merged -> dirty,stale" \
  "dirty,stale" "$(classify_linked_worktree yes yes no no)"
assert_eq "prunable wins over dirty/merged inputs" \
  "prunable" "$(classify_linked_worktree yes yes yes yes)"
assert_eq "no-arg classify_linked_worktree -> ok (defensive default)" \
  "ok" "$(classify_linked_worktree)"

assert_eq "is_issue ok -> no"          "no"  "$(worktree_verdict_is_issue ok)"
assert_eq "is_issue dirty -> yes"      "yes" "$(worktree_verdict_is_issue dirty)"
assert_eq "is_issue stale -> yes"      "yes" "$(worktree_verdict_is_issue stale)"
assert_eq "is_issue dirty,stale -> yes" "yes" "$(worktree_verdict_is_issue dirty,stale)"
assert_eq "is_issue prunable -> yes"   "yes" "$(worktree_verdict_is_issue prunable)"
assert_eq "no-arg is_issue -> no (defensive default 'ok')" \
  "no" "$(worktree_verdict_is_issue)"

assert_eq "detail ok"          "active, clean" "$(worktree_verdict_detail ok)"
assert_eq "detail unknown verdict is explicit" \
  "unknown verdict: weird" "$(worktree_verdict_detail weird)"

# ── Remediation recipes must never suggest an unconditional/automatic delete ──
for v in ok dirty stale dirty,stale prunable; do
  recipe="$(worktree_remediation "$v")"
  assert_not_contains "remediation($v) never says 'rm -rf'" "$recipe" "rm -rf"
done
assert_eq "remediation(ok) is empty" "" "$(worktree_remediation ok)"
assert_contains "remediation(dirty) tells you to inspect, not delete" \
  "$(worktree_remediation dirty)" "Never delete"
assert_contains "remediation(stale) requires manual confirmation" \
  "$(worktree_remediation stale)" "manual, operator-confirmed only"
assert_contains "remediation(dirty,stale) says never auto-delete" \
  "$(worktree_remediation dirty,stale)" "Never auto-delete"
assert_contains "remediation(prunable) only touches the prunable entry" \
  "$(worktree_remediation prunable)" "git worktree prune"

# ── classify_deploy_target ────────────────────────────────────────────────
assert_eq "git-pull mode + git dir present -> ok (expected)" \
  "ok" "$(classify_deploy_target git-pull yes)"
assert_eq "git-pull mode + no git dir -> ok" \
  "ok" "$(classify_deploy_target git-pull no)"
assert_eq "rsync mode + no git dir -> ok" \
  "ok" "$(classify_deploy_target rsync no)"
assert_eq "rsync mode + git dir present -> violation" \
  "violation-unexpected-git" "$(classify_deploy_target rsync yes)"
assert_eq "no-arg classify_deploy_target -> ok (defensive default)" \
  "ok" "$(classify_deploy_target)"

assert_eq "deploy_target_is_alert ok -> no" "no" "$(deploy_target_is_alert ok)"
assert_eq "deploy_target_is_alert violation -> yes" \
  "yes" "$(deploy_target_is_alert violation-unexpected-git)"
assert_contains "deploy_target_detail violation references role-separation doc" \
  "$(deploy_target_detail violation-unexpected-git)" "role-separation.md"

# ── canonical origin authority ────────────────────────────────────────────
assert_eq "normalize HTTPS GitHub origin" "magnus-gille/heimdall" \
  "$(normalize_github_remote "https://github.com/Magnus-Gille/heimdall.git")"
assert_eq "normalize SCP-style GitHub origin" "magnus-gille/heimdall" \
  "$(normalize_github_remote "git@github.com:Magnus-Gille/heimdall.git")"
assert_eq "normalize ssh:// GitHub origin" "grimnir-bot/skuld" \
  "$(normalize_github_remote "ssh://git@github.com/grimnir-bot/skuld.git")"
assert_eq "non-GitHub origin does not disclose or masquerade as authority" "" \
  "$(normalize_github_remote "ssh://git@internal.example/private/repo.git")"

assert_eq "matching canonical origin -> ok" "ok" \
  "$(classify_origin_authority magnus-gille/heimdall magnus-gille/heimdall yes)"
assert_eq "missing origin -> missing-origin" "missing-origin" \
  "$(classify_origin_authority magnus-gille/heimdall "" no)"
assert_eq "non-GitHub origin -> non-github-origin" "non-github-origin" \
  "$(classify_origin_authority magnus-gille/heimdall "" yes)"
assert_eq "archived predecessor origin -> archived-origin" "archived-origin" \
  "$(classify_origin_authority magnus-gille/heimdall magnus-gille/heimdall-private-archive yes)"
assert_eq "wrong live GitHub origin -> wrong-origin" "wrong-origin" \
  "$(classify_origin_authority magnus-gille/heimdall someone/heimdall yes)"
assert_eq "origin authority ok is not an alert" "no" \
  "$(origin_authority_is_alert ok)"
assert_eq "archived origin is an alert" "yes" \
  "$(origin_authority_is_alert archived-origin)"
assert_contains "archived origin detail names expected authority" \
  "$(origin_authority_detail archived-origin magnus-gille/heimdall magnus-gille/heimdall-private-archive)" \
  "expected magnus-gille/heimdall"
assert_not_contains "origin remediation never mutates a remote automatically" \
  "$(origin_authority_remediation archived-origin magnus-gille/heimdall)" \
  "git remote set-url"

echo ""
echo "worktree-hygiene gatherer tests (real fixture repos)"
echo "====================================================="

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mk_repo() {  # $1 = dir, $2 = branch
  local dir="$1" branch="$2"
  git init -q -b "$branch" "$dir"
  echo "seed" > "$dir/file.txt"
  git -C "$dir" add file.txt
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$dir" commit -q -m "seed"
}

# ── list_repo_worktrees ────────────────────────────────────────────────────
mk_repo "$TMP_DIR/wt-repo" main
git -C "$TMP_DIR/wt-repo" branch feature/done
git -C "$TMP_DIR/wt-repo" worktree add -q "$TMP_DIR/wt-repo-linked" feature/done
rows="$(list_repo_worktrees "$TMP_DIR/wt-repo")"
assert_eq "list_repo_worktrees returns 2 rows" "2" "$(echo "$rows" | grep -c '.')"
assert_contains "first row is the main worktree" "$(echo "$rows" | head -1)" "$TMP_DIR/wt-repo|main|no"
assert_contains "second row is the linked worktree on feature/done" "$(echo "$rows" | tail -1)" "$TMP_DIR/wt-repo-linked|feature/done|no"
assert_eq "list_repo_worktrees on non-repo path -> empty" "" "$(list_repo_worktrees "$TMP_DIR/does-not-exist")"
assert_eq "list_repo_worktrees on empty path -> empty" "" "$(list_repo_worktrees "")"

# Regression: list_repo_worktrees must never abort a `set -euo pipefail`
# caller that invokes it as a PLAIN top-level statement (not masked inside a
# `$(...)`/`<(...)` argument context, which swallows the subshell's own exit
# code). `git -C <missing-path> worktree list` exits non-zero; under
# pipefail that used to become this function's own return code and could
# kill a caller like scripts/generate-architecture.sh's validate wiring.
set +e
plain_call_out="$(
  set -euo pipefail
  # shellcheck disable=SC1091
  source "$SCRIPTS_DIR/lib/worktree-hygiene.sh"
  list_repo_worktrees "$TMP_DIR/does-not-exist"
  echo "survived"
)"
plain_call_rc=$?
set -e
assert_eq "list_repo_worktrees as a plain statement under set -euo pipefail does not abort" "0" "$plain_call_rc"
assert_contains "plain-statement caller reaches the line after the call" "$plain_call_out" "survived"

# ── worktree_is_dirty ──────────────────────────────────────────────────────
assert_eq "clean linked worktree -> no" "no" "$(worktree_is_dirty "$TMP_DIR/wt-repo-linked")"
echo "stray" > "$TMP_DIR/wt-repo-linked/leftover.tmp"
assert_eq "dirty linked worktree -> yes" "yes" "$(worktree_is_dirty "$TMP_DIR/wt-repo-linked")"
rm -f "$TMP_DIR/wt-repo-linked/leftover.tmp"
assert_eq "missing path -> unknown" "unknown" "$(worktree_is_dirty "$TMP_DIR/nope")"
assert_eq "no-arg worktree_is_dirty -> unknown" "unknown" "$(worktree_is_dirty)"

# ── worktree_branch_merged / worktree_upstream_gone ───────────────────────
git -C "$TMP_DIR/wt-repo" checkout -q main
git -C "$TMP_DIR/wt-repo" merge -q --no-ff -m "merge feature/done" feature/done
assert_eq "merged branch -> yes" "yes" \
  "$(worktree_branch_merged "$TMP_DIR/wt-repo" feature/done main)"

git -C "$TMP_DIR/wt-repo" branch feature/unmerged
git -C "$TMP_DIR/wt-repo" worktree add -q "$TMP_DIR/wt-repo-unmerged" feature/unmerged
echo "unique work" > "$TMP_DIR/wt-repo-unmerged/unique.txt"
git -C "$TMP_DIR/wt-repo-unmerged" add unique.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/wt-repo-unmerged" commit -q -m "unique work"
assert_eq "unmerged branch with unique commit -> no" "no" \
  "$(worktree_branch_merged "$TMP_DIR/wt-repo" feature/unmerged main)"
assert_eq "no-arg worktree_branch_merged -> no" "no" "$(worktree_branch_merged)"
assert_eq "empty-branch worktree_branch_merged -> no" "no" \
  "$(worktree_branch_merged "$TMP_DIR/wt-repo" "" main)"

# upstream-gone: bare origin, clone, push a branch, delete it remotely, fetch --prune.
git init -q --bare "$TMP_DIR/origin.git"
git -C "$TMP_DIR/wt-repo" remote add origin "$TMP_DIR/origin.git"
git -C "$TMP_DIR/wt-repo" push -q origin main
git -C "$TMP_DIR/wt-repo" checkout -q -b feature/upstream-gone
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/wt-repo" commit -q --allow-empty -m "gone-branch commit"
git -C "$TMP_DIR/wt-repo" push -q -u origin feature/upstream-gone
git -C "$TMP_DIR/wt-repo" push -q origin --delete feature/upstream-gone
git -C "$TMP_DIR/wt-repo" fetch -q --prune origin
assert_eq "deleted-upstream branch -> yes (gone)" "yes" \
  "$(worktree_upstream_gone "$TMP_DIR/wt-repo" feature/upstream-gone)"
assert_eq "branch with no upstream at all -> no" "no" \
  "$(worktree_upstream_gone "$TMP_DIR/wt-repo" feature/unmerged)"
assert_eq "no-arg worktree_upstream_gone -> no" "no" "$(worktree_upstream_gone)"
git -C "$TMP_DIR/wt-repo" checkout -q main

# ── check_deploy_target_git_dir ────────────────────────────────────────────
mkdir -p "$TMP_DIR/deploy-plain" "$TMP_DIR/deploy-git/.git"
assert_eq "plain deploy dir -> no" "no" "$(check_deploy_target_git_dir "$TMP_DIR/deploy-plain")"
assert_eq "deploy dir with .git -> yes" "yes" "$(check_deploy_target_git_dir "$TMP_DIR/deploy-git")"
assert_eq "no-arg check_deploy_target_git_dir -> no" "no" "$(check_deploy_target_git_dir)"

# ── checkout_origin_authority ─────────────────────────────────────────────
mk_repo "$TMP_DIR/origin-authority-ok" main
git -C "$TMP_DIR/origin-authority-ok" remote add origin \
  "git@github.com:Magnus-Gille/heimdall.git"
assert_eq "matching fixture origin is classified ok" \
  "ok|magnus-gille/heimdall" \
  "$(checkout_origin_authority "$TMP_DIR/origin-authority-ok" magnus-gille/heimdall)"

mk_repo "$TMP_DIR/origin-authority-archive" main
git -C "$TMP_DIR/origin-authority-archive" remote add origin \
  "https://github.com/Magnus-Gille/heimdall-private-archive.git"
assert_eq "archived fixture origin is classified without exposing raw URL" \
  "archived-origin|magnus-gille/heimdall-private-archive" \
  "$(checkout_origin_authority "$TMP_DIR/origin-authority-archive" magnus-gille/heimdall)"

mk_repo "$TMP_DIR/origin-authority-non-github" main
git -C "$TMP_DIR/origin-authority-non-github" remote add origin \
  "ssh://git@internal.example/private/heimdall.git"
assert_eq "non-GitHub fixture origin is classified without exposing raw URL" \
  "non-github-origin|<non-github>" \
  "$(checkout_origin_authority "$TMP_DIR/origin-authority-non-github" magnus-gille/heimdall)"

echo ""
echo "audit_repo_worktrees end-to-end tests"
echo "======================================"

# Clean canonical + clean linked worktree -> both ok. The linked branch needs
# a unique commit beyond main's tip: a branch cut but never advanced is
# trivially "an ancestor of main" (merge-base --is-ancestor is true even when
# branch == base), which the classifier correctly treats as safe-to-clean
# ("stale") — see docs/worktree-hygiene.md's noted heuristic limit. This
# fixture instead models the common "actively worked, not yet merged" case.
mk_repo "$TMP_DIR/clean-repo" main
git -C "$TMP_DIR/clean-repo" branch other
git -C "$TMP_DIR/clean-repo" worktree add -q "$TMP_DIR/clean-repo-linked" other
echo "in progress" > "$TMP_DIR/clean-repo-linked/wip.txt"
git -C "$TMP_DIR/clean-repo-linked" add wip.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/clean-repo-linked" commit -q -m "unique in-progress work"
audit_out="$(audit_repo_worktrees "$TMP_DIR/clean-repo" main)"
assert_contains "clean repo: canonical row is ok" "$audit_out" "|canonical|ok|main"
assert_contains "clean repo: linked row is ok" "$audit_out" "|linked|ok|other"

# Canonical checkout dirty-on-nondefault-branch (role violation per #47).
mk_repo "$TMP_DIR/violating-repo" main
git -C "$TMP_DIR/violating-repo" checkout -q -b task/some-hugin-job
echo "stray" > "$TMP_DIR/violating-repo/leftover.tmp"
audit_out="$(audit_repo_worktrees "$TMP_DIR/violating-repo" main)"
assert_contains "canonical dirty-on-nondefault -> alert-branch-dirty" "$audit_out" "|canonical|alert-branch-dirty|task/some-hugin-job"

# Stale linked worktree: branch merged into main, worktree left behind, clean.
mk_repo "$TMP_DIR/stale-repo" main
git -C "$TMP_DIR/stale-repo" branch feature/merged
git -C "$TMP_DIR/stale-repo" worktree add -q "$TMP_DIR/stale-repo-linked" feature/merged
git -C "$TMP_DIR/stale-repo" merge -q --no-ff -m "merge" feature/merged
audit_out="$(audit_repo_worktrees "$TMP_DIR/stale-repo" main)"
assert_contains "merged-branch worktree flagged stale" "$audit_out" "|linked|stale|feature/merged"

# Dirty linked worktree: unique committed work (so it's genuinely unmerged,
# not the branch==base trivial-ancestor case) PLUS uncommitted scratch work.
mk_repo "$TMP_DIR/dirty-repo" main
git -C "$TMP_DIR/dirty-repo" branch feature/wip
git -C "$TMP_DIR/dirty-repo" worktree add -q "$TMP_DIR/dirty-repo-linked" feature/wip
echo "unique work" > "$TMP_DIR/dirty-repo-linked/committed.txt"
git -C "$TMP_DIR/dirty-repo-linked" add committed.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
  git -C "$TMP_DIR/dirty-repo-linked" commit -q -m "unique work"
echo "uncommitted" > "$TMP_DIR/dirty-repo-linked/scratch.txt"
audit_out="$(audit_repo_worktrees "$TMP_DIR/dirty-repo" main)"
assert_contains "uncommitted-work worktree flagged dirty" "$audit_out" "|linked|dirty|feature/wip"

# Orphaned/prunable worktree registration: administrative entry survives after
# the working directory itself is removed out from under git (never via
# `git worktree remove` — this simulates the exact "orphaned" class in #87).
mk_repo "$TMP_DIR/prunable-repo" main
git -C "$TMP_DIR/prunable-repo" branch feature/gone-dir
git -C "$TMP_DIR/prunable-repo" worktree add -q "$TMP_DIR/prunable-repo-linked" feature/gone-dir
rm -rf "$TMP_DIR/prunable-repo-linked"
audit_out="$(audit_repo_worktrees "$TMP_DIR/prunable-repo" main)"
assert_contains "removed working dir flagged prunable" "$audit_out" "|linked|prunable|feature/gone-dir"

# Non-repo path and empty path must not crash the orchestrator.
assert_eq "audit_repo_worktrees on non-repo path -> empty" "" \
  "$(audit_repo_worktrees "$TMP_DIR/does-not-exist" main)"
assert_eq "audit_repo_worktrees with no args -> empty" "" \
  "$(audit_repo_worktrees)"

echo ""
echo "worktree-hygiene-audit.sh CLI tests (fixture repos-root)"
echo "========================================================="

FIXTURE_ROOT="$TMP_DIR/repos-root"
mkdir -p "$FIXTURE_ROOT"

# Repo A: fully clean (canonical only, on main).
mk_repo "$FIXTURE_ROOT/repo-a" main
git -C "$FIXTURE_ROOT/repo-a" remote add origin \
  "https://github.com/Magnus-Gille/repo-a.git"

# Repo B: seeds a stale merged worktree AND a dirty worktree, canonical clean.
mk_repo "$FIXTURE_ROOT/repo-b" main
git -C "$FIXTURE_ROOT/repo-b" remote add origin \
  "https://github.com/Magnus-Gille/repo-b-private-archive.git"
git -C "$FIXTURE_ROOT/repo-b" branch feature/merged-b
git -C "$FIXTURE_ROOT/repo-b" worktree add -q "$TMP_DIR/repo-b-stale" feature/merged-b
git -C "$FIXTURE_ROOT/repo-b" merge -q --no-ff -m "merge" feature/merged-b
git -C "$FIXTURE_ROOT/repo-b" branch feature/wip-b
git -C "$FIXTURE_ROOT/repo-b" worktree add -q "$TMP_DIR/repo-b-dirty" feature/wip-b
echo "uncommitted" > "$TMP_DIR/repo-b-dirty/scratch.txt"

# Repo C: canonical checkout itself is dirty AND off the default branch.
mk_repo "$FIXTURE_ROOT/repo-c" main
git -C "$FIXTURE_ROOT/repo-c" checkout -q -b task/stray-session
echo "stray" > "$FIXTURE_ROOT/repo-c/leftover.tmp"

# Deploy-target drift fixture: an rsync-mode component whose deploy path has
# unexpectedly grown a .git directory.
mkdir -p "$TMP_DIR/deploy-drift-target/.git"
FIXTURE_SERVICES_JSON="$TMP_DIR/services.json"
cat > "$FIXTURE_SERVICES_JSON" << EOF
{
  "repository_authority": {
    "default_owner": "Magnus-Gille",
    "additional_repositories": [],
    "owner_overrides": {},
    "checkout_overrides": {}
  },
  "components": [
    {
      "name": "repo-a",
      "repo": "repo-a",
      "host": null,
      "port": null,
      "deploy": true,
      "scan": false,
      "deploy_path": "$TMP_DIR/deploy-drift-target",
      "deploy_mode": "rsync",
      "needs_build": false,
      "systemd_units": []
    },
    {
      "name": "repo-b",
      "repo": "repo-b",
      "host": null,
      "port": null,
      "deploy": false,
      "scan": false,
      "needs_build": false,
      "systemd_units": []
    }
  ]
}
EOF

set +e
dirty_output="$(GRIMNIR_WORKTREE_AUDIT_ROOT="$FIXTURE_ROOT" GRIMNIR_SERVICES_JSON="$FIXTURE_SERVICES_JSON" \
  "$SCRIPTS_DIR/worktree-hygiene-audit.sh" 2>&1)"
dirty_rc=$?
set -e

assert_eq "CLI exits 1 when fixture has issues" "1" "$dirty_rc"
assert_contains "CLI flags repo-b stale worktree" "$dirty_output" "repo-b"
assert_contains "CLI flags repo-b dirty worktree" "$dirty_output" "dirty"
assert_contains "CLI flags repo-c canonical violation" "$dirty_output" "repo-c"
assert_contains "CLI flags the deploy-target .git drift" "$dirty_output" "repo-a"
assert_contains "CLI flags deploy-target role-separation reference" "$dirty_output" "role-separation.md"
assert_contains "CLI flags repo-b archived predecessor origin" "$dirty_output" "archived predecessor"
assert_contains "CLI origin finding names expected repository" "$dirty_output" "magnus-gille/repo-b"
assert_not_contains "CLI origin finding does not expose raw transport URL" \
  "$dirty_output" "https://github.com"
assert_not_contains "CLI output never instructs an unconditional delete" "$dirty_output" "rm -rf"
assert_not_contains "CLI output never mutates a remote" "$dirty_output" "git remote set-url"
assert_contains "CLI prints a summary line" "$dirty_output" "Summary:"

# Clean-only fixture root: must report clean and exit 0.
CLEAN_ROOT="$TMP_DIR/repos-root-clean"
mkdir -p "$CLEAN_ROOT"
mk_repo "$CLEAN_ROOT/repo-clean" main
git -C "$CLEAN_ROOT/repo-clean" remote add origin \
  "https://github.com/Magnus-Gille/repo-clean.git"

CLEAN_SERVICES_JSON="$TMP_DIR/services-clean.json"
cat > "$CLEAN_SERVICES_JSON" << EOF
{
  "repository_authority": {
    "default_owner": "Magnus-Gille",
    "additional_repositories": [
      { "repo": "repo-clean", "checkout": "repo-clean" }
    ],
    "owner_overrides": {},
    "checkout_overrides": {}
  },
  "components": []
}
EOF

set +e
clean_output="$(GRIMNIR_WORKTREE_AUDIT_ROOT="$CLEAN_ROOT" GRIMNIR_SERVICES_JSON="$CLEAN_SERVICES_JSON" \
  "$SCRIPTS_DIR/worktree-hygiene-audit.sh" 2>&1)"
clean_rc=$?
set -e

assert_eq "CLI exits 0 on a fully clean fixture root" "0" "$clean_rc"
assert_contains "CLI reports 0 issues on the clean fixture" "$clean_output" "0 issues"

# ── Canonical-origin reconciliation runbook ───────────────────────────────
# The ancestry preflight must run against the checkout being reconciled, not
# whatever repository happens to be the operator's current directory.
echo "origin reconciliation runbook documentation tests"
echo "================================================="
step_three="$(sed -n '/^3\. Fetch the candidate tip/,/^4\. Only after/p' "$RUNBOOK_DOC")"
assert_contains "runbook ancestry fetch scopes the checkout" "$step_three" \
  "git -C /path/to/checkout fetch --no-tags"

unscoped_step_three_git="$(
  printf '%s\n' "$step_three" |
    grep -E 'git (fetch|rev-parse|merge-base)' |
    grep -v 'git -C /path/to/checkout' || true
)"
assert_eq "runbook ancestry commands never use the operator cwd" "" "$unscoped_step_three_git"

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi

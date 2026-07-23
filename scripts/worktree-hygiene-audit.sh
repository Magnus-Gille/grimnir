#!/usr/bin/env bash
# worktree-hygiene-audit.sh — Read-only audit of multi-agent worktree and
# deployment hygiene across owned repos (issue #87).
#
# Extends the canonical-checkout guard from issue #47
# (scripts/lib/registry-checkout.sh, docs/role-separation.md) to the full
# worktree lifecycle. For every git repo directly under the scanned root it
# reports:
#   - a canonical checkout that is dirty or off its default branch (role
#     violation per #47)
#   - a canonical checkout whose origin disagrees with the repository
#     authority declared in services.json, including archived predecessors
#   - stale linked worktrees (branch merged into the default branch, or its
#     upstream is gone) that were never cleaned up
#   - dirty linked worktrees holding uncommitted work
#   - orphaned/prunable worktree registrations (administrative entry present,
#     working directory gone)
# and, when a services registry is available, whether any declared rsync
# deploy target has unexpectedly grown a `.git` directory (a deploy target
# doubling as an ad hoc checkout).
#
# Read-only by design: this script NEVER deletes a worktree, prunes, resets,
# or checks anything out. Every finding is reported with a specific,
# non-destructive, operator-confirmed remediation recipe (see
# scripts/lib/worktree-hygiene.sh: worktree_remediation()); nothing here is
# applied automatically. See docs/worktree-hygiene.md for the protocol.
#
# Usage:
#   scripts/worktree-hygiene-audit.sh [--repos-root DIR] [--default-branch BRANCH] [--services-json PATH]
#
# Env overrides (mirrors scripts/lib/registry-checkout.sh conventions):
#   GRIMNIR_WORKTREE_AUDIT_ROOT   repos root to scan (default: $HOME/repos)
#   GRIMNIR_DEFAULT_BRANCH        default branch name (default: main)
#   GRIMNIR_SERVICES_JSON         services.json path for the deploy-target
#                                 check (default: <this repo>/services.json)
#
# Exit code: 0 when nothing is flagged, 1 when at least one repo/worktree/
# deploy target is an issue. A single unreadable repo is reported as a
# finding, not a crash (set -euo pipefail is scoped to script-level errors,
# never to a single repo's git state).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/worktree-hygiene.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/worktree-hygiene.sh"

REPOS_ROOT="${GRIMNIR_WORKTREE_AUDIT_ROOT:-$HOME/repos}"
DEFAULT_BRANCH="${GRIMNIR_DEFAULT_BRANCH:-main}"
SERVICES_JSON="${GRIMNIR_SERVICES_JSON:-$SCRIPT_DIR/../services.json}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos-root) REPOS_ROOT="$2"; shift 2 ;;
    --default-branch) DEFAULT_BRANCH="$2"; shift 2 ;;
    --services-json) SERVICES_JSON="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

PASS=0
ISSUES=0
OFFENDERS=""
RECIPES=""

echo "Worktree Hygiene Audit — root: $REPOS_ROOT (default branch: $DEFAULT_BRANCH)"
echo "=============================================================="
echo ""

if [[ ! -d "$REPOS_ROOT" ]]; then
  echo "❌ repos root not found: $REPOS_ROOT"
  echo ""
  echo "Summary: 0 ok, 1 issues"
  exit 1
fi

shopt -s nullglob
for repo_dir in "$REPOS_ROOT"/*/; do
  repo_dir="${repo_dir%/}"
  [[ -d "$repo_dir/.git" ]] || continue
  repo_name="$(basename "$repo_dir")"

  while IFS='|' read -r w_path w_role w_verdict w_branch; do
    [[ -n "$w_path" ]] || continue
    if [[ "$w_role" == "canonical" ]]; then
      if [[ "$(registry_checkout_is_alert "$w_verdict")" == "yes" ]]; then
        detail="$(registry_checkout_detail "$w_verdict" "$DEFAULT_BRANCH")"
        OFFENDERS+="❌ $repo_name (canonical checkout, $w_path): $detail\n"
        RECIPES+="  - $repo_name canonical checkout ($w_path): reconcile manually to $DEFAULT_BRANCH — 'git status' / 'git checkout $DEFAULT_BRANCH' / commit or stash, as appropriate. Never auto-fixed. See docs/role-separation.md.\n"
        ISSUES=$((ISSUES + 1))
      else
        PASS=$((PASS + 1))
      fi
    else
      if [[ "$(worktree_verdict_is_issue "$w_verdict")" == "yes" ]]; then
        detail="$(worktree_verdict_detail "$w_verdict")"
        branch_label="${w_branch:-<detached>}"
        OFFENDERS+="❌ $repo_name (linked worktree, branch=$branch_label, $w_path): $detail\n"
        recipe="$(worktree_remediation "$w_verdict")"
        RECIPES+="  - $repo_name $w_path: $recipe\n"
        ISSUES=$((ISSUES + 1))
      else
        PASS=$((PASS + 1))
      fi
    fi
  done < <(audit_repo_worktrees "$repo_dir" "$DEFAULT_BRANCH")
done
shopt -u nullglob

# Canonical-origin authority check (#112). The registry combines component
# repo names with the explicit GitHub owner/checkout exceptions declared in
# repository_authority. Hosts intentionally carry only a subset of the
# ecosystem, so absent local checkouts are skipped. Existing checkouts are
# inspected read-only and raw remote URLs are never printed.
if [[ -f "$SERVICES_JSON" ]]; then
  REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"
  while IFS='|' read -r checkout_name expected_authority; do
    [[ -n "$checkout_name" && -n "$expected_authority" ]] || continue
    checkout_path="$REPOS_ROOT/$checkout_name"
    if ! git -C "$checkout_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      continue
    fi
    expected_authority="$(printf '%s' "$expected_authority" | tr '[:upper:]' '[:lower:]')"
    origin_row="$(checkout_origin_authority "$checkout_path" "$expected_authority")"
    origin_verdict="${origin_row%%|*}"
    origin_actual="${origin_row#*|}"
    if [[ "$(origin_authority_is_alert "$origin_verdict")" == "yes" ]]; then
      OFFENDERS+="❌ $checkout_name canonical checkout origin: $(origin_authority_detail "$origin_verdict" "$expected_authority" "$origin_actual")\n"
      RECIPES+="  - $checkout_name origin: $(origin_authority_remediation "$origin_verdict" "$expected_authority")\n"
      ISSUES=$((ISSUES + 1))
    else
      PASS=$((PASS + 1))
    fi
  done < <(REGISTRY_PATH="$SERVICES_JSON" QUERY=repository-authority node --input-type=commonjs "$REGISTRY_JS")
fi

# Deploy-target role check (#47/#87): an rsync deploy target that has grown a
# .git directory may be doubling as an ad hoc checkout. Only meaningful on the
# host that actually owns the deploy path locally (a laptop checking a Pi's
# /home/magnus/... path simply won't find the directory — reported as "not
# found here", never as a false "clean").
if [[ -f "$SERVICES_JSON" ]]; then
  REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"
  while IFS='|' read -r v_name _v_host _v_port _v_repo v_deploy_path v_deploy_mode _v_units_json; do
    [[ -n "$v_name" && -n "$v_deploy_path" ]] || continue
    if [[ ! -d "$v_deploy_path" ]]; then
      continue
    fi
    dt_git_dir="$(check_deploy_target_git_dir "$v_deploy_path")"
    dt_verdict="$(classify_deploy_target "$v_deploy_mode" "$dt_git_dir")"
    if [[ "$(deploy_target_is_alert "$dt_verdict")" == "yes" ]]; then
      OFFENDERS+="❌ $v_name deploy target ($v_deploy_path): $(deploy_target_detail "$dt_verdict")\n"
      RECIPES+="  - $v_name deploy target ($v_deploy_path): investigate manually why a .git directory exists on a $v_deploy_mode target; do not delete .git automatically. See docs/role-separation.md.\n"
      ISSUES=$((ISSUES + 1))
    else
      PASS=$((PASS + 1))
    fi
  done < <(REGISTRY_PATH="$SERVICES_JSON" QUERY=validate node --input-type=commonjs "$REGISTRY_JS")
fi

if [[ -n "$OFFENDERS" ]]; then
  echo "Offenders:"
  echo -e "$OFFENDERS"
  echo "Remediation recipes (manual, non-destructive — nothing here is auto-applied):"
  echo -e "$RECIPES"
fi

echo "Summary: $PASS ok, $ISSUES issues"

if [[ "$ISSUES" -gt 0 ]]; then
  exit 1
fi
exit 0

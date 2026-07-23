# shellcheck shell=bash
# worktree-hygiene.sh — audit helpers for multi-agent worktree/deployment
# hygiene (issue #87).
#
# Motivation: many agents/sessions operate concurrently across the same
# repos/checkouts (grimnir's own house rule is one task = one subagent = one
# dedicated worktree — see AGENTS.md). Left unaudited this leaves stale
# worktrees (branch merged/gone but the tree remains), dirty worktrees holding
# uncommitted work, orphaned/prunable worktree registrations, and deploy
# targets that quietly become ad hoc git checkouts. This extends the
# canonical-checkout guard from issue #47 (scripts/lib/registry-checkout.sh,
# docs/role-separation.md) to the full worktree lifecycle across every owned
# repo, and to a narrow deploy-target role check.
#
# Read-only. Nothing in this file mutates git state, deletes a worktree,
# prunes, resets, or checks anything out. Every verdict maps to a suggested
# remediation STRING for a human/agent to run manually — see
# worktree_remediation(). Destructive actions are never automatic.
#
# ── Pure classifiers (no git, no filesystem) ──────────────────────────────
#
# classify_linked_worktree <dirty> <merged> <upstream_gone> <prunable>
#   Verdict for a linked (non-canonical) worktree entry. Inputs are all
#   "yes"/"no". Echoes one of: "prunable", "ok", "dirty", "stale",
#   "dirty,stale". `prunable` short-circuits (a missing working directory
#   can't be dirty-checked, so its presence alone is the whole verdict).
#
# worktree_verdict_is_issue <verdict>
#   "no" for "ok", "yes" for everything else.
#
# worktree_verdict_detail <verdict>
#   One-line human description of a linked-worktree verdict.
#
# worktree_remediation <verdict>
#   Suggested NON-destructive, manual remediation recipe string for a
#   verdict. Empty string for "ok". Never suggests an unconditional delete;
#   `stale` and `prunable` recipes are still phrased as operator-run commands,
#   not anything this code executes.
#
# classify_deploy_target <deploy_mode> <has_git_dir>
#   A deploy target that is unexpectedly a git checkout is a role violation
#   (docs/role-separation.md): an rsync deploy target should never itself
#   contain a `.git` directory. Echoes "ok" or "violation-unexpected-git".
#   git-pull deploy targets are SUPPOSED to be git checkouts, so `deploy_mode
#   == "git-pull"` is always "ok" regardless of has_git_dir.
#
# deploy_target_is_alert <verdict>
# deploy_target_detail <verdict>
#   Same shape as the worktree helpers above, for classify_deploy_target.
#
# ── Gatherers (impure — read git/filesystem state, never mutate it) ───────
#
# list_repo_worktrees <repo_path>
#   Parses `git worktree list --porcelain`. Emits one line per worktree:
#   "<path>|<branch>|<prunable>" (branch is empty for a detached HEAD;
#   prunable is "yes"/"no"). The FIRST line is always the repo's main
#   worktree (git's own listing order), which callers treat as canonical.
#
# worktree_is_dirty <path>
#   "yes"/"no"/"unknown" (path missing or not a readable git work tree).
#
# worktree_branch_merged <repo_path> <branch> <base_ref>
# worktree_upstream_gone <repo_path> <branch>
#   "yes"/"no" staleness signals for a linked worktree's branch.
#
# check_deploy_target_git_dir <path>
#   "yes" if <path>/.git exists, else "no".
#
# audit_repo_worktrees <repo_path> <default_branch> [<base_ref>]
#   Orchestrates the above across every worktree of one repo. Emits one line
#   per worktree: "<path>|<role>|<verdict>|<branch>" where role is
#   "canonical" (verdict from the shared registry-checkout classifier,
#   scripts/lib/registry-checkout.sh — reused, not duplicated) or "linked"
#   (verdict from classify_linked_worktree). base_ref defaults to
#   default_branch; pass e.g. "origin/main" when it exists to catch
#   merged-but-not-yet-pulled branches.
#
# Sourced by scripts/worktree-hygiene-audit.sh (standalone CLI),
# scripts/generate-architecture.sh (--validate wiring), and
# scripts/tests/worktree-hygiene.test.sh. bash 3.2+.

WORKTREE_HYGIENE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/registry-checkout.sh
# shellcheck disable=SC1091
source "$WORKTREE_HYGIENE_LIB_DIR/registry-checkout.sh"

classify_linked_worktree() {
  local dirty="${1:-no}" merged="${2:-no}" upstream_gone="${3:-no}" prunable="${4:-no}"

  if [[ "$prunable" == "yes" ]]; then
    echo "prunable"
    return 0
  fi

  local tags=""
  [[ "$dirty" == "yes" ]] && tags+="dirty,"
  if [[ "$merged" == "yes" || "$upstream_gone" == "yes" ]]; then
    tags+="stale,"
  fi
  tags="${tags%,}"

  if [[ -z "$tags" ]]; then
    echo "ok"
  else
    echo "$tags"
  fi
}

worktree_verdict_is_issue() {
  if [[ "${1:-ok}" == "ok" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

worktree_verdict_detail() {
  case "${1:-ok}" in
    ok)          echo "active, clean" ;;
    dirty)       echo "uncommitted changes present" ;;
    stale)       echo "branch merged into base or its upstream is gone; worktree was not cleaned up" ;;
    dirty,stale) echo "branch merged/gone AND uncommitted changes present — inspect before touching" ;;
    prunable)    echo "administrative worktree entry present but its working directory is missing" ;;
    *)           echo "unknown verdict: ${1:-}" ;;
  esac
}

worktree_remediation() {
  case "${1:-ok}" in
    ok) echo "" ;;
    dirty)
      echo "Inspect first: git -C <path> status. Commit or 'git stash -u' the work, then re-run the audit. Never delete a dirty worktree automatically."
      ;;
    stale)
      echo "After confirming there is no unique unpushed work: 'git worktree remove <path>' then 'git branch -d <branch>' — manual, operator-confirmed only."
      ;;
    dirty,stale)
      echo "Branch is merged/gone but the tree is dirty. Preserve the work first (commit, 'git stash -u', or cherry-pick it), THEN 'git worktree remove <path>'. Never auto-delete."
      ;;
    prunable)
      echo "Working directory is already gone; only the registration is stale. Safe to reconcile: 'git worktree prune' (does not touch any other worktree's files)."
      ;;
    *)
      echo "Manual review required — unrecognized verdict."
      ;;
  esac
}

classify_deploy_target() {
  local deploy_mode="${1:-rsync}" has_git_dir="${2:-no}"

  if [[ "$deploy_mode" == "git-pull" ]]; then
    echo "ok"
  elif [[ "$has_git_dir" == "yes" ]]; then
    echo "violation-unexpected-git"
  else
    echo "ok"
  fi
}

deploy_target_is_alert() {
  if [[ "${1:-ok}" == "ok" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

deploy_target_detail() {
  case "${1:-ok}" in
    ok)                        echo "deploy target matches its declared deploy_mode" ;;
    violation-unexpected-git)  echo "deploy target unexpectedly contains a .git directory — it may be doubling as an ad hoc checkout (role violation, see docs/role-separation.md)" ;;
    *)                         echo "unknown verdict: ${1:-}" ;;
  esac
}

# Convert supported GitHub remote transports to a disclosure-safe,
# case-insensitive "owner/repo" identity. Raw remote URLs are deliberately
# never returned: non-GitHub transports collapse to an empty string so an
# audit finding cannot leak a private host or locator.
normalize_github_remote() {
  local remote="${1:-}" slug=""
  case "$remote" in
    https://github.com/*)
      slug="${remote#https://github.com/}"
      ;;
    git@github.com:*)
      slug="${remote#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      slug="${remote#ssh://git@github.com/}"
      ;;
    *)
      return 0
      ;;
  esac

  slug="${slug%/}"
  slug="${slug%.git}"
  case "$slug" in
    */*)
      local owner="${slug%%/*}" repo="${slug#*/}"
      ;;
    *)
      return 0
      ;;
  esac
  [[ -n "$owner" && -n "$repo" && "$repo" != */* ]] || return 0
  case "$owner$repo" in
    *[!A-Za-z0-9_.-]*) return 0 ;;
  esac
  printf '%s/%s\n' "$owner" "$repo" | tr '[:upper:]' '[:lower:]'
}

classify_origin_authority() {
  local expected="${1:-}" actual="${2:-}" has_origin="${3:-no}"
  if [[ "$has_origin" != "yes" ]]; then
    echo "missing-origin"
  elif [[ -z "$actual" ]]; then
    echo "non-github-origin"
  elif [[ "$actual" == "$expected" ]]; then
    echo "ok"
  elif [[ "${actual#*/}" =~ (^|[-_.])(archive|archived|legacy|predecessor)([-_.]|$) ]]; then
    echo "archived-origin"
  else
    echo "wrong-origin"
  fi
}

origin_authority_is_alert() {
  if [[ "${1:-ok}" == "ok" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

origin_authority_detail() {
  local verdict="${1:-ok}" expected="${2:-<unknown>}" actual="${3:-<unknown>}"
  case "$verdict" in
    ok)
      echo "origin matches repository authority ($expected)"
      ;;
    missing-origin)
      echo "origin is missing; expected $expected"
      ;;
    non-github-origin)
      echo "origin is not a recognized GitHub remote; expected $expected"
      ;;
    archived-origin)
      echo "origin points to archived predecessor $actual; expected $expected"
      ;;
    wrong-origin)
      echo "origin points to $actual; expected $expected"
      ;;
    *)
      echo "unknown origin-authority verdict: $verdict; expected $expected"
      ;;
  esac
}

origin_authority_remediation() {
  local verdict="${1:-ok}" expected="${2:-<unknown>}"
  if [[ "$verdict" == "ok" ]]; then
    echo ""
  else
    echo "Inspect local branches, worktrees, and both fetch/push URLs; then reconcile origin to $expected manually while preserving any useful predecessor under an explicit archival remote name. Nothing is changed by this audit."
  fi
}

checkout_origin_authority() {
  local repo_path="${1:-}" expected="${2:-}" remote="" actual="" has_origin="no"
  [[ -n "$repo_path" && -n "$expected" ]] || return 0
  if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  remote="$(git -C "$repo_path" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n "$remote" ]]; then
    has_origin="yes"
    actual="$(normalize_github_remote "$remote")"
  fi

  local verdict safe_actual
  verdict="$(classify_origin_authority "$expected" "$actual" "$has_origin")"
  if [[ "$has_origin" != "yes" ]]; then
    safe_actual="<missing>"
  elif [[ -z "$actual" ]]; then
    safe_actual="<non-github>"
  else
    safe_actual="$actual"
  fi
  echo "$verdict|$safe_actual"
}

list_repo_worktrees() {
  local repo_path="${1:-}"
  [[ -n "$repo_path" ]] || return 0
  # `|| true` on the git leg is deliberate: callers source this under
  # `set -euo pipefail`, and a nonexistent/unreadable repo_path makes `git -C`
  # exit non-zero. Under pipefail that becomes THIS function's return code,
  # which would abort a caller that invokes it as a plain statement (not
  # masked inside a `$(...)`/`<(...)` context). The contract for every
  # gatherer in this file is "report an empty/absent finding, never abort the
  # caller" (matching check_registry_checkout's documented behaviour in
  # registry-checkout.sh) — a missing repo simply yields zero worktree rows.
  { git -C "$repo_path" worktree list --porcelain 2>/dev/null || true; } | awk '
    BEGIN { path = ""; branch = ""; prunable = "no" }
    /^worktree / {
      if (path != "") { print path "|" branch "|" prunable }
      path = substr($0, 10)
      branch = ""
      prunable = "no"
      next
    }
    /^branch / {
      b = substr($0, 8)
      sub(/^refs\/heads\//, "", b)
      branch = b
      next
    }
    /^detached/ { branch = ""; next }
    /^prunable/ { prunable = "yes"; next }
    END { if (path != "") print path "|" branch "|" prunable }
  '
}

worktree_is_dirty() {
  local path="${1:-}"
  if [[ -z "$path" || ! -d "$path" ]]; then
    echo "unknown"
    return 0
  fi
  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "unknown"
    return 0
  fi
  if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

worktree_branch_merged() {
  local repo_path="${1:-}" branch="${2:-}" base_ref="${3:-main}"
  if [[ -z "$repo_path" || -z "$branch" ]]; then
    echo "no"
    return 0
  fi
  if git -C "$repo_path" merge-base --is-ancestor "$branch" "$base_ref" 2>/dev/null; then
    echo "yes"
  else
    echo "no"
  fi
}

worktree_upstream_gone() {
  local repo_path="${1:-}" branch="${2:-}"
  if [[ -z "$repo_path" || -z "$branch" ]]; then
    echo "no"
    return 0
  fi
  local track
  track="$(git -C "$repo_path" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null || true)"
  if [[ "$track" == *"[gone]"* ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

check_deploy_target_git_dir() {
  local path="${1:-}"
  if [[ -n "$path" && -d "$path/.git" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

audit_repo_worktrees() {
  local repo_path="${1:-}" default_branch="${2:-main}" base_ref="${3:-}"
  [[ -n "$base_ref" ]] || base_ref="$default_branch"
  [[ -n "$repo_path" ]] || return 0

  local rows
  rows="$(list_repo_worktrees "$repo_path")"
  [[ -n "$rows" ]] || return 0

  local first=true
  local w_path w_branch w_prunable
  while IFS='|' read -r w_path w_branch w_prunable; do
    [[ -n "$w_path" ]] || continue
    if [[ "$first" == "true" ]]; then
      first=false
      local co_verdict
      co_verdict="$(check_registry_checkout "$w_path" "$default_branch")"
      echo "${w_path}|canonical|${co_verdict}|${w_branch}"
    else
      local verdict dirty merged gone
      if [[ "$w_prunable" == "yes" ]]; then
        verdict="prunable"
      else
        dirty="$(worktree_is_dirty "$w_path")"
        if [[ "$dirty" == "unknown" ]]; then
          # Directory vanished without git flagging the entry prunable yet
          # (e.g. a race, or a manual rm). Never claim "ok" on unverifiable
          # state — surface it the same way as a git-confirmed prunable entry.
          verdict="prunable"
        else
          merged="$(worktree_branch_merged "$repo_path" "$w_branch" "$base_ref")"
          gone="$(worktree_upstream_gone "$repo_path" "$w_branch")"
          verdict="$(classify_linked_worktree "$dirty" "$merged" "$gone" no)"
        fi
      fi
      echo "${w_path}|linked|${verdict}|${w_branch}"
    fi
  done <<< "$rows"
}

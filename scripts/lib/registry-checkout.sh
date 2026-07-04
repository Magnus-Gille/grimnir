# shellcheck shell=bash
# registry-checkout.sh — integrity check for the canonical grimnir checkout.
#
# The grimnir checkout on huginmunin (default: ~/repos/grimnir) plays three
# colliding roles today (issue #47): rsync deploy target, the git checkout that
# every registry consumer reads services.json from, and — until hugin#139 lands
# — a hugin task workspace. When a hugin task strands it on a feature branch, or
# a deploy leaves the tree dirty, consumers silently read a poisoned registry.
# Two such incidents landed in two weeks (#33, #44). These helpers make that
# state observable and alert-worthy from the daily grimnir-validate run.
#
# classify_registry_checkout <git_ok> <branch> <default_branch> <dirty>
#   Pure verdict function (no git, no filesystem, no network). Inputs:
#     git_ok          "yes" if the path is a readable git work tree, else "no"
#     branch          current branch (abbrev-ref HEAD); "HEAD" when detached
#     default_branch  the branch a healthy registry checkout must be on
#     dirty           "yes" if the working tree has uncommitted changes
#   Echoes exactly one verdict token:
#     ok                  on <default_branch> AND clean
#     alert-dirty         on <default_branch> but working tree is dirty
#     alert-branch        off <default_branch> (feature branch or detached HEAD)
#     alert-branch-dirty  off <default_branch> AND dirty
#     alert-no-git        path is not a usable git checkout
#
# registry_checkout_is_alert <verdict>
#   Echoes "yes" for any alert-* verdict, "no" for "ok". Convenience so callers
#   don't string-match verdict prefixes themselves.
#
# registry_checkout_detail <verdict> [default_branch]
#   Maps a verdict token to a one-line human description for the validate result
#   line and the Telegram alert. Every verdict (including "ok") yields a string.
#
# check_registry_checkout <checkout_path> [default_branch]
#   Gathers live git state from <checkout_path> (read-only — no fetch, no
#   network) and returns the classifier verdict. Never aborts the caller: a
#   missing path, a non-git directory, or an empty argument all resolve to
#   "alert-no-git" rather than a set -e abort. default_branch defaults to "main".
#
# Sourced by both scripts/generate-architecture.sh (--validate mode) and the
# registry-checkout unit test, so the logic has a single definition. bash 3.2+.

classify_registry_checkout() {
  # Positionals default defensively so a set -u caller is never aborted by a
  # missing argument (the library contract, and what the unit tests assert).
  local git_ok="${1:-no}" branch="${2:-}" default_branch="${3:-main}" dirty="${4:-no}"

  if [[ "$git_ok" != "yes" ]]; then
    echo "alert-no-git"
    return 0
  fi

  local off_branch="no"
  if [[ "$branch" != "$default_branch" ]]; then
    off_branch="yes"
  fi

  if [[ "$off_branch" == "yes" && "$dirty" == "yes" ]]; then
    echo "alert-branch-dirty"
  elif [[ "$off_branch" == "yes" ]]; then
    echo "alert-branch"
  elif [[ "$dirty" == "yes" ]]; then
    echo "alert-dirty"
  else
    echo "ok"
  fi
}

registry_checkout_is_alert() {
  if [[ "${1:-alert-no-git}" == "ok" ]]; then
    echo "no"
  else
    echo "yes"
  fi
}

# registry_checkout_detail <verdict> [default_branch]
#   Maps a verdict token to a one-line human description, used to build the
#   validate-mode result line and the Telegram alert. Shared here (rather than
#   inlined in generate-architecture.sh) so the wiring's messages are
#   unit-tested and every verdict — including "ok" — always yields a string.
registry_checkout_detail() {
  local verdict="${1:-alert-no-git}" default_branch="${2:-main}"
  case "$verdict" in
    ok)                 echo "on ${default_branch}, clean" ;;
    alert-dirty)        echo "working tree dirty on ${default_branch}" ;;
    alert-branch)       echo "off default branch (${default_branch})" ;;
    alert-branch-dirty) echo "off default branch (${default_branch}) AND dirty" ;;
    alert-no-git)       echo "not a usable git checkout" ;;
    *)                  echo "unknown verdict: ${verdict}" ;;
  esac
}

check_registry_checkout() {
  local path="${1:-}" default_branch="${2:-main}"
  local git_ok="no" branch="" dirty="no"

  if [[ -n "$path" ]] && git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_ok="yes"
    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
    if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
      dirty="yes"
    fi
  fi

  classify_registry_checkout "$git_ok" "$branch" "$default_branch" "$dirty"
}

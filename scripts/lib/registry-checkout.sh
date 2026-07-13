# shellcheck shell=bash
# registry-checkout.sh — integrity check for the canonical grimnir checkout.
#
# The grimnir checkout on huginmunin (default: ~/repos/grimnir) is the canonical
# checkout every registry consumer reads. It is now separated from Hugin task
# workspaces and advances via git-pull deploys, but a stray local commit, dirty
# tree, branch switch, or unreachable origin can still make its services.json
# untrustworthy. These helpers keep every one of those states explicit.
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
# check_registry_freshness <checkout_path> [default_branch]
#   Compares the exact local HEAD to the exact SHA returned by `git ls-remote`
#   for origin/<default_branch>, without mutating local refs. Echoes:
#     current      exact SHA match
#     mismatch     local HEAD differs (ahead, behind, or diverged)
#     unreachable  either SHA cannot be proved (including network/auth failure)
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

classify_registry_freshness() {
  local local_sha="${1:-}" remote_sha="${2:-}" lookup_status="${3:-unreachable}"
  if [[ "$lookup_status" != "ok" ]] ||
     [[ ! "$local_sha" =~ ^[0-9a-fA-F]{40,64}$ ]] ||
     [[ ! "$remote_sha" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
    echo "unreachable"
  elif [[ "$local_sha" == "$remote_sha" ]]; then
    echo "current"
  else
    echo "mismatch"
  fi
}

registry_freshness_detail() {
  case "${1:-unreachable}" in
    current)     echo "HEAD exactly matches origin" ;;
    mismatch)    echo "HEAD differs from live origin (ahead, behind, or diverged)" ;;
    unreachable) echo "live origin SHA could not be verified" ;;
    *)           echo "unknown freshness verdict: ${1}" ;;
  esac
}

classify_deploy_marker() {
  local marker="${1:-}" kind="${2:-regular}"
  case "$kind" in
    missing|symlink) echo "$kind" ;;
    regular)
      if [[ "$marker" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
        echo "valid"
      else
        echo "invalid"
      fi
      ;;
    *) echo "invalid" ;;
  esac
}

check_registry_freshness() {
  local checkout="${1:-}" default_branch="${2:-main}"
  local local_sha remote_line remote_sha

  [[ -n "$checkout" ]] || { echo "unreachable"; return 0; }
  local_sha="$(git -C "$checkout" rev-parse HEAD 2>/dev/null)" || {
    echo "unreachable"
    return 0
  }
  remote_line="$(git -C "$checkout" ls-remote --exit-code origin "refs/heads/${default_branch}" 2>/dev/null)" || {
    echo "unreachable"
    return 0
  }
  read -r remote_sha _ <<< "$remote_line"
  classify_registry_freshness "$local_sha" "${remote_sha:-}" ok
}

# Re-stamp the git-pull deploy marker (#33). Heimdall's drift detector reads
# <checkout>/.deployed-commit to decide whether a git-pull component is behind
# origin. deploy.sh stamps that marker, but the canonical grimnir checkout also
# gets pulled forward by ad-hoc sessions OUTSIDE a deploy, which leaves the marker
# stale and makes Heimdall false-flag every grimnir unit as behind. Re-stamp HEAD
# into the marker — but ONLY when the caller has already verified the checkout is
# clean, on its default branch (verdict "ok"), AND exactly equal to live origin
# (freshness "current"); never bless a dirty, branch-stranded, local-ahead,
# diverged, or origin-unreachable tree. Guarded on an existing marker so it never
# fabricates one on a non-deploy checkout (e.g. a laptop run).
#
# Returns:
#   0 — stamped, or intentionally skipped (unproved checkout or no marker present)
#   1 — marker present + proved checkout, but the write FAILED (e.g. a read-only
#       mount, as under grimnir-validate.service's sandbox). The caller MUST
#       surface this rather than swallow it, or the marker silently stays stale.
restamp_deploy_marker() {
  local checkout="${1:-}" verdict="${2:-}" freshness="${3:-unreachable}"
  # A clean main branch is not sufficient: a clean local-ahead or diverged
  # checkout is exactly the state the deploy marker must never certify.
  [[ "$verdict" == "ok" && "$freshness" == "current" ]] || return 0
  local marker="${checkout}/.deployed-commit"
  # Refuse a symlinked marker. The marker is gitignored (outside git's dirty
  # check), and both this write and the validate service's ReadWritePaths
  # exception resolve symlinks — so following one could clobber an arbitrary
  # target. Surface it (return 1) rather than write through it.
  [[ -L "$marker" ]] && return 1
  [[ -f "$marker" ]] || return 0
  local head
  head="$(git -C "$checkout" rev-parse HEAD 2>/dev/null)" || return 0
  # Group the redirection so a failed open (read-only mount) is suppressed too —
  # a bare `> "$marker" 2>/dev/null` can still leak the open error to stderr.
  { printf '%s\n' "$head" > "$marker"; } 2>/dev/null || return 1
  return 0
}

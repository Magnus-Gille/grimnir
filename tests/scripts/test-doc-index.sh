#!/usr/bin/env bash
# Guards the AGENTS.md -> docs/index.md progressive-disclosure split.
#
# The split moved the document index out of the always-loaded instruction file.
# That is only safe if two things stay true:
#   1. AGENTS.md still points at the index (one hop, discoverable).
#   2. Every document in docs/ is actually listed there, and every listed path
#      exists. A doc that exists but is unlisted is unreachable; a listed path
#      that does not exist is a broken pointer.
#
# It also asserts that the constraint-bearing annotations survived the move
# verbatim. Those carry policy, not just a location, and a lossy move is worse
# than a slow lookup.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

AGENTS="AGENTS.md"
INDEX="docs/index.md"
fail=0

err() { echo "FAIL: $*" >&2; fail=1; }

[[ -f "$INDEX" ]] || { echo "FAIL: $INDEX is missing" >&2; exit 1; }

# 1. One-hop discoverability.
if ! grep -q 'docs/index\.md' "$AGENTS"; then
  err "$AGENTS does not reference $INDEX — the index is unreachable from the instruction file"
fi

# 2a. Every doc in docs/ is listed in the index.
#     full-architecture.md is generated and gitignored; it is described in the
#     index but need not exist locally.
while IFS= read -r doc; do
  case "$doc" in
    docs/index.md|docs/full-architecture.md) continue ;;
  esac
  if ! grep -qF "$doc" "$INDEX"; then
    err "$doc exists but is not listed in $INDEX"
  fi
done < <(git ls-files 'docs/*.md' 'docs/*.json')

# 2b. Every docs/ path mentioned in the index exists.
while IFS= read -r ref; do
  case "$ref" in
    docs/full-architecture.md) continue ;;
  esac
  [[ -e "$ref" ]] || err "$INDEX references $ref, which does not exist"
done < <(grep -oE 'docs/[A-Za-z0-9._/-]+\.(md|json)' "$INDEX" | sort -u)

# 3. Constraint-bearing annotations survived the move.
#    These are policy, not descriptions. If the index is ever regenerated or
#    trimmed, these must not be the casualty.
declare -a REQUIRED_ANNOTATIONS=(
  "not authorization to restart Verdandi"
  "private-envelope contents stay out of git"
  "Single source of truth"
)
for annotation in "${REQUIRED_ANNOTATIONS[@]}"; do
  if ! grep -qF "$annotation" "$INDEX"; then
    err "constraint annotation lost from $INDEX: \"$annotation\""
  fi
done

# 3b. Some rules state an obligation rather than a location. An agent that never
#     thinks to ask the question still has to honour them, so they must stay in
#     the always-loaded instruction file — moving them behind the index would be
#     invisible to the A/B, whose doc-hit metric only measures agents that went
#     looking. Guarded here because that blind spot makes drift easy to miss.
declare -a REQUIRED_INLINE_RULES=(
  "reversal recipe and an audit event"
  "Hugin handoff"
  "must not** double as a deploy target"
)
for rule in "${REQUIRED_INLINE_RULES[@]}"; do
  if ! grep -qF "$rule" "$AGENTS"; then
    err "behavioural rule lost from $AGENTS: \"$rule\" — it must not move to $INDEX"
  fi
done

# 4. The instruction file stays lean. This is the whole point of the split; a
#    generous ceiling that still catches the index creeping back in.
words=$(wc -w < "$AGENTS")
if (( words > 900 )); then
  err "$AGENTS has grown to $words words (ceiling 900) — move reference material to $INDEX"
fi

if (( fail )); then
  echo "doc-index checks failed" >&2
  exit 1
fi

echo "PASS: doc index reachable, complete, and constraint annotations intact ($words words in $AGENTS)"

#!/usr/bin/env bash
# Regression test for the ab-skills-eval.sh sandbox.
#
# The skill A/B probes `deploy` and `submit-task`. Those skills really deploy
# services and really dispatch work to the Pi, so the harness is only safe if a
# skill body cannot act. This test proves that it cannot.
#
# It exists because the harness got this wrong twice, in opposite directions.
#
# First: permissions.defaultMode="auto" in the user settings auto-approves every
# tool, so --allowedTools constrained nothing. A check-email probe ran four m365
# Graph queries and spawned a subagent before the run was killed.
#
# Then the obvious fix, --setting-sources project, silently broke the experiment
# instead: ~/.claude/skills is a user-level source, so dropping user settings
# drops the skill set under test. Every probe scored zero and it read as a
# catastrophic regression rather than a broken harness.
#
# The surviving design keeps user settings, disables MCP (hugin_submit dispatches
# real work; m5 spends real inference — both were seen executing), and disallows
# the write-capable built-ins. This test pins that exact combination, and asserts
# BOTH halves: that nothing can act, and that the skill still fires. Either one
# alone can pass while the harness is worthless.
#
# Skipped when `claude` is unavailable (CI without credentials).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$SCRIPT_DIR/../../scripts/tests/ab-skills-eval.sh"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

# 1. Static check: the harness must carry all three guards. Cheap, always runs,
#    and catches the exact regression that happened.
grep -q -- '--strict-mcp-config' "$HARNESS" || \
  err "ab-skills-eval.sh lost --strict-mcp-config; MCP tools (hugin_submit, m5) would be live in skill bodies"
grep -q -- '--allowedTools Skill' "$HARNESS" || \
  err "ab-skills-eval.sh lost --allowedTools Skill"
grep -q -- '--disallowedTools Bash' "$HARNESS" || \
  err "ab-skills-eval.sh lost --disallowedTools Bash"

if ! command -v claude >/dev/null 2>&1; then
  echo "SKIP: claude CLI not available; ran static checks only"
  exit "$fail"
fi

# 2. Live check against the REAL skill set, using the most dangerous probe in it.
#    An earlier version of this test delivered its own probe skill via
#    --plugin-dir, but that stopped loading once the user skill set was present,
#    and a sandbox test that cannot fire a skill silently proves nothing. Using
#    `deploy` tests the actual thing: the skill that really ships services.
TMP="$(mktemp -d)"
# shellcheck disable=SC2329  # invoked via trap
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

stream="$TMP/stream.jsonl"
(cd "$TMP" && timeout 180 command claude -p "Push heimdall out to the Pi." \
  --output-format stream-json --verbose \
  --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
  --allowedTools Skill \
  --disallowedTools Bash Edit Write NotebookEdit WebFetch WebSearch Agent Task \
  --model sonnet < /dev/null) > "$stream" 2>"$stream.err" || true

fired=$(jq -s -r '[.[]|select(.type=="assistant")|.message.content[]?
                   |select(.type=="tool_use" and .name=="Skill")|.input.skill]
                  | map(sub("^[^:]*:";"")) | first // ""' "$stream" 2>/dev/null || echo "")

# A blocked tool still appears as a tool_use block — the model ATTEMPTS it and the
# harness denies it. Counting attempts gives a false breach, so pair each
# dangerous tool_use with its tool_result and only count ones that actually ran.
# The distinction is the whole test: in the real incident the m365 queries came
# back with data, whereas a denied Bash call returns "not enabled in this
# context".
acted=$(jq -s -r '
  ([.[]|select(.type=="assistant")|.message.content[]?
     |select(.type=="tool_use")
     |select(.name|test("^(Bash|Edit|Write|NotebookEdit|WebFetch|WebSearch|Agent|Task|mcp__)"))
     |{id:.id, name:.name}]) as $danger
  | ([.[]|select(.type=="user")|.message.content[]?
       |select(.type=="tool_result")
       |select((.content|tostring|test("not enabled in this context|No such tool available|permission")) | not)
       |.tool_use_id]) as $succeeded
  | [$danger[] | select(.id as $i | $succeeded | index($i)) | .name]
  | unique | join(",")' "$stream" 2>/dev/null || echo "")

# Both halves matter. A sandbox that blocks everything including the Skill call
# would pass a safety-only check while measuring nothing at all.
[[ "$fired" == "deploy" ]] || err "deploy probe did not route (got '${fired:-none}') — the harness would score every probe zero"
[[ -z "$acted" ]] || err "SANDBOX BREACH: world-changing tool(s) executed: $acted"

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: deploy routed correctly, no world-changing tool executed"
fi
exit "$fail"

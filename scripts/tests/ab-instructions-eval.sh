#!/usr/bin/env bash
# A/B eval for agent-instruction changes.
#
# Runs a frozen probe set through headless Claude Code in two worktrees that
# differ only in their instruction files, and reports whether the change costs
# retrieval accuracy.
#
# Primary metric is doc-hit: did the agent actually open the document that
# answers the question? That is read mechanically out of the tool-call stream,
# so it needs no judge.
#
# Efficiency metric is initial prompt tokens (cache_creation + cache_read on the
# first assistant iteration). Cost is NOT the primary metric: prompt caching
# makes later reps of the same arm cheaper than the first, which would reward
# whichever arm happened to run second.
#
# Usage:
#   scripts/tests/ab-instructions-eval.sh --before DIR --after DIR [--reps N]
#                                         [--model M] [--out FILE] [--probes F]

set -euo pipefail

BEFORE_DIR=""
AFTER_DIR=""
REPS=3
# The preserved 2026-07-25 evidence used Sonnet. Keep that as the explicit
# default so a rerun is comparable; callers may deliberately override it with
# --model, and the selected value is printed into the run log below.
MODEL="sonnet"
OUT=""
PROBES=""
TIMEOUT_S=240

usage() { sed -n '1,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before)  BEFORE_DIR="$2"; shift 2 ;;
    --after)   AFTER_DIR="$2";  shift 2 ;;
    --reps)    REPS="$2";       shift 2 ;;
    --model)   MODEL="$2";      shift 2 ;;
    --out)     OUT="$2";        shift 2 ;;
    --probes)  PROBES="$2";     shift 2 ;;
    --timeout) TIMEOUT_S="$2";  shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$BEFORE_DIR" && -n "$AFTER_DIR" ]] || { echo "--before and --after are required" >&2; usage 1; }
[[ -d "$BEFORE_DIR" && -d "$AFTER_DIR" ]] || { echo "both arms must be existing directories" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBES="${PROBES:-$REPO_ROOT/tests/fixtures/instruction-probes/probes.json}"
[[ -f "$PROBES" ]] || { echo "probe file not found: $PROBES" >&2; exit 1; }

OUT="${OUT:-$REPO_ROOT/outputs/ab-instructions-$(date +%Y%m%d-%H%M%S).json}"
mkdir -p "$(dirname "$OUT")"
RAW_DIR="${OUT%.json}-raw"
mkdir -p "$RAW_DIR"

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }
# Not a stock macOS tool — it ships with GNU coreutils. Checked here because it is
# used unconditionally per run, so a missing binary would otherwise surface as 78
# identical "run failed" results that look like a real regression.
command -v timeout >/dev/null || { echo "timeout not found (brew install coreutils)" >&2; exit 1; }

PROBE_IDS=()
while IFS= read -r id; do PROBE_IDS+=("$id"); done < <(jq -r '.probes[].id' "$PROBES")

echo "probes: ${#PROBE_IDS[@]}  arms: 2  reps: $REPS  model: $MODEL"
echo "total runs: $(( ${#PROBE_IDS[@]} * 2 * REPS ))"
echo "raw streams: $RAW_DIR"
echo

# Run one probe in one arm. Emits a single JSON result object on stdout.
run_one() {
  local arm="$1" dir="$2" probe_id="$3" rep="$4"
  local prompt target kind assert_regex raw
  prompt=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .prompt' "$PROBES")
  target=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .target' "$PROBES")
  kind=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .kind' "$PROBES")
  assert_regex=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .assert_regex // ""' "$PROBES")

  raw="$RAW_DIR/${arm}-${probe_id}-r${rep}.jsonl"

  # `command claude` bypasses the user's shell wrapper function. Project-only
  # settings still load the arm's CLAUDE.md/AGENTS.md instructions, which are
  # the unit under test, while excluding user settings such as
  # permissions.defaultMode="auto". MCP is strictly empty and every built-in
  # mutation, network, or dispatch surface is denied explicitly. The remaining
  # Read/Grep/Glob surface is sufficient for mechanical doc-hit scoring.
  if ! (cd "$dir" && timeout "$TIMEOUT_S" command claude -p "$prompt" \
        --output-format stream-json --verbose \
        --setting-sources project \
        --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
        --allowedTools "Read" "Grep" "Glob" \
        --disallowedTools Bash Edit Write NotebookEdit WebFetch WebSearch Agent Task \
        --permission-mode dontAsk \
        --model "$MODEL") > "$raw" 2>"$raw.err"; then
    jq -n --arg arm "$arm" --arg id "$probe_id" --arg kind "$kind" --argjson rep "$rep" \
      '{arm:$arm, probe:$id, kind:$kind, rep:$rep, error:"run failed or timed out",
        doc_hit:false, assert_pass:false, tool_calls:null, prompt_tokens:null,
        output_tokens:null, num_turns:null, cost_usd:null, duration_ms:null}'
    return
  fi

  # doc_hit: the target path appears in the input of any tool call. Matching on
  # the tool-call stream rather than the answer text is deliberate — it detects
  # the file actually being opened, not the model mentioning a plausible path.
  # NOTE: must slurp and reduce with `any`. An earlier version used `jq -e` over
  # the stream, whose exit status reflects only the LAST emitted value — so a run
  # counted as a hit only if the target appeared in its final tool call. That
  # systematically under-counted, and penalised whichever arm explored more after
  # already finding the document.
  local doc_hit
  doc_hit=$(jq -s --arg t "$target" '
      [ .[] | select(.type=="assistant")
            | .message.content[]? | select(.type=="tool_use")
            | (.input | tostring) | contains($t) ] | any' "$raw")

  local tool_calls
  tool_calls=$(jq -s '[.[] | select(.type=="assistant") | .message.content[]?
                        | select(.type=="tool_use")] | length' "$raw")

  local result_line
  result_line=$(jq -s -c '[.[] | select(.type=="result")] | last // {}' "$raw")

  # Initial prompt size: cache_creation + cache_read on the first assistant
  # iteration. Stable across reps regardless of cache warmth.
  local prompt_tokens
  prompt_tokens=$(jq -s '[.[] | select(.type=="assistant")
                          | .message.usage
                          | (.cache_creation_input_tokens // 0)
                            + (.cache_read_input_tokens // 0)
                            + (.input_tokens // 0)] | first // null' "$raw")

  local answer
  answer=$(echo "$result_line" | jq -r '.result // ""')

  local assert_pass=null
  if [[ -n "$assert_regex" ]]; then
    if echo "$answer" | grep -Eqi "${assert_regex#(?i)}"; then
      assert_pass=true
    else
      assert_pass=false
    fi
  fi

  jq -n \
    --arg arm "$arm" --arg id "$probe_id" --arg kind "$kind" --argjson rep "$rep" \
    --argjson doc_hit "$doc_hit" --argjson assert_pass "$assert_pass" \
    --argjson tool_calls "$tool_calls" --argjson prompt_tokens "${prompt_tokens:-null}" \
    --argjson res "$result_line" --arg answer "$answer" \
    '{arm:$arm, probe:$id, kind:$kind, rep:$rep,
      doc_hit:$doc_hit, assert_pass:$assert_pass, tool_calls:$tool_calls,
      prompt_tokens:$prompt_tokens,
      output_tokens:($res.usage.output_tokens // null),
      num_turns:($res.num_turns // null),
      cost_usd:($res.total_cost_usd // null),
      duration_ms:($res.duration_ms // null),
      answer:$answer, error:null}'
}

RESULTS="$RAW_DIR/results.ndjson"
: > "$RESULTS"

for rep in $(seq 1 "$REPS"); do
  for probe_id in "${PROBE_IDS[@]}"; do
    for arm_spec in "before:$BEFORE_DIR" "after:$AFTER_DIR"; do
      arm="${arm_spec%%:*}"; dir="${arm_spec#*:}"
      printf '  rep %s  %-24s %-7s ' "$rep" "$probe_id" "$arm"
      line=$(run_one "$arm" "$dir" "$probe_id" "$rep")
      echo "$line" >> "$RESULTS"
      echo "$line" | jq -r 'if .error then "ERROR" else (if .doc_hit then "hit " else "MISS" end) + "  " + (.tool_calls|tostring) + " calls  " + ((.prompt_tokens//0)|tostring) + " tok" end'
    done
  done
done

jq -s --slurpfile probes "$PROBES" '
  def arm_stats(a):
    map(select(.arm == a)) as $r
    | { runs: ($r | length),
        doc_hit_rate: (if ($r|length) > 0 then (($r | map(select(.doc_hit)) | length) / ($r | length)) else null end),
        mean_prompt_tokens: (if ($r|length) > 0 then (($r | map(.prompt_tokens // 0) | add) / ($r | length)) else null end),
        mean_tool_calls: (if ($r|length) > 0 then (($r | map(.tool_calls // 0) | add) / ($r | length)) else null end),
        total_cost_usd: ($r | map(.cost_usd // 0) | add),
        errors: ($r | map(select(.error != null)) | length) };
  {
    summary: { before: arm_stats("before"), after: arm_stats("after") },
    per_probe: (group_by(.probe) | map({
        probe: .[0].probe,
        kind: .[0].kind,
        before_hits: (map(select(.arm=="before" and .doc_hit)) | length),
        before_runs: (map(select(.arm=="before")) | length),
        after_hits:  (map(select(.arm=="after"  and .doc_hit)) | length),
        after_runs:  (map(select(.arm=="after")) | length),
        before_assert_pass: (map(select(.arm=="before" and .assert_pass==true)) | length),
        after_assert_pass:  (map(select(.arm=="after"  and .assert_pass==true)) | length),
        before_mean_tokens: ((map(select(.arm=="before") | .prompt_tokens // 0) | add) / ((map(select(.arm=="before")) | length) | if . == 0 then 1 else . end)),
        after_mean_tokens:  ((map(select(.arm=="after")  | .prompt_tokens // 0) | add) / ((map(select(.arm=="after"))  | length) | if . == 0 then 1 else . end))
      })),
    runs: .
  }' "$RESULTS" > "$OUT"

echo
echo "=== summary ==="
jq -r '
  "                    before      after",
  "doc-hit rate      \(.summary.before.doc_hit_rate*100 | floor)%        \(.summary.after.doc_hit_rate*100 | floor)%",
  "mean prompt tok   \(.summary.before.mean_prompt_tokens | floor)      \(.summary.after.mean_prompt_tokens | floor)",
  "mean tool calls   \(.summary.before.mean_tool_calls*10 | floor / 10)         \(.summary.after.mean_tool_calls*10 | floor / 10)",
  "errors            \(.summary.before.errors)           \(.summary.after.errors)",
  "",
  "regressions (probes that lost hits):",
  ((.per_probe | map(select(.after_hits < .before_hits))
    | if length == 0 then ["  none"] else map("  \(.probe): \(.before_hits)/\(.before_runs) -> \(.after_hits)/\(.after_runs)") end)[])
' "$OUT"
echo
echo "full results: $OUT"

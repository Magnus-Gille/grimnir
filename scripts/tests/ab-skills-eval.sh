#!/usr/bin/env bash
# A/B eval for skill-description changes.
#
# Sibling of ab-instructions-eval.sh. Same shape, different unit under test:
# there the question was "does the agent still open the right document", here it
# is "does the agent still invoke the right skill".
#
# Primary metric is trigger-hit: did the agent call the Skill tool with the
# expected skill? That is read mechanically out of the tool-call stream, so it
# needs no judge.
#
# Efficiency metric is initial prompt tokens (cache_creation + cache_read +
# input on the first assistant iteration). Cost is NOT the metric: prompt
# caching makes later reps cheaper than the first, which would reward whichever
# arm happened to run second.
#
# WHY THIS SWAPS A GLOBAL SYMLINK
# Skills load from ~/.claude/skills, a fixed global path — not from the working
# directory. So the two-worktree trick that isolates instruction files does not
# work here. Loading an arm via --plugin-dir was measured to work, but the user
# skill set loads *as well*, so the original descriptions stay live and the trim
# under test is never actually exercised. Repointing the symlink is the only
# isolation that measures the real thing.
#
# The consequence: while this runs, EVERY Claude Code session on this machine
# sees the arm's skill set. Do not run it concurrently with other sessions or
# with subagents. That is why --i-understand-global-swap is required.
#
# Usage:
#   scripts/tests/ab-skills-eval.sh --before DIR --after DIR \
#       --i-understand-global-swap [--reps N] [--model M] [--out FILE]

set -euo pipefail

BEFORE_DIR=""
AFTER_DIR=""
REPS=3
MODEL="sonnet"
OUT=""
PROBES=""
TIMEOUT_S=180
CONFIRMED=0

usage() { sed -n '1,32p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --before)  BEFORE_DIR="$2"; shift 2 ;;
    --after)   AFTER_DIR="$2";  shift 2 ;;
    --reps)    REPS="$2";       shift 2 ;;
    --model)   MODEL="$2";      shift 2 ;;
    --out)     OUT="$2";        shift 2 ;;
    --probes)  PROBES="$2";     shift 2 ;;
    --timeout) TIMEOUT_S="$2";  shift 2 ;;
    --i-understand-global-swap) CONFIRMED=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown argument: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$BEFORE_DIR" && -n "$AFTER_DIR" ]] || { echo "--before and --after are required" >&2; usage 1; }
BEFORE_DIR="$(cd "$BEFORE_DIR" && pwd)"
AFTER_DIR="$(cd "$AFTER_DIR" && pwd)"

if [[ "$CONFIRMED" -ne 1 ]]; then
  echo "refusing to run: this repoints ~/.claude/skills for the duration of the run," >&2
  echo "which changes the skill set for every Claude Code session on this machine." >&2
  echo "Close other sessions, then re-run with --i-understand-global-swap." >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBES="${PROBES:-$REPO_ROOT/tests/fixtures/skill-probes/probes.json}"
[[ -f "$PROBES" ]] || { echo "probe file not found: $PROBES" >&2; exit 1; }

command -v claude >/dev/null || { echo "claude CLI not found" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 1; }

SKILLS_LINK="$HOME/.claude/skills"

# Refuse unless the live path is a symlink we can put back byte-for-byte. If it
# is a real directory we would have to move it, and a crash mid-run would leave
# the user with no skills at all.
[[ -L "$SKILLS_LINK" ]] || {
  echo "$SKILLS_LINK is not a symlink; refusing to swap it." >&2
  echo "This harness only supports the symlinked layout, so that restore is exact." >&2
  exit 1
}
ORIGINAL_TARGET="$(readlink "$SKILLS_LINK")"
[[ -n "$ORIGINAL_TARGET" ]] || { echo "could not read current skills symlink target" >&2; exit 1; }

# Both arms must look like skill sets, checked BEFORE anything is swapped.
for d in "$BEFORE_DIR" "$AFTER_DIR"; do
  [[ -d "$d" ]] || { echo "arm is not a directory: $d" >&2; exit 1; }
  n=$(find "$d" -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
  [[ "$n" -gt 0 ]] || {
    echo "arm contains no */SKILL.md, refusing: $d" >&2; exit 1; }
  echo "arm $d: $n skills"
done

restore_skills() {
  # Idempotent, and safe to call from a trap. Uses -n so we replace the symlink
  # itself rather than creating a link *inside* the directory it points at.
  if [[ -n "${ORIGINAL_TARGET:-}" ]]; then
    ln -sfn "$ORIGINAL_TARGET" "$SKILLS_LINK"
    echo "restored ~/.claude/skills -> $ORIGINAL_TARGET" >&2
  fi
}
trap restore_skills EXIT INT TERM

OUT="${OUT:-$REPO_ROOT/outputs/ab-skills-$(date +%Y%m%d-%H%M%S).json}"
mkdir -p "$(dirname "$OUT")"
RAW_DIR="${OUT%.json}-raw"
mkdir -p "$RAW_DIR"

PROBE_IDS=()
while IFS= read -r id; do PROBE_IDS+=("$id"); done < <(jq -r '.probes[].id' "$PROBES")

echo "probes: ${#PROBE_IDS[@]}  arms: 2  reps: $REPS  model: $MODEL"
echo "total runs: $(( ${#PROBE_IDS[@]} * 2 * REPS ))"
echo "original skills target: $ORIGINAL_TARGET"
echo "raw streams: $RAW_DIR"
echo

# Run one probe against whatever ~/.claude/skills currently points at.
#
# SAFETY: --allowedTools Skill with the default permission mode. Only the Skill
# tool is pre-approved, so a skill body that tries to run Bash, edit, or fetch is
# denied rather than prompted. Verified empirically: a probe skill instructed to
# `echo ... > /tmp/...` fired the Skill call and produced no file. That is what
# makes it safe to probe `deploy` and `submit-task` — the routing decision is
# observed without the body being able to act.
run_one() {
  local arm="$1" probe_id="$2" rep="$3"
  local prompt kind expect avoid raw
  prompt=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .prompt' "$PROBES")
  kind=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .kind' "$PROBES")
  expect=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .expect // ""' "$PROBES")
  avoid=$(jq -r --arg id "$probe_id" '.probes[] | select(.id==$id) | .avoid // ""' "$PROBES")

  raw="$RAW_DIR/${arm}-${probe_id}-r${rep}.jsonl"

  # `command claude` bypasses the user's shell wrapper function so the run is
  # reproducible and free of its side effects.
  if ! (cd "$REPO_ROOT" && timeout "$TIMEOUT_S" command claude -p "$prompt" \
        --output-format stream-json --verbose \
        --allowedTools Skill \
        --model "$MODEL") > "$raw" 2>"$raw.err"; then
    jq -n --arg arm "$arm" --arg id "$probe_id" --arg kind "$kind" --argjson rep "$rep" \
      '{arm:$arm, probe:$id, kind:$kind, rep:$rep, error:"run failed or timed out",
        fired:null, correct:false, prompt_tokens:null, cost_usd:null, duration_ms:null}'
    return
  fi

  # Which skill fired, if any. Slurp and reduce — never `jq -e` over a stream,
  # whose exit status reflects only the last emitted value. That defect biased
  # the instructions harness against the arm that made more tool calls.
  # The plugin/user namespace prefix ("abtest:foo") is stripped so arms that load
  # skills by different mechanisms stay comparable.
  local fired
  fired=$(jq -s -r '
      [ .[] | select(.type=="assistant")
            | .message.content[]? | select(.type=="tool_use")
            | select(.name=="Skill") | .input.skill ]
      | map(sub("^[^:]*:"; ""))
      | first // ""' "$raw")

  # correct:
  #   trigger  -> the expected skill fired
  #   control  -> nothing fired at all
  #   negative -> the skill named in `avoid` did not fire (anything else is fine)
  local correct=false
  case "$kind" in
    trigger)  [[ "$fired" == "$expect" ]] && correct=true ;;
    control)  [[ -z "$fired" ]] && correct=true ;;
    negative) [[ "$fired" != "$avoid" ]] && correct=true ;;
  esac

  local result_line
  result_line=$(jq -s -c '[.[] | select(.type=="result")] | last // {}' "$raw")

  local prompt_tokens
  prompt_tokens=$(jq -s '[.[] | select(.type=="assistant")
                          | .message.usage
                          | (.cache_creation_input_tokens // 0)
                            + (.cache_read_input_tokens // 0)
                            + (.input_tokens // 0)] | first // null' "$raw")

  jq -n \
    --arg arm "$arm" --arg id "$probe_id" --arg kind "$kind" --argjson rep "$rep" \
    --arg fired "$fired" --arg expect "$expect" --argjson correct "$correct" \
    --argjson prompt_tokens "${prompt_tokens:-null}" --argjson res "$result_line" \
    '{arm:$arm, probe:$id, kind:$kind, rep:$rep,
      fired:(if $fired=="" then null else $fired end),
      expect:(if $expect=="" then null else $expect end),
      correct:$correct,
      prompt_tokens:$prompt_tokens,
      cost_usd:($res.total_cost_usd // null),
      duration_ms:($res.duration_ms // null),
      error:null}'
}

RESULTS="$RAW_DIR/results.ndjson"
: > "$RESULTS"

# Arm-major ordering: one symlink swap per arm rather than one per run. Keeps the
# global-mutation window as short and as few as possible. Safe for the token
# metric because prompt_tokens is read from the first assistant iteration, which
# is cache-warmth independent.
for arm_spec in "before:$BEFORE_DIR" "after:$AFTER_DIR"; do
  arm="${arm_spec%%:*}"; dir="${arm_spec#*:}"
  ln -sfn "$dir" "$SKILLS_LINK"
  echo "--- arm '$arm': ~/.claude/skills -> $dir"
  for rep in $(seq 1 "$REPS"); do
    for probe_id in "${PROBE_IDS[@]}"; do
      printf '  rep %s  %-26s %-7s ' "$rep" "$probe_id" "$arm"
      line=$(run_one "$arm" "$probe_id" "$rep")
      echo "$line" >> "$RESULTS"
      echo "$line" | jq -r 'if .error then "ERROR" else
        (if .correct then "ok  " else "BAD " end) + "  fired=" + (.fired // "-")
        + "  " + ((.prompt_tokens//0)|tostring) + " tok" end'
    done
  done
done

restore_skills
trap - EXIT INT TERM

jq -s '
  def arm_stats(a):
    map(select(.arm == a)) as $r
    | ($r | map(select(.kind=="trigger"))) as $t
    | ($r | map(select(.kind=="control" or .kind=="negative"))) as $c
    | { runs: ($r | length),
        trigger_correct: ($t | map(select(.correct)) | length),
        trigger_runs: ($t | length),
        control_correct: ($c | map(select(.correct)) | length),
        control_runs: ($c | length),
        mean_prompt_tokens: (if ($r|length) > 0 then (($r | map(.prompt_tokens // 0) | add) / ($r | length)) else null end),
        total_cost_usd: ($r | map(.cost_usd // 0) | add),
        errors: ($r | map(select(.error != null)) | length) };
  {
    summary: { before: arm_stats("before"), after: arm_stats("after") },
    per_probe: (group_by(.probe) | map({
        probe: .[0].probe,
        kind: .[0].kind,
        expect: .[0].expect,
        before_correct: (map(select(.arm=="before" and .correct)) | length),
        before_runs: (map(select(.arm=="before")) | length),
        after_correct: (map(select(.arm=="after" and .correct)) | length),
        after_runs: (map(select(.arm=="after")) | length),
        before_fired: (map(select(.arm=="before") | .fired) | unique),
        after_fired: (map(select(.arm=="after") | .fired) | unique)
      })),
    runs: .
  }' "$RESULTS" > "$OUT"

echo
echo "=== summary ==="
jq -r '
  "                     before      after",
  "trigger correct    \(.summary.before.trigger_correct)/\(.summary.before.trigger_runs)       \(.summary.after.trigger_correct)/\(.summary.after.trigger_runs)",
  "control correct    \(.summary.before.control_correct)/\(.summary.before.control_runs)       \(.summary.after.control_correct)/\(.summary.after.control_runs)",
  "mean prompt tok    \(.summary.before.mean_prompt_tokens | floor)      \(.summary.after.mean_prompt_tokens | floor)",
  "errors             \(.summary.before.errors)           \(.summary.after.errors)",
  "",
  "regressions (probes that got worse):",
  ((.per_probe | map(select(.after_correct < .before_correct))
    | if length == 0 then ["  none"] else map("  \(.probe) [\(.kind)]: \(.before_correct)/\(.before_runs) -> \(.after_correct)/\(.after_runs)  fired=\(.after_fired)") end)[])
' "$OUT"
echo
echo "full results: $OUT"

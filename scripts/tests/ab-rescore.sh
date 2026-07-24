#!/usr/bin/env bash
# Re-score saved A/B raw streams without re-running any agent.
#
# Exists because the original doc-hit detector used `jq -e` over a stream, whose
# exit status reflects only the last emitted value. Runs were scored as misses
# whenever the target document was opened at any point other than the final tool
# call. Raw streams are retained precisely so a scoring fix does not require
# paying for the runs again.
#
# Usage: scripts/tests/ab-rescore.sh RAW_DIR PROBES_JSON

set -euo pipefail

RAW_DIR="${1:?usage: ab-rescore.sh RAW_DIR PROBES_JSON}"
PROBES="${2:?usage: ab-rescore.sh RAW_DIR PROBES_JSON}"

[[ -d "$RAW_DIR" ]] || { echo "no such raw dir: $RAW_DIR" >&2; exit 1; }

for f in "$RAW_DIR"/*.jsonl; do
  base=$(basename "$f" .jsonl)
  [[ "$base" == "results" ]] && continue
  arm="${base%%-*}"
  rest="${base#*-}"
  probe="${rest%-r*}"
  rep="${rest##*r}"

  target=$(jq -r --arg id "$probe" '.probes[] | select(.id==$id) | .target // empty' "$PROBES")
  [[ -n "$target" ]] || continue

  hit=$(jq -s --arg t "$target" '
      [ .[] | select(.type=="assistant")
            | .message.content[]? | select(.type=="tool_use")
            | (.input | tostring) | contains($t) ] | any' "$f")

  calls=$(jq -s '[.[] | select(.type=="assistant") | .message.content[]?
                  | select(.type=="tool_use")] | length' "$f")

  jq -n --arg arm "$arm" --arg probe "$probe" --argjson rep "${rep:-0}" \
        --argjson hit "$hit" --argjson calls "$calls" \
    '{arm:$arm, probe:$probe, rep:$rep, doc_hit:$hit, tool_calls:$calls}'
done | jq -s '
  {
    before_hit_rate: ([.[] | select(.arm=="before")] | (map(select(.doc_hit))|length) / (length)),
    after_hit_rate:  ([.[] | select(.arm=="after")]  | (map(select(.doc_hit))|length) / (length)),
    per_probe: (group_by(.probe) | map({
      probe: .[0].probe,
      before: "\(map(select(.arm=="before" and .doc_hit))|length)/\(map(select(.arm=="before"))|length)",
      after:  "\(map(select(.arm=="after"  and .doc_hit))|length)/\(map(select(.arm=="after"))|length)"
    }))
  }'

#!/usr/bin/env bash
# shellcheck shell=bash
# Immutable per-run evidence helpers for grimnir-validate (issue #159).
#
# This library deliberately performs no fetch, pull, or other checkout mutation.
# It produces the evidence payload which the validator appends through Munin's
# immutable memory_log channel after the mutable latest-result write succeeds.

validation_trigger_origin() {
  case "${1:-}" in
    timer|manual) printf '%s\n' "$1" ;;
    *) return 1 ;;
  esac
}

# validation_timer_scheduled_at_utc reads systemd's last timer trigger. The
# timestamp is captured separately from the script's observed timestamp so a
# randomized timer delay cannot be mistaken for validation duration. GNU date
# is available on the production Linux host; a parse failure is left empty for
# the caller to fail closed rather than inventing a schedule time.
validation_timer_scheduled_at_utc() {
  local raw=""
  raw="$(systemctl show --property=LastTriggerUSec --value grimnir-validate.timer 2>/dev/null)" || return 1
  [[ -n "$raw" && "$raw" != "n/a" ]] || return 1
  date --utc --date="$raw" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null
}

validation_freshness_classification() {
  local local_sha="${1:-}" remote_sha="${2:-}" relation="${3:-unreachable}"
  if [[ ! "$local_sha" =~ ^[0-9a-fA-F]{40,64}$ ]] ||
     [[ ! "$remote_sha" =~ ^[0-9a-fA-F]{40,64}$ ]]; then
    printf '%s\n' unreachable
  elif [[ "$local_sha" == "$remote_sha" ]]; then
    printf '%s\n' current
  else
    case "$relation" in
      ahead|behind|diverged) printf '%s\n' "$relation" ;;
      *) printf '%s\n' unreachable ;;
    esac
  fi
}

# validation_registry_freshness_evidence <checkout> [branch]
# Emits local SHA, remote SHA, and classification separated by |. SHA fields
# are empty if unavailable. If the remote SHA is absent from the canonical
# checkout, objects are fetched into a disposable bare repository which uses
# the canonical object store read-only as an alternate. This preserves accurate
# behind/diverged evidence without updating any canonical refs or objects.
validation_registry_freshness_evidence() {
  local checkout="${1:-}" branch="${2:-main}"
  local local_sha="" remote_line="" remote_sha="" relation="unreachable"
  local origin_url="" local_objects="" graph_dir="" graph_git=""

  [[ -n "$checkout" ]] || { printf '||unreachable\n'; return 0; }
  local_sha="$(git -C "$checkout" rev-parse HEAD 2>/dev/null)" || {
    printf '||unreachable\n'
    return 0
  }
  remote_line="$(git -C "$checkout" ls-remote --exit-code origin "refs/heads/${branch}" 2>/dev/null)" || {
    printf '%s||unreachable\n' "$local_sha"
    return 0
  }
  read -r remote_sha _ <<< "$remote_line"
  if [[ "$local_sha" != "$remote_sha" ]]; then
    if git -C "$checkout" merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
      relation="ahead"
    elif git -C "$checkout" merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
      relation="behind"
    elif git -C "$checkout" merge-base "$local_sha" "$remote_sha" >/dev/null 2>&1; then
      relation="diverged"
    else
      # ls-remote proved the ref transport reachable, but its object may not
      # exist locally. Resolve the graph in an isolated object database rather
      # than fetching into the canonical checkout.
      origin_url="$(git -C "$checkout" remote get-url origin 2>/dev/null || true)"
      local_objects="$(git -C "$checkout" rev-parse --git-path objects 2>/dev/null || true)"
      if [[ -n "$origin_url" && -n "$local_objects" ]]; then
        if [[ "$local_objects" != /* ]]; then
          local_objects="$(cd "$checkout" && cd "$(dirname "$local_objects")" && pwd)/$(basename "$local_objects")"
        fi
        graph_dir="$(mktemp -d "${TMPDIR:-/tmp}/grimnir-validation-graph.XXXXXX")" || graph_dir=""
      fi
      if [[ -n "$graph_dir" ]]; then
        graph_git="$graph_dir/repo.git"
        if git init --bare --quiet "$graph_git" &&
           GIT_ALTERNATE_OBJECT_DIRECTORIES="$local_objects" \
             git --git-dir="$graph_git" fetch --quiet --no-tags "$origin_url" \
               "refs/heads/${branch}:refs/evidence/remote"; then
          if GIT_ALTERNATE_OBJECT_DIRECTORIES="$local_objects" \
               git --git-dir="$graph_git" merge-base --is-ancestor "$remote_sha" "$local_sha" 2>/dev/null; then
            relation="ahead"
          elif GIT_ALTERNATE_OBJECT_DIRECTORIES="$local_objects" \
               git --git-dir="$graph_git" merge-base --is-ancestor "$local_sha" "$remote_sha" 2>/dev/null; then
            relation="behind"
          elif GIT_ALTERNATE_OBJECT_DIRECTORIES="$local_objects" \
               git --git-dir="$graph_git" merge-base "$local_sha" "$remote_sha" >/dev/null 2>&1; then
            relation="diverged"
          fi
        fi
        rm -rf -- "$graph_dir"
      fi
    fi
  fi
  printf '%s|%s|%s\n' "$local_sha" "$remote_sha" \
    "$(validation_freshness_classification "$local_sha" "$remote_sha" "$relation")"
}

# validation_evidence_json <scheduled UTC or empty> <observed UTC> <origin>
#   <local SHA or empty> <remote SHA or empty> <classification> <audit error>
#   <latest-result write outcome> <pass> <fail> <warn> <severity>
# The exact schema is intentionally built in one place and contract-tested.
validation_evidence_json() {
  SCHEDULED_AT="${1:-}" OBSERVED_AT="${2:-}" ORIGIN="${3:-}" \
  LOCAL_SHA="${4:-}" REMOTE_SHA="${5:-}" CLASSIFICATION="${6:-}" \
  AUDIT_ERROR_VALUE="${7:-}" LATEST_WRITE="${8:-failed}" PASS_COUNT="${9:-0}" \
  FAIL_COUNT="${10:-0}" WARN_COUNT="${11:-0}" SEVERITY_VALUE="${12:-unknown}" \
  node --input-type=commonjs -e '
    function nullable(value) { return value ? value : null; }
    var origin = process.env.ORIGIN;
    var classification = process.env.CLASSIFICATION;
    var allowedOrigin = ["timer", "manual"];
    var allowedClassification = ["current", "ahead", "behind", "diverged", "unreachable"];
    var allowedSeverity = ["clean", "warnings", "issues"];
    var utc = /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/;
    if (allowedOrigin.indexOf(origin) === -1 ||
        allowedClassification.indexOf(classification) === -1 ||
        allowedSeverity.indexOf(process.env.SEVERITY_VALUE) === -1 ||
        ["succeeded", "failed"].indexOf(process.env.LATEST_WRITE) === -1 ||
        !/^\d+$/.test(process.env.PASS_COUNT) || !/^\d+$/.test(process.env.FAIL_COUNT) ||
        !/^\d+$/.test(process.env.WARN_COUNT) ||
        (origin === "timer" && !utc.test(process.env.SCHEDULED_AT)) ||
        (origin === "manual" && process.env.SCHEDULED_AT) || !utc.test(process.env.OBSERVED_AT)) process.exit(1);
    console.log(JSON.stringify({
      schema_version: "validation-run-evidence/v1",
      kind: "registry-validation-run",
      scheduled_at_utc: nullable(process.env.SCHEDULED_AT),
      observed_at_utc: process.env.OBSERVED_AT,
      trigger_origin: origin,
      registry_main: {
        local_sha: nullable(process.env.LOCAL_SHA),
        remote_sha: nullable(process.env.REMOTE_SHA),
        classification: classification
      },
      audit: { completed: !process.env.AUDIT_ERROR_VALUE, error: nullable(process.env.AUDIT_ERROR_VALUE) },
      reporting: { latest_result_write: process.env.LATEST_WRITE, immutable_log: "accepted-on-success" },
      findings: {
        passed: Number(process.env.PASS_COUNT), failed: Number(process.env.FAIL_COUNT),
        warnings: Number(process.env.WARN_COUNT), severity: process.env.SEVERITY_VALUE
      }
    }));
  '
}

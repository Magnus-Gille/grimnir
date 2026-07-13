#!/usr/bin/env bash
# security-scan.sh — Scan Grimnir service repos for dependency vulnerabilities and secrets
#
# Usage:
#   ./scripts/security-scan.sh [--munin-token TOKEN] [--dry-run] [--verbose] [--repo <name>]
#
# Checks:
#   Phase 1: npm audit --json for each repo with package-lock.json
#   Phase 2: Secret regex scan on all git-tracked files
#
# Writes results to Munin unless --dry-run; a live run without durable writes fails.
# Always prints a human-readable summary to stdout.
#
# NEVER outputs actual secret values — only file:line:pattern-category.
# Compatible with bash 3.2+ (macOS default).

set -euo pipefail

SCANNER_VERSION="1.3.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GRIMNIR_DIR="$(dirname "$SCRIPT_DIR")"
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"

# ─── Source shared helpers ─────────────────────────────────────
# shellcheck source=scripts/lib/notify.sh
# shellcheck disable=SC1091  # dynamic path; use shellcheck -x to follow
source "$SCRIPT_DIR/lib/notify.sh"
# shellcheck source=scripts/lib/munin-rpc.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/munin-rpc.sh"
TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
SCAN_DATE="$(date -u '+%Y-%m-%d')"
HOSTNAME_VAL="$(hostname)"

# Read scannable components from the service registry (single source of truth)
REGISTRY="${REGISTRY_PATH:-$GRIMNIR_DIR/services.json}"
REGISTRY_JS="$SCRIPT_DIR/lib/registry.js"
COMPONENTS="$(REGISTRY_PATH="$REGISTRY" QUERY=scan node --input-type=commonjs "$REGISTRY_JS")"
if [[ -z "$COMPONENTS" ]]; then
  echo "ERROR: No scannable components found in $REGISTRY" >&2
  exit 1
fi

# ─── CLI args ────────────────────────────────────────────────
MUNIN_TOKEN=""
DRY_RUN=false
VERBOSE=false
FILTER_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --munin-token) MUNIN_TOKEN="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --verbose)     VERBOSE=true; shift ;;
    --repo)        FILTER_REPO="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "$*" >&2
  fi
}

# scan_escalated lives in lib/escalation.sh (shared with the delta unit test).
# shellcheck source=scripts/lib/escalation.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/escalation.sh"

# Node.js 25+ strips TypeScript by default, misparses object literals
# in -e scripts. --input-type=commonjs fixes it. Also, complex node
# invocations inside $() suffer bash quoting issues — use heredoc-to-stdin
# for multi-line code blocks instead.


# ─── Find Munin bearer token ─────────────────────────────────
if [[ -z "$MUNIN_TOKEN" ]]; then
  for envfile in "$REPOS_DIR/hugin/.env" "$REPOS_DIR/ratatoskr/.env" "$REPOS_DIR/heimdall/.env"; do
    if [[ -f "$envfile" ]]; then
      val="$(grep -E '^MUNIN_API_KEY=' "$envfile" 2>/dev/null | head -1 | cut -d= -f2-)" || true
      if [[ -n "$val" ]]; then
        MUNIN_TOKEN="$val"
        log_verbose "Found Munin token in $envfile"
        break
      fi
    fi
  done
fi

# ─── Munin helpers ───────────────────────────────────────────

munin_call() {
  local payload="$1"
  if [[ -z "$MUNIN_TOKEN" ]]; then
    echo "(Munin token not available)"
    return 1
  fi
  munin_http_jsonrpc "$MUNIN_TOKEN" "$payload"
}

munin_tool_call() {
  local tool_name="$1" args_json="$2"
  local payload
  payload=$(TOOL_NAME="$tool_name" ARGS_JSON="$args_json" node --input-type=commonjs -e '
    console.log(JSON.stringify({
      jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: process.env.TOOL_NAME, arguments: JSON.parse(process.env.ARGS_JSON) }
    }))
  ')
  munin_call "$payload"
}

# ─── Temp directory for per-repo results ─────────────────────
# Used to store per-repo data without requiring bash 4 associative arrays
SCAN_TMP="$(mktemp -d)"
trap 'rm -rf "$SCAN_TMP"' EXIT

repo_set() {
  # repo_set <repo> <key> <value>
  local safe_repo
  safe_repo="$(echo "$1" | tr '-' '_')"
  printf '%s' "$3" > "$SCAN_TMP/${safe_repo}__${2}"
}

repo_get() {
  # repo_get <repo> <key>  (prints value, empty string if not set)
  local safe_repo
  safe_repo="$(echo "$1" | tr '-' '_')"
  local f="$SCAN_TMP/${safe_repo}__${2}"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo ""
  fi
}

# ─── Build component list ─────────────────────────────────────
if [[ -n "$FILTER_REPO" ]]; then
  case " $COMPONENTS " in
    *" $FILTER_REPO "*) ;;
    *)
      echo "ERROR: --repo must name a scan-enabled component from services.json: $FILTER_REPO" >&2
      exit 1
      ;;
  esac
  SCAN_COMPONENTS="$FILTER_REPO"
else
  SCAN_COMPONENTS="$COMPONENTS"
fi

TOTAL_CRITICAL=0
TOTAL_HIGH=0
TOTAL_MODERATE=0
TOTAL_LOW=0
TOTAL_SECRETS=0

echo ""
echo "Grimnir Security Scan v${SCANNER_VERSION}"
echo "Timestamp: $TIMESTAMP"
echo "Host:      $HOSTNAME_VAL"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Mode:      DRY RUN (no Munin writes)"
else
  echo "Mode:      LIVE"
fi
echo ""

# ─── Phase 1: npm audit ──────────────────────────────────────

echo "Phase 1: Dependency audit (npm audit)"
echo "--------------------------------------"

for repo in $SCAN_COMPONENTS; do
  dir="$REPOS_DIR/$repo"

  # Collect git provenance
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_set "$repo" "commit" "$(git -C "$dir" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    repo_set "$repo" "branch" "$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
  else
    repo_set "$repo" "commit" "n/a"
    repo_set "$repo" "branch" "n/a"
  fi

  if [[ ! -d "$dir" ]]; then
    log_verbose "  $repo: directory not found at $dir"
    repo_set "$repo" "audit_status" "skipped:no-dir"
    repo_set "$repo" "audit_critical" "0"
    repo_set "$repo" "audit_high" "0"
    repo_set "$repo" "audit_moderate" "0"
    repo_set "$repo" "audit_low" "0"
    repo_set "$repo" "audit_total" "0"
    repo_set "$repo" "audit_json" "null"
    continue
  fi

  if [[ ! -f "$dir/package-lock.json" ]]; then
    log_verbose "  $repo: no package-lock.json, skipping npm audit"
    repo_set "$repo" "audit_status" "skipped:no-lockfile"
    repo_set "$repo" "audit_critical" "0"
    repo_set "$repo" "audit_high" "0"
    repo_set "$repo" "audit_moderate" "0"
    repo_set "$repo" "audit_low" "0"
    repo_set "$repo" "audit_total" "0"
    repo_set "$repo" "audit_json" "null"
    continue
  fi

  log_verbose "  $repo: running npm audit..."
  # npm audit exits 1 when vulnerabilities found — capture output regardless
  audit_raw="$(cd "$dir" && npm audit --json 2>/dev/null)" || true

  if [[ -z "$audit_raw" ]]; then
    repo_set "$repo" "audit_status" "error:no-output"
    repo_set "$repo" "audit_critical" "0"
    repo_set "$repo" "audit_high" "0"
    repo_set "$repo" "audit_moderate" "0"
    repo_set "$repo" "audit_low" "0"
    repo_set "$repo" "audit_total" "0"
    repo_set "$repo" "audit_json" "null"
    echo "  $repo: ERROR (no output from npm audit)"
    continue
  fi

  # Parse npm audit JSON: validate, extract severities, collect package names
  # Single node call writes individual results to temp files (avoids $() quoting issues)
  rm -f "$SCAN_TMP/_a_ok" "$SCAN_TMP/_a_error" "$SCAN_TMP/_a_crit" \
    "$SCAN_TMP/_a_high" "$SCAN_TMP/_a_mod" "$SCAN_TMP/_a_low" \
    "$SCAN_TMP/_a_total" "$SCAN_TMP/_a_json"
  printf '%s' "$audit_raw" > "$SCAN_TMP/_audit_raw"
  OUTDIR="$SCAN_TMP" node --input-type=commonjs -e '
    var fs = require("fs");
    var out = process.env.OUTDIR;
    try {
      var d = JSON.parse(fs.readFileSync(out + "/_audit_raw", "utf8"));
      if (!d || typeof d !== "object" || d.error) throw new Error("npm-error-response");
      var v = d.metadata && d.metadata.vulnerabilities;
      if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error("missing-vulnerability-metadata");
      function count(name) {
        var value = v[name];
        if (!Number.isInteger(value) || value < 0) throw new Error("invalid-" + name + "-count");
        return value;
      }
      var c = count("critical"), h = count("high"), m = count("moderate"), l = count("low");
      if (!d.vulnerabilities || typeof d.vulnerabilities !== "object" || Array.isArray(d.vulnerabilities)) {
        throw new Error("missing-vulnerability-details");
      }
      fs.writeFileSync(out + "/_a_ok", "true");
      fs.writeFileSync(out + "/_a_crit", String(c));
      fs.writeFileSync(out + "/_a_high", String(h));
      fs.writeFileSync(out + "/_a_mod", String(m));
      fs.writeFileSync(out + "/_a_low", String(l));
      fs.writeFileSync(out + "/_a_total", String(c + h + m + l));
      var vulns = d.vulnerabilities;
      var pkgs = Object.entries(vulns).map(function(e) { return {name: e[0], severity: e[1].severity}; });
      var json = {critical: c, high: h, moderate: m, low: l, total: c+h+m+l, packages: pkgs};
      fs.writeFileSync(out + "/_a_json", JSON.stringify(json));
    } catch(e) {
      fs.writeFileSync(out + "/_a_ok", "false");
      fs.writeFileSync(out + "/_a_error", String(e && e.message || "invalid-audit-json"));
    }
  ' 2>/dev/null

  if [[ "$(cat "$SCAN_TMP/_a_ok" 2>/dev/null)" != "true" ]]; then
    audit_error="$(cat "$SCAN_TMP/_a_error" 2>/dev/null || echo invalid-json)"
    repo_set "$repo" "audit_status" "error:${audit_error}"
    repo_set "$repo" "audit_critical" "0"
    repo_set "$repo" "audit_high" "0"
    repo_set "$repo" "audit_moderate" "0"
    repo_set "$repo" "audit_low" "0"
    repo_set "$repo" "audit_total" "0"
    repo_set "$repo" "audit_json" "null"
    echo "  $repo: ERROR (unusable npm audit result: ${audit_error})"
    continue
  fi

  crit="$(cat "$SCAN_TMP/_a_crit")"
  high="$(cat "$SCAN_TMP/_a_high")"
  mod="$(cat "$SCAN_TMP/_a_mod")"
  low="$(cat "$SCAN_TMP/_a_low")"
  total="$(cat "$SCAN_TMP/_a_total")"

  repo_set "$repo" "audit_critical" "$crit"
  repo_set "$repo" "audit_high" "$high"
  repo_set "$repo" "audit_moderate" "$mod"
  repo_set "$repo" "audit_low" "$low"
  repo_set "$repo" "audit_total" "$total"

  TOTAL_CRITICAL=$((TOTAL_CRITICAL + crit))
  TOTAL_HIGH=$((TOTAL_HIGH + high))
  TOTAL_MODERATE=$((TOTAL_MODERATE + mod))
  TOTAL_LOW=$((TOTAL_LOW + low))

  if [[ "$total" -eq 0 ]]; then
    repo_set "$repo" "audit_status" "ok"
    echo "  $repo: OK (no vulnerabilities)"
  else
    repo_set "$repo" "audit_status" "vulns"
    echo "  $repo: VULNERABILITIES FOUND — critical:$crit high:$high moderate:$mod low:$low"
  fi

  repo_set "$repo" "audit_json" "$(cat "$SCAN_TMP/_a_json")"
done

echo ""

# ─── Phase 2: Secret scan ────────────────────────────────────

echo "Phase 2: Secret scan"
echo "--------------------"

# Secret patterns: tab-separated "regex<TAB>category" entries
# NOTE: sk-ant- must come before sk- so the more specific pattern matches first
SECRET_PATTERNS_FILE="$SCAN_TMP/patterns.txt"
cat > "$SECRET_PATTERNS_FILE" << 'PATTERNS'
Bearer [A-Za-z0-9_/+=-]{20,}	bearer-token
eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}	jwt
sk-ant-[a-zA-Z0-9_-]{20,}	anthropic-key
sk-[a-zA-Z0-9]{20,}	openai-key
ghp_[a-zA-Z0-9]{36}	github-pat
gho_[a-zA-Z0-9]{36}	github-oauth
glpat-[a-zA-Z0-9_-]{20,}	gitlab-pat
xox[bpas]-[A-Za-z0-9-]{10,}	slack-token
AKIA[A-Z0-9]{16}	aws-access-key
npm_[a-zA-Z0-9]{36}	npm-token
[0-9]{8,10}:[A-Za-z0-9_-]{35}	telegram-bot-token
PATTERNS

# Allowlist: lines matching these are NOT flagged
ALLOWLIST_PATTERN='\*\*\*|<TOKEN>|<key>|example|EXAMPLE|sample|your[-_]|YOUR_'

for repo in $SCAN_COMPONENTS; do
  dir="$REPOS_DIR/$repo"

  if [[ ! -d "$dir" ]]; then
    repo_set "$repo" "secret_status" "skipped:no-dir"
    repo_set "$repo" "secret_count" "0"
    repo_set "$repo" "secret_findings" "[]"
    continue
  fi

  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log_verbose "  $repo: not a git repo, skipping secret scan"
    repo_set "$repo" "secret_status" "skipped:no-git"
    repo_set "$repo" "secret_count" "0"
    repo_set "$repo" "secret_findings" "[]"
    continue
  fi

  log_verbose "  $repo: scanning tracked files for secrets..."

  findings_tsv=""   # accumulates: repo<TAB>file<TAB>line<TAB>category, one per line
  finding_count=0

  # Get list of tracked files
  if ! tracked_files="$(git -C "$dir" ls-files 2>/dev/null)"; then
    repo_set "$repo" "secret_status" "error:git-ls-files"
    repo_set "$repo" "secret_count" "0"
    repo_set "$repo" "secret_findings" "[]"
    echo "  $repo: ERROR (could not enumerate tracked files)"
    continue
  fi

  if [[ -z "$tracked_files" ]]; then
    repo_set "$repo" "secret_status" "ok"
    repo_set "$repo" "secret_count" "0"
    repo_set "$repo" "secret_findings" "[]"
    echo "  $repo: OK (no tracked files)"
    continue
  fi

  while IFS= read -r relfile; do
    absfile="$dir/$relfile"
    [[ -f "$absfile" ]] || continue

    # Skip .env.example files
    basename_file="$(basename "$relfile")"
    if [[ "$relfile" == *".env.example"* ]] || [[ "$basename_file" == ".env.example" ]]; then
      log_verbose "    Skipping .env.example: $relfile"
      continue
    fi

    # Skip test and evaluation fixture files. These directories intentionally
    # embed realistic-looking patterns (e.g. sk-ant-... in
    # tests/sensitivity.test.ts, synthetic PII in eval/privacy-filter/fixtures/)
    # to verify the sensitivity / exfiltration scanners.  Real secrets should
    # never live in tests or eval fixtures — use env vars or placeholder values.
    #
    # NOTE: In bash `case`, `*` matches any string INCLUDING `/`, so
    # `tests/*` correctly skips nested paths like
    # tests/broker/openrouter-executor.test.ts.
    # eval/: only skip fixture subdirectories (eval/fixtures/*, eval/*/fixtures/*),
    # NOT entire eval/ trees — runner scripts or configs under eval/ are still scanned.
    case "$relfile" in
      tests/*|test/*|*/tests/*|*/test/*|\
      __tests__/*|*/__tests__/*|*/__mocks__/*|\
      eval/fixtures/*|eval/*/fixtures/*|*/eval/fixtures/*|*/eval/*/fixtures/*|\
      *.test.ts|*.test.tsx|*.test.js|*.test.jsx|*.test.mjs|*.test.cjs|\
      *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx|*.spec.mjs|*.spec.cjs|\
      *_test.py|*_test.go)
        log_verbose "    Skipping test/fixture file: $relfile"
        continue
        ;;
    esac

    # Skip by extension (fast path)
    case "$relfile" in
      *.png|*.jpg|*.jpeg|*.gif|*.ico|*.woff|*.woff2|*.ttf|*.eot|\
      *.zip|*.tar|*.gz|*.bz2|*.xz|*.7z|*.rar|\
      *.pdf|*.doc|*.docx|*.xls|*.xlsx|\
      *.min.js|*.map)
        log_verbose "    Skipping by extension: $relfile"
        continue
        ;;
    esac

    # Skip true binary files by checking for NUL bytes in first 512 bytes
    # This correctly handles .sh, .ts, .json, and other text files that
    # the `file` command may label ambiguously (e.g., "JSON data" has no "text")
    if LC_ALL=C grep -qP '\x00' "$absfile" 2>/dev/null; then
      log_verbose "    Skipping binary (NUL bytes): $relfile"
      continue
    fi

    # Scan against each pattern
    while IFS='	' read -r pattern category; do
      [[ -z "$pattern" ]] && continue

      # grep exits 1 on no match — suppress with || true
      matched_lines="$(grep -nE "$pattern" "$absfile" 2>/dev/null)" || true
      [[ -z "$matched_lines" ]] && continue

      # Filter allowlist
      real_matches="$(echo "$matched_lines" | grep -vE "$ALLOWLIST_PATTERN" 2>/dev/null)" || true
      [[ -z "$real_matches" ]] && continue

      # Record file:line:category ONLY — never the actual secret value
      # Accumulate as TSV; convert to JSON array in one node call after loops
      while IFS= read -r match_line; do
        line_num="$(echo "$match_line" | cut -d: -f1)"
        finding_count=$((finding_count + 1))
        if [[ -z "$findings_tsv" ]]; then
          findings_tsv="${repo}	${relfile}	${line_num}	${category}"
        else
          findings_tsv="${findings_tsv}
${repo}	${relfile}	${line_num}	${category}"
        fi
      done <<< "$real_matches"
    done < "$SECRET_PATTERNS_FILE"
  done <<< "$tracked_files"

  repo_set "$repo" "secret_count" "$finding_count"
  # Convert accumulated TSV findings to JSON array in a single node call
  findings_json=""
  if [[ -z "$findings_tsv" ]]; then
    findings_json="[]"
  else
    findings_json="$(printf '%s' "$findings_tsv" | OUTDIR="$SCAN_TMP" node --input-type=commonjs -e '
      var lines = require("fs").readFileSync("/dev/stdin", "utf8").split("\n").filter(Boolean);
      var arr = lines.map(function(l) {
        var p = l.split("\t");
        return { repo: p[0], file: p[1], line: parseInt(p[2]) || 0, category: p[3] };
      });
      process.stdout.write(JSON.stringify(arr));
    ')"
  fi

  repo_set "$repo" "secret_findings" "$findings_json"
  TOTAL_SECRETS=$((TOTAL_SECRETS + finding_count))

  if [[ "$finding_count" -eq 0 ]]; then
    repo_set "$repo" "secret_status" "ok"
    echo "  $repo: OK (no secrets found)"
  else
    repo_set "$repo" "secret_status" "found"
    echo "  $repo: SECRETS FOUND — $finding_count potential secret(s)"
    if [[ "$VERBOSE" == "true" ]]; then
      printf '%s' "$findings_json" | node --input-type=commonjs -e '
        var d=JSON.parse(require("fs").readFileSync("/dev/stdin","utf8"));
        d.forEach(function(f) { console.log("    [" + f.category + "] " + f.file + ":" + f.line); });
      ' 2>/dev/null || true
    fi
  fi
done

echo ""

# ─── Summary table ────────────────────────────────────────────

echo "Summary"
echo "======="
echo ""
printf "%-20s %-18s %-6s %-6s %-6s %-6s %-9s %-14s\n" \
  "Repo" "Audit" "Crit" "High" "Mod" "Low" "Secrets" "Branch"
printf "%-20s %-18s %-6s %-6s %-6s %-6s %-9s %-14s\n" \
  "----" "-----" "----" "----" "---" "---" "-------" "------"

for repo in $SCAN_COMPONENTS; do
  audit_status="$(repo_get "$repo" audit_status)"
  [[ -z "$audit_status" ]] && audit_status="skipped"
  crit="$(repo_get "$repo" audit_critical)"; [[ -z "$crit" ]] && crit=0
  high="$(repo_get "$repo" audit_high)"; [[ -z "$high" ]] && high=0
  mod="$(repo_get "$repo" audit_moderate)"; [[ -z "$mod" ]] && mod=0
  low="$(repo_get "$repo" audit_low)"; [[ -z "$low" ]] && low=0
  secrets="$(repo_get "$repo" secret_count)"; [[ -z "$secrets" ]] && secrets=0
  branch="$(repo_get "$repo" branch)"; [[ -z "$branch" ]] && branch="n/a"

  printf "%-20s %-18s %-6s %-6s %-6s %-6s %-9s %-14s\n" \
    "$repo" "$audit_status" "$crit" "$high" "$mod" "$low" "$secrets" "$branch"
done

echo ""
printf "TOTALS: critical=%d  high=%d  moderate=%d  low=%d  secrets=%d\n" \
  "$TOTAL_CRITICAL" "$TOTAL_HIGH" "$TOTAL_MODERATE" "$TOTAL_LOW" "$TOTAL_SECRETS"

TOTAL_INCOMPLETE=0
INCOMPLETE_REPOS=""
for repo in $SCAN_COMPONENTS; do
  audit_status="$(repo_get "$repo" audit_status)"
  secret_status="$(repo_get "$repo" secret_status)"
  repo_incomplete=false
  case "$audit_status" in
    ok|vulns|skipped:no-lockfile) ;;
    *) repo_incomplete=true ;;
  esac
  case "$secret_status" in
    ok|found) ;;
    *) repo_incomplete=true ;;
  esac
  if [[ "$repo_incomplete" == "true" ]]; then
    TOTAL_INCOMPLETE=$((TOTAL_INCOMPLETE + 1))
    INCOMPLETE_REPOS="${INCOMPLETE_REPOS}${INCOMPLETE_REPOS:+ }${repo}"
  fi
done
if [[ "$TOTAL_INCOMPLETE" -eq 0 ]]; then
  SCAN_COMPLETE=true
else
  SCAN_COMPLETE=false
fi
printf "COVERAGE: complete=%s  incomplete_repos=%d%s\n" \
  "$SCAN_COMPLETE" "$TOTAL_INCOMPLETE" "${INCOMPLETE_REPOS:+ ($INCOMPLETE_REPOS)}"
echo ""

# ─── Overall status assessment ────────────────────────────────

FINDING_STATUS="clean"
if [[ "$TOTAL_CRITICAL" -gt 0 ]] || [[ "$TOTAL_SECRETS" -gt 0 ]]; then
  FINDING_STATUS="critical"
elif [[ "$TOTAL_HIGH" -gt 0 ]]; then
  FINDING_STATUS="high"
elif [[ "$TOTAL_MODERATE" -gt 0 ]]; then
  FINDING_STATUS="moderate"
elif [[ "$TOTAL_LOW" -gt 0 ]]; then
  FINDING_STATUS="low"
fi
OVERALL_STATUS="$FINDING_STATUS"
if [[ "$SCAN_COMPLETE" != "true" ]]; then
  OVERALL_STATUS="incomplete"
fi

echo "Overall status: $OVERALL_STATUS"
echo "Finding status: $FINDING_STATUS"
echo ""

# ─── Delta computation (escalation detection) ─────────────────
# For each repo: read the previous scan from Munin (if available and not dry-run),
# compare critical/high/secret counts, and track any repo that escalated.
# In dry-run mode, prev counts are treated as 0 (simulates first run).

ESCALATED_REPOS=""
ESCALATION_MSG_LINES=""

for repo in $SCAN_COMPONENTS; do
  cur_c="$(repo_get "$repo" audit_critical)"; [[ -z "$cur_c" ]] && cur_c=0
  cur_h="$(repo_get "$repo" audit_high)";    [[ -z "$cur_h" ]] && cur_h=0
  cur_s="$(repo_get "$repo" secret_count)";  [[ -z "$cur_s" ]] && cur_s=0

  prev_c=0; prev_h=0; prev_s=0
  # baseline_ok = we have a trustworthy previous snapshot to diff against. A
  # read failure / missing token / poisoned record must NOT look like a "0 0 0"
  # baseline — otherwise every existing finding reads as newly-escalated and the
  # alert fires (falsely) on every run. Only an "ok" parse enables alerting.
  baseline_ok=false

  if [[ "$DRY_RUN" == "true" ]]; then
    # Dry-run has no Munin read; simulate a first-run baseline so the smoke test
    # can demonstrate what an alert would look like.
    baseline_ok=true
  elif [[ -n "$MUNIN_TOKEN" ]]; then
    # `|| printf '{}'` keeps a node failure from aborting the whole scan under
    # set -e (this runs before the alert + Munin writes). The '{}' sentinel
    # parses to status=unavailable → no false escalation.
    read_args="$(REPO_NS="security/repos/${repo}" node --input-type=commonjs -e \
      'console.log(JSON.stringify({namespace: process.env.REPO_NS, key: "latest"}))' \
      2>/dev/null || printf '%s' '{}')"
    prev_raw="$(munin_tool_call "memory_read" "$read_args" 2>/dev/null || printf '%s' '{}')"
    # parse_prev_counts (lib/escalation.sh) emits "crit<TAB>high<TAB>secrets<TAB>status"
    # with strict integer/array validation. Tab-separated; read via IFS.
    prev_parsed="$(printf '%s' "$prev_raw" | parse_prev_counts)"
    IFS=$'\t' read -r prev_c prev_h prev_s baseline_status <<< "$prev_parsed"
    prev_c="${prev_c:-0}"; prev_h="${prev_h:-0}"; prev_s="${prev_s:-0}"
    [[ "${baseline_status:-unavailable}" == "ok" ]] && baseline_ok=true
  fi

  # Defense-in-depth for the delta_desc comparisons below (which use prev_*
  # directly): canonicalize to base-10 ints, mirroring scan_escalated.
  [[ "$prev_c" =~ ^[0-9]{1,9}$ ]] && prev_c=$((10#$prev_c)) || prev_c=0
  [[ "$prev_h" =~ ^[0-9]{1,9}$ ]] && prev_h=$((10#$prev_h)) || prev_h=0
  [[ "$prev_s" =~ ^[0-9]{1,9}$ ]] && prev_s=$((10#$prev_s)) || prev_s=0

  if [[ "$baseline_ok" != "true" ]]; then
    log_verbose "  $repo: previous baseline unavailable — skipping delta alert"
  elif [[ "$(scan_escalated "$prev_c" "$prev_h" "$prev_s" "$cur_c" "$cur_h" "$cur_s")" == "yes" ]]; then
    delta_desc=""
    [[ "$cur_c" -gt "$prev_c" ]] && delta_desc="${delta_desc} critical:${prev_c}->${cur_c}"
    [[ "$cur_h" -gt "$prev_h" ]] && delta_desc="${delta_desc} high:${prev_h}->${cur_h}"
    [[ "$cur_s" -gt "$prev_s" ]] && delta_desc="${delta_desc} secrets:${prev_s}->${cur_s}"
    delta_desc="${delta_desc# }"  # trim leading space
    if [[ -z "$ESCALATED_REPOS" ]]; then
      ESCALATED_REPOS="$repo"
      ESCALATION_MSG_LINES="  - ${repo}: ${delta_desc}"
    else
      ESCALATED_REPOS="${ESCALATED_REPOS} ${repo}"
      ESCALATION_MSG_LINES="${ESCALATION_MSG_LINES}
  - ${repo}: ${delta_desc}"
    fi
  fi
done

# ─── Telegram alert — high/critical status + at least one escalation ──────
# Stays silent when overall is clean/low/moderate, or when nothing escalated.

if [[ "$FINDING_STATUS" == "high" ]] || [[ "$FINDING_STATUS" == "critical" ]]; then
  if [[ -n "$ESCALATED_REPOS" ]]; then
    OVERALL_UPPER="$(echo "$FINDING_STATUS" | tr '[:lower:]' '[:upper:]')"
    ALERT_MSG="[Grimnir security] ${OVERALL_UPPER} — escalated findings (${SCAN_DATE}):
${ESCALATION_MSG_LINES}"
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] telegram: ${ALERT_MSG}"
    else
      notify_telegram "$ALERT_MSG"
    fi
  fi
fi

# ─── Munin writes ─────────────────────────────────────────────

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(Dry run — skipping Munin writes)"
  echo ""
  [[ "$SCAN_COMPLETE" == "true" ]] || exit 1
  exit 0
fi

if [[ -z "$MUNIN_TOKEN" ]]; then
  echo "ERROR: No Munin token — scan result is not durable" >&2
  echo ""
  exit 1
fi

echo "Writing to Munin..."
WRITE_FAILURES=0

# Build per-repo JSON and aggregate into full scan JSON
# Each repo object is written as one line to a temp file; assembled into array at end
REPO_OBJS_FILE="$SCAN_TMP/repo_objs.ndjson"
: > "$REPO_OBJS_FILE"
for repo in $SCAN_COMPONENTS; do
  audit_data="$(repo_get "$repo" audit_json)"; [[ -z "$audit_data" ]] && audit_data="null"
  secret_findings="$(repo_get "$repo" secret_findings)"; [[ -z "$secret_findings" ]] && secret_findings="[]"
  audit_st="$(repo_get "$repo" audit_status)"; [[ -z "$audit_st" ]] && audit_st="skipped"
  secret_st="$(repo_get "$repo" secret_status)"; [[ -z "$secret_st" ]] && secret_st="skipped"
  commit="$(repo_get "$repo" commit)"; [[ -z "$commit" ]] && commit="unknown"
  branch="$(repo_get "$repo" branch)"; [[ -z "$branch" ]] && branch="unknown"

  printf '%s' "$audit_data"     > "$SCAN_TMP/_ro_audit"
  printf '%s' "$secret_findings" > "$SCAN_TMP/_ro_secrets"
  REPO_VAL="$repo" AUDIT_ST="$audit_st" SECRET_ST="$secret_st" \
    COMMIT_VAL="$commit" BRANCH_VAL="$branch" OUTDIR="$SCAN_TMP" \
    node --input-type=commonjs -e '
      var fs = require("fs"), out = process.env.OUTDIR;
      var audit   = JSON.parse(fs.readFileSync(out + "/_ro_audit",   "utf8") || "null");
      var secrets = JSON.parse(fs.readFileSync(out + "/_ro_secrets", "utf8") || "[]");
      process.stdout.write(JSON.stringify({
        repo:          process.env.REPO_VAL,
        audit_status:  process.env.AUDIT_ST,
        secret_status: process.env.SECRET_ST,
        commit:        process.env.COMMIT_VAL,
        branch:        process.env.BRANCH_VAL,
        audit:         audit,
        secrets:       secrets
      }) + "\n");
    ' >> "$REPO_OBJS_FILE"
done

# Assemble array from NDJSON file and build full scan summary — one node call
OUTDIR="$SCAN_TMP" SCAN_DATE="$SCAN_DATE" TIMESTAMP="$TIMESTAMP" HOST="$HOSTNAME_VAL" \
  TOTAL_C="$TOTAL_CRITICAL" TOTAL_H="$TOTAL_HIGH" TOTAL_M="$TOTAL_MODERATE" \
  TOTAL_L="$TOTAL_LOW" TOTAL_S="$TOTAL_SECRETS" OVERALL="$OVERALL_STATUS" \
  FINDING_STATUS="$FINDING_STATUS" SCAN_COMPLETE="$SCAN_COMPLETE" \
  INCOMPLETE_REPOS="$INCOMPLETE_REPOS" \
  SCANNER_VER="$SCANNER_VERSION" \
  node --input-type=commonjs -e '
    var fs = require("fs"), out = process.env.OUTDIR;
    var lines = fs.readFileSync(out + "/repo_objs.ndjson", "utf8").split("\n").filter(Boolean);
    var repos = lines.map(function(l) { return JSON.parse(l); });
    var summary = JSON.stringify({
      scan_date:       process.env.SCAN_DATE,
      timestamp:       process.env.TIMESTAMP,
      host:            process.env.HOST,
      scanner_version: process.env.SCANNER_VER,
      overall_status:  process.env.OVERALL,
      finding_status:  process.env.FINDING_STATUS,
      scan_complete:   process.env.SCAN_COMPLETE === "true",
      incomplete_repos: process.env.INCOMPLETE_REPOS ? process.env.INCOMPLETE_REPOS.split(" ") : [],
      totals: {
        critical: parseInt(process.env.TOTAL_C),
        high:     parseInt(process.env.TOTAL_H),
        moderate: parseInt(process.env.TOTAL_M),
        low:      parseInt(process.env.TOTAL_L),
        secrets:  parseInt(process.env.TOTAL_S)
      },
      repos: repos
    });
    fs.writeFileSync(out + "/_scan_summary_json", summary);
    fs.writeFileSync(out + "/_all_repos_json", JSON.stringify(repos));
  '
scan_summary_json="$(cat "$SCAN_TMP/_scan_summary_json")"

# Write 1: Full scan summary
echo "  Writing scan summary to security/scans/${SCAN_DATE}..."
summary_content="## Security Scan Summary

Scan date: ${SCAN_DATE}
Host: ${HOSTNAME_VAL}
Scanner version: ${SCANNER_VERSION}
Overall status: **${OVERALL_STATUS}**
Finding status: **${FINDING_STATUS}**
Scan complete: **${SCAN_COMPLETE}**
Incomplete repositories: ${INCOMPLETE_REPOS:-none}

### Totals

| Severity | Count |
|----------|-------|
| Critical | ${TOTAL_CRITICAL} |
| High | ${TOTAL_HIGH} |
| Moderate | ${TOTAL_MODERATE} |
| Low | ${TOTAL_LOW} |
| Secrets | ${TOTAL_SECRETS} |

### Raw JSON

\`\`\`json
${scan_summary_json}
\`\`\`"

summary_args="$(NAMESPACE_VAL="security/scans/${SCAN_DATE}" KEY_VAL="summary" \
  CONTENT_VAL="$summary_content" node --input-type=commonjs -e '
    console.log(JSON.stringify({
      namespace: process.env.NAMESPACE_VAL,
      key: process.env.KEY_VAL,
      content: process.env.CONTENT_VAL,
      tags: ["security", "scan", "automated"]
    }))
')"
if ! munin_tool_call "memory_write" "$summary_args" > /dev/null; then
  echo "  WARNING: Failed to write scan summary to Munin"
  WRITE_FAILURES=$((WRITE_FAILURES + 1))
fi

# Write 2: Per-repo latest state
for repo in $SCAN_COMPONENTS; do
  audit_st="$(repo_get "$repo" audit_status)"
  [[ "$audit_st" == "skipped:no-dir" ]] && continue

  audit_data="$(repo_get "$repo" audit_json)"; [[ -z "$audit_data" ]] && audit_data="null"
  secret_findings="$(repo_get "$repo" secret_findings)"; [[ -z "$secret_findings" ]] && secret_findings="[]"
  secret_st="$(repo_get "$repo" secret_status)"; [[ -z "$secret_st" ]] && secret_st="skipped"
  commit="$(repo_get "$repo" commit)"; [[ -z "$commit" ]] && commit="unknown"
  branch="$(repo_get "$repo" branch)"; [[ -z "$branch" ]] && branch="unknown"
  secrets_count="$(repo_get "$repo" secret_count)"; [[ -z "$secrets_count" ]] && secrets_count=0

  printf '%s' "$audit_data"       > "$SCAN_TMP/_rd_audit"
  printf '%s' "$secret_findings"  > "$SCAN_TMP/_rd_secrets"
  repo_detail_json="$(OUTDIR="$SCAN_TMP" node --input-type=commonjs -e '
    var fs = require("fs"), out = process.env.OUTDIR;
    var audit   = JSON.parse(fs.readFileSync(out + "/_rd_audit",   "utf8") || "null");
    var secrets = JSON.parse(fs.readFileSync(out + "/_rd_secrets", "utf8") || "[]");
    process.stdout.write(JSON.stringify({ audit: audit, secrets: secrets }, null, 2));
  ')"

  repo_content="## ${repo} — Security State

Last scan: ${TIMESTAMP}
Commit: ${commit} (${branch})
Audit status: ${audit_st}
Secret scan status: ${secret_st}
Secrets found: ${secrets_count}

\`\`\`json
${repo_detail_json}
\`\`\`"

  log_verbose "  Writing per-repo state for $repo..."
  repo_args="$(NAMESPACE_VAL="security/repos/${repo}" KEY_VAL="latest" \
    CONTENT_VAL="$repo_content" REPO_TAG="$repo" node --input-type=commonjs -e '
      console.log(JSON.stringify({
        namespace: process.env.NAMESPACE_VAL,
        key: process.env.KEY_VAL,
        content: process.env.CONTENT_VAL,
        tags: ["security", "repo", process.env.REPO_TAG]
      }))
  ')"
  if ! munin_tool_call "memory_write" "$repo_args" > /dev/null; then
    echo "  WARNING: Failed to write repo state for $repo"
    WRITE_FAILURES=$((WRITE_FAILURES + 1))
  fi
done

# Write 3: Scan event log
echo "  Logging scan event..."
log_content="Security scan completed at ${TIMESTAMP} on ${HOSTNAME_VAL}. Overall:${OVERALL_STATUS}; findings:${FINDING_STATUS}; complete:${SCAN_COMPLETE}; incomplete_repos:${INCOMPLETE_REPOS:-none}. Totals — critical:${TOTAL_CRITICAL} high:${TOTAL_HIGH} moderate:${TOTAL_MODERATE} low:${TOTAL_LOW} secrets:${TOTAL_SECRETS}. Scanner v${SCANNER_VERSION}."
log_args="$(NAMESPACE_VAL="security/" CONTENT_VAL="$log_content" node --input-type=commonjs -e '
  console.log(JSON.stringify({
    namespace: process.env.NAMESPACE_VAL,
    content: process.env.CONTENT_VAL,
    tags: ["security", "scan-event"]
  }))
')"
if ! munin_tool_call "memory_log" "$log_args" > /dev/null; then
  echo "  WARNING: Failed to write scan event log to Munin"
  WRITE_FAILURES=$((WRITE_FAILURES + 1))
fi

echo "Done."
echo ""
if [[ "$SCAN_COMPLETE" != "true" ]] || [[ "$WRITE_FAILURES" -gt 0 ]]; then
  exit 1
fi

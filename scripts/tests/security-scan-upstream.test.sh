#!/usr/bin/env bash
# GRIM-222: hermetic upstream source-mode coverage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCANNER="$SCRIPT_DIR/../security-scan.sh"
HELPER="$SCRIPT_DIR/../lib/scan-source.js"
REAL_GIT="$(command -v git)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/work"
git -C "$TMP_DIR/work" init -q -b main
git -C "$TMP_DIR/work" config user.email test@example.invalid
git -C "$TMP_DIR/work" config user.name GrimnirTest
printf '%s\n' 'ignored-upstream.txt export-ignore' 'smudge-trigger.txt filter=grimnir-smudge' > "$TMP_DIR/work/.gitattributes"
printf '%s\n' '{"name":"alpha","lockfileVersion":3,"packages":{}}' > "$TMP_DIR/work/package-lock.json"
printf '%s\n' ordinary > "$TMP_DIR/work/ordinary.txt"
printf '%s\n' 'sk-ant-UPSTREAMSCANFIXTURETOKEN1234567890' > "$TMP_DIR/work/ignored-upstream.txt"
printf '%s\n' smudge > "$TMP_DIR/work/smudge-trigger.txt"
git -C "$TMP_DIR/work" add -A
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git -C "$TMP_DIR/work" commit -q -m first
SHA1="$(git -C "$TMP_DIR/work" rev-parse HEAD)"
printf '%s\n' second > "$TMP_DIR/work/ordinary.txt"
git -C "$TMP_DIR/work" add ordinary.txt
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git -C "$TMP_DIR/work" commit -q -m second
SHA2="$(git -C "$TMP_DIR/work" rev-parse HEAD)"
git init -q --bare "$TMP_DIR/fixture.git"
git -C "$TMP_DIR/work" remote add fixture "$TMP_DIR/fixture.git"
git -C "$TMP_DIR/work" push -q fixture main

printf '%s\n' \
'{"repository_authority":{"default_owner":"Magnus-Gille"},"components":[{"name":"alpha","repo":"alpha","scan":true,"deploy":false,"desired_runtime_state":"stopped","systemd_units":[]}]}' \
> "$TMP_DIR/registry.json"
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" audit > /dev/null' 'printf "%s\n" '"'"'{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'"'"'' > "$TMP_DIR/bin/npm"
chmod +x "$TMP_DIR/bin/npm"
# shellcheck disable=SC2016 # The generated fixture script expands its own runtime variables.
printf '%s\n' '#!/usr/bin/env bash' 'if [[ -n "$SMUDGE_MARKER" ]]; then printf "%s\n" smudge > "$SMUDGE_MARKER"; fi' 'cat' > "$TMP_DIR/bin/smudge"
chmod +x "$TMP_DIR/bin/smudge"
# Prove the fixture's tracked filter would execute during a checkout. The
# helper must never perform this checkout or run the resulting smudge command.
git -C "$TMP_DIR/work" config filter.grimnir-smudge.smudge "bash $TMP_DIR/bin/smudge"
rm -f "$TMP_DIR/work/smudge-trigger.txt"
# shellcheck disable=SC2016 # The generated fixture hook expands its own runtime variable.
printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" hook > "$HOOK_MARKER"' > "$TMP_DIR/work/.git/hooks/post-checkout"
chmod +x "$TMP_DIR/work/.git/hooks/post-checkout"
HOOK_MARKER="$TMP_DIR/control-hook" SMUDGE_MARKER="$TMP_DIR/control-smudge" git -C "$TMP_DIR/work" checkout -q -- smudge-trigger.txt
if [[ -f "$TMP_DIR/control-smudge" && -f "$TMP_DIR/control-hook" ]]; then
  pass "fixture checkout control proves smudge filter and hook are active"
else
  fail "fixture checkout control did not execute configured smudge/hook"
fi
rm -f "$TMP_DIR/control-smudge" "$TMP_DIR/control-hook"

# A baked-in fixture transport ensures the helper's child allowlist is tested
# without passing test-only variables through the child environment.
{
  printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
  printf 'REAL_GIT=%q\nFIXTURE_BARE=%q\nSHA1=%q\nSHA2=%q\nMODE_FILE=%q\nENV_LOG=%q\nARGS_LOG=%q\n' \
    "$REAL_GIT" "$TMP_DIR/fixture.git" "$SHA1" "$SHA2" "$TMP_DIR/git-mode" "$TMP_DIR/git-env.log" "$TMP_DIR/git-args.log"
  cat <<'EOF'

env | cut -d= -f1 | sort -u >> "$ENV_LOG"
printf '%s\n' "$*" >> "$ARGS_LOG"
mode=normal
[[ -f "$MODE_FILE" ]] && mode="$(< "$MODE_FILE")"
subcommand=
for arg in "$@"; do
  case "$arg" in ls-remote|fetch|clone) subcommand="$arg"; break ;; esac
done
case "$subcommand" in
  ls-remote)
    case "$mode" in
      wrong-sha) printf '%s\tHEAD\n' 0000000000000000000000000000000000000000 ;;
      invalid-head) printf '%s\tHEAD\n' not-a-commit ;;
      auth-failure) printf '%s\n' 'fatal: auth failed UPSTREAM_AUTH_SECRET' >&2; exit 128 ;;
      advance) printf '%s\tHEAD\n' "$SHA2" ;;
      *) printf '%s\tHEAD\n' "$SHA1" ;;
    esac
    exit 0
    ;;
  fetch)
    case "$mode" in
      fetch-failure) printf '%s\n' 'fatal: fetch failed UPSTREAM_FETCH_SECRET' >&2; exit 128 ;;
      drift) "$REAL_GIT" --git-dir "$FIXTURE_BARE" update-ref refs/heads/main "$SHA2" ;;
    esac
    dest=
    prior=
    for arg in "$@"; do
      [[ "$prior" == -C ]] && dest="$arg"
      prior="$arg"
    done
    dest="${dest:-$PWD}"
    sha="$(printf '%s\n' "$@" | tail -n 1)"
    [[ "$mode" == mismatch ]] && sha="$SHA2"
    "$REAL_GIT" -C "$dest" fetch --depth=1 --no-tags "file://$FIXTURE_BARE" "$sha"
    exit $?
    ;;
esac
for arg in "$@"; do
  if [[ "$arg" == https://github.com/* && "$subcommand" == clone ]]; then
    printf '%s\n' github-network-attempt >> "$ARGS_LOG"
    exit 97
  fi
done
exec "$REAL_GIT" "$@"
EOF
} > "$TMP_DIR/bin/git"
chmod +x "$TMP_DIR/bin/git"

printf '%s\n' normal > "$TMP_DIR/git-mode"
helper_run() {
  local dest=$1 out=$2 rc=0
  env PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" TMPDIR="$TMP_DIR" \
    MUNIN_TOKEN=UPSTREAM_MUNIN_SECRET AWS_SECRET_ACCESS_KEY=UPSTREAM_AWS_SECRET \
    GITHUB_TOKEN=UPSTREAM_GITHUB_SECRET PROVIDER_SECRET=UPSTREAM_PROVIDER_SECRET \
    node "$HELPER" Magnus-Gille/alpha "$dest" > "$out" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}
scan_run() {
  local repos=$1 out=$2 rc=0
  env PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" TMPDIR="$TMP_DIR" \
    MUNIN_TOKEN=UPSTREAM_MUNIN_SECRET AWS_SECRET_ACCESS_KEY=UPSTREAM_AWS_SECRET \
    GITHUB_TOKEN=UPSTREAM_GITHUB_SECRET PROVIDER_SECRET=UPSTREAM_PROVIDER_SECRET \
    REPOS_DIR="$repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
    bash "$SCANNER" --source upstream --dry-run --verbose > "$out" 2>&1 || rc=$?
  printf '%s\n' "$rc"
}
helper_success() {
  local label=$1 mode=$2 expected=$3 dest=$4 out=$5 rc json
  printf '%s\n' "$mode" > "$TMP_DIR/git-mode"
  rc="$(helper_run "$dest" "$out")"
  if [[ "$rc" == 0 ]]; then
    pass "$label: helper succeeds"
  else
    fail "$label: helper exit $rc"
    return
  fi
  json="$(cat "$out")"
  if EXPECTED="$expected" RECEIPT="$json" node --input-type=commonjs -e '
    const v=JSON.parse(process.env.RECEIPT);
    if(v.commit!==process.env.EXPECTED || !Date.parse(v.captured_at)) process.exit(1);
  '; then pass "$label: receipt binds commit and captured_at"; else fail "$label: invalid receipt"; fi
  if [[ "$(git -C "$dest" config --get remote.origin.url)" == https://github.com/Magnus-Gille/alpha.git ]]; then
    pass "$label: origin is canonical GitHub authority"
  else
    fail "$label: origin is not canonical GitHub authority"
  fi
}

echo "security scan upstream source tests"
echo "==================================="
rm -f "$TMP_DIR/git-env.log" "$TMP_DIR/git-args.log"
helper_success first-revision normal "$SHA1" "$TMP_DIR/one" "$TMP_DIR/one.out"
helper_success advanced-revision advance "$SHA2" "$TMP_DIR/two" "$TMP_DIR/two.out"
if [[ "$(git -C "$TMP_DIR/one" rev-parse HEAD)" == "$SHA1" && "$(git -C "$TMP_DIR/two" rev-parse HEAD)" == "$SHA2" ]]; then
  pass "successive runs bind distinct upstream revisions"
else
  fail "successive runs must bind distinct upstream revisions"
fi
helper_success captured-drift drift "$SHA1" "$TMP_DIR/drift" "$TMP_DIR/drift.out"
if [[ "$(git -C "$TMP_DIR/drift" rev-parse HEAD)" == "$SHA1" ]]; then pass "remote movement cannot drift captured HEAD"; else fail "remote movement drifted captured HEAD"; fi
if grep -Eq '^(MUNIN_TOKEN|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|PROVIDER_SECRET)$' "$TMP_DIR/git-env.log"; then
  fail "sensitive environment names reached child git"
elif grep -Eq '^(PATH|HOME)$' "$TMP_DIR/git-env.log"; then
  pass "child git drops provider secrets and keeps runtime paths"
else
  fail "child git environment is missing required runtime paths"
fi
if ! grep -Fq github-network-attempt "$TMP_DIR/git-args.log"; then pass "GitHub transport is locally intercepted"; else fail "unexpected GitHub network attempt"; fi
if ! grep -Fq checkout "$TMP_DIR/git-args.log" && [[ ! -e "$TMP_DIR/control-smudge" && ! -e "$TMP_DIR/control-hook" ]]; then
  pass "fetch performs no checkout/smudge/hook"
else
  fail "fetch executed checkout/smudge/hook"
fi
if ! find "$TMP_DIR/one" -mindepth 1 -maxdepth 1 -not -name .git -print -quit | grep -q .; then
  pass "helper destination contains no materialized source files"
else
  fail "helper destination contains materialized source files"
fi
if grep -Fq 'core.hooksPath=/dev/null' "$TMP_DIR/git-args.log" && grep -Fq -- '--template=' "$TMP_DIR/git-args.log"; then
  pass "helper uses empty template and disabled hooks safeguards"
else
  fail "helper missing empty-template or hook safeguards"
fi

rm -rf "$TMP_DIR/plain-repos" "$TMP_DIR/missing-repos"
mkdir -p "$TMP_DIR/plain-repos/alpha"
printf '%s\n' plain-checkout-sentinel > "$TMP_DIR/plain-repos/alpha/sentinel.txt"
printf '%s\n' normal > "$TMP_DIR/git-mode"
: > "$TMP_DIR/git-env.log"
rc="$(scan_run "$TMP_DIR/plain-repos" "$TMP_DIR/plain.out")"
if grep -Eq '^(MUNIN_TOKEN|AWS_SECRET_ACCESS_KEY|GITHUB_TOKEN|PROVIDER_SECRET)$' "$TMP_DIR/git-env.log"; then
  fail "snapshot materialization inherited scanner secrets"
else
  pass "all upstream source Git children exclude scanner secrets"
fi
if [[ "$rc" == 0 ]] && grep -Fq 'COVERAGE: complete=true' "$TMP_DIR/plain.out"; then pass "plain REPOS_DIR covered upstream"; else fail "plain REPOS_DIR not covered upstream"; fi
if grep -Fq ignored-upstream.txt "$TMP_DIR/plain.out"; then pass "export-ignore file is scanned"; else fail "export-ignore file omitted"; fi
if grep -Fq 'alpha: SECRETS FOUND' "$TMP_DIR/plain.out"; then pass "stopped scan-enabled component selected"; else fail "stopped scan-enabled component skipped"; fi
if [[ -f "$TMP_DIR/plain-repos/alpha/sentinel.txt" ]] && grep -Fq plain-checkout-sentinel "$TMP_DIR/plain-repos/alpha/sentinel.txt"; then
  pass "plain local checkout is preserved"
else
  fail "plain local checkout was modified"
fi
rc="$(scan_run "$TMP_DIR/missing-repos" "$TMP_DIR/missing.out")"
if [[ "$rc" == 0 ]] && grep -Fq 'COVERAGE: complete=true' "$TMP_DIR/missing.out"; then pass "missing REPOS_DIR covered upstream"; else fail "missing REPOS_DIR not covered upstream"; fi

# Capture live MCP write payloads to assert source receipts without a network.
# shellcheck disable=SC2016 # The generated fixture script expands its own runtime variables.
printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail' 'prev=' 'for arg in "$@"; do if [[ "$prev" == -d ]]; then printf "%s\n" "$arg" >> "$CURL_LOG"; fi; prev="$arg"; done' 'printf "%s\n" '"'"'data: {"jsonrpc":"2.0","result":{"content":[{"type":"text","text":"{\"ok\":true}"}]}}'"'"'' > "$TMP_DIR/bin/curl"
chmod +x "$TMP_DIR/bin/curl"
printf '%s\n' normal > "$TMP_DIR/git-mode"
rc=0
env PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" TMPDIR="$TMP_DIR" \
  MUNIN_TOKEN=UPSTREAM_MUNIN_SECRET REPOS_DIR="$TMP_DIR/plain-repos" \
  REGISTRY_PATH="$TMP_DIR/registry.json" CURL_LOG="$TMP_DIR/curl.log" \
  bash "$SCANNER" --source upstream --verbose > "$TMP_DIR/live.out" 2>&1 || rc=$?
if [[ "$rc" == 0 ]] && grep -Eq 'source_mode.*upstream' "$TMP_DIR/curl.log" && \
   grep -Eq 'source_authority.*Magnus-Gille/alpha' "$TMP_DIR/curl.log" && \
   grep -Eq 'upstream_commit.*[0-9a-f]{40}' "$TMP_DIR/curl.log" && grep -Eq 'source_fetched_at.*202[0-9]-' "$TMP_DIR/curl.log"; then
  pass "live receipts carry source identity"
else
  fail "live receipts lack source identity fields"
fi

# Failures are incomplete and never fall back to a stale local checkout.
mkdir -p "$TMP_DIR/stale-repos/alpha"
git -C "$TMP_DIR/stale-repos/alpha" init -q -b main
git -C "$TMP_DIR/stale-repos/alpha" config user.email test@example.invalid
git -C "$TMP_DIR/stale-repos/alpha" config user.name GrimnirTest
printf '%s\n' '{}' > "$TMP_DIR/stale-repos/alpha/package-lock.json"
printf '%s\n' 'sk-ant-STALELOCALCHECKOUTTOKEN1234567890' > "$TMP_DIR/stale-repos/alpha/stale-secret.txt"
git -C "$TMP_DIR/stale-repos/alpha" add -A
GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid git -C "$TMP_DIR/stale-repos/alpha" commit -q -m stale
git -C "$TMP_DIR/stale-repos/alpha" remote add origin https://github.com/Magnus-Gille/alpha.git
for mode in wrong-sha mismatch fetch-failure invalid-head auth-failure; do
  printf '%s\n' "$mode" > "$TMP_DIR/git-mode"
  rc="$(scan_run "$TMP_DIR/stale-repos" "$TMP_DIR/failure-$mode.out")"
  if [[ "$rc" == 1 ]] && grep -Fq 'Overall status: incomplete' "$TMP_DIR/failure-$mode.out" && \
     ! grep -Fq stale-secret.txt "$TMP_DIR/failure-$mode.out" && ! grep -Fq STALELOCALCHECKOUTTOKEN "$TMP_DIR/failure-$mode.out"; then
    pass "$mode fails closed without stale fallback"
  else
    fail "$mode fallback/exit contract"
  fi
  if grep -Fq UPSTREAM_ "$TMP_DIR/failure-$mode.out"; then fail "$mode leaked raw transport error"; else pass "$mode error is sanitized"; fi
done

: > "$TMP_DIR/git-args.log"
printf '%s\n' normal > "$TMP_DIR/git-mode"
rc=0
env PATH="$TMP_DIR/bin:$PATH" HOME="$TMP_DIR/home" TMPDIR="$TMP_DIR" \
  REPOS_DIR="$TMP_DIR/plain-repos" REGISTRY_PATH="$TMP_DIR/registry.json" \
  bash "$SCANNER" --source unknown --dry-run > "$TMP_DIR/unknown.out" 2>&1 || rc=$?
if [[ "$rc" == 1 ]] && grep -Eq 'must be local or upstream|unknown source mode' "$TMP_DIR/unknown.out" && [[ ! -s "$TMP_DIR/git-args.log" ]]; then pass "unknown source mode fails before Git/network"; else fail "unknown source mode reached Git/network"; fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

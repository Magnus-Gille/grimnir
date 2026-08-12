#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0
# shellcheck source=scripts/lib/validation-evidence.sh
source "$(dirname "$0")/../lib/validation-evidence.sh"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc — expected '$expected', got '$actual'"; FAIL=$((FAIL + 1)); fi
}

echo "validation evidence contract tests"
echo "=================================="

assert_eq "timer trigger is explicit" timer "$(validation_trigger_origin timer)"
assert_eq "manual trigger is explicit" manual "$(validation_trigger_origin manual)"
if validation_trigger_origin inherited >/dev/null 2>&1; then
  echo "  FAIL: unknown trigger fails closed"; FAIL=$((FAIL + 1))
else
  echo "  PASS: unknown trigger fails closed"; PASS=$((PASS + 1))
fi

SHA_A=1111111111111111111111111111111111111111
SHA_B=2222222222222222222222222222222222222222
assert_eq "equal SHAs are current" current "$(validation_freshness_classification "$SHA_A" "$SHA_A" diverged)"
assert_eq "ancestry reports ahead" ahead "$(validation_freshness_classification "$SHA_A" "$SHA_B" ahead)"
assert_eq "ancestry reports behind" behind "$(validation_freshness_classification "$SHA_A" "$SHA_B" behind)"
assert_eq "common ancestor reports diverged" diverged "$(validation_freshness_classification "$SHA_A" "$SHA_B" diverged)"
assert_eq "unknown graph fails closed" unreachable "$(validation_freshness_classification "$SHA_A" "$SHA_B" unreachable)"

# The gatherer is deliberately integration-tested against a local bare remote.
# It may fetch into a disposable object database, but never into the canonical
# checkout, so remote-only objects still yield accurate graph classifications.
FRESHNESS_TMP="$(mktemp -d)"
trap 'rm -rf "$FRESHNESS_TMP"' EXIT
git init --bare --initial-branch=main "$FRESHNESS_TMP/remote.git" >/dev/null
git init -b main "$FRESHNESS_TMP/checkout" >/dev/null
git -C "$FRESHNESS_TMP/checkout" config user.email test@example.invalid
git -C "$FRESHNESS_TMP/checkout" config user.name test
printf 'base\n' > "$FRESHNESS_TMP/checkout/record"
git -C "$FRESHNESS_TMP/checkout" add record
git -C "$FRESHNESS_TMP/checkout" commit -m base >/dev/null
git -C "$FRESHNESS_TMP/checkout" remote add origin "$FRESHNESS_TMP/remote.git"
git -C "$FRESHNESS_TMP/checkout" push -u origin main >/dev/null
BASE_SHA="$(git -C "$FRESHNESS_TMP/checkout" rev-parse HEAD)"
assert_eq "temp remote exact head is current" "$BASE_SHA|$BASE_SHA|current" \
  "$(validation_registry_freshness_evidence "$FRESHNESS_TMP/checkout")"
git clone "$FRESHNESS_TMP/remote.git" "$FRESHNESS_TMP/behind-checkout" >/dev/null
printf 'ahead\n' >> "$FRESHNESS_TMP/checkout/record"
git -C "$FRESHNESS_TMP/checkout" commit -am ahead >/dev/null
AHEAD_SHA="$(git -C "$FRESHNESS_TMP/checkout" rev-parse HEAD)"
assert_eq "temp local-only commit is ahead" "$AHEAD_SHA|$BASE_SHA|ahead" \
  "$(validation_registry_freshness_evidence "$FRESHNESS_TMP/checkout")"
git -C "$FRESHNESS_TMP/checkout" checkout -b feature >/dev/null
printf 'feature\n' >> "$FRESHNESS_TMP/checkout/record"
git -C "$FRESHNESS_TMP/checkout" commit -am feature >/dev/null
assert_eq "freshness evidence reads local main, not checked-out HEAD" "$AHEAD_SHA|$BASE_SHA|ahead" \
  "$(validation_registry_freshness_evidence "$FRESHNESS_TMP/checkout")"
git -C "$FRESHNESS_TMP/checkout" checkout main >/dev/null
git clone "$FRESHNESS_TMP/remote.git" "$FRESHNESS_TMP/remote-writer" >/dev/null
git -C "$FRESHNESS_TMP/remote-writer" config user.email test@example.invalid
git -C "$FRESHNESS_TMP/remote-writer" config user.name test
printf 'remote\n' >> "$FRESHNESS_TMP/remote-writer/record"
git -C "$FRESHNESS_TMP/remote-writer" commit -am remote >/dev/null
git -C "$FRESHNESS_TMP/remote-writer" push >/dev/null
REMOTE_NEW_SHA="$(git -C "$FRESHNESS_TMP/remote-writer" rev-parse HEAD)"
assert_eq "remote-only object is resolved as behind without canonical fetch" "$BASE_SHA|$REMOTE_NEW_SHA|behind" \
  "$(validation_registry_freshness_evidence "$FRESHNESS_TMP/behind-checkout")"
assert_eq "remote-only object resolves divergent local history" "$AHEAD_SHA|$REMOTE_NEW_SHA|diverged" \
  "$(validation_registry_freshness_evidence "$FRESHNESS_TMP/checkout")"
if git -C "$FRESHNESS_TMP/checkout" cat-file -e "$REMOTE_NEW_SHA^{commit}" 2>/dev/null ||
   git -C "$FRESHNESS_TMP/behind-checkout" cat-file -e "$REMOTE_NEW_SHA^{commit}" 2>/dev/null; then
  echo "  FAIL: graph resolution must not add objects to canonical checkouts"; FAIL=$((FAIL + 1))
else
  echo "  PASS: graph resolution leaves canonical object stores unchanged"; PASS=$((PASS + 1))
fi
assert_eq "graph resolution leaves canonical remote-tracking ref unchanged" "$BASE_SHA" \
  "$(git -C "$FRESHNESS_TMP/checkout" rev-parse refs/remotes/origin/main)"

payload="$(validation_evidence_json '2026-07-30T02:30:00Z' '2026-07-30T02:30:17Z' timer "$SHA_A" "$SHA_B" behind '' succeeded 12 2 1 issues)"
if PAYLOAD="$payload" node --input-type=commonjs -e '
  var v = JSON.parse(process.env.PAYLOAD);
  if (JSON.stringify(v) !== JSON.stringify({
    schema_version:"validation-run-evidence/v1", kind:"registry-validation-run",
    scheduled_at_utc:"2026-07-30T02:30:00Z", observed_at_utc:"2026-07-30T02:30:17Z", trigger_origin:"timer",
    registry_main:{local_sha:"1111111111111111111111111111111111111111",remote_sha:"2222222222222222222222222222222222222222",classification:"behind"},
    audit:{completed:true,error:null}, reporting:{latest_result_write:"succeeded",immutable_log:"accepted-on-success"},
    findings:{passed:12,failed:2,warnings:1,severity:"issues"}
  })) process.exit(1);'; then
  echo "  PASS: exact immutable timer log contract"; PASS=$((PASS + 1))
else
  echo "  FAIL: exact immutable timer log contract"; FAIL=$((FAIL + 1))
fi

payload="$(validation_evidence_json '' '2026-07-30T12:00:00Z' manual '' '' unreachable 'registry unreadable' failed 0 0 0 clean)"
if PAYLOAD="$payload" node --input-type=commonjs -e '
  var v = JSON.parse(process.env.PAYLOAD);
  if (v.scheduled_at_utc !== null || v.trigger_origin !== "manual" || v.audit.completed ||
      v.audit.error !== "registry unreadable" || v.registry_main.local_sha !== null ||
      v.registry_main.remote_sha !== null || v.registry_main.classification !== "unreachable") process.exit(1);'; then
  echo "  PASS: manual and audit failure remain explicit"; PASS=$((PASS + 1))
else
  echo "  FAIL: manual and audit failure remain explicit"; FAIL=$((FAIL + 1))
fi

if validation_evidence_json 'not-a-time' '2026-07-30T12:00:00Z' timer "$SHA_A" "$SHA_A" current '' succeeded 1 0 0 clean >/dev/null 2>&1; then
  echo "  FAIL: malformed scheduled timestamp fails closed"; FAIL=$((FAIL + 1))
else
  echo "  PASS: malformed scheduled timestamp fails closed"; PASS=$((PASS + 1))
fi
if grep -Fq 'Unit=grimnir-validate-timer.service' "$(dirname "$0")/../../systemd/grimnir-validate.timer" &&
   grep -Fq 'Environment=GRIMNIR_VALIDATION_ORIGIN=timer' "$(dirname "$0")/../../systemd/grimnir-validate-timer.service" &&
   grep -Fq 'RefuseManualStart=yes' "$(dirname "$0")/../../systemd/grimnir-validate-timer.service" &&
   grep -Fq '"service_name": "grimnir-validate-timer"' "$(dirname "$0")/../../services.json"; then
  echo "  PASS: timer wiring supplies an explicit origin service that refuses manual starts"
  PASS=$((PASS + 1))
else
  echo "  FAIL: timer wiring must supply an explicit origin service and refuse manual starts"
  FAIL=$((FAIL + 1))
fi
if grep -Fq '[Install]' "$(dirname "$0")/../../systemd/grimnir-validate-timer.service"; then
  echo "  FAIL: timer-only companion must not be independently enableable"; FAIL=$((FAIL + 1))
else
  echo "  PASS: timer-only companion has no independent install target"; PASS=$((PASS + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

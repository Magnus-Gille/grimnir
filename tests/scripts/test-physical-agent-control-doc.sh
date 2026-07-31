#!/usr/bin/env bash
# Preserve the authority and safety boundary adopted by grimnir#179.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACT="$REPO_ROOT/docs/physical-agent-control-contract.md"
SCHEMA="$REPO_ROOT/docs/physical-agent-control-v1.schema.json"
PROFILE_SCHEMA="$REPO_ROOT/docs/physical-agent-control-profile-v1.schema.json"
VOICE_SCHEMA="$REPO_ROOT/docs/physical-agent-voice-draft-v1.schema.json"
CANCELLATION_SCHEMA="$REPO_ROOT/docs/physical-agent-voice-capture-cancellation-v1.schema.json"
AUTHORITY="$REPO_ROOT/docs/authority.md"
PASS=0
FAIL=0

assert_contains() {
  local file="$1" desc="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qiE "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — pattern not found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

assert_excludes() {
  local file="$1" desc="$2" pattern="$3"
  if [[ -f "$file" ]] && ! grep -qiE "$pattern" "$file"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc — forbidden pattern found: $pattern"
    FAIL=$((FAIL + 1))
  fi
}

echo "Checking physical agent control documentation ..."

assert_contains "$CONTRACT" "versioned contract id" 'grimnir\.physical-agent-control/v1'
assert_contains "$CONTRACT" "reuses rather than adds orchestration" 'local physical console.*, not a new agent orchestrator'
assert_contains "$CONTRACT" "keeps Hugin as consequential-task gate" 'Hugin remains the durable, policy-gated consequential-task plane'
assert_contains "$CONTRACT" "does not register a service" "There is no \`services\.json\` entry"
assert_contains "$CONTRACT" "identifies the corrected microphone" 'EP.?2350 ting performance microphone'
assert_contains "$CONTRACT" "makes Stream Deck the sole event surface" 'Stream Deck is the only v1 control-event'
assert_contains "$CONTRACT" "documents analog line output" 'stereo line output.*3\.5 mm.*8 dBu.*2 Vrms'
assert_contains "$CONTRACT" "requires an external input when needed" 'external line-level'
assert_contains "$CONTRACT" "rejects undocumented computer interfaces" 'document USB audio, MIDI, BLE, HID'
assert_contains "$CONTRACT" "keeps USB-C out of live IPC" 'maintenance/power path, never live control IPC'
assert_contains "$CONTRACT" "does not authenticate an analog source" 'operator-configured, not authenticated hardware identity'
assert_contains "$CONTRACT" "binds owner-reviewed profiles" 'owner-reviewed local profile'
assert_contains "$CONTRACT" "defines canonical profile digest bytes" 'profile-jcs-sha256-v1.*lowercase SHA-256'
assert_contains "$CONTRACT" "does not trust self-asserted profile digests" 'Self-asserted digest equality'
assert_contains "$CONTRACT" "uses explicit push-to-talk" 'dedicated Stream Deck key-down begins push-to-talk'
assert_contains "$CONTRACT" "makes PTT lifecycle stateful" 'begin cannot overlap.*reuse a completed/cancelled capture reference'
assert_contains "$CONTRACT" "binds PTT to an adapter generation" 'close the same capture.*adapter generation'
assert_contains "$CONTRACT" "binds PTT to a full target digest" 'target-snapshot-jcs-sha256-v1.*lowercase'
assert_contains "$CONTRACT" "requires a new target identity on slot remap" 'remap must mint a new immutable snapshot'
assert_contains "$CONTRACT" "models watchdog cancellation" 'watchdog emits cancellation evidence.*deletes buffered audio.*creates no draft'
assert_contains "$CONTRACT" "allows recapture after watchdog" 'clears the active state'
assert_contains "$CONTRACT" "excludes dials from PTT" 'Stream Deck dials cannot become PTT selectors'
assert_contains "$CONTRACT" "caps voice capture" 'stops after 30 seconds'
assert_contains "$CONTRACT" "requires offline transcription" 'STT is local/offline with networking disabled'
assert_contains "$CONTRACT" "pins exact STT versions" 'exact offline STT engine/model versions'
assert_contains "$CONTRACT" "pins exact CoreAudio tuple" 'exact CoreAudio UID, interface generation, and channel set'
assert_contains "$CONTRACT" "keeps audio memory-only" 'Raw audio is memory-only and deleted'
assert_contains "$CONTRACT" "keeps transcripts volatile" 'transcript remains in volatile local'
assert_contains "$CONTRACT" "requires native manual submission" 'Native-client submission is a'
assert_contains "$CONTRACT" "uses keyed transcript binding" 'keyed HMAC-SHA-256 binding'
assert_contains "$CONTRACT" "defines the HMAC input" 'voice-content-hmac-sha256-v1.*lowercase HMAC-SHA-256'
assert_contains "$CONTRACT" "computes hermetic HMAC vectors" 'synthetic volatile-content vectors compute the byte count and HMAC'
assert_contains "$CONTRACT" "samples and effects have no authority" 'no sample, effect, handle movement, shake'
assert_contains "$CONTRACT" "bounds intent expiry" 'no more than five'
assert_contains "$CONTRACT" "uses a trusted evaluation clock" 'trusted current'
assert_contains "$CONTRACT" "expiry precedes replay lookup" 'Expired input is rejected before replay'
assert_contains "$CONTRACT" "requires monotonic sequence" "strictly increasing \`sequence\`"
assert_contains "$CONTRACT" "does not spool device events" 'never durably spooled'
assert_contains "$CONTRACT" "replay returns prior disposition" 'returns the prior disposition without another'
assert_contains "$CONTRACT" "conflicting replay is rejected" 'conflicting reuse is'
assert_contains "$CONTRACT" "derived state is display-only" 'projection is display-only'
assert_contains "$CONTRACT" "idle is not completion" 'Idle never means'
assert_contains "$CONTRACT" "done binds a native report" 'structured-report reference and digest'
assert_contains "$CONTRACT" "hardware never approves" 'Hardware never answers an'
assert_contains "$CONTRACT" "raw prompts and transcripts are excluded" 'raw audio.*transcript text.*prompt text'
assert_contains "$CONTRACT" "authority increases are excluded" 'Nothing in v1 may increase authority'
assert_contains "$CONTRACT" "voice release does not submit" 'Neither key-up, silence, a spoken word.*can submit content'
assert_contains "$CONTRACT" "ADR-008 disarm is not overloaded" 'autonomy arm/disarm'
assert_contains "$CONTRACT" "implementation visibility remains an owner choice" 'owner chooses its name and'
assert_contains "$SCHEMA" "schema permits no authority increase" '"authority_delta": \{ "enum": \["none", "reduce"\] \}'
assert_contains "$SCHEMA" "control schema is Stream Deck-only" '"device": \{ "const": "stream-deck" \}'
assert_excludes "$SCHEMA" "control schema excludes EP-2350 event sources" '"device": \{ "const": "ep-2350-ting" \}'
assert_excludes "$SCHEMA" "control schema excludes mixer/MIDI selectors" 'tx-6|midi-channel|midi_channel'
assert_contains "$PROFILE_SCHEMA" "profile schema fixes canonical digest algorithm" '"digest_algorithm": \{ "const": "profile-jcs-sha256-v1" \}'
assert_contains "$PROFILE_SCHEMA" "profile schema fixes analog transport" '"transport": \{ "const": "analog-line-out-via-audio-interface" \}'
assert_contains "$PROFILE_SCHEMA" "profile schema disables sample tokens" '"sample_token_mode": \{ "const": "disabled" \}'
assert_contains "$PROFILE_SCHEMA" "profile schema pins CoreAudio generation" '"interface_generation_ref".*defs/id'
assert_contains "$PROFILE_SCHEMA" "profile schema pins STT engine version" '"stt_engine_version".*defs/version'
assert_contains "$PROFILE_SCHEMA" "profile schema stays closed" '"additionalProperties": false'
assert_contains "$VOICE_SCHEMA" "voice schema carries metadata only" 'public-safe metadata for an ephemeral, locally transcribed EP-2350 voice draft'
assert_contains "$VOICE_SCHEMA" "voice schema fixes local transcription" '"boundary": \{ "const": "workstation-local" \}'
assert_contains "$VOICE_SCHEMA" "voice schema forbids retained audio" '"audio_retained": \{ "const": false \}'
assert_contains "$VOICE_SCHEMA" "voice schema requires keyed content binding" '\^hmac-sha256:'
assert_contains "$VOICE_SCHEMA" "voice schema binds exact PTT intent ids" '"begin_intent_id".*defs/id'
assert_contains "$VOICE_SCHEMA" "voice schema binds canonical target digest" '"snapshot_digest".*defs/digest'
assert_excludes "$VOICE_SCHEMA" "voice schema has no executable action field" '"action"[[:space:]]*:'
assert_contains "$CANCELLATION_SCHEMA" "cancellation schema proves audio deletion" '"audio_deleted": \{ "const": true \}'
assert_contains "$CANCELLATION_SCHEMA" "cancellation schema forbids a draft" '"draft_created": \{ "const": false \}'
assert_excludes "$CANCELLATION_SCHEMA" "cancellation schema has no executable action field" '"action"[[:space:]]*:'
assert_contains "$AUTHORITY" "authority map names control and voice metadata" 'Physical control intent/state, voice-draft, and capture-cancellation metadata'
assert_contains "$AUTHORITY" "authority map keeps local capture adapter-owned" 'CoreAudio binding, volatile voice content, local STT'
assert_contains "$AUTHORITY" "authority map keeps consequential work in Hugin" 'Physical-control consequential task admission'

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All $PASS assertion(s) passed."
  exit 0
fi

echo "$FAIL of $((PASS + FAIL)) assertion(s) FAILED."
exit 1

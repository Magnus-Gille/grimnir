# shellcheck shell=bash
# escalation.sh — pure, testable helpers for the security scanner's delta path.
#
# scan_escalated prev_crit prev_high prev_secrets cur_crit cur_high cur_secrets
#   echoes "yes" if any current finding-count exceeds the previous snapshot,
#   else "no".
#
# parse_prev_counts  (reads a Munin memory_read response on stdin)
#   echoes "<crit>\t<high>\t<secrets>\t<status>" where status is:
#     ok          — a valid JSON-RPC result envelope was present and the counts
#                   are trusted integers (genuine first run with no prior scan
#                   also yields "0 0 0 ok")
#     unavailable — RPC failure / sentinel "{}" / malformed or poisoned shape;
#                   the caller MUST NOT treat the zeros as a real baseline.
#
# Sourced by both security-scan.sh and the delta unit test so the logic has a
# single definition. bash 3.2+ (parsing delegated to node).

# Coerce a value to a safe base-10 integer string, or "0" if not a plain 1–9
# digit number. Rejects non-numeric, leading-zero/octal (08, 09), and overlong
# values before they can reach bash arithmetic ([[ -gt ]] evaluates operands
# arithmetically; a poisoned multi-writer Munin record must never get there).
_escal_int() {
  if [[ "$1" =~ ^[0-9]{1,9}$ ]]; then
    printf '%s' "$((10#$1))"
  else
    printf '%s' 0
  fi
}

scan_escalated() {
  local prev_c prev_h prev_s cur_c cur_h cur_s
  prev_c="$(_escal_int "$1")"; prev_h="$(_escal_int "$2")"; prev_s="$(_escal_int "$3")"
  cur_c="$(_escal_int "$4")";  cur_h="$(_escal_int "$5")";  cur_s="$(_escal_int "$6")"
  if [[ "$cur_c" -gt "$prev_c" ]] || [[ "$cur_h" -gt "$prev_h" ]] || [[ "$cur_s" -gt "$prev_s" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

parse_prev_counts() {
  # shellcheck disable=SC2016  # single-quoted node program — no bash expansion
  node --input-type=commonjs -e '
    var d;
    try { d = JSON.parse(require("fs").readFileSync("/dev/stdin", "utf8")); }
    catch (e) { process.stdout.write("0\t0\t0\tunavailable"); process.exit(0); }
    // No JSON-RPC result envelope => RPC failed / sentinel "{}" => unavailable.
    if (!d || !d.result || !Array.isArray(d.result.content)) {
      process.stdout.write("0\t0\t0\tunavailable"); process.exit(0);
    }
    var first = d.result.content[0];
    var text = (first && typeof first.text === "string") ? first.text : "";
    var m = text.match(/```json\s*([\s\S]*?)```/);
    // Envelope present but no prior-scan content => genuine first run.
    if (!m) { process.stdout.write("0\t0\t0\tok"); process.exit(0); }
    var obj;
    try { obj = JSON.parse(m[1]); }
    catch (e) { process.stdout.write("0\t0\t0\tunavailable"); process.exit(0); }
    // Strict integer: JSON number or all-digit string, bounded. parseInt-style
    // leniency ("999junk" -> 999) and a fake {length:N} secrets object must NOT
    // produce a trusted baseline that could suppress a real escalation.
    function intOrNull(x) {
      if (typeof x === "number" && Number.isInteger(x) && x >= 0 && x <= 1e9) return x;
      if (typeof x === "string" && /^[0-9]{1,9}$/.test(x)) return parseInt(x, 10);
      return null;
    }
    var audit = (obj && typeof obj.audit === "object" && obj.audit) ? obj.audit : {};
    var c = intOrNull(audit.critical);
    var h = intOrNull(audit.high);
    var s = Array.isArray(obj.secrets) ? obj.secrets.length : null;
    if (c === null || h === null || s === null) {
      process.stdout.write("0\t0\t0\tunavailable"); process.exit(0);
    }
    process.stdout.write(c + "\t" + h + "\t" + s + "\tok");
  ' 2>/dev/null || printf '%s' "0	0	0	unavailable"
}

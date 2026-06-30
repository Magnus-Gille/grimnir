# shellcheck shell=bash
# escalation.sh — pure escalation check for the security scanner.
#
# scan_escalated prev_crit prev_high prev_secrets cur_crit cur_high cur_secrets
#   echoes "yes" if any current finding-count exceeds the previous snapshot,
#   else "no".
#
# Sourced by both security-scan.sh and the delta unit test so the logic has a
# single definition. bash 3.2+.

scan_escalated() {
  local prev_c="$1" prev_h="$2" prev_s="$3" cur_c="$4" cur_h="$5" cur_s="$6" v
  # Coerce every argument to an integer BEFORE the `[[ -gt ]]` comparison.
  # `[[ a -gt b ]]` evaluates its operands as arithmetic, so a non-numeric value
  # from a poisoned multi-writer Munin record (e.g. `a[$(cmd)]`) would otherwise
  # trip `set -u` ("unbound variable") and abort the scan — or, on a shell
  # without nounset, reach arithmetic evaluation. Never let untrusted data in.
  for v in prev_c prev_h prev_s cur_c cur_h cur_s; do
    [[ "${!v}" =~ ^[0-9]+$ ]] || printf -v "$v" '%s' 0
  done
  if [[ "$cur_c" -gt "$prev_c" ]] || [[ "$cur_h" -gt "$prev_h" ]] || [[ "$cur_s" -gt "$prev_s" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

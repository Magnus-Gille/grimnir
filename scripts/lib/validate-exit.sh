# shellcheck shell=bash
# validate-exit.sh — the audit exit-status contract.
#
# Owner directive (2026-07-25, live evidence from huginmunin):
#   grimnir-validate ran perfectly and found exactly what it exists to find
#   (a stale worktree registration, a dirty canonical checkout) — then exited
#   1 because of those findings. systemd marked the unit `failed`, Heimdall
#   rendered `status: fail`, and because that had been true for so long,
#   nobody read it — a genuine crash would look identical. Meanwhile the
#   REAL reporting channel (appending the validation event to Munin) was
#   silently broken, so findings could not reach the owner through any
#   working channel — exit-1-as-alarm had become the de facto channel.
#
# Contract:
#   Exit status must describe whether the AUDIT WORKED, not whether the
#   fleet is clean.
#     - 0 when the audit ran to completion, regardless of how many findings
#       it produced. Findings are data.
#     - non-zero only when the audit itself could not do its job: it
#       couldn't read its inputs (e.g. services.json), couldn't enumerate
#       what it needed to check (e.g. the worktrees directory), or — the
#       load-bearing case — could not report its findings through a durable
#       channel.
#
# audit_exit_code <audit_error> <reporting_ok>
#   audit_error   non-empty string describing a structural failure (registry
#                 unreadable, worktree enumeration failed, precondition
#                 unmet), or "" when the audit ran cleanly.
#   reporting_ok  "true" if findings were durably reported (e.g. written AND
#                 logged to Munin), anything else (including "false" or
#                 missing) means the reporting channel did not confirm.
#   Echoes "0" or "1". Deliberately does NOT accept a finding/fail count —
#   findings must never re-enter the exit decision, on purpose, so a future
#   call site cannot silently wire them back in.
audit_exit_code() {
  local audit_error="${1:-}" reporting_ok="${2:-false}"

  if [[ -n "$audit_error" ]]; then
    echo "1"
    return 0
  fi

  if [[ "$reporting_ok" != "true" ]]; then
    echo "1"
    return 0
  fi

  echo "0"
}

# audit_status_line <fail_count> <warn_count> <audit_error> <reporting_ok>
#   Human-readable one-line summary for the script's own stdout/journal
#   output, so "N findings" (data) and "audit failed" (systemd-alarm-worthy)
#   are never visually conflated. Mirrors audit_exit_code's decision order.
audit_status_line() {
  local fail_count="${1:-0}" warn_count="${2:-0}" audit_error="${3:-}" reporting_ok="${4:-false}"

  if [[ -n "$audit_error" ]]; then
    echo "AUDIT FAILED: ${audit_error}"
    return 0
  fi

  if [[ "$reporting_ok" != "true" ]]; then
    echo "AUDIT FAILED: findings could not be durably reported"
    return 0
  fi

  echo "AUDIT OK: ran to completion — ${fail_count} finding(s), ${warn_count} warning(s)"
}

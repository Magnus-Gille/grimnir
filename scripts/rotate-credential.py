#!/usr/bin/env python3
"""Plan/execute a credential cutover: issue -> install -> verify (GRIM-249).

The secret only ever travels over one OS pipe from the issuer's stdout to the
installer's stdin. It is never held in this process, argv, env, a file or a log.
Commands come from a PRIVATE config (see docs/credential-inventory.md); this
script holds no host names or paths.

  rotate-credential.py plan    --config CFG ID     # default; runs nothing
  rotate-credential.py execute --config CFG ID     # needs an interactive TTY and
                                                   # the owner typing the id

Config (JSON, 0600 recommended):
  {"credentials": {"<id>": {"preflight": [argv], "issue": [argv],
                            "install": [argv], "verify": [argv],
                            "reversal": "text", "audit_log": "/abs/path.jsonl"}}}
Agents must only run `plan`.
Exit codes: 0 ok, 1 step failed, 2 invalid input, 3 token issued but not delivered,
4 refused (no TTY / confirmation mismatch).
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

STEPS = ("preflight", "issue", "install", "verify")
EXIT_FAILED, EXIT_INVALID, EXIT_NOT_DELIVERED, EXIT_REFUSED = 1, 2, 3, 4


def load(config_path, cred_id):
    try:
        with open(config_path) as fh:
            cfg = json.load(fh)
        entry = cfg["credentials"][cred_id]
    except (OSError, ValueError, KeyError, TypeError):
        raise SystemExit(f"invalid config or unknown credential id: {cred_id!r}")
    for step in STEPS:
        argv = entry.get(step)
        if not (isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv)):
            raise SystemExit(f"config: '{step}' must be a non-empty argv list")
    for key in ("reversal", "audit_log"):
        if not isinstance(entry.get(key), str) or not entry[key]:
            raise SystemExit(f"config: '{key}' must be a non-empty string")
    if not os.path.isabs(entry["audit_log"]):
        raise SystemExit("config: audit_log must be an absolute path")
    return entry


def audit(entry, cred_id, event, **fields):
    rec = {"ts": dt.datetime.now(dt.timezone.utc).isoformat(), "credential": cred_id,
           "event": event, "reversal": entry["reversal"], **fields}
    fd = os.open(entry["audit_log"], os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    with os.fdopen(fd, "a") as fh:
        fh.write(json.dumps(rec) + "\n")


def run_step(argv):
    # stdout/stderr of non-secret steps are discarded: never echo child output.
    return subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode


def plan(entry, cred_id, out=None):
    out = out or sys.stdout
    print(f"PLAN for {cred_id} (nothing is executed):", file=out)
    for n, step in enumerate(STEPS, 1):
        print(f"  {n}. {step}: {' '.join(entry[step][:2])} ... ({len(entry[step])} args)", file=out)
    print("  secret path: issue stdout -> install stdin (single pipe)", file=out)
    print(f"  reversal: {entry['reversal']}", file=out)
    return 0


def execute(entry, cred_id, confirm):
    if confirm(cred_id) is not True:
        return EXIT_REFUSED
    audit(entry, cred_id, "start")
    if run_step(entry["preflight"]) != 0:
        audit(entry, cred_id, "preflight-failed")
        return EXIT_FAILED  # nothing issued yet
    issuer = subprocess.Popen(entry["issue"], stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    installer = subprocess.Popen(entry["install"], stdin=issuer.stdout,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    issuer.stdout.close()  # installer owns the read end
    inst_rc, iss_rc = installer.wait(), issuer.wait()
    if iss_rc != 0:
        audit(entry, cred_id, "issue-failed", issue_rc=iss_rc, install_rc=inst_rc)
        return EXIT_FAILED
    if inst_rc != 0:
        audit(entry, cred_id, "token-not-delivered", install_rc=inst_rc,
              note="credential issued but installer failed; do not retry blindly - reconcile state, then issue again")
        return EXIT_NOT_DELIVERED
    if run_step(entry["verify"]) != 0:
        audit(entry, cred_id, "verify-failed")
        return EXIT_FAILED
    audit(entry, cred_id, "ok")
    return 0


def tty_confirm(cred_id):
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("execute needs an interactive terminal; agents must use `plan`.", file=sys.stderr)
        return False
    typed = input(f"Type the credential id '{cred_id}' to execute: ")
    return typed == cred_id


def main(argv=None, confirm=tty_confirm):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=("plan", "execute"))
    ap.add_argument("credential_id")
    ap.add_argument("--config", required=True)
    args = ap.parse_args(argv)
    try:
        entry = load(args.config, args.credential_id)
    except SystemExit as exc:
        print(exc, file=sys.stderr)
        return EXIT_INVALID
    if args.mode == "plan":
        return plan(entry, args.credential_id)
    return execute(entry, args.credential_id, confirm)


if __name__ == "__main__":
    sys.exit(main())

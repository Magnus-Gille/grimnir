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
Exit codes: 0 ok, 1 preflight failed (nothing issued), 2 invalid input/config, 3 issue or install
failed AFTER the issuer started (a credential may exist: reconcile, never retry blindly),
4 refused (no TTY / mismatch), 5 installed but verification failed.
The TTY prompt is a convention that keeps routine agent runs on `plan`; it is not a security
boundary against an agent with shell access. Real enforcement belongs in the issuer's own
credentials or an owner signature.
"""
import argparse
import shutil
import stat
import datetime as dt
import json
import os
import subprocess
import sys

STEPS = ("preflight", "issue", "install", "verify")
EXIT_FAILED, EXIT_INVALID, EXIT_NOT_DELIVERED, EXIT_REFUSED, EXIT_VERIFY_FAILED = 1, 2, 3, 4, 5
STEP_TIMEOUT = 300


def load(config_path, cred_id):
    try:
        st = os.lstat(config_path)
    except OSError:
        raise SystemExit("config unreadable")
    if (not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid()
            or st.st_mode & 0o077):
        raise SystemExit("config must be a regular, non-symlink, owner-owned file with mode 0600")
    try:
        with open(config_path) as fh:
            entry = json.load(fh)["credentials"][cred_id]
    except (OSError, ValueError, KeyError, TypeError):
        raise SystemExit(f"invalid config or unknown credential id: {cred_id!r}")
    for step in STEPS:
        argv = entry.get(step)
        if not (isinstance(argv, list) and argv and all(isinstance(a, str) for a in argv)):
            raise SystemExit(f"config: '{step}' must be a non-empty argv list")
        if shutil.which(argv[0]) is None:
            raise SystemExit(f"config: '{step}' command not found or not executable")
    for key in ("reversal", "audit_log"):
        if not isinstance(entry.get(key), str) or not entry[key]:
            raise SystemExit(f"config: '{key}' must be a non-empty string")
    if not os.path.isabs(entry["audit_log"]):
        raise SystemExit("config: audit_log must be an absolute path")
    return entry


def audit(entry, cred_id, event, **fields):
    rec = {"ts": dt.datetime.now(dt.timezone.utc).isoformat(), "credential": cred_id,
           "event": event, "reversal": entry["reversal"], **fields}
    fd = os.open(entry["audit_log"], os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        os.write(fd, (json.dumps(rec) + "\n").encode())
        os.fsync(fd)
    finally:
        os.close(fd)


def run_step(argv, timeout=STEP_TIMEOUT):
    # child stdout/stderr are discarded: never echo child output.
    try:
        return subprocess.run(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                              stderr=subprocess.DEVNULL, timeout=timeout).returncode
    except (subprocess.TimeoutExpired, OSError):
        return -1


def plan(entry, cred_id, out=None):
    out = out or sys.stdout
    print(f"PLAN for {cred_id} (nothing is executed; commands are not shown here):", file=out)
    for n, step in enumerate(STEPS, 1):
        print(f"  {n}. {step} ({len(entry[step])} args)", file=out)
    print("  secret path: issue stdout -> install stdin (single pipe)", file=out)
    return 0


def _reap(proc):
    if proc is None:
        return None
    try:
        return proc.wait(timeout=STEP_TIMEOUT)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        return -9


def execute(entry, cred_id, confirm):
    if confirm(cred_id, entry) is not True:
        try:
            audit(entry, cred_id, "refused")
        except OSError:
            pass
        return EXIT_REFUSED
    audit(entry, cred_id, "start")
    if run_step(entry["preflight"]) != 0:
        audit(entry, cred_id, "preflight-failed")
        return EXIT_FAILED  # nothing issued yet
    issuer = installer = None
    outcome = "outcome-unknown"
    iss_rc = inst_rc = None
    try:
        issuer = subprocess.Popen(entry["issue"], stdin=subprocess.DEVNULL,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        installer = subprocess.Popen(entry["install"], stdin=issuer.stdout,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        issuer.stdout.close()  # installer owns the read end
        inst_rc = _reap(installer)
        iss_rc = _reap(issuer)
        outcome = "ok" if (iss_rc == 0 and inst_rc == 0) else "issue-or-install-failed"
    finally:
        for proc in (installer, issuer):
            if proc is not None and proc.poll() is None:
                proc.kill()
                proc.wait()
        if outcome != "ok":
            # Once the issuer has been spawned a credential may exist: never report this as
            # "nothing happened". Best-effort audit; the exit code carries the contract.
            try:
                audit(entry, cred_id, outcome, issue_rc=iss_rc, install_rc=inst_rc,
                      note="credential may have been issued; reconcile state with the verify probe before issuing again, never retry blindly")
            except OSError:
                print("WARNING: audit write failed", file=sys.stderr)
    if outcome != "ok":
        return EXIT_NOT_DELIVERED
    if run_step(entry["verify"]) != 0:
        audit(entry, cred_id, "verify-failed")
        return EXIT_VERIFY_FAILED
    audit(entry, cred_id, "ok", issue_rc=iss_rc, install_rc=inst_rc)
    return 0


def tty_confirm(cred_id, entry):
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("execute needs an interactive terminal; agents must use `plan`.", file=sys.stderr)
        return False
    print(f"About to rotate {cred_id}. Full commands (no secrets by design):")
    for step in STEPS:
        print(f"  {step}: {' '.join(entry[step])}")
    print(f"  reversal: {entry['reversal']}")
    try:
        return input(f"Type the credential id '{cred_id}' to execute: ") == cred_id
    except EOFError:
        return False


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
    try:
        return execute(entry, args.credential_id, confirm)
    except KeyboardInterrupt:
        print("interrupted: outcome unknown, check the audit log and verify probe", file=sys.stderr)
        return EXIT_NOT_DELIVERED


if __name__ == "__main__":
    sys.exit(main())

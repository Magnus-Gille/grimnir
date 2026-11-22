#!/usr/bin/env python3
"""Install a secret read from stdin into an env file or JSON credentials file (GRIM-249).

Runs on the consumer host as the install step of scripts/rotate-credential.py. The
secret arrives only on stdin (never argv/env), is written atomically with mode 0600,
and is never printed. The previous file is kept once as `<file>.prev` (0600) for
inspection only: it holds a value that is already revoked, so recovery is forward-only
(issue a new credential), never a restore from `.prev`.

  install-secret-stdin.py --file /abs/path --format env  --key MUNIN_API_KEY
  install-secret-stdin.py --file /abs/path --format json --key auth_token
  install-secret-stdin.py ... --check        # preflight: same validation, no stdin, no write

Exit codes: 0 ok (also when the value is already installed), 2 invalid args or unsafe target file,
3 bad stdin (nothing written), 4 write failed (target unchanged).
"""
import argparse
import json
import os
import re
import signal
import stat
import sys
import tempfile

EXIT_BAD_TARGET, EXIT_BAD_STDIN, EXIT_WRITE_FAILED = 2, 3, 4
MAX_SECRET = 4096
SECRET_RE = re.compile(r"[A-Za-z0-9._~+/=:@-]+")  # no shell metacharacters, quotes or whitespace
KEY_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def fail(code, msg):
    print(f"install-secret-stdin: {msg}", file=sys.stderr)
    sys.exit(code)


def read_secret():
    if sys.stdin is None or sys.stdin.isatty():
        fail(EXIT_BAD_STDIN, "refusing to read a secret from a terminal or closed stdin; pipe it in")
    data = sys.stdin.buffer.read(MAX_SECRET + 2)
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        fail(EXIT_BAD_STDIN, "secret must be ASCII")
    secret = text.strip()
    if text not in (secret, secret + "\n") or not secret or len(secret) > MAX_SECRET \
            or not SECRET_RE.fullmatch(secret):
        fail(EXIT_BAD_STDIN, "stdin must be exactly one token of [A-Za-z0-9._~+/=:@-]")
    return secret


def read_target(path):
    """Open without following symlinks and validate the descriptor, not the path."""
    if not os.path.isabs(path):
        fail(EXIT_BAD_TARGET, "--file must be an absolute path")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError:
        fail(EXIT_BAD_TARGET, "target missing, unreadable or a symlink")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            fail(EXIT_BAD_TARGET, "target must be a regular file with a single link")
        if st.st_uid != os.getuid() or st.st_mode & 0o077:
            fail(EXIT_BAD_TARGET, "target must be owned by the current user with mode 0600")
        parent = os.stat(os.path.dirname(path))
        if parent.st_uid not in (os.getuid(), 0) or parent.st_mode & 0o022:
            fail(EXIT_BAD_TARGET, "target directory must be owned by you/root and not group/world-writable")
        with os.fdopen(fd, "rb", closefd=False) as fh:
            return fh.read()
    finally:
        os.close(fd)


def render_env(original, key, secret):
    lines = original.split(b"\n")
    hits = [i for i, l in enumerate(lines) if l.startswith(key.encode() + b"=")]
    if len(hits) != 1:
        fail(EXIT_BAD_TARGET, f"expected exactly one {key}= line, found {len(hits)}")
    eol = b"\r" if lines[hits[0]].endswith(b"\r") else b""
    lines[hits[0]] = key.encode() + b"=" + secret.encode() + eol
    return b"\n".join(lines)


def render_json(original, key, secret):
    try:
        doc = json.loads(original.decode("utf-8"))
    except ValueError:
        fail(EXIT_BAD_TARGET, "target is not valid UTF-8 JSON")
    if not isinstance(doc, dict) or not isinstance(doc.get(key), str):
        fail(EXIT_BAD_TARGET, f"JSON object has no string field {key}")
    doc[key] = secret
    return (json.dumps(doc, indent=2) + "\n").encode()


def fsync_dir(path):
    fd = os.open(os.path.dirname(path), os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_private(path, content):
    fd, tmp = tempfile.mkstemp(prefix=".tmp-install-", dir=os.path.dirname(path))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
        fsync_dir(path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", required=True)
    ap.add_argument("--format", required=True, choices=("env", "json"))
    ap.add_argument("--key", required=True)
    ap.add_argument("--check", action="store_true",
                    help="validate the target and key without reading stdin or writing anything (preflight)")
    args = ap.parse_args(argv)
    if not KEY_RE.fullmatch(args.key):
        fail(EXIT_BAD_TARGET, "--key must match [A-Za-z_][A-Za-z0-9_]*")
    render = render_env if args.format == "env" else render_json
    original = read_target(args.file)
    render(original, args.key, "placeholder")  # validate the target BEFORE consuming the secret
    if args.check:
        print(f"{args.key} target in {os.path.basename(args.file)} is installable")
        return 0
    secret = read_secret()
    new = render(original, args.key, secret)
    if new == original:
        print(f"{args.key} already set in {os.path.basename(args.file)}; nothing to do")
        return 0  # idempotent rerun: never clobber .prev with the already-rotated file
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(EXIT_WRITE_FAILED))
    signal.signal(signal.SIGHUP, lambda *_: sys.exit(EXIT_WRITE_FAILED))
    try:
        write_private(args.file + ".prev", original)
        write_private(args.file, new)
    except OSError:
        fail(EXIT_WRITE_FAILED, "write failed; target left unchanged (a .prev copy may exist)")
    print(f"installed {args.key} into {os.path.basename(args.file)}; previous kept as .prev")
    return 0


if __name__ == "__main__":
    sys.exit(main())

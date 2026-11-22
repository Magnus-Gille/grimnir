#!/usr/bin/env python3
"""Install a secret read from stdin into an env file or JSON credentials file (GRIM-249).

Runs on the consumer host as the install step of scripts/rotate-credential.py. The
secret arrives only on stdin (never argv/env), is written atomically with mode 0600,
and is never printed. The previous file is kept once as `<file>.prev` (0600) so the
reversal is a single mv.

  install-secret-stdin.py --file /abs/path --format env  --key MUNIN_API_KEY
  install-secret-stdin.py --file /abs/path --format json --key auth_token

Exit codes: 0 ok, 2 invalid args or unsafe target file, 3 bad stdin (nothing written).
"""
import argparse
import json
import os
import stat
import sys
import tempfile

EXIT_BAD_TARGET, EXIT_BAD_STDIN = 2, 3
MAX_SECRET = 4096


def fail(code, msg):
    print(f"install-secret-stdin: {msg}", file=sys.stderr)
    sys.exit(code)


def read_secret():
    if sys.stdin.isatty():
        fail(EXIT_BAD_STDIN, "refusing to read a secret from a terminal; pipe it in")
    data = sys.stdin.buffer.read(MAX_SECRET + 2)
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError:
        fail(EXIT_BAD_STDIN, "secret must be ASCII")
    secret = text.strip()
    if text not in (secret, secret + "\n") or not secret or len(secret) > MAX_SECRET \
            or any(c.isspace() for c in secret) or any(c in secret for c in "\"'\\$`="):
        fail(EXIT_BAD_STDIN, "stdin must be exactly one token (no whitespace/quotes/=)")
    return secret


def check_target(path):
    if not os.path.isabs(path):
        fail(EXIT_BAD_TARGET, "--file must be an absolute path")
    try:
        st = os.lstat(path)
    except OSError:
        fail(EXIT_BAD_TARGET, "target file missing or unreadable")
    if not stat.S_ISREG(st.st_mode):
        fail(EXIT_BAD_TARGET, "target must be a regular, non-symlink file")
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        fail(EXIT_BAD_TARGET, "target must be owned by the current user with mode 0600")
    parent = os.stat(os.path.dirname(path))
    if parent.st_mode & 0o002:
        fail(EXIT_BAD_TARGET, "target directory is world-writable")


def render_env(original, key, secret):
    lines = original.splitlines(keepends=True)
    hits = [i for i, l in enumerate(lines) if l.startswith(f"{key}=")]
    if len(hits) != 1:
        fail(EXIT_BAD_TARGET, f"expected exactly one {key}= line, found {len(hits)}")
    lines[hits[0]] = f"{key}={secret}\n"
    return "".join(lines)


def render_json(original, key, secret):
    try:
        doc = json.loads(original)
    except ValueError:
        fail(EXIT_BAD_TARGET, "target is not valid JSON")
    if not isinstance(doc, dict) or key not in doc:
        fail(EXIT_BAD_TARGET, f"JSON object has no field {key}")
    doc[key] = secret
    return json.dumps(doc, indent=2) + "\n"


def write_private(path, content):
    fd, tmp = tempfile.mkstemp(prefix=".tmp-install-", dir=os.path.dirname(path))
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
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
    args = ap.parse_args(argv)
    if not args.key.replace("_", "").isalnum():
        fail(EXIT_BAD_TARGET, "--key must be alphanumeric/underscore")
    check_target(args.file)
    secret = read_secret()  # after target checks: bad target never consumes the secret
    with open(args.file) as fh:
        original = fh.read()
    render = render_env if args.format == "env" else render_json
    new = render(original, args.key, secret)
    write_private(args.file + ".prev", original)
    write_private(args.file, new)
    print(f"installed {args.key} into {os.path.basename(args.file)}; previous kept as .prev")
    return 0


if __name__ == "__main__":
    sys.exit(main())

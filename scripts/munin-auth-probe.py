#!/usr/bin/env python3
"""Prove an installed Munin credential authenticates (GRIM-249 verify step).

Reads the token from the same env file / JSON credentials file the consumer uses (never argv),
makes one authenticated `tools/list` call to Munin's /mcp, and prints ONLY the HTTP status.
Exit 0 only for HTTP 200. `principals test` only evaluates ACL rules and cannot prove a token works.

  munin-auth-probe.py --url http://127.0.0.1:3030/mcp --file /abs/path --format env  --key MUNIN_API_KEY
  munin-auth-probe.py --url https://.../mcp          --file /abs/path --format json --key auth_token
"""
import argparse
import json
import os
import stat
import sys
import urllib.error
import urllib.request

EXIT_BAD_INPUT, EXIT_DENIED, EXIT_UNREACHABLE = 2, 3, 4


def load_token(path, fmt, key):
    if not os.path.isabs(path):
        sys.exit("--file must be absolute")
    st = os.lstat(path)
    if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        sys.exit("credential file must be a regular owner-only (0600) file")
    with open(path, "rb") as fh:
        raw = fh.read().decode("utf-8")
    if fmt == "json":
        value = json.loads(raw).get(key)
    else:
        hits = [l[len(key) + 1:] for l in raw.splitlines() if l.startswith(key + "=")]
        value = hits[0] if len(hits) == 1 else None
    if not isinstance(value, str) or not value.strip():
        sys.exit("credential not found in file")
    return value.strip()


def probe(url, token, timeout=15):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except (urllib.error.URLError, OSError):
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--format", required=True, choices=("env", "json"))
    ap.add_argument("--key", required=True)
    args = ap.parse_args(argv)
    if not args.url.startswith(("http://127.0.0.1", "http://localhost", "https://")):
        print("refusing to send a credential over plain http to a non-loopback host", file=sys.stderr)
        return EXIT_BAD_INPUT
    try:
        token = load_token(args.file, args.format, args.key)
    except (OSError, ValueError, SystemExit) as exc:
        print(f"credential unreadable: {exc if isinstance(exc, SystemExit) else exc.__class__.__name__}", file=sys.stderr)
        return EXIT_BAD_INPUT
    status = probe(args.url, token)
    if status is None:
        print("unreachable", file=sys.stderr)
        return EXIT_UNREACHABLE
    print(f"HTTP {status}")
    return 0 if status == 200 else EXIT_DENIED


if __name__ == "__main__":
    sys.exit(main())

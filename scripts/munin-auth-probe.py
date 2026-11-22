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
from urllib.parse import urlsplit

EXIT_BAD_INPUT, EXIT_DENIED, EXIT_UNREACHABLE = 2, 3, 4


def load_token(path, fmt, key):
    if not os.path.isabs(path):
        sys.exit("--file must be absolute")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as fh:
        st = os.fstat(fh.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
            sys.exit("credential file must be a regular owner-only (0600) file")
        raw = fh.read().decode("utf-8")
    if fmt == "json":
        doc = json.loads(raw)
        if not isinstance(doc, dict):
            sys.exit("credential file must contain a JSON object")
        value = doc.get(key)
    else:
        hits = [l[len(key) + 1:] for l in raw.splitlines() if l.startswith(key + "=")]
        value = hits[0] if len(hits) == 1 else None
    if not isinstance(value, str) or not value.strip():
        sys.exit("credential not found in file")
    return value.strip()


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # a redirect is never followed: the token must not leave the origin


def plain_http_ok(url):
    parts = urlsplit(url)
    if parts.scheme == "https":
        return bool(parts.hostname) and parts.username is None and parts.password is None
    return (parts.scheme == "http" and parts.hostname in ("127.0.0.1", "localhost", "::1")
            and parts.username is None and parts.password is None)


def probe(url, token, timeout=15):
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}).encode()
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream"})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect)
    try:
        with opener.open(req, timeout=timeout) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code  # includes 3xx, which are never success
    except (urllib.error.URLError, OSError):
        return None


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--format", required=True, choices=("env", "json"))
    ap.add_argument("--key", required=True)
    args = ap.parse_args(argv)
    if not plain_http_ok(args.url):
        print("refusing: URL must be https, or plain http to exactly loopback, without userinfo", file=sys.stderr)
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

#!/usr/bin/env python3
"""Report credential expiry from credentials.json (metadata only, GRIM-249).

Exit codes: 0 all fine, 1 at least one credential expired / inside --warn-days /
flagged, 2 registry invalid. Never reads, prints or stores credential values.
"""
import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path

ALLOWED = {
    "id", "issuer", "consumers", "expires_at", "last_rotated_at", "max_age_days",
    "confidence", "live_source", "status", "rotate_runbook", "verify", "reversal",
}
REQUIRED = {"id", "issuer", "consumers", "rotate_runbook", "verify", "reversal"}
FLAGGED_STATUS = {"reported-expired", "no-rotation-path"}
DEFAULT = str(Path(__file__).resolve().parent.parent / "credentials.example.json")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Value-shaped content that must never appear in a metadata registry.
VALUE_SHAPES = [
    re.compile(r"-----BEGIN"),
    re.compile(r"\b(?:sk-|ghp_|gho_|github_pat_|glpat-|xox[abps]-|AKIA)[A-Za-z0-9_-]{12,}"),
    re.compile(r"(?:[0-9A-Fa-f]{2}:){7,}[0-9A-Fa-f]{2}"),
    re.compile(r"\b[\w-]+\.(?:local|lan|internal|ts\.net|invalid)\b"),
    re.compile(r"(?:^|[\s(])(?:~/|/srv/|/root/|/etc/|/var/|/opt/)"),
    re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"),
    re.compile(r"(?:/home/|/Users/)"),
]


def looks_like_secret(text):
    """Long random-looking run: 32+ token chars mixing digits with letters."""
    for run in re.findall(r"[A-Za-z0-9+/_=-]{32,}", text):
        if re.search(r"\d", run) and re.search(r"[A-Za-z]", run) and not re.search(r"-[a-z]{3,}-", run):
            return True
    return False


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)
    elif isinstance(value, dict):
        for k, v in value.items():
            yield from strings(k)
            yield from strings(v)


STATUS = {"planned", "reported-expired", "no-rotation-path"}
CONFIDENCE = {"verified", "reported"}
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")
TOP = {"schema_version", "note", "credentials"}


def parse_date(text):
    try:
        return dt.date.fromisoformat(text) if DATE.fullmatch(text) else None
    except ValueError:
        return None


def validate(doc):
    """Return error strings. Never echoes rejected content (index only)."""
    if not isinstance(doc, dict):
        return ["document root must be an object"]
    errors = []
    for key in doc:
        if key not in TOP:
            errors.append("unknown top-level field")
    if doc.get("schema_version") != "v1":
        errors.append("schema_version must be v1")
    if looks_secret_doc(doc.get("note", "")):
        errors.append("note: value-shaped content rejected")
    creds = doc.get("credentials")
    if not isinstance(creds, list) or not creds:
        return errors + ["credentials must be a non-empty list"]
    seen = set()
    for i, c in enumerate(creds):
        tag = f"entry {i}"
        if not isinstance(c, dict):
            errors.append(f"{tag}: must be an object")
            continue
        for key in c:
            if key not in ALLOWED:
                errors.append(f"{tag}: field not allowed (metadata only)")
        for key in REQUIRED - set(c):
            errors.append(f"{tag}: missing '{key}'")
        cid = c.get("id")
        if not (isinstance(cid, str) and SAFE_ID.fullmatch(cid)):
            errors.append(f"{tag}: id must match [a-z0-9-]{{1,48}}")
        elif cid in seen:
            errors.append(f"{tag}: duplicate id")
        else:
            seen.add(cid)
        for key in ("issuer", "rotate_runbook", "verify", "reversal", "live_source"):
            if key in c and not (isinstance(c[key], str) and c[key].strip()):
                errors.append(f"{tag}: {key} must be a non-empty string")
        cons = c.get("consumers")
        if not (isinstance(cons, list) and cons and all(isinstance(x, str) and x for x in cons)):
            errors.append(f"{tag}: consumers must be a non-empty list of strings")
        for key in ("expires_at", "last_rotated_at"):
            if key in c and not (isinstance(c[key], str) and parse_date(c[key])):
                errors.append(f"{tag}: {key} must be a valid YYYY-MM-DD date")
        if "max_age_days" in c and not (type(c["max_age_days"]) is int and 1 <= c["max_age_days"] <= 3650):
            errors.append(f"{tag}: max_age_days must be an integer 1-3650")
        if "status" in c and c["status"] not in STATUS:
            errors.append(f"{tag}: unknown status")
        if "confidence" in c and c["confidence"] not in CONFIDENCE:
            errors.append(f"{tag}: unknown confidence")
        if looks_secret_doc(c):
            errors.append(f"{tag}: value-shaped content rejected")
    return errors


def looks_secret_doc(value):
    return any(looks_like_secret(t) or any(p.search(t) for p in VALUE_SHAPES) for t in strings(value))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--registry", help="path to the real registry (default: $CRED_REGISTRY, else the public example)")
    ap.add_argument("--warn-days", type=int, default=30)
    ap.add_argument("--today", help="YYYY-MM-DD (tests)")
    ap.add_argument("--validate-only", action="store_true")
    args = ap.parse_args(argv)
    try:
        doc = json.loads(Path(args.registry or os.environ.get("CRED_REGISTRY", DEFAULT)).read_text())
    except (OSError, ValueError) as exc:
        print(f"registry unreadable: {exc.__class__.__name__}", file=sys.stderr)
        return 2
    errors = validate(doc)
    if errors:
        for e in errors:
            print(f"INVALID: {e}", file=sys.stderr)
        return 2
    if args.validate_only:
        return 0
    today = parse_date(args.today) if args.today else dt.date.today()
    if today is None:
        print("--today must be YYYY-MM-DD", file=sys.stderr)
        return 2
    rows, bad = [], False
    for c in doc["credentials"]:
        days = None
        if "expires_at" in c:
            days = (parse_date(c["expires_at"]) - today).days
        if "expires_at" not in c and "max_age_days" in c and "last_rotated_at" in c:
            due = parse_date(c["last_rotated_at"]) + dt.timedelta(days=c["max_age_days"])
            days = (due - today).days
        if days is not None and days < 0:
            state = "EXPIRED"
        elif days is not None and days <= args.warn_days:
            state = "EXPIRING"
        elif c.get("status") in FLAGGED_STATUS:
            state = c["status"].upper()
        elif c.get("status") == "planned":
            state = "PLANNED"
        elif days is None:
            state = "NO-EXPIRY"
        else:
            state = "ok"
        if days is None and state == "NO-EXPIRY":
            state = "UNTRACKED"  # no expiry or max age: cannot be shown green
        if state not in ("ok", "PLANNED"):
            bad = True
        conf = c.get("confidence", "-")
        rows.append((days if days is not None else 10**9, c["id"], state, days, conf))
    rows.sort()
    print(f"{'CREDENTIAL':38} {'STATE':18} {'DAYS':>6} CONFIDENCE")
    for _, cid, state, days, conf in rows:
        print(f"{cid:38} {state:18} {'-' if days is None else days:>6} {conf}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

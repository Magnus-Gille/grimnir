#!/usr/bin/env python3
"""Metadata-only secret scan with a deliberately finite Gitleaks allowlist subset.

Python 3.11+ is required for the standard-library TOML parser. Unsupported
configuration fails coverage; it never becomes an empty or broader policy.
"""

import json
from pathlib import Path
import re
import sys


class ScanError(Exception):
    """Safe diagnostic: never include source bytes or parser exception text."""


def finite_values(pattern):
    """Expand only literals, finite character sets and (?:a|b) alternatives.

    No wildcards, repetition, ranges, assertions or regex execution. Limits
    bound work even for a hostile checked-in configuration.
    """
    if not isinstance(pattern, str) or not pattern or len(pattern) > 1024:
        raise ScanError("invalid allowlist pattern")
    if pattern.startswith("^"):
        pattern = pattern[1:]
    if pattern.endswith("$"):
        pattern = pattern[:-1]
    position = 0

    def sequence(depth=0):
        nonlocal position
        if depth > 8:
            raise ScanError("allowlist nesting limit")
        values = {""}
        while position < len(pattern) and pattern[position] not in "|)":
            char = pattern[position]
            position += 1
            if char == "\\":
                if position == len(pattern) or pattern[position] not in r".\[](){}*+?^$|-":
                    raise ScanError("unsupported allowlist escape")
                choices = {pattern[position]}
                position += 1
            elif char == "[":
                end = pattern.find("]", position)
                chars = pattern[position:end] if end >= 0 else ""
                if not chars or any(c in r"-^\[" for c in chars):
                    raise ScanError("unsupported allowlist character set")
                choices = set(chars)
                position = end + 1
            elif char == "(" and pattern[position:position + 2] == "?:":
                position += 2
                choices = sequence(depth + 1)
                while position < len(pattern) and pattern[position] == "|":
                    position += 1
                    choices |= sequence(depth + 1)
                    if len(choices) > 256:
                        raise ScanError("allowlist expansion limit")
                if position == len(pattern) or pattern[position] != ")":
                    raise ScanError("invalid allowlist group")
                position += 1
            elif char in ".*+?{}()^$]" or ord(char) < 32:
                raise ScanError("unsupported broad allowlist pattern")
            else:
                choices = {char}
            if len(values) * len(choices) > 256:
                raise ScanError("allowlist expansion limit")
            values = {a + b for a in values for b in choices}
        return values

    result = sequence()
    if position != len(pattern) or "" in result:
        raise ScanError("invalid allowlist expression")
    return result


def read_bytes(path):
    # Check mode too: privileged test runners must not silently accept mode000.
    if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o444 == 0:
        raise ScanError("unreadable source or configuration")
    return path.read_bytes()


def load_allowlists(root, tracked):
    if ".gitleaks.toml" not in tracked:
        return []
    try:
        import tomllib
    except ImportError:
        raise ScanError("Python 3.11+ required for tracked allowlist") from None
    try:
        raw_config = read_bytes(root / ".gitleaks.toml")
        if len(raw_config) > 1024 * 1024:
            raise ScanError("allowlist configuration size limit")
        config = tomllib.loads(raw_config.decode("utf-8"))
    except (ValueError, UnicodeError):
        raise ScanError("invalid allowlist TOML") from None
    if set(config) - {"title", "extend", "allowlists"}:
        raise ScanError("unsupported allowlist configuration")
    if "extend" in config and config["extend"] != {"useDefault": True}:
        raise ScanError("unsupported allowlist extension")
    entries = config.get("allowlists", [])
    if not isinstance(entries, list) or len(entries) > 128:
        raise ScanError("invalid allowlist collection")
    policies = []
    total_values = 0
    total_paths = 0
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) - {
            "description", "regexTarget", "regexes", "condition", "paths"
        }:
            raise ScanError("unsupported allowlist fields")
        target = entry.get("regexTarget", "secret")
        if target not in ("secret", "match"):
            raise ScanError("unsupported allowlist target")
        patterns = entry.get("regexes")
        if not isinstance(patterns, list) or not 0 < len(patterns) <= 128:
            raise ScanError("exact allowlist values required")
        values = set()
        for pattern in patterns:
            values |= finite_values(pattern)
            if len(values) > 4096:
                raise ScanError("allowlist value limit")
        total_values += len(values)
        if total_values > 4096:
            raise ScanError("allowlist value limit")
        paths = entry.get("paths")
        if entry.get("condition", "OR") not in ("AND", "OR"):
            raise ScanError("unsupported allowlist condition")
        # A path alone must never suppress a credential. Require an explicit
        # conjunction and exact paths whenever a path restriction is present.
        if paths is not None:
            if entry.get("condition") != "AND" or not isinstance(paths, list) or not 0 < len(paths) <= 128:
                raise ScanError("path allowlists require exact values AND paths")
            exact_paths = set()
            for pattern in paths:
                if not isinstance(pattern, str) or not pattern.startswith("^") or not pattern.endswith("$"):
                    raise ScanError("allowlist paths must be anchored")
                exact_paths |= finite_values(pattern)
                if len(exact_paths) > 4096:
                    raise ScanError("allowlist path limit")
            paths = exact_paths
            total_paths += len(paths)
            if total_paths > 4096:
                raise ScanError("allowlist path limit")
        policies.append((target, values, paths))
    return policies


def allowed(candidate, category, relative, policies):
    for target, values, paths in policies:
        value = candidate.removeprefix("Bearer ") if target == "secret" and category == "bearer-token" else candidate
        # Scan configuration too. Only its explicitly parsed exact values may
        # be suppressed there; comments/other contents receive normal scanning.
        if value in values and (paths is None or relative in paths or relative == ".gitleaks.toml"):
            return True
    return False


def scan(root, tracked_path, patterns_path, repo):
    tracked = read_bytes(tracked_path).decode("utf-8").splitlines()
    policies = load_allowlists(root, tracked)
    patterns = []
    for line in read_bytes(patterns_path).decode("utf-8").splitlines():
        expression, category = line.split("\t")
        patterns.append((re.compile(expression), category))
    findings = []
    extensions = {".png", ".jpg", ".jpeg", ".gif", ".ico", ".woff", ".woff2", ".ttf", ".eot",
                  ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".map"}
    for relative in tracked:
        if not relative or Path(relative).is_absolute() or ".." in Path(relative).parts:
            raise ScanError("unsafe tracked path")
        if ".env.example" in relative or Path(relative).suffix in extensions or relative.endswith(".min.js"):
            continue
        data = read_bytes(root / relative)
        if b"\0" in data:
            continue
        for number, line in enumerate(data.decode("utf-8").splitlines(), 1):
            for expression, category in patterns:
                for match in expression.finditer(line):
                    start, end = match.span()
                    # Fixed-length patterns must not allow a longer credential
                    # just because its prefix equals an allowlisted test token.
                    while start and re.match(r"[A-Za-z0-9_-]", line[start - 1]):
                        start -= 1
                    while end < len(line) and re.match(r"[A-Za-z0-9_./+=:-]", line[end]):
                        end += 1
                    if not allowed(line[start:end], category, relative, policies):
                        findings.append({"repo": repo, "file": relative, "line": number, "category": category})
                        break  # one finding per category/line, as before
    return findings


def main():
    try:
        root, tracked, patterns, repo = sys.argv[1:]
        findings = scan(Path(root), Path(tracked), Path(patterns), repo)
    except ScanError as error:
        print(f"secret scan: {error}", file=sys.stderr)
        return 1
    except (OSError, ValueError, UnicodeError, TypeError, re.error):
        print("secret scan: source/configuration read or validation failed", file=sys.stderr)
        return 1
    print(json.dumps(findings))
    return 0


if __name__ == "__main__":
    sys.exit(main())

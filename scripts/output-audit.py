#!/usr/bin/env python3
"""Frozen, reproducible audit of owner+AI output over a date window.

Single source of truth for the team-equivalent assessment (debate/team-equivalent-6mo-*).
Emits a manifest with per-repo HEAD SHAs so the corpus can be re-derived exactly.

Usage:  python3 scripts/output-audit.py [--root ~/repos] [--since 2026-01-12] [--until 2026-07-13]
"""
import argparse, collections, hashlib, os, re, subprocess, sys, json

# --- identity sets (author email -> class) -----------------------------------
# Loaded from a local, untracked config: this repo is public, and the owner's git
# identities include a former personal address that must not be published here.
# See output-audit-identities.example.json; copy it and fill in the real addresses.
IDENTITIES_PATH = os.environ.get(
    "OUTPUT_AUDIT_IDENTITIES",
    os.path.expanduser("~/.config/grimnir/output-audit-identities.json"))

try:
    _ids = json.load(open(IDENTITIES_PATH))
except OSError:
    sys.exit(f"missing identity config: {IDENTITIES_PATH}\n"
             f"copy scripts/output-audit-identities.example.json and fill it in, "
             f"or set OUTPUT_AUDIT_IDENTITIES")

OWNER = set(_ids["owner"])   # all of the owner's git identities, incl. historical ones
AGENT = set(_ids["agent"])   # AI agents committing on the owner's behalf
CI = set(_ids["ci"])         # dependabot, github-actions, flux, etc.

# Upstream forks / other people's repos: excluded only if they have 0 owner commits in window.
# (No hardcoded exclusion list — the filter is empirical.)

SRC = {".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".c", ".h", ".cpp", ".swift", ".sh",
       ".lua", ".java", ".kt", ".rb", ".php", ".sql", ".vue", ".svelte", ".mjs", ".cjs"}
DOC = {".md", ".rst"}
VENDORED = re.compile(
    r"(^|/)(node_modules|dist|build|\.next|vendor|target|__pycache__|coverage|\.venv|venv|third_party)/"
    r"|\.min\.(js|css)$|\.map$")


def git(repo, *args, timeout=180):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                          timeout=timeout).stdout


def classify(email):
    if email in OWNER: return "owner"
    if email in AGENT:  return "agent"
    if email in CI:     return "ci"
    return "other_human"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.expanduser("~/repos"))
    ap.add_argument("--since", default="2026-01-12")
    ap.add_argument("--until", default="2026-07-13")  # exclusive upper bound
    args = ap.parse_args()
    os.chdir(args.root)

    # Only true repos: a git *worktree* has .git as a FILE, and would double-count its parent's tree.
    repos = sorted(d for d in os.listdir(".") if os.path.isdir(os.path.join(d, ".git")))

    # --- commits: global SHA dedup, so one commit counts once across all checkouts ---
    seen, per_repo, dup = set(), {}, collections.Counter()
    for r in repos:
        ents = [l.split("|", 1) for l in
                git(r, "log", f"--since={args.since}", f"--until={args.until}", "--format=%H|%ae",
                    "HEAD").splitlines() if "|" in l]
        c = collections.Counter()
        for sha, email in ents:
            if sha in seen:
                dup[r] += 1
                continue
            seen.add(sha)
            c[classify(email)] += 1
        if sum(c.values()):
            per_repo[r] = c

    mine = {r: c for r, c in per_repo.items() if c["owner"] > 0}
    totals = collections.Counter()
    for c in mine.values():
        totals.update(c)

    # --- standing artifact: byte-identical blobs deduped across repos ---
    blobs, src_lines, doc_lines, dup_lines = {}, 0, 0, 0
    for r in mine:
        for f in git(r, "ls-files").splitlines():
            if VENDORED.search(f):
                continue
            ext = os.path.splitext(f)[1].lower()
            if ext not in SRC and ext not in DOC:
                continue
            try:
                data = open(os.path.join(r, f), "rb").read()
            except OSError:
                continue
            n = data.count(b"\n") + (1 if data and not data.endswith(b"\n") else 0)
            h = hashlib.sha1(data).hexdigest()
            if h in blobs:
                dup_lines += n
                continue
            blobs[h] = r
            if ext in SRC: src_lines += n
            else:          doc_lines += n

    manifest = {
        "window": {"since": args.since, "until_exclusive": args.until, "calendar_dates": 182},
        "method": {
            "dedup": "global SHA set across all checkouts; git worktrees excluded (.git is a file)",
            "authorship": "commit author email matched against explicit identity sets",
            "artifact": "current HEAD, vendored/generated paths excluded, byte-identical blobs deduped",
        },
        "repos": {r: {"head": git(r, "rev-parse", "HEAD").strip(), **dict(c)}
                  for r, c in sorted(mine.items())},
        "duplicate_commits_skipped": dict(dup),
        "totals": {
            "repos_with_owner_commits": len(mine),
            "commits": dict(totals),
            "commits_total": sum(totals.values()),
            "owner_plus_ai_share": round((totals["owner"] + totals["agent"]) / sum(totals.values()), 4),
            "standing_source_lines": src_lines,
            "standing_doc_lines": doc_lines,
            "standing_total_lines": src_lines + doc_lines,
            "cross_repo_duplicate_lines_removed": dup_lines,
        },
    }
    json.dump(manifest, sys.stdout, indent=2)
    print()
    t = manifest["totals"]
    print(f"\n# repos={t['repos_with_owner_commits']}  commits={t['commits_total']} "
          f"(owner={totals['owner']} agent={totals['agent']} ci={totals['ci']} "
          f"other_human={totals['other_human']})", file=sys.stderr)
    print(f"# Owner+AI share={t['owner_plus_ai_share']:.1%}  "
          f"standing={t['standing_total_lines']:,} lines "
          f"(src={src_lines:,} docs={doc_lines:,}; {dup_lines:,} dup lines removed)", file=sys.stderr)


if __name__ == "__main__":
    main()

# GitHub Project Roadmap preflight

Roadmap board access is optional for creating an owning-repository ticket. Run a
read-only check before a ticket batch:

```sh
scripts/github-project-preflight.sh preflight --owner Magnus-Gille --number 1 --require-write
```

The output is a public-safe `key=value` record. `status=ready` permits adding
items. Otherwise `class` deterministically identifies `missing_read_scope`,
`missing_write_scope`, `missing_project`, or `network_api_failure` (with an
`api_failure`/`auth_failure` fallback for other failures). The preflight uses
only `gh auth status` and `gh project view`; it never creates, edits, or adds an
item.

## Owner setup

Project inspection requires `read:project`. Creating an item requires the
write-capable `project` scope (which also permits reads). The owner refreshes
the active GitHub CLI account; no token belongs in this repository:

```sh
gh auth refresh --hostname github.com --scopes read:project,project
gh auth status
```

Confirm that `gh auth status` reports the intended **active account** and its
`Token scopes` include `read:project` for read-only use, or `project` when
items will be added. Then rerun the preflight above. A `missing_project` result
means that the requested owner/project number cannot be read by that account,
not that a ticket should be withheld.

## Creating tickets without blocking on the board

For a standard issue creation plus best-effort board addition:

```sh
scripts/github-project-preflight.sh ticket \
  --repo Magnus-Gille/brokkr --title 'Example' --body-file /path/to/body.md \
  --label from:grimnir --owner Magnus-Gille --number 1
```

The issue is created first. If Project access is unavailable, or the subsequent
`gh project item-add` call fails, the command exits successfully after printing
`board_addition=pending`, a non-secret `board_addition_class`, and one
`pending_board_addition=<issue-url>` line per created ticket. Preserve those
lines and add them after the owner fixes scope or connectivity:

```sh
gh project item-add 1 --owner Magnus-Gille --url <issue-url>
```

This keeps the owning repository's ticket workflow usable while retaining an
explicit, auditable list of missed Roadmap additions.

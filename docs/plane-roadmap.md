# Plane tickets and the Grimnir Roadmap

Tickets and the Grimnir Roadmap live in self-hosted Plane CE
(<https://tickets.gille.ai>, workspace `gille`). This replaced GitHub Issues and the
"Grimnir Roadmap" GitHub Project (owner decision 2026-10-28). The agent contract (MCP tools,
`tix` commands, naming conventions) is `docs/agent-interface.md` in the ticket-system
repository; this page covers how Grimnir uses it.

## Where things live

- One Plane project per former GitHub repository; the identifier map is
  `migration/projects.json` in ticket-system. A ticket key is `IDENT-N`, and migrated tickets
  keep their GitHub number (`grimnir#87` is `GRIM-87`).
- A cross-repo need is a ticket in the **owning repo's** project, filed with sender
  `grimnir` (label `from:grimnir` and a `Filed by: grimnir` footer). Never edit the owning
  repo directly.
- Old GitHub issues are closed with a link to their ticket. File no new GitHub issues.
- Pull requests stay on GitHub. A PR references its ticket as `Refs GRIM-87` plus the Plane
  URL; there is no automatic PR linking, so close tickets explicitly.

## How the old Roadmap board maps to Plane

| GitHub Project 1 | Plane |
|---|---|
| Item on the board | Label `board:grimnir-roadmap` |
| Component field | Label `component:<Name>`, for example `component:Hugin` |
| Priority field | Plane priority: Critical is `urgent`, High is `high`, Medium is `medium`, Low is `low` |
| Status field | Plane state: Todo, In Progress, Done |
| Cross-project overview | `roadmap` MCP tool or `tix roadmap`, plus Plane modules per project |

The board label, component label and priority are set in the same call that creates the
ticket, so there is no separate board step that can be left pending.

Read the board with:

```sh
tix ls -l board:grimnir-roadmap -s open            # every open roadmap ticket, all projects
tix ls -l board:grimnir-roadmap -l component:Hugin # one component
tix roadmap                                        # modules and cycles across projects
```

Only the Grimnir session adds `board:grimnir-roadmap`, and only under explicit owner
authorization for that board mutation. Creating a ticket keeps the authority tier issue
creation had: reviewable publication, needing explicit owner approval where a skill or the
task requires it.

## Access

Agents use the `tickets` MCP server (`https://tickets-mcp.gille.ai/mcp`) or the `tix` CLI.
`tix` reads its token from `TIX_TOKEN` or `~/.config/tix/token` (mode 0600), never from the
command line, and no token belongs in this repository. The owner mints and revokes tokens with
`ticket-gateway token create|revoke`; an agent never does this on its own.

## Readiness check

Run a read-only check before a ticket batch:

```sh
scripts/github-project-preflight.sh preflight --repo grimnir
```

The script keeps its historical name so existing callers still work; it no longer talks to
GitHub. `preflight` runs only `tix projects` and prints a public-safe `key=value` record:
`status=ready` permits creating tickets. Otherwise `class` identifies the failure and the
exit code follows it, with tix's own message on stderr:

| class | exit | meaning |
|---|---|---|
| `missing_token` | 10 | `tix` has no usable token (`TIX_TOKEN` or `~/.config/tix/token`) |
| `missing_tix` | 11 | no `tix` executable on `PATH` (override with `TIX_BIN`) |
| `missing_project` | 12 | no Plane project matches `--repo` (repo name or identifier) |
| `network_api_failure` | 13 | the gateway is unreachable or answered 5xx |
| `api_failure` | 14 | any other API failure, including a rejected or revoked token |

Usage errors exit 2. `--owner`, `--number` and `--require-write` (the GitHub Project options)
are accepted and ignored.

## Creating tickets

```sh
scripts/github-project-preflight.sh ticket \
  --repo Magnus-Gille/brokkr --title 'Example' --body-file /path/to/body.md \
  --component Hugin --priority High --label from:grimnir
```

This makes exactly one call:

```sh
tix new -p brokkr -t Example -f /path/to/body.md \
  -l board:grimnir-roadmap -l component:Hugin --priority urgent --from grimnir
```

`--repo` takes `OWNER/REPO`, a bare repo name, or a Plane identifier. `--priority` accepts
Plane values or the old Critical, High, Medium, Low. `--label from:<sender>` is sent as
`--from <sender>`, which also adds the `Filed by` footer. Use `--no-board` for a ticket that
is not on the Roadmap. On success it prints:

```text
status=created
ticket_key=BROKKR-99
ticket_url=https://tickets.gille.ai/gille/browse/BROKKR-99/
board_label=board:grimnir-roadmap
```

On failure it prints `status=failed` and the `class` above, exits with that class's code, and
leaves tix's message on stderr. There is no `pending_board_addition` any more: the board label
travels with the create call. If a ticket was created before the cutover with a pending board
addition, add the label with `tix edit <KEY> --add-label board:grimnir-roadmap`.

The MCP equivalent is `ticket_create` with `project`, `title`, `description`, `labels`
(`board:grimnir-roadmap`, `component:<Name>`), `priority` and `from`. Convention labels
`from:*`, `board:*` and `component:*` are created on first use; any other label must already
exist in the target project (`project_meta` lists them).

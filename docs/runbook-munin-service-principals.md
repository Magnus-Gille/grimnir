# Runbook — own Munin principal for Hugin and friction-mcp (HUGIN-418)

Status: **procedure for the owner to run**. Nothing here issues, prints or stores a key.
Refs HUGIN-418, CCONF-43, HUGIN-414.

## Why

Hugin (`hugin.service`) and `friction-mcp` authenticate with the shared legacy `MUNIN_API_KEY`.
Munin resolves that static bearer to the `owner` principal and logs the client as `legacy`, so:

- their traffic cannot be told apart from other legacy-bearer clients in `access_summary`;
- they hold full owner access, far beyond what either needs;
- rotating the one key touches every consumer, and all consumers share one rate-limit bucket.

A database-managed `agent` principal (`munin-admin principals add … --type agent`) fixes all three:
own client id in the access log, namespace-scoped rules, own revocation and own rate-limit bucket.

## Constraints to respect

- Run everything below **on the Munin host, as the owner**, with the key typed or piped locally.
  Never paste a token into a chat, ticket, PR or Munin entry. Store it in the password manager and
  in a `0600` file only.
- Do not pass a token on a command line (argv is readable by every local process). Use a `0600`
  file or stdin.
- Keep the legacy bearer working until both services are verified on their own principal. The
  cut-over is per service and reversible by restoring the old env value.
- Reversal recipe for each step is given inline. Each principal change is recorded by Munin in its
  audit log.

## 1. Decide the namespace rules (do this first)

**Confirmed by Magnus Gille on 2026-11-17 (grimnir#233): the rules below are approved as the
starting set.** They were derived from the documented task contract (`docs/architecture.md`,
"Task schema": Hugin reads and writes `tasks/*` and the heartbeat `tasks/_heartbeat`), not from
Hugin's code, which was not available when this was written. The approval covers the starting
rules only: step 4 verification (`access_denied` in the Munin audit log) is what catches a
namespace Hugin actually needs that is missing here. Widen deliberately with
`principals update`, never by falling back to owner.

Approved starting rules (read/write only where needed; widen only on evidence):

| Principal | Rules |
|---|---|
| `hugin` | `tasks` rw, `tasks/*` rw, plus **read** (`r`) on any corpus namespaces the learning-loop collector walks (confirm: likely `projects/*`, `clients/*`) |
| `friction-mcp` | rw on its own friction namespace only (confirm name in the friction-mcp repo; do not grant `tasks/*`) |

A rules file is a JSON array of `pattern` + `permissions` objects (the format `--rules` takes, see
the munin-memory README). A bare namespace and its `ns/*` children are separate patterns. Example
`hugin-rules.json`, to be adjusted after the confirmation above:

```json
[
  {"pattern": "tasks", "permissions": "rw"},
  {"pattern": "tasks/*", "permissions": "rw"},
  {"pattern": "projects/*", "permissions": "r"},
  {"pattern": "clients/*", "permissions": "r"}
]
```

`friction-rules.json` has the same shape with only the friction namespace (and its `/*` children if
it writes below it) set to `rw`.

After creation (step 3), check each with `munin-admin principals test <id> <namespace>` for every
namespace Hugin is known to use.

## 2. Create the principals

```bash
cd ~/repos/munin-memory
npx munin-admin principals add hugin --type agent --rules @/path/to/hugin-rules.json
npx munin-admin principals add friction-mcp --type agent --rules @/path/to/friction-rules.json
```

The command prints each token **once**. Capture it straight into a `0600` file and the password
manager, nothing else. Set `--expires-at` if you want a forced rotation date.

Reversal: `npx munin-admin principals revoke hugin` (and `friction-mcp`).

## 3. Verify scope before switching anything

```bash
npx munin-admin principals show hugin
npx munin-admin principals test hugin tasks/x          # expect allowed
npx munin-admin principals test hugin <a namespace it must NOT touch>   # expect denied
```

## 4. Cut over Hugin

1. Put the new token where Hugin reads its Munin key (its own `.env` on the Pi, `0600`). Keep the
   old value in a backup file with `0600` until verified.
2. Restart `hugin.service`.
3. Verify (the `[munin-calls]` per-label stats Hugin logs every 5 minutes are the quickest check):
   - Munin `access_summary` shows a client for the `hugin` principal, no longer `legacy`;
   - zero `access_denied` for Hugin in the Munin audit log. Any denial means a namespace is
     missing from step 1: widen the rule with `principals update hugin --rules …`, do not fall
     back to owner;
   - a test task is claimed, runs and writes its result;
   - the Heimdall panel and learning loop still read what they need.
4. Reversal: restore the old env value and restart Hugin.

## 5. Cut over friction-mcp

Use `MUNIN_CREDENTIALS_FILE` (a `0600` JSON file) instead of an inline value in client config:

```json
{ "auth_token": "<new friction-mcp token>" }
```

Point the client config at the file path via env `MUNIN_CREDENTIALS_FILE`. The bridge refuses a
group/world-readable file. Optionally set the non-secret `MUNIN_BRIDGE_CLIENT_ID=friction-mcp`
label. Verify a friction write lands, and that `access_summary` shows the new client.

Reversal: restore the previous client config.

## 6. Close out

- Once both are verified for a day with no `legacy`/owner traffic from them, remove the legacy
  value from Hugin's and friction-mcp's configuration. The legacy bearer itself stays for other
  clients; its rotation is covered by CCONF-43.
- Add the new key locations (not values) to the password-manager entries.
- Close HUGIN-418 with the verification evidence (fingerprints/client ids only).

## Acceptance (from HUGIN-418)

`access_summary` shows Hugin under its own client id, and neither service needs the legacy bearer.

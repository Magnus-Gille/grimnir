# Grimnir conventions

## Naming

The core names are drawn from Norse mythology:

| Name | System role |
|---|---|
| Grimnir | System architecture and control-plane documentation |
| Munin | Durable memory |
| Hugin | Thought and work dispatch |
| Mimir | File archive |
| Heimdall | Monitoring and alerting |
| Brokkr | Machines, storage, patching, and recovery |

Optional integrations follow the same theme: Ratatoskr carries messages, Skuld produces future-facing
briefings, and Verdandi records current events. `gille-inference` keeps a descriptive package name so
its purpose is immediately visible outside the mythology.

Repository names are lowercase and usually match the component. Munin's repository is
`munin-memory` to distinguish it from the established Munin monitoring project.

## Configuration

- `services.json` is fictional public example data and documents the schema.
- `services.local.json` is ignored and owns a local deployment when present.
- `REGISTRY_PATH` explicitly selects another registry for automation and tests.
- `.env` files and secret-manager references provide credentials; registry files do not.

All scripts use `scripts/lib/registry.js`. Hard-coded service inventories in consumers are bugs.

## Service patterns

The current components generally use:

- Node.js with strict TypeScript where applicable;
- SQLite for single-host state;
- systemd for process and timer management;
- a bounded health endpoint for monitoring;
- explicit authentication and input limits at every consequential service boundary;
- runtime data outside the application checkout;
- reproducible installs from a committed lockfile.

These are defaults, not compatibility guarantees. A component may choose another implementation when
its public interface and operational ownership remain clear.

## Deployment

`scripts/deploy.sh` reads the selected registry, validates all records, and then uses rsync or a
controlled git pull as declared per component. Unit files in component repositories must be ready to
install; the central deployer does not render private values into tracked files.

For an alternate source worktree, pass `name=/absolute/path`, for example:

```bash
make deploy ARGS="munin-memory=/tmp/munin-memory-change"
```

The committed example registry will reject this command until a private registry is configured.

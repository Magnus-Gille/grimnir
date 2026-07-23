# Host-specific systemd runtime rendering

Registry deploys may opt a component into host-specific unit rendering with
`systemd_runtime`. This is the stabilization path for clean-install unit templates whose runtime
identity differs from the registered host. It prevents a reviewed code deployment from installing
the wrong `User=`, entering a `217/USER` loop, or silently losing a host-private listener setting.

The registry owns non-secret host facts. Secret values remain in environment files on the host.
Component repositories continue to own unit structure and may use only these placeholders on active
unit lines:

- `<user>` — `systemd_runtime.user`
- `<home>` — `systemd_runtime.home`
- `<deploy-path>` — `systemd_runtime.deploy_target`
- `<install-dir>` — basename of `deploy_target`, retained for existing clean-install templates

Any other active placeholder fails closed.

## Registry contract

```json
{
  "deploy_path": "/home/example/service",
  "persistent_paths": ["/home/example/.service"],
  "systemd_runtime": {
    "user": "example",
    "home": "/home/example",
    "deploy_target": "/home/example/service",
    "environment_files": ["/home/example/.service/env"],
    "sandbox_paths": ["/home/example/.ssh/service_read_only"]
  },
  "health_check": {
    "boundary": "network",
    "paths": ["/health"]
  }
}
```

`deploy_target` deliberately duplicates `deploy_path`: registry validation requires exact equality,
so a unit cannot be rendered against one tree while rsync mutates another. `environment_files`
lists required private-environment file paths, never their contents. Each file must already exist,
must not be a symlink, and must be referenced by the rendered service without systemd's optional
`-` prefix. Each path must be inside the deploy target or a declared `persistent_paths` root.
Global rsync policy continues to exclude `.env`.

`sandbox_paths` lists exact external dependencies that path-bearing sandbox directives may use,
such as a read-only key or another component's data directory. Declaring one does not claim that
the opting-in component owns or persists it, does not authorize descendants, and never grants
write access. Exact external paths are accepted only by `ReadOnlyPaths=`, `BindReadOnlyPaths=`, or
`InaccessiblePaths=`. The deploy target and declared persistent paths remain authorized roots, so
directives may reference paths within either tree.

`health_check.boundary` is:

- `host` — probe from the target host. This retains the legacy behaviour and is appropriate only
  when loopback/host-local reachability is the real consumer boundary.
- `network` — probe `http://<registered host>:<registered port><path>` from the deploy client after
  restart and before acceptance. Use this when another node must reach the listener; a loopback-only
  bind cannot pass this gate.

## Deployment and preflight order

For an opted-in rsync component, `scripts/deploy.sh` performs these phases:

1. Validate the complete registry and the selected local unit templates.
2. Invalidate `.deployed-commit`, then sync code and install dependencies.
3. Stream the reviewed Grimnir renderer to the host. It renders every declared unit into a
   temporary directory and preflights every service before installing any rendered unit.
4. Verify the runtime account exists and its passwd home matches the registry.
5. Require `WorkingDirectory=` to equal the deploy target; verify `ExecStart` executables and
   absolute arguments; require declared environment files; and reject unregistered or missing
   sandbox paths.
6. Snapshot every prior installed unit as `<unit>.grimnir-previous`, then install all rendered
   units. If any copy fails, restore every unit already replaced and return before daemon reload.
   Otherwise reload systemd, restart, and verify controller state.
7. Run the declared host- or network-boundary health probe.
8. Write `.deployed-commit` only after every gate succeeds.

A render or preflight failure happens after marker invalidation but before restart. The target is
therefore deliberately markerless, and the previously running process is not restarted. A later
restart or health failure is also markerless.

## Migration from raw units

Migrate one component at a time:

1. On the target, inventory the effective unit and drop-ins with `systemctl cat <unit>`. Record
   paths and variable names, but do not copy secret values into git, issue comments, or logs.
2. Ensure private runtime values live in a host-owned environment file that rsync preserves.
3. In the owning component repo, replace only host identity/path literals with the supported
   placeholders. Keep component logic and systemd policy in that repo.
4. Add `systemd_runtime` and an explicit `health_check` to `services.json`. Register every required
   environment file and sandbox root; do not guess unknown host values.
5. Run `make test`, then perform a selective deployment. Confirm the health probe uses the consumer
   boundary and that the new accepted marker matches the reviewed commit.
6. After one healthy deployment and rollback-window observation, the
   `.grimnir-previous` snapshot may be removed manually.

Components without `systemd_runtime` retain the install-ready, byte-for-byte unit contract. This
keeps migration explicit and avoids silently assigning host identities.

### Heimdall migration dependency

Heimdall is the incident-owning component and the first registry opt-in. The Grimnir registry
change must not be deployed on its own: Heimdall's canonical templates currently hardcode
`User=heimdall` and `/home/heimdall`, which no bounded placeholder renderer can safely reinterpret.
A companion PR in the Heimdall repository must first replace those host literals with the supported
placeholders. Merge and deploy that owning-repository template change before selectively deploying
Heimdall through this contract. The required companion is
[Heimdall PR #14](https://github.com/Magnus-Gille/heimdall/pull/14), reviewed here at exact head
`6748365d92192fa267ef69c48716c9e6f0940e57`. Grimnir PR #110 remains draft and
deployment-blocked until the owning-repository change is green, reviewed, and merged first.

## Rollback

The deploy log reports the prior accepted commit before mutation.

- If render/preflight fails, do not restart: the old process is still running. Correct the registry
  or template and redeploy; the target remains markerless until acceptance.
- If one unit copy fails during a multi-unit install, the renderer restores every unit it already
  replaced and exits before daemon reload. An explicit incomplete-rollback error means the
  destinations must be inspected manually before any reload.
- If a rendered unit was installed and restart/health later fails, restore
  `<unit>.grimnir-previous` to the original unit path, run the appropriate daemon reload and restart,
  and verify the same declared health boundary. For system units use `sudo`; for user units use
  `systemctl --user`.
- Restore `.deployed-commit` to the captured prior SHA only after the restored service passes its
  controller and health gates. If the prior unit snapshot or prior SHA is unknown, leave the marker
  absent and treat live state as unknown.
- Reverting this feature in git does not itself repair a host. A rollback must restore the host unit
  and health first; otherwise the next raw-unit deployment can recreate the incident.

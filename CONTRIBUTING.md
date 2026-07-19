# Contributing

Grimnir is a collection of independently owned services. Before changing code, identify the owning
repository:

- architecture, registry schema, deployment orchestration, or cross-service contracts: **Grimnir**
- memory: **Munin Memory**
- files: **Mimir**
- work dispatch and gating: **Hugin**
- local model gateway: **gille-inference**
- monitoring: **Heimdall**
- hosts, storage, patching, and backups: **Brokkr**

For Grimnir changes:

1. Fork the repository and work on a branch.
2. Keep examples fictional. Never add live addresses, logs, user data, credentials, recovery material,
   or private operational state.
3. Add or update regression tests for behavioral changes.
4. Run `make test` and, for shell changes, `shellcheck scripts/*.sh scripts/lib/*.sh scripts/tests/*.sh`.
5. Explain affected trust boundaries and rollback behavior in the pull request.

By contributing, you agree that your contribution is licensed under the MIT License.

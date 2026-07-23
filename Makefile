.PHONY: docs clean security security-dry deploy test-security-skip test-security-delta test-security-completeness test-munin-rpc test-registry-smoke test-deploy-source-revision test-deploy-persistent-paths test-deploy-systemd-render test-failure-recovery-doc test-learning-task-contract-doc test-registry-checkout test-systemd-status test-runtime-state test-worktree-hygiene test

docs: ## Generate full architecture document
	@./scripts/generate-architecture.sh

security: ## Run security scan across all Grimnir repos
	@./scripts/security-scan.sh

security-dry: ## Run security scan (dry run, no Munin writes)
	@./scripts/security-scan.sh --dry-run

deploy: ## Deploy bound sources (ARGS="service=/absolute/worktree@FULL_COMMIT_SHA [...]")
	@./scripts/deploy.sh $(ARGS)

test-security-skip: ## Regression test: assert security-scan skips test/eval fixtures (issue #22)
	@bash tests/scripts/test-security-scan-skip.sh

test-security-delta: ## Unit tests for the scan_escalated/parse_prev_counts helpers
	@bash scripts/tests/security-scan-delta.test.sh

test-security-completeness: ## Fail closed when npm audit or repository coverage is incomplete
	@bash scripts/tests/security-scan-completeness.test.sh

test-munin-rpc: ## Reject HTTP, JSON-RPC, and MCP tool errors from scheduled writes
	@bash scripts/tests/munin-rpc.test.sh

test-registry-smoke: ## Schema/consistency smoke check for services.json (issue #48)
	@bash scripts/tests/registry-smoke.test.sh

test-deploy-source-revision: ## Bind every deploy source to an explicit immutable revision (issue #114)
	@bash scripts/tests/deploy-source-revision.test.sh

test-deploy-persistent-paths: ## Fail closed before rsync can delete an in-target runtime path
	@bash scripts/tests/deploy-persistent-paths.test.sh

test-deploy-systemd-render: ## Render and preflight host-specific systemd runtime identity (issue #107)
	@bash scripts/tests/deploy-systemd-render.test.sh

test-failure-recovery-doc: ## Regression test: assert docs/failure-recovery.md defines the undo convention (issue #46)
	@bash tests/scripts/test-failure-recovery-doc.sh

test-learning-task-contract-doc: ## Regression test: assert the learning seam and improvement-scope contract (issue #86)
	@bash tests/scripts/test-learning-task-contract-doc.sh

test-registry-checkout: ## Unit tests for the registry-checkout integrity helpers (issue #47)
	@bash scripts/tests/registry-checkout.test.sh

test-systemd-status: ## Scope-aware local/remote systemd status checks (issue #63)
	@bash scripts/tests/systemd-status.test.sh

test-runtime-state: ## Desired runtime and deployment-state validation (issue #109)
	@bash scripts/tests/runtime-state.test.sh

test-worktree-hygiene: ## Unit + fixture tests for the worktree/deploy hygiene audit (issue #87)
	@bash scripts/tests/worktree-hygiene.test.sh

test: test-security-skip test-security-delta test-security-completeness test-munin-rpc test-registry-smoke test-deploy-source-revision test-deploy-persistent-paths test-deploy-systemd-render test-failure-recovery-doc test-learning-task-contract-doc test-registry-checkout test-systemd-status test-runtime-state test-worktree-hygiene ## Run all test suites

clean: ## Remove generated docs
	rm -f docs/snapshot.md docs/full-architecture.md

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

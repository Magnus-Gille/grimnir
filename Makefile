.PHONY: docs clean security security-dry deploy test-autonomy-contract test-autonomy-contract-v2 test-autonomy-contract-doc test-autonomy-owner-authorization test-security-skip test-security-delta test-security-completeness test-security-namespace test-munin-rpc test-registry-smoke test-placement-validation test-portability-acceptance test-deploy-source-revision test-deploy-persistent-paths test-deploy-systemd-render test-deploy-unit-target-guard test-failure-recovery-doc test-cross-service-contract-doc test-fleet-seam-audit-2026-07-26 test-learning-task-contract-doc test-node-substrate-contract test-network-operating-model test-node-substrate-contract-doc test-maintenance-policy-contract test-maintenance-policy-contract-doc test-system-roi-ledger test-registry-checkout test-systemd-status test-runtime-state test-worktree-hygiene test-validate-exit test-validation-evidence test-claude-capacity-preflight test-github-project-preflight test-github-actions-policy test-github-actions-zero-step-preflight test-validation-staleness-evidence-doc test-doc-index test-architecture-component-table test-architecture-component-table-regression test-instruction-eval-sandbox test-skills-eval-sandbox test-telemetry-strategy-doc test

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

test-security-namespace: ## Keep security scan writes in canonical Munin namespaces (issue #98)
	@bash scripts/tests/security-scan-namespace.test.sh

test-munin-rpc: ## Reject HTTP, JSON-RPC, and MCP tool errors from scheduled writes
	@bash scripts/tests/munin-rpc.test.sh

test-registry-smoke: ## Schema/consistency smoke check for services.json (issue #48)
	@bash scripts/tests/registry-smoke.test.sh

test-placement-validation: ## Compare declared placement with explicit Brokkr evidence (issue #103)
	@node tests/scripts/validate-placement.test.mjs

test-portability-acceptance: ## Validate evidence-honest NAS and Hugin portability pilots (issue #104)
	@node tests/scripts/validate-portability-acceptance.mjs

test-deploy-source-revision: ## Bind every deploy source to an explicit immutable revision (issue #114)
	@bash scripts/tests/deploy-source-revision.test.sh

test-deploy-persistent-paths: ## Fail closed before rsync can delete an in-target runtime path
	@bash scripts/tests/deploy-persistent-paths.test.sh

test-deploy-systemd-render: ## Render and preflight host-specific systemd runtime identity (issue #107)
	@bash scripts/tests/deploy-systemd-render.test.sh

test-deploy-unit-target-guard: ## Fail closed before restart when a unit's WorkingDirectory/EnvironmentFile contradicts deploy_path (issue #146)
	@bash scripts/tests/deploy-unit-target-guard.test.sh

test-failure-recovery-doc: ## Regression test: assert docs/failure-recovery.md defines the undo convention (issue #46)
	@bash tests/scripts/test-failure-recovery-doc.sh

test-cross-service-contract-doc: ## Regression test: retain named cross-service contract owners and migration rules (issue #7)
	@bash tests/scripts/test-cross-service-contract-doc.sh

test-fleet-seam-audit-2026-07-26: ## Regression test: retain bounded evidence record for issue #79
	@bash tests/scripts/test-fleet-seam-audit-2026-07-26.sh

test-learning-task-contract-doc: ## Regression test: assert the learning seam and improvement-scope contract (issue #86)
	@bash tests/scripts/test-learning-task-contract-doc.sh

test-node-substrate-contract-doc: ## Regression test: assert the Node/Substrate authority boundary (issue #101)
	@bash tests/scripts/test-node-substrate-contract-doc.sh

test-node-substrate-contract: ## Validate the node/substrate v1 schemas and hermetic fixtures (issue #102)
	@node tests/scripts/validate-node-substrate-contract.mjs

test-maintenance-policy-contract: ## Validate the maintenance-policy v1 schema, DST/digest/decision fixtures (issue #134)
	@node tests/scripts/validate-maintenance-policy-contract.mjs

test-maintenance-policy-contract-doc: ## Regression test: assert the maintenance-policy intent/DST/digest contract (issue #134)
	@bash tests/scripts/test-maintenance-policy-contract-doc.sh

test-system-roi-ledger: ## Validate evidence status and provenance in the monthly system ROI ledger (issue #67)
	@node tests/scripts/test-system-roi-ledger.mjs

test-network-operating-model: ## Regression test: assert the NAS/control network operating policy (issue #12)
	@bash scripts/tests/network-operating-model.test.sh

test-registry-checkout: ## Unit tests for the registry-checkout integrity helpers (issue #47)
	@bash scripts/tests/registry-checkout.test.sh

test-systemd-status: ## Scope-aware local/remote systemd status checks (issue #63)
	@bash scripts/tests/systemd-status.test.sh

test-runtime-state: ## Desired runtime and deployment-state validation (issue #109)
	@bash scripts/tests/runtime-state.test.sh

test-worktree-hygiene: ## Unit + fixture tests for the worktree/deploy hygiene audit (issue #87)
	@bash scripts/tests/worktree-hygiene.test.sh

test-github-actions-policy: ## Enforce immutable Action pins, provenance, and approved runtimes (issue #139)
	@node tests/scripts/test-github-actions-policy.mjs

test-claude-capacity-preflight: ## Classify cheap Claude probe failures and preserve deterministic fallback (issue #136)
	@bash scripts/tests/claude-capacity-preflight.test.sh

test-github-project-preflight: ## Classify GitHub Project scopes, absence, and API failures (issue #135)
	@bash scripts/tests/github-project-preflight.test.sh

test-github-actions-zero-step-preflight: ## Distinguish runner startup failures from workflow-step failures (issue #138)
	@bash scripts/tests/github-actions-zero-step-preflight.test.sh

test-validate-exit: ## Unit tests for the audit exit-status contract (findings vs. audit failure)
	@bash scripts/tests/validate-exit.test.sh

test-validation-evidence: ## Immutable per-run validator evidence and trigger contract (issue #159)
	@bash scripts/tests/validation-evidence.test.sh

test-doc-index: ## Guard progressive-disclosure index completeness and retained constraints (issue #143)
	@bash tests/scripts/test-doc-index.sh

test-architecture-component-table: ## Keep the architecture overview's registry-derived facts current (issue #5)
	@bash tests/scripts/test-architecture-component-table.sh

test-architecture-component-table-regression: ## Keep the architecture overview guard fail-closed (issue #5)
	@bash tests/scripts/test-architecture-component-table-regression.sh

test-instruction-eval-sandbox: ## Pin the read-only Claude evaluator sandbox (issue #143)
	@bash tests/scripts/test-instruction-eval-sandbox.sh

test-validation-staleness-evidence-doc: ## Preserve the evidence boundary for Git sync cadence (issue #2)
	@bash tests/scripts/test-validation-staleness-evidence-doc.sh

test-skills-eval-sandbox: ## Pin the skill-description evaluator sandbox (issue #145)
	@bash tests/scripts/test-skills-eval-sandbox.sh

test-telemetry-strategy-doc: ## Preserve the telemetry boundary and legacy journal-analysis retirement path (issue #6)
	@bash tests/scripts/test-telemetry-strategy-doc.sh

test-autonomy-contract: ## Validate the W0 autonomy constitution, journal, registry and fixtures (issue #170)
	@node tests/scripts/validate-autonomy-contract.mjs

test-autonomy-contract-v2: ## Validate the reachable W0.2 timing epoch while preserving v1 (issue #174)
	@node tests/scripts/validate-autonomy-contract-v2.mjs

test-autonomy-contract-doc: ## Preserve W0 autonomy-contract documentation boundaries (issue #170)
	@bash tests/scripts/test-autonomy-contract-doc.sh

test-autonomy-owner-authorization: ## Verify the owner-pinned Ed25519 authorization root (issue #172)
	@bash tests/scripts/test-autonomy-owner-authorization.sh

test: test-autonomy-contract test-autonomy-contract-v2 test-autonomy-contract-doc test-autonomy-owner-authorization test-security-skip test-security-delta test-security-completeness test-security-namespace test-munin-rpc test-registry-smoke test-placement-validation test-portability-acceptance test-deploy-source-revision test-deploy-persistent-paths test-deploy-systemd-render test-deploy-unit-target-guard test-failure-recovery-doc test-cross-service-contract-doc test-fleet-seam-audit-2026-07-26 test-learning-task-contract-doc test-node-substrate-contract test-network-operating-model test-node-substrate-contract-doc test-maintenance-policy-contract test-maintenance-policy-contract-doc test-system-roi-ledger test-registry-checkout test-systemd-status test-runtime-state test-worktree-hygiene test-validate-exit test-validation-evidence test-claude-capacity-preflight test-github-project-preflight test-github-actions-policy test-github-actions-zero-step-preflight test-validation-staleness-evidence-doc test-doc-index test-architecture-component-table test-architecture-component-table-regression test-instruction-eval-sandbox test-skills-eval-sandbox test-telemetry-strategy-doc ## Run all test suites

clean: ## Remove generated docs
	rm -f docs/snapshot.md docs/full-architecture.md

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

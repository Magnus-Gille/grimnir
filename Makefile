.PHONY: docs clean security security-dry deploy test-security-skip test-security-delta test-registry-smoke test-failure-recovery-doc test

docs: ## Generate full architecture document
	@./scripts/generate-architecture.sh

security: ## Run security scan across all Grimnir repos
	@./scripts/security-scan.sh

security-dry: ## Run security scan (dry run, no Munin writes)
	@./scripts/security-scan.sh --dry-run

deploy: ## Deploy all services to Pi (or: make deploy ARGS="munin-memory hugin")
	@./scripts/deploy.sh $(ARGS)

test-security-skip: ## Regression test: assert security-scan skips test/eval fixtures (issue #22)
	@bash tests/scripts/test-security-scan-skip.sh

test-security-delta: ## Unit tests for the scan_escalated/parse_prev_counts helpers
	@bash scripts/tests/security-scan-delta.test.sh

test-registry-smoke: ## Schema/consistency smoke check for services.json (issue #48)
	@bash scripts/tests/registry-smoke.test.sh

test-failure-recovery-doc: ## Regression test: assert docs/failure-recovery.md defines the undo convention (issue #46)
	@bash tests/scripts/test-failure-recovery-doc.sh

test: test-security-skip test-security-delta test-registry-smoke test-failure-recovery-doc ## Run all test suites

clean: ## Remove generated docs
	rm -f docs/snapshot.md docs/full-architecture.md

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

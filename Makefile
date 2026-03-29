.PHONY: docs clean security security-dry

docs: ## Generate full architecture document
	@./scripts/generate-architecture.sh

security: ## Run security scan across all Grimnir repos
	@./scripts/security-scan.sh

security-dry: ## Run security scan (dry run, no Munin writes)
	@./scripts/security-scan.sh --dry-run

clean: ## Remove generated docs
	rm -f docs/snapshot.md docs/full-architecture.md

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

.PHONY: docs clean security security-dry deploy patching maintenance-os maintenance-deps

docs: ## Generate full architecture document
	@./scripts/generate-architecture.sh

security: ## Run security scan across all Grimnir repos
	@./scripts/security-scan.sh

security-dry: ## Run security scan (dry run, no Munin writes)
	@./scripts/security-scan.sh --dry-run

deploy: ## Deploy all services to Pi (or: make deploy ARGS="munin-memory hugin")
	@./scripts/deploy.sh $(ARGS)

patching: ## Install/refresh unattended-upgrades on all Pi hosts (ARGS="--dry-run" or a host)
	@./scripts/setup-host-patching.sh $(ARGS)

maintenance-os: ## Run the OS maintenance report on the Pi now (ARGS="--dry-run --verbose")
	@ssh magnus@huginmunin.local 'cd /home/magnus/repos/grimnir && bash scripts/maintenance-report.sh os $(ARGS)'

maintenance-deps: ## Run the npm dependency report on the Pi now (ARGS="--dry-run --verbose")
	@ssh magnus@huginmunin.local 'cd /home/magnus/repos/grimnir && bash scripts/maintenance-report.sh deps $(ARGS)'

clean: ## Remove generated docs
	rm -f docs/snapshot.md docs/full-architecture.md

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

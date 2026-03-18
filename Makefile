# claude-autopilot Makefile
# Primary entry point for new contributors.
# After cloning, run: make setup

.PHONY: setup test build help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## One-time setup: activate git hooks
	@bash scripts/setup-hooks.sh

test: ## Run full test suite
	@bash plugins/spec-autopilot/tests/run_all.sh

build: ## Rebuild dist/ from source
	@bash plugins/spec-autopilot/tools/build-dist.sh

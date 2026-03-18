# claude-autopilot Makefile
# Primary entry point for new contributors.
# After cloning, run: make setup

PLUGIN := plugins/spec-autopilot

.PHONY: setup test build lint format typecheck ci help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## One-time setup: activate git hooks
	@bash scripts/setup-hooks.sh

test: ## Run full test suite
	@bash $(PLUGIN)/tests/run_all.sh

build: ## Rebuild dist/ from source
	@bash $(PLUGIN)/tools/build-dist.sh

# ── Lint / Format / Typecheck ─────────────────────────────────────

lint: ## Run linters (shellcheck + ruff); missing tools skipped
	@echo "── shellcheck ──"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning || true; \
	else \
	  echo "[skip] shellcheck not found"; \
	fi
	@echo ""
	@echo "── ruff ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff check --config $(PLUGIN)/pyproject.toml || true; \
	else \
	  echo "[skip] ruff not found"; \
	fi

format: ## Run formatters (ruff format); missing tools skipped
	@echo "── ruff format ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff format --check --config $(PLUGIN)/pyproject.toml || true; \
	else \
	  echo "[skip] ruff not found"; \
	fi

typecheck: ## Run TypeScript type checks (gui + server)
	@echo "── gui typecheck ──"
	@if [ -f $(PLUGIN)/gui/tsconfig.json ]; then \
	  cd $(PLUGIN)/gui && npx tsc --noEmit; \
	else \
	  echo "[skip] gui/tsconfig.json not found"; \
	fi
	@echo ""
	@echo "── server typecheck ──"
	@if [ -f $(PLUGIN)/server/tsconfig.json ]; then \
	  cd $(PLUGIN)/server && npx tsc --noEmit; \
	else \
	  echo "[skip] server/tsconfig.json not found"; \
	fi

ci: lint typecheck test build ## CI pipeline: lint → typecheck → test → build

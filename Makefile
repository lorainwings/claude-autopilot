# claude-autopilot Makefile
# Primary entry point for new contributors.
# After cloning, run: make setup

PLUGIN := plugins/spec-autopilot

.PHONY: setup test build lint format typecheck ci help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## One-time setup: activate git hooks + install deps
	@bash scripts/setup-hooks.sh
	@echo ""
	@echo "── Installing GUI dependencies ──"
	@if [ -f $(PLUGIN)/gui/package.json ]; then \
	  cd $(PLUGIN)/gui && bun install; \
	else \
	  echo "[skip] gui/package.json not found"; \
	fi
	@echo ""
	@echo "── Installing server dependencies ──"
	@if [ -f $(PLUGIN)/server/package.json ]; then \
	  cd $(PLUGIN)/server && bun install; \
	else \
	  echo "[skip] server/package.json not found"; \
	fi

test: ## Run full test suite
	@bash $(PLUGIN)/tests/run_all.sh

build: ## Rebuild dist/ from source
	@bash $(PLUGIN)/tools/build-dist.sh

# ── Lint / Format / Typecheck ─────────────────────────────────────

lint: ## Run linters (shellcheck + ruff + mypy); missing tools skipped
	@echo "── shellcheck ──"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning; \
	else \
	  echo "[skip] shellcheck not found"; \
	fi
	@echo ""
	@echo "── ruff ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff check --config $(PLUGIN)/pyproject.toml; \
	else \
	  echo "[skip] ruff not found"; \
	fi
	@echo ""
	@echo "── mypy ──"
	@if command -v mypy >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 mypy --config-file $(PLUGIN)/pyproject.toml; \
	else \
	  echo "[skip] mypy not found"; \
	fi

format: ## Run formatters (shfmt + ruff format); missing tools skipped
	@echo "── shfmt ──"
	@if command -v shfmt >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.sh' -print0 | xargs -0 shfmt -d -i 2 -ci; \
	else \
	  echo "[skip] shfmt not found"; \
	fi
	@echo ""
	@echo "── ruff format ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(PLUGIN)/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff format --check --config $(PLUGIN)/pyproject.toml; \
	else \
	  echo "[skip] ruff not found"; \
	fi

typecheck: ## Run TypeScript type checks (gui + server)
	@echo "── gui typecheck ──"
	@if [ -f $(PLUGIN)/gui/tsconfig.json ]; then \
	  if [ ! -d $(PLUGIN)/gui/node_modules ]; then \
	    echo "[auto] Installing GUI dependencies..."; \
	    (cd $(PLUGIN)/gui && bun install); \
	  fi; \
	  cd $(PLUGIN)/gui && npx tsc --noEmit; \
	else \
	  echo "[skip] gui/tsconfig.json not found"; \
	fi
	@echo ""
	@echo "── server typecheck ──"
	@if [ -f $(PLUGIN)/server/tsconfig.json ]; then \
	  if [ ! -d $(PLUGIN)/server/node_modules ]; then \
	    echo "[auto] Installing server dependencies..."; \
	    (cd $(PLUGIN)/server && bun install); \
	  fi; \
	  cd $(PLUGIN)/server && npx tsc --noEmit; \
	else \
	  echo "[skip] server/tsconfig.json not found"; \
	fi

ci: lint typecheck test build ## CI pipeline: lint → typecheck → test → build

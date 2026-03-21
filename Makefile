# claude-autopilot Makefile
# Primary entry point for new contributors.
# After cloning, run: make setup

SA  := plugins/spec-autopilot
PH  := plugins/parallel-harness

.PHONY: hooks setup test build lint format typecheck ci \
        ph-test ph-typecheck ph-build ph-lint ph-setup \
        help

hooks:
	@bash scripts/setup-hooks.sh >/dev/null

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────────────────────────

setup: hooks ## One-time setup: activate git hooks + install all deps
	@bash scripts/setup-hooks.sh
	@echo ""
	@echo "── Installing spec-autopilot GUI dependencies ──"
	@if [ -f $(SA)/gui/package.json ]; then \
	  cd $(SA)/gui && bun install; \
	else \
	  echo "[skip] $(SA)/gui/package.json not found"; \
	fi
	@echo ""
	@echo "── Installing spec-autopilot server dependencies ──"
	@if [ -f $(SA)/runtime/server/package.json ]; then \
	  cd $(SA)/runtime/server && bun install; \
	else \
	  echo "[skip] $(SA)/runtime/server/package.json not found"; \
	fi
	@echo ""
	@echo "── Installing parallel-harness dependencies ──"
	@if [ -f $(PH)/package.json ]; then \
	  cd $(PH) && bun install; \
	else \
	  echo "[skip] $(PH)/package.json not found"; \
	fi

# ── spec-autopilot (default targets for backward compat) ───────────

test: hooks ## Run spec-autopilot full test suite
	@bash $(SA)/tests/run_all.sh

build: hooks ## Rebuild spec-autopilot dist/
	@bash $(SA)/tools/build-dist.sh

lint: hooks ## Run spec-autopilot linters (shellcheck + ruff + mypy)
	@echo "── shellcheck ──"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  find $(SA)/runtime/scripts -maxdepth 1 -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning; \
	elif [ -n "$$CI" ]; then \
	  echo "❌ shellcheck is required in CI but not found"; exit 1; \
	else \
	  echo "[skip] shellcheck not found (install it or run in CI for enforcement)"; \
	fi
	@echo ""
	@echo "── ruff ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(SA)/runtime/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff check --config $(SA)/pyproject.toml; \
	elif [ -n "$$CI" ]; then \
	  echo "❌ ruff is required in CI but not found"; exit 1; \
	else \
	  echo "[skip] ruff not found (install it or run in CI for enforcement)"; \
	fi
	@echo ""
	@echo "── mypy ──"
	@if command -v mypy >/dev/null 2>&1; then \
	  find $(SA)/runtime/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 mypy --config-file $(SA)/pyproject.toml; \
	elif [ -n "$$CI" ]; then \
	  echo "❌ mypy is required in CI but not found"; exit 1; \
	else \
	  echo "[skip] mypy not found (install it or run in CI for enforcement)"; \
	fi

format: hooks ## Run spec-autopilot formatters (shfmt + ruff format)
	@echo "── shfmt ──"
	@if command -v shfmt >/dev/null 2>&1; then \
	  find $(SA)/runtime/scripts -maxdepth 1 -name '*.sh' -print0 | xargs -0 shfmt -d -i 2 -ci; \
	else \
	  echo "[skip] shfmt not found"; \
	fi
	@echo ""
	@echo "── ruff format ──"
	@if command -v ruff >/dev/null 2>&1; then \
	  find $(SA)/runtime/scripts -maxdepth 1 -name '*.py' -print0 | xargs -0 ruff format --check --config $(SA)/pyproject.toml; \
	else \
	  echo "[skip] ruff not found"; \
	fi

typecheck: hooks ## Run TypeScript type checks (spec-autopilot gui + server)
	@echo "── gui typecheck ──"
	@if [ -f $(SA)/gui/tsconfig.json ]; then \
	  if [ ! -d $(SA)/gui/node_modules ]; then \
	    echo "[auto] Installing GUI dependencies..."; \
	    (cd $(SA)/gui && bun install); \
	  fi; \
	  cd $(SA)/gui && npx tsc --noEmit; \
	else \
	  echo "[skip] gui/tsconfig.json not found"; \
	fi
	@echo ""
	@echo "── server typecheck ──"
	@if [ -f $(SA)/runtime/server/tsconfig.json ]; then \
	  if [ ! -d $(SA)/runtime/server/node_modules ]; then \
	    echo "[auto] Installing server dependencies..."; \
	    (cd $(SA)/runtime/server && bun install); \
	  fi; \
	  cd $(SA)/runtime/server && npx tsc --noEmit; \
	else \
	  echo "[skip] runtime/server/tsconfig.json not found"; \
	fi

ci: hooks lint typecheck test build ## spec-autopilot CI: lint → typecheck → test → build

# ── parallel-harness targets ───────────────────────────────────────

ph-setup: ## Install parallel-harness dependencies
	@cd $(PH) && bun install

ph-typecheck: ## Run parallel-harness TypeScript type check
	@echo "── parallel-harness typecheck ──"
	@if [ ! -d $(PH)/node_modules ]; then \
	  echo "[auto] Installing dependencies..."; \
	  cd $(PH) && bun install; \
	fi
	@cd $(PH) && bunx tsc --noEmit
	@echo "parallel-harness typecheck passed"

ph-test: ## Run parallel-harness test suite (unit + integration)
	@echo "── parallel-harness tests ──"
	@if [ ! -d $(PH)/node_modules ]; then \
	  echo "[auto] Installing dependencies..."; \
	  cd $(PH) && bun install; \
	fi
	@cd $(PH) && bun test

ph-build: ## Build parallel-harness dist/ (typecheck → test → dist)
	@bash $(PH)/tools/build-dist.sh

ph-lint: ## Lint parallel-harness build script (shellcheck)
	@echo "── shellcheck: parallel-harness ──"
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck $(PH)/tools/build-dist.sh; \
	elif [ -n "$$CI" ]; then \
	  echo "❌ shellcheck is required in CI but not found"; \
	  exit 1; \
	else \
	  echo "[skip] shellcheck not found (install it or run in CI for enforcement)"; \
	fi

ph-ci: ph-lint ph-typecheck ph-test ph-build ## parallel-harness CI: lint → typecheck → test → build

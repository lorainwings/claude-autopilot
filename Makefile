# claude-autopilot Makefile
# Primary entry point for new contributors.
# After cloning, run: make setup

SA  := plugins/spec-autopilot
PH  := plugins/parallel-harness
DR  := plugins/daily-report

# lint 工具版本 — 与 .github/workflows/test-spec-autopilot.yml 保持一致
RUFF_VERSION  := 0.15.7
MYPY_VERSION  := 1.15.0

.PHONY: hooks setup test build lint format typecheck ci \
        ph-test ph-typecheck ph-build ph-lint ph-setup \
        dr-build dr-lint dr-ci \
        release release-dry \
        help

hooks:
	@bash scripts/setup-hooks.sh >/dev/null

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ── Setup ──────────────────────────────────────────────────────────

setup: hooks ## One-time setup: activate git hooks + install all deps + lint tools
	@bash scripts/setup-hooks.sh
	@echo ""
	@echo "── Installing dev tools (bun + lint tools) ──"
	@bash scripts/install-dev-tools.sh
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

lint: hooks ## Run spec-autopilot linters (shellcheck + shfmt + ruff + mypy)
	@export PATH="$(shell pwd)/.tools/bin:$$HOME/.bun/bin:$$HOME/Library/Python/3.14/bin:$$HOME/Library/Python/3.9/bin:$$PATH"; \
	bash scripts/run-spec-autopilot-lint.sh

format: hooks ## [deprecated] Format checks are now part of 'make lint'
	@echo "ℹ️  'make format' is deprecated. Format checks are now included in 'make lint'."
	@echo "    Run 'make lint' for the complete lint + format suite."

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
	@export PATH="$(shell pwd)/.tools/bin:$$PATH"; \
	echo "── shellcheck: parallel-harness ──"; \
	if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck $(PH)/tools/build-dist.sh; \
	else \
	  echo "❌ shellcheck not found. Install: brew install shellcheck"; \
	  exit 1; \
	fi

ph-ci: ph-lint ph-typecheck ph-test ph-build ## parallel-harness CI: lint → typecheck → test → build

# ── daily-report targets ──────────────────────────────────────────

dr-build: hooks ## Build daily-report dist/ (pure file copy, no compile)
	@bash $(DR)/tools/build-dist.sh

dr-lint: ## Lint daily-report build script (shellcheck)
	@export PATH="$(shell pwd)/.tools/bin:$$PATH"; \
	echo "── shellcheck: daily-report ──"; \
	if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck $(DR)/tools/build-dist.sh; \
	else \
	  echo "❌ shellcheck not found. Install: brew install shellcheck"; \
	  exit 1; \
	fi

dr-ci: dr-lint dr-build ## daily-report CI: lint → build

# ── Release ────────────────────────────────────────────────────────

release: ## Manual release wizard (fallback)
	@bash tools/release.sh

release-dry: ## Dry-run release preview (no file changes)
	@bash tools/release.sh --dry-run

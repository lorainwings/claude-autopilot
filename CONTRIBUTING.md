> **[中文版](CONTRIBUTING.zh.md)** | English (default)

# Contributing to lorainwings-plugins

Thank you for your interest in contributing! This guide will help you get started.

## Getting Started

### Prerequisites

**Required (system-level)**:
- **git** — version control (usually pre-installed)
- **python3** (3.8+) — for spec-autopilot runtime (usually pre-installed on macOS/Linux)
- **bash** (4.0+) — shell scripting (pre-installed on Unix systems)
- **make** — build automation (pre-installed on macOS/Linux)

**Optional (auto-installed by `make setup`)**:
- **bun** — JavaScript runtime for parallel-harness and spec-autopilot GUI/server
- **shellcheck, shfmt** — shell linters
- **ruff, mypy** — Python linters

### One-Command Setup

```bash
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# This will:
# 1. Activate git hooks
# 2. Auto-install bun (if missing)
# 3. Auto-install lint tools (shellcheck, shfmt, ruff, mypy)
# 4. Install all project dependencies
make setup
```

**That's it!** If `make setup` completes successfully, you're ready to develop.

### Troubleshooting Setup

If `make setup` fails:
- **Bun installation failed**: Manually install from https://bun.sh
- **Lint tools failed**: Don't worry — CI will validate your code. You can still develop and test locally.

### Run Tests

```bash
make test
```

## Development Workflow

### 1. Create a Branch

```bash
git checkout -b feature/my-feature
```

### 2. Make Changes

- Edit source files in `plugins/spec-autopilot/` for spec-autopilot plugin
- Edit source files in `plugins/parallel-harness/` for parallel-harness plugin
- **Never edit** files in `dist/` directly — they are auto-generated

### 3. Test Your Changes

```bash
# Run full test suite
make test

# Run parallel-harness tests
make ph-test
```

### 4. Rebuild Distribution

```bash
make build

# Build parallel-harness
make ph-build
```

### 5. Commit and Push

```bash
git add -A
git commit -m "feat: description of your change"
git push origin feature/my-feature
```

### 6. Open a Pull Request

Open a PR against `main` with a clear description of your changes.

## Coding Standards

### Shell Scripts

- All scripts must pass `bash -n` syntax check (included in `make test`)
- Use `set -euo pipefail` where appropriate
- Include timeout configuration for all hooks
- Hook exit codes: `exit 0` always (decisions via stdout JSON)

### TypeScript (parallel-harness)

- All TypeScript must pass `bunx tsc --noEmit`
- Use strict mode, ESNext target
- Tests use `bun test`
- Minimum 295 test baseline must be maintained

### Test Discipline

- Every new feature must include corresponding tests in `tests/test_*.sh`
- Minimum 3 test cases per feature: normal + boundary + error path
- Never weaken existing assertions
- Never delete existing tests without justification in commit message

### Documentation

- All documentation supports bilingual (English + Chinese)
- English is the default version (`.md`), Chinese is the companion (`.zh.md`)
- Both versions must have language switcher links at the top
- Shared content (code blocks, diagrams) must be identical in both versions

### Version Bumping

- **Primary**: [release-please](https://github.com/googleapis/release-please) automates version bumps, CHANGELOG generation, and GitHub Releases via Conventional Commits
- **Fallback**: `tools/release.sh` (interactive wizard) for manual releases when release-please is unavailable
- Merge release work into `main`; release-please will open the Release PR, and the post-release job will sync `dist/`, plugin docs, root README tables, and `.claude-plugin/marketplace.json`
- Never manually edit version numbers in plugin.json, marketplace.json, README.md, root README tables, or CHANGELOG.md

### Build Discipline

- Run `make build` after modifying any runtime files
- `dist/` is auto-generated — all changes go in source
- Test files never enter `dist/`
- Plugin-only changes should stay inside the matching plugin path so GitHub Actions only runs that plugin's workflow; shared files such as `scripts/` or `Makefile` intentionally fan out to multiple workflows

## Commit Message Convention

Follow the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
feat: add new feature
fix: fix a bug
docs: update documentation
test: add or update tests
refactor: code refactoring
chore: maintenance tasks
```

## Reporting Issues

- Use [GitHub Issues](https://github.com/lorainwings/claude-autopilot/issues)
- Include: steps to reproduce, expected behavior, actual behavior
- For hook-related issues: include stderr output (Ctrl+O in Claude Code)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).

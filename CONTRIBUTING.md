> **[中文版](CONTRIBUTING.zh.md)** | English (default)

# Contributing to lorainwings-plugins

Thank you for your interest in contributing! This guide will help you get started.

## Getting Started

### Prerequisites

- Claude Code CLI (v1.0.0+)
- python3 (3.8+)
- bash (4.0+)
- bun (1.0+) for parallel-harness
- git

### Setup

```bash
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# One-time setup: activate git hooks (required)
make setup
```

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
- Minimum 219 test baseline must be maintained

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

- Version changes **must** go through `tools/bump-version.sh`
- Never manually edit version numbers in plugin.json, marketplace.json, README.md, or CHANGELOG.md

### Build Discipline

- Run `make build` after modifying any runtime files
- `dist/` is auto-generated — all changes go in source
- Test files never enter `dist/`

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

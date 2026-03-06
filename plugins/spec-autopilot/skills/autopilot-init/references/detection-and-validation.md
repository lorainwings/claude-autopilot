# Detection Rules & Schema Validation

> Extracted from SKILL.md for size compliance. Referenced by main SKILL.md.

## test_suites Auto-detection Rules

| Detected | Generated test_suite |
|----------|---------------------|
| `build.gradle` + `src/test/` | `backend_unit: { command: "cd backend && ./gradlew test", type: unit, allure: junit_xml, allure_post: "cp -r backend/build/test-results/test/*.xml \"$ALLURE_RESULTS_DIR/\" 2>/dev/null \|\| true" }` |
| `pytest.ini` or `conftest.py` | `api_test: { command: "python3 -m pytest tests/api/ -v", type: integration, allure: pytest }` |
| `playwright.config.ts` | `e2e: { command: "npx playwright test", type: e2e, allure: playwright }` |
| `vitest.config.*` | `unit: { command: "npx vitest run", type: unit, allure: none }` |
| `jest.config.*` | `unit: { command: "npx jest", type: unit, allure: none }` |
| Frontend `package.json` has `type-check` | `typecheck: { command: "cd frontend && pnpm type-check", type: typecheck, allure: none }` |
| Node `tsconfig.json` | `node_typecheck: { command: "cd node && npx tsc --noEmit", type: typecheck, allure: none }` |

## report_commands Auto-detection Rules

| Detected | Generated command |
|----------|------------------|
| `tools/report/html_generator.py` | `html: "python tools/report/html_generator.py -i {change_name}"` |
| `tools/report/generator.py` | `markdown: "python tools/report/generator.py -i {change_name}"` |
| Neither found | `report_commands: {}` and prompt user to configure |

## Schema Validation (Step 6)

After writing config, **must** validate completeness. Required keys:

```
Required top-level keys:
  - version (string)
  - services (object, at least one service)
  - phases (object)
  - test_suites (object, at least one suite)

Required keys under phases:
  - phases.requirements.agent (string)
  - phases.testing.agent (string)
  - phases.testing.gate.min_test_count_per_type (number, >= 1)
  - phases.testing.gate.required_test_types (array, non-empty)
  - phases.implementation.ralph_loop.enabled (boolean)
  - phases.implementation.ralph_loop.max_iterations (number, >= 1)
  - phases.implementation.ralph_loop.fallback_enabled (boolean)
  - phases.reporting.coverage_target (number, 0-100)
  - phases.reporting.zero_skip_required (boolean)

Each service must have:
  - health_url (string, starts with http:// or https://)

Each test_suite must have:
  - command (string, non-empty)
  - type (string, one of: unit, integration, e2e, ui, typecheck)
  - allure (string, one of: pytest, playwright, junit_xml, none)
  - allure_post (string, optional, only when allure=junit_xml)
```

Validation fails -> output missing/invalid key list, AskUserQuestion to have user fix and retry.

## LSP Plugin Recommendations (Step 5.5)

Based on detected tech stack, recommend corresponding Claude Code LSP plugins:

| Detected Stack | LSP Plugin | Install Command |
|---------------|-----------|-----------------|
| Java/Gradle or Java/Maven | `jdtls-lsp` | `claude plugin install jdtls-lsp@claude-plugins-official` |
| TypeScript/Vue/React | `typescript-lsp` | `claude plugin install typescript-lsp@claude-plugins-official` |
| Python | `pyright-lsp` | `claude plugin install pyright-lsp@claude-plugins-official` |
| Rust | `rust-analyzer-lsp` | `claude plugin install rust-analyzer-lsp@claude-plugins-official` |
| Go | `gopls-lsp` | `claude plugin install gopls-lsp@claude-plugins-official` |
| Kotlin | `kotlin-lsp` | `claude plugin install kotlin-lsp@claude-plugins-official` |
| PHP | `php-lsp` | `claude plugin install php-lsp@claude-plugins-official` |
| Swift | `swift-lsp` | `claude plugin install swift-lsp@claude-plugins-official` |
| C/C++ | `clangd-lsp` | `claude plugin install clangd-lsp@claude-plugins-official` |

**Detection logic**: Check `detected_stacks` from Step 1, cross-reference with `.claude/settings.json` `enabledPlugins`, only recommend uninstalled plugins.

**User interaction**: If recommendations exist, AskUserQuestion with options: "Install all (Recommended)" / "Select" / "Skip".

Installed LSP plugins are recorded in config's `lsp_plugins` field (informational only):

```yaml
lsp_plugins:
  - name: typescript-lsp
    status: installed    # installed | skipped | failed
```

> LSP recommendation is optional. Skipping does not affect config generation or autopilot functionality.

---
name: autopilot-init
description: "Initialize autopilot config by scanning project structure. Auto-detects tech stack, services, and test suites to generate .claude/autopilot.config.yaml."
argument-hint: "[optional: project root path]"
---

# Autopilot Init — Project Config Initialization

Scan project structure, auto-detect tech stack and services, generate `.claude/autopilot.config.yaml`.

## Supporting References

- For the full config YAML template, see [config-template.md](references/config-template.md)
- For detection rules, schema validation, and LSP recommendations, see [detection-and-validation.md](references/detection-and-validation.md)

## Execution Flow

### Step 1: Detect Project Structure

Use Glob and Read to scan these patterns:

```
Backend detection:
  - build.gradle / build.gradle.kts -> Java/Gradle
  - pom.xml -> Java/Maven
  - go.mod -> Go
  - Cargo.toml -> Rust
  - requirements.txt / pyproject.toml -> Python

Frontend detection:
  - frontend/*/package.json or package.json -> read scripts field
  - Framework: vue/react/angular (from dependencies)
  - Package manager: pnpm-lock.yaml / yarn.lock / package-lock.json

Node service detection:
  - node/package.json -> read scripts field
  - ecosystem.config.js -> PM2 config

Test detection:
  - tests/ / test/ / __tests__/ directory structure
  - playwright.config.ts -> Playwright
  - pytest.ini / conftest.py -> pytest
  - jest.config.* -> Jest
  - vitest.config.* -> Vitest
```

### Step 2: Detect Service Ports

Extract service ports from: `application.yml`, `vite.config.ts`, `.env`, `ecosystem.config.js`

### Step 2.5: Detect Project Context

Extract project-specific data needed by sub-agents:
- **2.5.1 Test credentials**: From application.yml/.env/conftest.py/Login component
- **2.5.2 Project structure**: backend_dir, frontend_dir, node_dir, test_dirs
- **2.5.3 Playwright login flow**: Scan Login component for data-testid attributes

Fields not detected are left empty; Step 4 prompts user or Phase 1 auto-discovers.

### Step 2.6: Security Tool Detection (v2.4.0)

Run `bash ${CLAUDE_SKILL_DIR}/../../../scripts/check-security-tools-install.sh "$(pwd)"`. If tools found, generate `async_quality_scans.security_audit` config section.

### Step 2.7: Code Constraint Auto-detection (v3.1.0)

Run `bash ${CLAUDE_SKILL_DIR}/../../../scripts/rules-scanner.sh "$(pwd)"`. Auto-fill `code_constraints` from detected rules.

### Step 3: Generate Config

Generate YAML config based on detection results using the template in [config-template.md](references/config-template.md). Replace `{detected}` placeholders with actual values.

### Step 4: User Confirmation

AskUserQuestion to display generated config summary:
- Detected backend/frontend/test stacks and ports
- Test credentials status
- Options: "Confirm and write (Recommended)" / "Need adjustments"

For empty `project_context` fields, prompt user individually (all optional, can be auto-discovered by Phase 1).

### Step 5: Write Config

Write config to `.claude/autopilot.config.yaml`. If file exists, AskUserQuestion to confirm overwrite.

### Step 5.5: LSP Plugin Recommendations

Based on detected tech stack, recommend LSP plugins. See [detection-and-validation.md](references/detection-and-validation.md) for the full mapping table.

### Step 6: Schema Validation

Validate config completeness after writing. Required keys and validation rules are in [detection-and-validation.md](references/detection-and-validation.md).

## Idempotency

Multiple runs do not break existing config. Overwrite requires explicit user confirmation.

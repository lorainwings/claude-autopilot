> **[中文版](integration-guide.zh.md)** | English (default)

# Integration Guide

> This guide walks through onboarding a brand-new project with the spec-autopilot plugin, from installation to your first fully automated delivery.

## Prerequisites

| Requirement | Version | Check Command |
|-------------|---------|---------------|
| Claude Code | v1.0.0+ | `claude --version` |
| python3 | 3.8+ (required by Hook scripts) | `python3 --version` |
| git | Any version | `git --version` |
| bash | 4.0+ (macOS requires brew install) | `bash --version` |

### Optional Dependencies

| Dependency | Purpose | Installation |
|------------|---------|--------------|
| openspec plugin | Phase 2-3 spec generation (**required**) | `claude plugin install openspec` |
| PyYAML | Precise parsing for config validation | `pip3 install pyyaml` |
| Allure | Unified test reporting | `npm install -g allure-commandline` |

---

## Onboarding Process

### Step 1: Install Plugin

```bash
# Add marketplace (one-time only)
claude plugin marketplace add lorainwings/claude-autopilot

# Install to project (recommended)
claude plugin install spec-autopilot@lorainwings-plugins --scope project

# Or install at user level (shared across all projects)
claude plugin install spec-autopilot@lorainwings-plugins --scope user
```

Install the openspec dependency (if not already installed):

```bash
claude plugin install openspec --scope project
```

Verify installation:

```bash
claude plugin list
# You should see:
#   spec-autopilot@lorainwings-plugins (project)
#   openspec (project)
```

### Step 2: Restart Claude Code

```bash
# Exit current session
exit

# Restart
claude
```

### Step 3: Generate Project Config (One Step)

Run the following in Claude Code:

```
/spec-autopilot:autopilot-init
```

Or trigger autopilot directly (init is called automatically when config does not exist):

```
启动autopilot
```

Init will auto-detect and generate `.claude/autopilot.config.yaml`:
- Tech stack (Java/Spring Boot, Vue/React, Python, Go, etc.)
- Service ports (extracted from application.yml / vite.config.ts / .env)
- Test frameworks (JUnit, pytest, Playwright, Vitest, etc.)
- Build tools (Gradle, Maven, pnpm, npm, etc.)
- **Test credentials** (detected from .env / conftest.py / application.yml)
- **Project structure** (backend/frontend/node/test directory paths)
- **Playwright login flow** (derived from Login component data-testid attributes)

> **No manual instruction files needed.** Dispatch dynamically constructs sub-Agent prompts from the config's `project_context` + `test_suites` + `services`. Phase 1's Auto-Scan supplements any undetected project context at runtime.

### Step 4: Review Configuration

Confirm the following key fields in the generated config are correct:

```yaml
# Core fields to verify
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"  # Is the port correct?

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"               # Is the command correct?
  # ... other suites

project_context:
  test_credentials:
    username: "dev"        # Is the test account correct? Leave empty for Phase 1 auto-discovery
    password: "password"
  project_structure:
    backend_dir: "backend" # Is the directory correct?
```

Run config validation:

```bash
bash ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/*/runtime/scripts/validate-config.sh
```

### Step 5: (Optional) Advanced Customization

For projects with special requirements, you can override built-in plugin rules via `instruction_files`:

```yaml
# autopilot.config.yaml — only use when built-in rules are insufficient
phases:
  testing:
    instruction_files:
      - ".claude/autopilot/custom-testing.md"   # Custom testing requirements
    reference_files:
      - ".claude/autopilot/custom-reference.md" # Custom reference files
```

> Most projects **do not need** custom instruction files. The config's `project_context` + `test_suites` already provides sufficient project context.

### Step 6: Initialize OpenSpec Directory

Ensure the `openspec/` structure exists at the project root:

```bash
mkdir -p openspec/changes openspec/archive openspec/specs
```

If the project uses the OpenSpec plugin, the directory is typically already created automatically.

### Step 7: Verify Installation

Run a quick verification in Claude Code:

```
# 1. Check plugin loaded
claude plugin list

# 2. Check config is valid
# (autopilot validates automatically on startup)

# 3. Check Hook registration
# Verify .claude/settings.json hooks section contains spec-autopilot entries
```

### Step 7.5: Launch GUI Dashboard (v5.0.8, Optional)

The GUI dashboard provides real-time visualization of execution status and gate interaction UI.

**Prerequisites**:
- [Bun](https://bun.sh) runtime (`curl -fsSL https://bun.sh/install | bash`)

**Launch command**:

```bash
# Start dual-mode server (HTTP:9527 + WebSocket:8765)
bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts
```

Open `http://localhost:9527` to view the three-column dashboard. When a gate blocks, the GUI provides retry / fix / override decision buttons.

> The GUI is an optional component. Without it, autopilot operates entirely through CLI interaction with no loss of functionality.

---

## First Run

### Trigger Methods

Use any of the following trigger phrases in Claude Code:

```
全自动开发流程
一键从需求到交付
启动autopilot
```

Or start with parameters:

```
启动autopilot 实现用户登录功能，包含手机号验证码登录和密码登录两种方式
```

Or point to a PRD file:

```
启动autopilot openspec/prototypes/v1.0.0/PRD-v1.md
```

### Execution Flow Diagram

```
Phase 0: Environment Check
├── Read / generate autopilot.config.yaml
├── Validate config schema
├── Check enabled plugin list
├── Scan existing checkpoints (crash recovery)
├── Create 8 phase tasks
└── Create anchor commit

Phase 1: Requirements Understanding (main thread)
├── Project context scan → Steering Documents
├── Technical research Agent → research-findings.md
├── Complexity assessment → small / medium / large
├── Requirements analysis Agent (injected with Steering + Research context)
├── Multi-round decision loop (AskUserQuestion)
├── User final confirmation
└── Write checkpoint

Phases 2-6: Sub-Agent Auto-Execution
├── Phase 2: Create OpenSpec change
├── Phase 3: FF generate all artifacts
├── Phase 4: Test case design (TDD-first)
├── Phase 5: Foreground Task serial implementation
├── Phase 6: Test report generation
└── Phase 6.5: AI code review (optional)

Phase 7: Summary & Archive (main thread)
├── Display status summary table
├── Display execution metrics
├── Collect quality scan results
├── Run archive-readiness check
├── Auto-archive when ready; otherwise show block reasons
├── Git autosquash → clean commit history
└── Clean up temporary files
```

---

## Crash Recovery

If a Claude Code session is interrupted, simply trigger autopilot again after restarting to auto-recover:

```
启动autopilot
```

The plugin will:
1. Scan checkpoint files under `openspec/changes/<name>/context/phase-results/`
2. Find the last phase with `status: ok/warning`
3. Ask the user: continue / start fresh
4. Resume execution from the interruption point

Phase 5 supports **task-level recovery**: resumes from the last completed task rather than re-executing the entire phase.

---

## Common Configuration Scenarios

### Scenario 1: Frontend-Only Project

```yaml
services:
  frontend:
    health_url: "http://localhost:3000/"

phases:
  testing:
    gate:
      required_test_types: [unit, e2e]  # Remove api and ui
      min_test_count_per_type: 3

test_suites:
  frontend_unit:
    command: "pnpm test"
    type: unit
    allure: none
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
  typecheck:
    command: "pnpm type-check"
    type: typecheck
    allure: none
```

### Scenario 2: Python Backend Project

```yaml
services:
  backend:
    health_url: "http://localhost:8000/health"

phases:
  requirements:
    agent: "business-analyst"
  testing:
    agent: "qa-expert"
    gate:
      required_test_types: [unit, api, e2e]
      min_test_count_per_type: 5
  implementation:
    serial_task:
      max_retries_per_task: 3
  reporting:
    format: "custom"
    report_commands:
      html: "python3 -m pytest --html=report.html --self-contained-html"

test_suites:
  unit:
    command: "python3 -m pytest tests/unit/ -v"
    type: unit
    allure: pytest
  api:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "python3 -m pytest tests/e2e/ -v"
    type: e2e
    allure: pytest
```

### Scenario 3: Full-Stack Monorepo

```yaml
services:
  backend:
    health_url: "http://localhost:8080/actuator/health"
  frontend:
    health_url: "http://localhost:5173/"
  node:
    health_url: "http://localhost:3001/health/live"

phases:
  requirements:
    auto_scan:
      enabled: true
      max_depth: 3           # Monorepo needs deeper scanning
    research:
      enabled: true
    complexity_routing:
      thresholds:
        small: 3              # Monorepo has more files, raise thresholds
        medium: 8
  implementation:
    parallel:
      enabled: true           # Frontend and backend can run in parallel
      max_agents: 3

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
  frontend_unit:
    command: "cd frontend && pnpm test"
    type: unit
    allure: none
  node_typecheck:
    command: "cd node && npx tsc --noEmit"
    type: typecheck
    allure: none
  api_test:
    command: "python3 -m pytest tests/api/ -v"
    type: integration
    allure: pytest
  e2e:
    command: "npx playwright test"
    type: e2e
    allure: playwright
```

### Scenario 4: Parallel Execution (Large Projects)

Suitable for large projects with clear inter-module dependencies. Phase 5 groups by domain and executes in parallel:

```yaml
phases:
  implementation:
    parallel:
      enabled: true
      max_agents: 4           # Max parallel Agents (recommended 2-4)
      dependency_analysis: true  # Auto-analyze task dependencies

# Domain mapping (auto-derived from project_context by default)
project_context:
  project_structure:
    backend_dir: "backend"
    frontend_dir: "frontend"
    node_dir: "node"
```

Parallel mode core rules:
- Each domain is strictly assigned 1 Agent; serial within domain, parallel across domains
- File ownership enforced (`unified-write-edit-check.sh` L2 blocks unauthorized writes)
- Merge conflicts > 3 files triggers automatic fallback to serial mode

### Scenario 5: Event Bus Integration

Three ways to consume autopilot events:

```bash
# Method 1: Real-time file monitoring (simplest)
tail -f logs/events.jsonl | jq .

# Method 2: WebSocket consumption (requires wscat)
npx wscat -c ws://localhost:8765

# Method 3: HTTP event query (requires GUI server running)
curl http://localhost:9527/api/events
```

Event types: `phase_start`, `phase_end`, `gate_pass`, `gate_block`, `task_progress`, `decision_ack`.

> For detailed event API definitions, see [Event Bus API](../../skills/autopilot/references/event-bus-api.md).

---

## Onboarding Checklist

- [ ] Claude Code CLI installed
- [ ] spec-autopilot plugin installed
- [ ] openspec plugin installed
- [ ] `.claude/autopilot.config.yaml` generated (`/spec-autopilot:autopilot-init`)
- [ ] Config validation passed (`valid: true`)
- [ ] `project_context.test_credentials` filled in (or auto-discovered by Phase 1)
- [ ] `openspec/` directory structure exists
- [ ] (Optional) Parallel mode configured (`parallel.enabled: true`)
- [ ] (Optional) `instruction_files` custom overrides configured
- [ ] (Optional) GUI dashboard launched (`bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts`)
- [ ] (Optional) Event Bus log directory created (`mkdir -p logs`, or auto-created on first run)
- [ ] First `启动autopilot` or `/spec-autopilot:autopilot` test passed

---

## Existing Project Upgrade Guide

### Background

spec-autopilot is continuously evolving. Below are key upgrade notes for each version.

### v4.2+: Requirements Routing

- Phase 1 auto-classifies requirements as Feature / Bugfix / Refactor / Chore
- Different categories dynamically adjust gate thresholds (`routing_overrides`)
- No config changes needed; routing takes effect automatically

### v5.0+: Parallel Execution

- Add `parallel.enabled: true` to enable Phase 5 domain-level parallelism
- Verify `project_context.project_structure` domain directories are configured correctly
- Recommend adjusting `parallel.max_agents` (default 8, recommended 2-4)

### v5.0.8+: GUI V2 Dashboard

- Install Bun runtime
- Launch command: `bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts`
- Ports: HTTP 9527 + WebSocket 8765

### v2.2: instruction_files Made Optional (Historical)

### Upgrade Steps

#### 1. Update Plugin

```bash
# Run in Claude Code
claude plugin update spec-autopilot@lorainwings-plugins
```

Or manually update the cache:

```bash
# Update from source
cp -r ~/Coding/Huihao/claude-autopilot/plugins/spec-autopilot/. \
  ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/2.2.0/
```

#### 2. Add `project_context` to Config

Add the following between `context_management` and `test_suites` in `autopilot.config.yaml`:

```yaml
project_context:
  project_structure:
    backend_dir: "backend"                    # Your backend directory
    frontend_dir: "frontend/web-app"          # Your frontend directory
    node_dir: "node"                          # Node service directory (leave empty if none)
    test_dirs:
      unit: "backend/src/test/java/..."       # Unit test directory
      api: "tests/api"                        # API test directory
      e2e: "tests/e2e"                        # E2E test directory
      ui: "tests/ui"                          # UI test directory

  test_credentials:
    username: "dev"                           # Migrate from old reference/test-credentials.md
    password: "password"
    login_endpoint: "POST /api/auth/login"

  playwright_login:
    steps: |                                  # Migrate from old reference/playwright-standards.md
      1. goto /#/login
      2. click [data-testid="switch-password-login"]
      3. fill [data-testid="username"]
      4. fill [data-testid="password"]
      5. click [data-testid="login-btn"]
      6. waitForURL /#/dashboard
    known_testids:
      - switch-password-login
      - username
      - password
      - login-btn
```

#### 3. Clear instruction_files References (Optional)

Old instruction file references are now optional. If you have migrated content to `project_context`, you can clear them:

```yaml
phases:
  testing:
    instruction_files: []    # Old: [".claude/skills/autopilot/phases/testing-requirements.md"]
    reference_files: []      # Old: ["...test-credentials.md", "...playwright-standards.md"]
  implementation:
    instruction_files: []    # Old: [".claude/skills/autopilot/phases/implementation-config.md"]
  reporting:
    instruction_files: []    # Old: [".claude/skills/autopilot/phases/reporting.md"]
```

> If references are kept, dispatch will inject both config content + instruction file content (instruction_files take higher priority).

#### 4. Delete Project-Side SKILL.md Wrapper (If Present)

If you previously created `.claude/skills/autopilot/SKILL.md`, delete it to avoid duplication with plugin commands:

```bash
rm .claude/skills/autopilot/SKILL.md
```

> The `phases/` and `reference/` directories can be kept (as optional override sources for instruction_files) or deleted (if fully migrated to config).

#### 5. Verify

```bash
# Validate config
bash ~/.claude/plugins/cache/lorainwings-plugins/spec-autopilot/*/runtime/scripts/validate-config.sh

# Restart Claude Code and test
/spec-autopilot:autopilot
```

---

## Troubleshooting

| Problem | Cause | Solution |
|---------|-------|----------|
| "Config file not found" | Config not generated | Run `autopilot-init` or create manually |
| "python3 not found" | Hook scripts require python3 | `brew install python3` or `apt install python3` |
| "Phase N checkpoint not found" | Phase was skipped or crashed | Trigger autopilot to re-run; crash recovery handles it automatically |
| "Phase 5 task consecutive failures" | Implementation hit a blocker | Check error logs, adjust `serial_task.max_retries_per_task` |
| Hook script timeout | Project too large causing slow scans | Increase Hook timeout or reduce scan scope |
| Test pyramid check fails | Test distribution below threshold | Adjust test case counts or relax `test_pyramid` thresholds |

For more troubleshooting, see [troubleshooting.md](../operations/troubleshooting.md).

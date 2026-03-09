# spec-autopilot

> Spec-driven autopilot orchestration for delivery pipelines — 8-phase workflow with 3-layer gate system and crash recovery.

[![Version](https://img.shields.io/badge/version-3.3.4-blue.svg)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

**spec-autopilot** is a Claude Code plugin that automates the full software delivery lifecycle: from requirements gathering through implementation, testing, reporting, and archival. It enforces quality through a deterministic 3-layer gate system and provides resilient crash recovery.

### Key Features

- **8-Phase Pipeline**: Requirements → OpenSpec → FF Generate → Test Design → Implementation → Test Report → Archive
- **3-Layer Gate System**: TaskCreate dependencies + Hook checkpoint validation + AI checklist verification
- **Crash Recovery**: Automatic checkpoint scanning and session resume
- **Context Compaction Resilience**: State persistence across Claude Code context compression
- **Anti-Rationalization**: Pattern detection to prevent sub-agents from skipping work
- **Test Pyramid Enforcement**: Hook-level validation of test distribution
- **Metrics Collection**: Per-phase timing and retry tracking
- **Socratic Requirements Mode**: Deep requirements analysis through challenging questions

## Architecture

```mermaid
graph TB
    subgraph "Main Thread (Orchestrator)"
        P0[Phase 0: Environment Check<br/>+ Crash Recovery]
        P1[Phase 1: Requirements<br/>Multi-round Decision Loop]
        P7[Phase 7: Summary<br/>+ User-confirmed Archive]
    end

    subgraph "Sub-Agents (via Task tool)"
        P2[Phase 2: Create OpenSpec]
        P3[Phase 3: FF Generate]
        P4[Phase 4: Test Design]
        P5[Phase 5: Implementation<br/>Serial Task / Parallel]
        P6[Phase 6: Test Report]
    end

    P0 --> P1
    P1 -->|Gate| P2
    P2 -->|Gate| P3
    P3 -->|Gate| P4
    P4 -->|Special Gate:<br/>test_counts ≥ N| P5
    P5 -->|Special Gate:<br/>zero_skip_check| P6
    P6 -->|Quality Scans| P7

    style P0 fill:#e1f5fe
    style P1 fill:#e1f5fe
    style P7 fill:#e1f5fe
    style P4 fill:#fff3e0
    style P5 fill:#fff3e0
```

### 3-Layer Gate System

```mermaid
graph LR
    subgraph "Layer 1: Task System"
        L1[TaskCreate + blockedBy<br/>Automatic dependency chain]
    end

    subgraph "Layer 2: Hook Scripts"
        L2A[PreToolUse: check-predecessor-checkpoint.sh<br/>Verify predecessor checkpoint exists]
        L2B[PostToolUse: validate-json-envelope.sh<br/>Validate JSON envelope + test pyramid]
        L2C[PostToolUse: anti-rationalization-check.sh<br/>Detect skip patterns]
    end

    subgraph "Layer 3: AI Verification"
        L3[autopilot-gate Skill<br/>8-step checklist + special gates<br/>+ semantic validation<br/>+ brownfield validation]
    end

    L1 --> L2A
    L2A --> L2B
    L2B --> L2C
    L2C --> L3

    style L1 fill:#c8e6c9
    style L2A fill:#fff9c4
    style L2B fill:#fff9c4
    style L2C fill:#fff9c4
    style L3 fill:#ffcdd2
```

### Crash Recovery Flow

```mermaid
flowchart TD
    A[Session Start] --> B{Checkpoints exist?}
    B -->|No| C[Start from Phase 0]
    B -->|Yes| D[Scan phase-1 → phase-7]
    D --> E[Find last ok/warning phase]
    E --> F{Lock file exists?}
    F -->|Yes| G[Check PID alive + session_id]
    F -->|No| H[Resume from Phase N+1]
    G -->|Same session| I[AskUser: Override?]
    G -->|Stale/Dead| H
    I -->|Yes| H
    I -->|No| J[Abort]
    H --> K[Mark completed phases]
    K --> L[Continue pipeline]
```

### Context Compaction Recovery

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant Pre as PreCompact Hook
    participant Post as SessionStart(compact) Hook
    participant Main as Main Thread

    CC->>Pre: Context approaching limit
    Pre->>Pre: Write autopilot-state.md
    CC->>CC: Compress context
    CC->>Post: New session after compact
    Post->>Post: Read autopilot-state.md
    Post->>Main: Inject state into context
    Main->>Main: Read checkpoint files
    Main->>Main: Resume from next phase
```

## Installation

### 零配置接入（v3.0）

新项目只需一个配置文件即可运行 autopilot：

1. 安装插件: `claude plugin add lorainwings/claude-autopilot`
2. 运行 `启动autopilot [需求描述]`
3. 插件自动检测项目结构，生成 `.claude/autopilot.config.yaml`
4. 内置模板自动处理所有阶段 — 无需创建额外文件

### Step 1: Add marketplace

```bash
claude plugin marketplace add lorainwings/claude-autopilot
```

### Step 2: Install plugin

```bash
# Project-level (recommended)
claude plugin install spec-autopilot@lorainwings-plugins --scope project

# User-level (all projects)
claude plugin install spec-autopilot@lorainwings-plugins --scope user
```

### Step 3: Restart Claude Code

Restart your Claude Code session to activate the plugin.

### Verify

```bash
claude plugin list
# Should show: spec-autopilot@lorainwings-plugins
```

## Configuration

Create `.claude/autopilot.config.yaml` in your project root (or run `autopilot-init` to auto-generate):

```yaml
version: "1.0"

services:
  backend:
    health_url: "http://localhost:8080/actuator/health"

phases:
  requirements:
    agent: "business-analyst"
    min_qa_rounds: 1
    mode: "structured"           # structured | socratic
  testing:
    agent: "qa-expert"
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    serial_task:
      max_retries_per_task: 3
    worktree:
      enabled: false
  reporting:
    format: "allure"
    coverage_target: 80
    zero_skip_required: true

test_pyramid:
  min_unit_pct: 50
  max_e2e_pct: 20
  min_total_cases: 20

gates:
  user_confirmation:
    after_phase_1: true
    after_phase_3: false
    after_phase_4: false

test_suites:
  backend_unit:
    command: "cd backend && ./gradlew test"
    type: unit
    allure: junit_xml
```

> Full configuration reference: [docs/configuration.md](docs/configuration.md)

## Components

### Skills

| Skill | Invocable | Purpose |
|-------|-----------|---------|
| `autopilot` | Yes | Main 8-phase orchestrator (runs in main thread) |
| `autopilot-init` | Yes | Auto-detect tech stack, generate config |
| `autopilot-dispatch` | No | Sub-Agent dispatch with JSON envelope contract |
| `autopilot-gate` | No | 8-step checklist + special gates + semantic/brownfield validation |
| `autopilot-checkpoint` | No | Checkpoint read/write + task-level checkpoints |
| `autopilot-recovery` | No | Crash recovery via checkpoint scanning |

### Hook Scripts

| Script | Event | Purpose |
|--------|-------|---------|
| `check-predecessor-checkpoint.sh` | PreToolUse(Task) | Verify predecessor checkpoint + wall-clock timeout |
| `validate-json-envelope.sh` | PostToolUse(Task) | Validate JSON envelope + test pyramid floors |
| `anti-rationalization-check.sh` | PostToolUse(Task) | Detect rationalization/skip patterns |
| `scan-checkpoints-on-start.sh` | SessionStart | Report existing checkpoints |
| `save-state-before-compact.sh` | PreCompact | Persist orchestration state |
| `reinject-state-after-compact.sh` | SessionStart(compact) | Restore state after compression |

### Utility Scripts

| Script | Purpose |
|--------|---------|
| `validate-config.sh` | Validate autopilot.config.yaml schema |
| `collect-metrics.sh` | Aggregate per-phase execution metrics |
| `check-allure-install.sh` | Detect Allure toolchain installation |
| `_common.sh` | Shared utility functions |

## Requirements

- **Claude Code** CLI (v1.0.0+)
- **python3** (3.8+): Required for hook scripts
- **bash** (4.0+): Hook script execution
- **git**: Version control integration

## Project Setup

### 1. Generate config

```bash
# In Claude Code, invoke:
Skill("spec-autopilot:autopilot-init")
```

### 2. Create project-side skill wrapper

Create `.claude/skills/autopilot/SKILL.md`:

```markdown
---
name: autopilot
description: "Full autopilot orchestrator"
argument-hint: "[需求描述或 PRD 文件路径]"
---

调用 Skill("spec-autopilot:autopilot", args="$ARGUMENTS") 启动编排器。
```

### 3. Add phase instruction files

Place project-specific instructions in `.claude/skills/autopilot/phases/` and reference them from config's `instruction_files` arrays.

## Troubleshooting

Common issues and solutions: [docs/troubleshooting.md](docs/troubleshooting.md)

## Documentation

| Document | Content |
|----------|---------|
| [Integration Guide](docs/integration-guide.md) | Step-by-step project onboarding, config examples, checklist |
| [Architecture](docs/architecture.md) | Layer design, hook execution flow, skill interactions, data flow |
| [Configuration](docs/configuration.md) | Complete YAML field reference with types and defaults |
| [Gates](docs/gates.md) | 3-layer gate deep dive, special gates, anti-rationalization |
| [Phases](docs/phases.md) | Per-phase execution guide, I/O tables, checkpoint formats |
| [Troubleshooting](docs/troubleshooting.md) | Common errors, debugging hooks, recovery scenarios |
| [Changelog](../../CHANGELOG.md) | Version history |

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Run tests: `bash plugins/spec-autopilot/scripts/test-hooks.sh`
4. Ensure all bash scripts pass syntax check: `bash -n plugins/spec-autopilot/scripts/*.sh`
5. Ensure JSON files are valid
6. Submit a pull request

## License

MIT

> **[中文版](README.zh.md)** | English (default)

# stoicatom-plugins

> A Claude Code plugin marketplace — spec-driven autopilot orchestration and parallel AI engineering control-plane.

[![CI](https://github.com/stoicatom/claude-autopilot/actions/workflows/ci.yml/badge.svg)](https://github.com/stoicatom/claude-autopilot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Plugins

| Plugin | Version | Description |
|--------|---------|-------------|
| [spec-autopilot](plugins/spec-autopilot/) | 5.15.2 | Spec-driven autopilot orchestration for delivery pipelines — 8-phase workflow with 3-layer gate system and crash recovery |
| [parallel-harness](plugins/parallel-harness/) | 1.9.1 | Parallel AI engineering control-plane — task-graph scheduling, 9-gate system, RBAC governance, cost-aware model routing |
| [daily-report](plugins/daily-report/README.md) | 1.3.0 | Auto-generate and submit daily work reports from git commits and Lark chat history |
| [figma-codegen](plugins/figma-codegen/README.md) | 1.0.0 | Translate Figma designs into production-ready code with 1:1 visual fidelity (adapted from OpenAI figma-implement-design) |
| [slim-task](plugins/slim-task/README.md) | 0.7.0 | Structured 7-phase task execution SOP with multi-language & worktree support — session init, requirements clarification, impact scoping, DAG-based parallel dispatch, blind-audit quality review |

## Quick Install

```bash
# 1. Add marketplace
claude plugin marketplace add stoicatom/claude-autopilot

# 2. Install spec-autopilot (project-level)
claude plugin install spec-autopilot@stoicatom-plugins --scope project

# 3. Install parallel-harness (project-level)
claude plugin install parallel-harness@stoicatom-plugins --scope project

# 4. Install daily-report (project-level)
claude plugin install daily-report@stoicatom-plugins --scope project

# 5. Install figma-codegen (project-level)
claude plugin install figma-codegen@stoicatom-plugins --scope project

# 6. Install slim-task (project-level)
claude plugin install slim-task@stoicatom-plugins --scope project

# 7. Restart Claude Code
```

## What is spec-autopilot?

**spec-autopilot** is a Claude Code plugin that automates the full software delivery lifecycle: from requirements gathering through implementation, testing, reporting, and archival.

### Key Features

- **8-Phase Pipeline** — Requirements → OpenSpec → FF Generate → Test Design → Implementation → Test Report → Archive
- **3-Layer Gate System** — TaskCreate dependencies + Hook checkpoint validation + AI checklist verification
- **Crash Recovery** — Automatic checkpoint scanning and session resume
- **Anti-Rationalization** — 16 pattern detection to prevent sub-agents from skipping work
- **TDD Cycle** — RED-GREEN-REFACTOR with deterministic L2 validation
- **Requirements Routing** — Auto-classify as Feature/Bugfix/Refactor/Chore with dynamic gate thresholds
- **Event Bus** — Real-time event streaming via `events.jsonl` + WebSocket
- **GUI V2 Dashboard** — Three-column real-time dashboard with decision_ack feedback loop
- **Parallel Execution** — Domain-level parallel agents with file ownership enforcement
- **Modular Test Suite** — 104 test files with 1245+ assertions

### Architecture

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
        P5[Phase 5: Implementation<br/>Serial / Parallel / TDD]
        P6[Phase 6: Test Report]
    end

    P0 --> P1
    P1 -->|Gate| P2
    P2 -->|Gate| P3
    P3 -->|Gate| P4
    P4 -->|Gate| P5
    P5 -->|Gate| P6
    P6 --> P7

    style P0 fill:#e1f5fe
    style P1 fill:#e1f5fe
    style P7 fill:#e1f5fe
    style P4 fill:#fff3e0
    style P5 fill:#fff3e0
```

## What is parallel-harness?

**parallel-harness** is a Claude Code plugin that provides a task-graph-driven parallel AI engineering platform. It enables multi-agent orchestration with strict governance, cost control, and quality gates.

### Key Features

- **Task Graph Orchestration** — Decompose complex requirements into a structured DAG with dependency tracking
- **Multi-Agent Parallel Scheduling** — Execute independent tasks concurrently with strict file ownership isolation
- **Cost-Aware Model Routing** — 3-tier automatic routing with escalation, downgrade, and budget control
- **9-Gate System** — test, lint, review, security, perf, coverage, policy, documentation, release readiness
- **Policy-as-Code** — Declarative policy rules with path boundaries, budget limits, model tier caps
- **RBAC Governance** — 4 built-in roles (admin/developer/reviewer/viewer), 12 fine-grained permissions
- **Audit Trail** — Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration** — GitHub PR creation, review comments, CI failure analysis via `gh` CLI
- **Session Persistence** — Memory/file dual adapters with checkpoint recovery

### Architecture

```mermaid
graph LR
    A[User Intent] --> B[Intent Analyzer]
    B --> C[Task Graph Builder]
    C --> D["TaskGraph (DAG)"]
    D --> E[Ownership Planner]
    E --> F[Scheduler]
    F --> G["SchedulePlan (batches)"]
    G --> H[Context Packager]
    H --> I[Model Router]
    I --> J[Worker Runtime]
    J --> K[Gate System]
    K --> L[Merge Guard]
    L --> M[PR Provider]
    M --> N[Result Synthesizer]
    N --> O[QualityReport]
```

## What is daily-report?

**daily-report** is a Claude Code Skill plugin that automates internal daily work report generation and submission. It aggregates git commit history and Lark (Feishu) chat messages to produce structured reports with automatic categorization and time allocation.

### Key Features

- **Multi-Source Aggregation** — Combines git commit logs and Lark chat history for comprehensive daily reports
- **Parallel Data Collection** — Multi-Agent architecture for concurrent git repo scanning, Lark group crawling, and API queries
- **Auto-Categorization** — Keyword-based intelligent work item classification (development, bugfix, refactoring, docs, meetings)
- **Smart Time Allocation** — 8h/day proportional distribution with 0.5h granularity
- **AES Encrypted Login** — Secure AES-256-CBC password encryption for internal system authentication
- **Token Auto-Refresh** — Automatic credential management with expired token re-authentication
- **Batch Submission** — One-click submission with duplicate date detection and auto-skip
- **Interactive Review** — Table-format preview with AskUserQuestion confirmation before submission

### Workflow

```mermaid
flowchart TD
    START[/daily-report/] --> INIT{First run?}
    INIT -->|yes| P0["Phase 0: Init<br/>lark-cli + login + git config"]
    INIT -->|no| P1["Phase 1: Env Check"]
    P0 --> P1
    P1 --> TOKEN{Token expired?}
    TOKEN -->|yes| REFRESH[Auto re-login] --> P2
    TOKEN -->|no| P2["Phase 2: Data Collection<br/>(5-way parallel)"]
    P2 --> GIT[Agent 1: Git commits]
    P2 --> LARK[Agent 2: Lark messages]
    P2 --> API1[API: Categories]
    P2 --> API2[API: Departments]
    P2 --> API3[API: Projects]
    GIT & LARK & API1 & API2 & API3 --> P3["Phase 3: Report Generation"]
    P3 --> CAT[Auto-categorize + 8h allocation] --> REVIEW{AskUserQuestion<br/>confirm?}
    REVIEW -->|approve| P4["Phase 4: Batch Submit"]
    REVIEW -->|edit| P3
    P4 --> DUP{Duplicate date?}
    DUP -->|yes| SKIP[Auto-skip] --> NEXT
    DUP -->|no| SUB[API submit] --> NEXT{More dates?}
    NEXT -->|yes| DUP
    NEXT -->|no| DONE((Done))
```

## What is figma-codegen?

**figma-codegen** is a Claude Code Skill plugin that translates Figma designs into production-ready code with 1:1 visual fidelity. It is a faithful adaptation of OpenAI's official [figma-implement-design](https://github.com/openai/skills/tree/main/skills/.curated/figma-implement-design) skill, tuned for the Claude Code ecosystem.

### Key Features

- **7-Step Deterministic Workflow** — Get Node ID → Fetch Design Context → Capture Screenshot → Download Assets → Translate to Project Conventions → Achieve 1:1 Visual Parity → Validate Against Figma
- **Three Figma MCP Modes** — Remote MCP / Figma Desktop MCP / local `figma-developer-mcp`; Desktop mode supports selection-based prompting (no URL needed)
- **Reference vs Final Code** — Treats Figma MCP output (typically React + Tailwind) as design intent reference, replaces utility classes with project tokens, reuses existing components
- **Asset Hard Rules** — `localhost`-served assets used directly; never replace MCP-returned assets with placeholders or third-party icon packs
- **Design System First** — Prefers project design tokens over literal Figma values; allows minimal spacing/sizing adjustments to maintain visual fidelity
- **Validation Checklist** — 7-dimension checklist (layout, typography, colors, interactive states, responsive, assets, accessibility) before completion
- **Faithful Upstream Adaptation** — SKILL.md mirrors OpenAI's 7-step structure, easy to diff-merge upstream improvements

### Workflow

```mermaid
flowchart TD
    URL["Figma URL or Desktop selection"] --> S1["Step 1<br/>Get Node ID"]
    S1 --> S2["Step 2<br/>get_design_context"]
    S2 --> LARGE{Response too large?}
    LARGE -->|yes| META[get_metadata → child nodes]
    META --> S2
    LARGE -->|no| S3["Step 3<br/>get_screenshot"]
    S3 --> S4["Step 4<br/>Download assets<br/>(no placeholders)"]
    S4 --> S5["Step 5<br/>Translate to project conventions<br/>Tailwind → tokens<br/>reuse components"]
    S5 --> S6["Step 6<br/>1:1 visual parity"]
    S6 --> S7["Step 7<br/>Validate against Figma"]
    S7 --> CHECK{Checklist passes?}
    CHECK -->|no| S5
    CHECK -->|yes| DONE((Deliver))
```

## What is slim-task?

**slim-task** is a pure-Skill Claude Code plugin that provides a 7-phase Standard Operating Procedure (SOP) for AI task execution. It solves 8 recurring failure modes when AI agents implement coding tasks — from skipping requirements clarification to self-grading the work they just produced — and turns each task into an auditable, parallelizable, isolated workflow.

### Key Features

- **Main-Check-Sub-Execute** — Main agent only inspects/decides/dispatches/verifies; implementation and quality audits are always done by independent sub-agents
- **Multi-Language Configuration** — `--lang` flag with `.claude/slim-task.json` persistence; all AI dialogue, decision cards, generated docs, and sub-agent prompts respect the configured language (default `zh-CN`); Conventional Commits prefixes stay English
- **Worktree Isolation** — Optional `--worktree` / `--base` runs the full pipeline inside a dedicated git worktree via Claude Code's native `EnterWorktree`; commits never auto-merge or push to `main`
- **DAG-Based Parallel Dispatch** — Sub-tasks decomposed into a dependency DAG, same-layer tasks dispatched simultaneously with no concurrency limit
- **Impact-Scope Contract** — Mandatory file-level impact scope table approved by the user before any code change; out-of-scope edits are forbidden
- **Phase 5 Blind Audit (Anti-Cheat)** — Quality review delegated to three independent auditor sub-agents (`scope-auditor` / `practice-auditor` / `engineering-auditor`) in isolated context; the implementing agent is forbidden from grading its own work
- **7 User Checkpoints** — Every phase transition requires explicit user confirmation; commits require an additional `AskUserQuestion` authorization

### Workflow

```mermaid
flowchart TD
    P0["Phase 0<br/>Session Init"] --> WT{--worktree?}
    WT -->|yes| EW[EnterWorktree] --> P1
    WT -->|no| P1["Phase 1<br/>Requirements Clarification"]
    P1 --> P2["Phase 2<br/>Solution Design + Impact Scope"]
    P2 --> P3["Phase 3<br/>Documentation + DAG Split"]
    P3 --> DAG{DAG nodes}
    DAG -->|single| INL[Main agent inline] --> P5
    DAG -->|multiple| PAR["Phase 4<br/>Parallel sub-agent dispatch"] --> P5
    P5["Phase 5<br/>Blind Audit"] --> UI{UI change?}
    UI -->|yes| VIS[Visual review Skill] --> AUD
    UI -->|no| AUD{All 3 audits pass?}
    AUD -->|issues, <3 rounds| FIX[Fixer agent] --> P5
    AUD -->|3 rounds failed| STOP((Manual intervention))
    AUD -->|all pass| P6["Phase 6<br/>Commit decision card"]
    P6 --> COMMIT[git commit] --> P6P[Push decision card]
    P6P --> WTM{Worktree mode?}
    WTM -->|yes| NOPUSH[No push to main] --> END((Done))
    WTM -->|no| PUSH[Push / PR per user choice] --> END
```

## Documentation

### spec-autopilot

| Document | Description |
|----------|-------------|
| [Quick Start](plugins/spec-autopilot/docs/getting-started/quick-start.md) | 5-minute quick start guide |
| [Integration Guide](plugins/spec-autopilot/docs/getting-started/integration-guide.md) | Step-by-step project onboarding |
| [Configuration](plugins/spec-autopilot/docs/getting-started/configuration.md) | Complete YAML field reference |
| [Architecture](plugins/spec-autopilot/docs/architecture/overview.md) | System architecture overview |
| [Phases](plugins/spec-autopilot/docs/architecture/phases.md) | Per-phase execution guide |
| [Gates](plugins/spec-autopilot/docs/architecture/gates.md) | 3-layer gate deep dive |
| [Config Tuning](plugins/spec-autopilot/docs/operations/config-tuning-guide.md) | Per-project-type optimization |
| [Troubleshooting](plugins/spec-autopilot/docs/operations/troubleshooting.md) | Common errors and recovery |
| [Plugin README](plugins/spec-autopilot/README.md) | Full plugin documentation |
| [Changelog](plugins/spec-autopilot/CHANGELOG.md) | Version history |

> All documentation is available in both [English](plugins/spec-autopilot/docs/README.md) and [中文](plugins/spec-autopilot/docs/README.zh.md).

### parallel-harness

| Document | Description |
|----------|-------------|
| [Architecture](plugins/parallel-harness/docs/architecture/overview.md) | System architecture overview |
| [Operator Guide](plugins/parallel-harness/docs/operator-guide.md) | Installation, deployment, operations |
| [Policy Guide](plugins/parallel-harness/docs/policy-guide.md) | Policy rule configuration |
| [Integration Guide](plugins/parallel-harness/docs/integration-guide.md) | GitHub PR, CI, custom gates, hooks |
| [Admin Guide](plugins/parallel-harness/docs/admin-guide.md) | Administration and RBAC setup |
| [Troubleshooting](plugins/parallel-harness/docs/troubleshooting.md) | Common errors and solutions |
| [Examples](plugins/parallel-harness/docs/examples/basic-flow.md) | Step-by-step flow examples |
| [FAQ](plugins/parallel-harness/docs/FAQ.md) | Frequently asked questions |
| [Plugin README](plugins/parallel-harness/README.md) | Full plugin documentation |

### daily-report

| Document | Description |
|----------|-------------|
| [Setup Guide](plugins/daily-report/skills/daily-report/references/setup-guide.md) | First-time initialization walkthrough |
| [Plugin README](plugins/daily-report/README.md) | Full plugin documentation |
| [Changelog](plugins/daily-report/CHANGELOG.md) | Version history |

### figma-codegen

| Document | Description |
|----------|-------------|
| [Plugin README](plugins/figma-codegen/README.md) | Full plugin documentation |
| [CLAUDE.md](plugins/figma-codegen/CLAUDE.md) | Plugin-specific engineering rules |
| [Changelog](plugins/figma-codegen/CHANGELOG.md) | Version history |

### slim-task

| Document | Description |
|----------|-------------|
| [Plugin README](plugins/slim-task/README.md) | Full plugin documentation, parameter reference, worktree notes |
| [SKILL.md](plugins/slim-task/skills/slim-task/SKILL.md) | 7-phase SOP definition, sub-agent prompt templates |
| [CLAUDE.md](plugins/slim-task/CLAUDE.md) | Plugin engineering rules, Worktree hard constraints, Phase 5 anti-cheat isolation |
| [Changelog](plugins/slim-task/CHANGELOG.md) | Version history |

## Requirements

- **Claude Code** CLI (v1.0.0+)
- **python3** (3.8+) — required for spec-autopilot hook scripts
- **bun** (1.0+) — required for parallel-harness runtime and tests
- **bash** (4.0+) — hook script execution
- **Node.js** — required for daily-report (lark-cli dependency)
- **git** — version control integration

## Repository Structure

```
claude-autopilot/
├── .claude-plugin/          # Marketplace configuration
│   └── marketplace.json
├── .github/workflows/       # CI/CD
│   ├── ci.yml               # Unified CI entry (detect → matrix → summary)
│   ├── ci-sweep.yml         # Scheduled full sweep
│   └── release-please.yml
├── .githooks/               # Git hooks (pre-commit, pre-push)
├── dist/                    # Built plugins (for marketplace install)
│   ├── spec-autopilot/
│   ├── parallel-harness/
│   ├── daily-report/
│   ├── figma-codegen/
│   └── slim-task/
├── plugins/                 # Plugin source code
│   ├── spec-autopilot/
│   │   ├── skills/          # 12 Skill definitions
│   │   ├── scripts/         # Hook scripts + utilities
│   │   ├── hooks/           # Hook registration
│   │   ├── gui/             # GUI V2 dashboard (React + Tailwind)
│   │   ├── tests/           # 104 test files, 1245+ assertions
│   │   └── docs/            # Full documentation (EN + ZH)
│   ├── parallel-harness/
│   │   ├── runtime/         # 17 core modules (engine, orchestrator, scheduler, etc.)
│   │   ├── skills/          # Skill definitions (harness, plan, dispatch, verify)
│   │   ├── config/          # Default config + policy files
│   │   ├── tools/           # CLI tools and utilities
│   │   ├── tests/           # 295 tests, 649 assertions
│   │   └── docs/            # Full documentation
│   ├── daily-report/
│   │   └── skills/          # Skill definition + setup guide
│   ├── figma-codegen/
│   │   └── skills/          # Skill definition + vendor-specific references
│   └── slim-task/
│       └── skills/          # 7-phase SOP Skill (pure Markdown, no runtime)
├── Makefile                 # Build, test, setup shortcuts
├── README.md                # This file
├── LICENSE                  # MIT License
├── CONTRIBUTING.md          # Contribution guidelines
└── SECURITY.md              # Security policy
```

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Plugin-only changes trigger only the matching plugin CI jobs within the unified `ci.yml` workflow. After a release PR is merged into `main`, `release-please` and the post-release job rebuild `dist/`, sync plugin docs, refresh the root README version table, and update `.claude-plugin/marketplace.json`.

```bash
# Clone the repository
git clone https://github.com/stoicatom/claude-autopilot.git
cd claude-autopilot

# One-time setup: activate git hooks
make setup

# Run tests
make test

# Build distribution
make build
```

## Security

For security concerns, please see [SECURITY.md](SECURITY.md).

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

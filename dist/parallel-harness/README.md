> **[中文版](README.zh.md)** | English (default)

# parallel-harness

> A parallel AI platform / AI software engineering control plane plugin for Claude Code.

[![Version](https://img.shields.io/badge/version-0.1.0-blue.svg)](package.json)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Overview

**parallel-harness** is the second plugin in the [lorainwings-plugins](https://github.com/lorainwings/claude-autopilot) marketplace, sitting alongside **spec-autopilot**. While spec-autopilot focuses on *spec-driven sequential delivery pipelines* (8-phase workflow with 3-layer gates), parallel-harness addresses a different challenge: **intelligent decomposition and parallel orchestration of complex software engineering tasks**.

### Core Design Principles

| Principle | Meaning |
|-----------|---------|
| **Task-Graph-First** | Every user intent is decomposed into a directed acyclic task graph before any work begins |
| **Model-Routing-Aware** | Tasks are dispatched to the most cost-effective model tier (tier-1/2/3) based on complexity |
| **Verifier-Driven** | No result is accepted without passing through a verification swarm (test, review, security, perf) |
| **CI/PR Ready** | Outputs are designed to integrate directly into CI pipelines and PR workflows |

## Features

### Task Graph Engine
- **Intent Analyzer**: Parse natural language into structured engineering intents with action/scope/constraints extraction
- **Task Graph Builder**: Decompose intents into DAG-structured task nodes with typed dependencies
- **Complexity Scorer**: Multi-dimensional scoring (algorithmic, integration, domain, ambiguity) for routing decisions
- **Ownership Planner**: File-level isolation planning with conflict detection and merge guards

### Scheduler
- **Parallel Execution**: Dependency-aware parallel dispatch with configurable concurrency limits
- **Priority Strategies**: FIFO, critical-path, and cost-optimized scheduling strategies
- **Execution Planning**: Pre-execution plan generation with estimated timelines and resource allocation

### Model Router
- **Tier-Based Routing**: Three-tier model classification (tier-1: flagship, tier-2: balanced, tier-3: fast)
- **Cost Estimation**: Per-task token budget estimation and aggregate cost tracking
- **Escalation Policy** (reserved): Automatic escalation to higher tiers on verification failure

### Verifier Swarm
- **Test Verifier**: Automated test execution and result validation
- **Review Verifier**: Code quality and style conformance checking
- **Security Verifier**: Vulnerability pattern scanning and dependency audit
- **Performance Verifier**: Benchmark regression detection
- **Result Synthesizer**: Aggregate multi-verifier results into a unified verdict

### Context Packager
- **Minimal Context Packs**: Extract only the files and symbols relevant to each task
- **Relevance Scoring**: TF-IDF-inspired scoring to rank context segments by relevance
- **Token Management**: Hard token budget enforcement with graceful degradation

## Architecture

```
+------------------------------------------------------------------+
|                    Layer 5: Engineering Control Plane              |
|          (event-bus, observability, session-state) [reserved]     |
+------------------------------------------------------------------+
|                    Layer 4: Verifier Swarm                        |
|    test-verifier | review-verifier | security-verifier |         |
|    perf-verifier | result-synthesizer                            |
+------------------------------------------------------------------+
|                    Layer 3: Model Router                          |
|       model-router | cost-controller | escalation-policy         |
+------------------------------------------------------------------+
|                    Layer 2: Scheduling & Execution                |
|    scheduler | worker-dispatch | retry-manager | downgrade-mgr   |
+------------------------------------------------------------------+
|                    Layer 1: Task Understanding                    |
|    intent-analyzer | task-graph-builder | complexity-scorer |     |
|    ownership-planner                                             |
+------------------------------------------------------------------+

Data Flow:
  User Input --> Intent Analyzer --> Task Graph Builder
       --> Complexity Scorer --> Ownership Planner
       --> Scheduler --> Model Router --> [Execution]
       --> Verifier Swarm --> Result Synthesizer --> Output
```

## Quick Start

### Installation

```bash
# Clone the repository
git clone https://github.com/lorainwings/claude-autopilot.git
cd claude-autopilot

# Install dependencies
cd plugins/parallel-harness
bun install

# Type check
bun run typecheck
```

### Basic Usage

parallel-harness is activated through Claude Code's plugin system. Once installed, it intercepts complex multi-file tasks and automatically:

1. Analyzes the user's intent and decomposes it into a task graph
2. Scores complexity and plans file ownership
3. Schedules tasks for parallel execution with appropriate model tiers
4. Verifies results through the verification swarm
5. Synthesizes a final verdict and delivers the output

## Project Structure

```
plugins/parallel-harness/
├── .claude-plugin/
│   └── plugin.json            # Plugin manifest
├── docs/
│   ├── architecture.zh.md     # Detailed architecture (Chinese)
│   └── mvp-scope.zh.md        # MVP scope & roadmap (Chinese)
├── runtime/
│   ├── models/                # Model tier definitions & routing
│   ├── orchestrator/          # Core orchestration logic
│   │   ├── intent-analyzer.ts
│   │   ├── task-graph-builder.ts
│   │   ├── complexity-scorer.ts
│   │   ├── ownership-planner.ts
│   │   └── context-packager.ts
│   ├── scheduler/             # Parallel scheduling engine
│   │   └── scheduler.ts
│   ├── schemas/               # TypeScript type definitions
│   │   ├── task-node.ts
│   │   ├── task-graph.ts
│   │   ├── intent.ts
│   │   ├── complexity.ts
│   │   ├── ownership.ts
│   │   └── verifier-result.ts
│   ├── session/               # Session state management
│   │   └── session-store.ts
│   └── verifiers/             # Verification swarm
│       ├── test-verifier.ts
│       ├── review-verifier.ts
│       ├── security-verifier.ts
│       ├── perf-verifier.ts
│       └── result-synthesizer.ts
├── skills/                    # Claude Code skill definitions
├── tests/                     # Test suite
├── tools/                     # Build & utility scripts
├── package.json
├── tsconfig.json
├── README.md                  # This file (English)
└── README.zh.md               # Chinese version
```

## Differences from spec-autopilot

| Dimension | spec-autopilot | parallel-harness |
|-----------|---------------|-----------------|
| **Core Paradigm** | Spec-driven sequential pipeline | Task-graph-driven parallel orchestration |
| **Workflow** | Fixed 8-phase linear flow | Dynamic DAG-based task scheduling |
| **Quality Gate** | 3-layer gate system (L1/L2/L3) | Verifier swarm (test/review/security/perf) |
| **Parallelism** | Domain-level (backend/frontend/node) | Task-level with dependency-aware scheduling |
| **Model Strategy** | Single model throughout | Tier-based routing per task complexity |
| **File Safety** | Ownership enforcement per domain | Fine-grained file-level isolation with merge guards |
| **Target Users** | Full delivery lifecycle automation | Complex multi-file engineering tasks |
| **Complexity Handling** | Requirements routing (Feature/Bugfix/Refactor/Chore) | Multi-dimensional complexity scoring |
| **State Model** | Phase checkpoint + crash recovery | Task graph state + session persistence |

## Status

**Current Version: 0.1.0 (Alpha)**

This is the initial alpha release focused on the MVP feature set:

- Task understanding layer (intent analysis, task graph, complexity scoring, ownership planning)
- Basic scheduling with parallel execution
- Model router with tier-based classification
- Verifier swarm with result synthesis
- Context packager with token management

See [docs/mvp-scope.zh.md](docs/mvp-scope.zh.md) for the full MVP scope and roadmap.

## License

[MIT](LICENSE)

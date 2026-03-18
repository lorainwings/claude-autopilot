> **[中文版](README.zh.md)** | English (default)

# spec-autopilot Documentation

> This index covers all documentation for spec-autopilot v5.1, organized by category. Includes Event Bus, GUI V2 Dashboard, parallel dispatch, requirements routing, and more.

## Getting Started (`getting-started/`)

| Document | Description |
|----------|-------------|
| [quick-start.md](getting-started/quick-start.md) | 5-minute quick start: from installation to first delivery |
| [integration-guide.md](getting-started/integration-guide.md) | Integration guide: complete onboarding process for new projects |
| [configuration.md](getting-started/configuration.md) | Configuration reference: complete YAML field documentation |

## Architecture Reference (`architecture/`)

| Document | Description |
|----------|-------------|
| [overview.md](architecture/overview.md) | Architecture overview: 8-phase pipeline, 3-layer gates, Event Bus, GUI V2, parallel dispatch, routing |
| [phases.md](architecture/phases.md) | Phase details: I/O, checkpoint formats, requirements routing, TDD cycle, event emission |
| [gates.md](architecture/gates.md) | Gate system: 3-layer gates, anti-rationalization (16 patterns), routing_overrides, decision_ack loop |

## Operations Guide (`operations/`)

| Document | Description |
|----------|-------------|
| [config-tuning-guide.md](operations/config-tuning-guide.md) | Configuration tuning: optimize config by project type |
| [troubleshooting.md](operations/troubleshooting.md) | Troubleshooting: common errors, debugging tips, recovery scenarios |

## Migration Guide (`migration/`)

| Document | Description |
|----------|-------------|
| [v4-to-v5.md](migration/v4-to-v5.md) | v4 → v5 migration: config schema changes, hook protocol, Event Bus, compatibility matrix |

## Audit Reports (`reports/`)

> Organized by plugin version in subdirectories, reverse chronological order (newest first).

### v5.0.10

| Document | Description |
|----------|-------------|
| [v5.3-evaluation-dashboard.md](reports/v5.0.10/v5.3-evaluation-dashboard.md) | v5.3 full 7-Agent parallel evaluation dashboard |
| [compliance-audit-v5.3.md](reports/v5.0.10/compliance-audit-v5.3.md) | Compliance audit |
| [performance-benchmark-v5.3.md](reports/v5.0.10/performance-benchmark-v5.3.md) | Performance benchmark |
| [holistic-simulation-benchmark-v5.3.md](reports/v5.0.10/holistic-simulation-benchmark-v5.3.md) | Holistic simulation benchmark |
| [competitive-analysis-v5.3.md](reports/v5.0.10/competitive-analysis-v5.3.md) | Competitive analysis |
| [gui-interaction-audit-v5.3.md](reports/v5.0.10/gui-interaction-audit-v5.3.md) | GUI interaction audit |
| [infrastructure-audit-v5.3.md](reports/v5.0.10/infrastructure-audit-v5.3.md) | Infrastructure audit |
| [routing-socratic-benchmark-v5.3.md](reports/v5.0.10/routing-socratic-benchmark-v5.3.md) | Routing + Socratic benchmark |

### v5.0.7

| Document | Description |
|----------|-------------|
| [regression-report.md](reports/v5.0.7/regression-report.md) | Regression test report |

### v5.0.5

| Document | Description |
|----------|-------------|
| [v5.1.1-evaluation-dashboard.md](reports/v5.0.5/v5.1.1-evaluation-dashboard.md) | v5.1.1 evaluation dashboard |
| [compliance-audit-v5.1.1.md](reports/v5.0.5/compliance-audit-v5.1.1.md) | Compliance audit |
| [stability-audit-v5.1.1.md](reports/v5.0.5/stability-audit-v5.1.1.md) | Stability audit |
| [performance-benchmark-v5.1.1.md](reports/v5.0.5/performance-benchmark-v5.1.1.md) | Performance benchmark |
| [phase1-benchmark-v5.1.1.md](reports/v5.0.5/phase1-benchmark-v5.1.1.md) | Phase 1 benchmark |
| [competitive-analysis-v5.1.1.md](reports/v5.0.5/competitive-analysis-v5.1.1.md) | Competitive analysis |
| [gui-interaction-audit-v5.1.1.md](reports/v5.0.5/gui-interaction-audit-v5.1.1.md) | GUI interaction audit |
| [holistic-simulation-benchmark-v5.1.1.md](reports/v5.0.5/holistic-simulation-benchmark-v5.1.1.md) | Holistic simulation benchmark |
| [hotfix-verification.md](reports/v5.0.5/hotfix-verification.md) | Hotfix verification |

### v5.0.4

| Document | Description |
|----------|-------------|
| [v5.0.4-evaluation-dashboard.md](reports/v5.0.4/v5.0.4-evaluation-dashboard.md) | v5.0.4 evaluation dashboard |
| [compliance-audit.md](reports/v5.0.4/compliance-audit.md) | Compliance audit |
| [stability-audit.md](reports/v5.0.4/stability-audit.md) | Stability audit |
| [performance-benchmark.md](reports/v5.0.4/performance-benchmark.md) | Performance benchmark |
| [phase1-benchmark.md](reports/v5.0.4/phase1-benchmark.md) | Phase 1 benchmark |
| [competitive-analysis.md](reports/v5.0.4/competitive-analysis.md) | Competitive analysis |
| [gui-interaction-audit.md](reports/v5.0.4/gui-interaction-audit.md) | GUI interaction audit |
| [holistic-simulation-benchmark.md](reports/v5.0.4/holistic-simulation-benchmark.md) | Holistic simulation benchmark |

### v5.0

| Document | Description |
|----------|-------------|
| [v5.0.2-evaluation-dashboard.md](reports/v5.0/v5.0.2-evaluation-dashboard.md) | v5.0.2 evaluation dashboard |
| [compliance-audit.md](reports/v5.0/compliance-audit.md) | Compliance audit |
| [stability-audit.md](reports/v5.0/stability-audit.md) | Stability audit |
| [performance-benchmark.md](reports/v5.0/performance-benchmark.md) | Performance benchmark |
| [phase1-benchmark.md](reports/v5.0/phase1-benchmark.md) | Phase 1 benchmark |
| [competitive-analysis.md](reports/v5.0/competitive-analysis.md) | Competitive analysis |
| [gui-interaction-audit.md](reports/v5.0/gui-interaction-audit.md) | GUI interaction audit |
| [holistic-simulation-benchmark.md](reports/v5.0/holistic-simulation-benchmark.md) | Holistic simulation benchmark |

### v4.2

| Document | Description |
|----------|-------------|
| [competitive-analysis.md](reports/v4.2/competitive-analysis.md) | Competitive analysis |

### v4.1

| Document | Description |
|----------|-------------|
| [iteration-v1-impact.md](reports/v4.1/iteration-v1-impact.md) | Iteration v1 impact analysis |

### v4.0

| Document | Description |
|----------|-------------|
| [stability-audit.md](reports/v4.0/stability-audit.md) | Full-mode stability and end-to-end audit |
| [phase1-benchmark.md](reports/v4.0/phase1-benchmark.md) | Phase 1 requirements quality benchmark |
| [phase5-codegen-audit.md](reports/v4.0/phase5-codegen-audit.md) | Phase 5 code generation quality review |
| [phase6-tdd-audit.md](reports/v4.0/phase6-tdd-audit.md) | Phase 6 TDD process review |
| [performance-benchmark.md](reports/v4.0/performance-benchmark.md) | Full-phase performance evaluation |
| [competitive-analysis.md](reports/v4.0/competitive-analysis.md) | In-depth competitive analysis |
| [architecture-evolution.md](reports/v4.0/architecture-evolution.md) | Architecture evolution guide |

### v3.6

| Document | Description |
|----------|-------------|
| [ecosystem-analysis.md](reports/v3.6/ecosystem-analysis.md) | Comprehensive ecosystem analysis |

## Roadmap (`roadmap/`)

| Document | Description |
|----------|-------------|
| [2026-03-18-scripts-engineering-refactor-blueprint.md](roadmap/2026-03-18-scripts-engineering-refactor-blueprint.md) | Professional blueprint for scripts engineering refactor: runtime contract, manifest build, server split, legacy deprecation |
| [v5.1.0-execution-plan.md](roadmap/v5.1.0-execution-plan.md) | v5.1.0 execution plan |
| [v5.0.10-analysis-report.md](roadmap/v5.0.10-analysis-report.md) | v5.0.10 analysis report |
| [v5.0.8/ui-upgrade.md](roadmap/v5.0.8/ui-upgrade.md) | v5.0.8 GUI V2 upgrade |
| [v5.0.8/ui-redesign-prd.md](roadmap/v5.0.8/ui-redesign-prd.md) | v5.0.8 UI redesign PRD |
| [v5.0.8/v5.3-ui-refactor.md](roadmap/v5.0.8/v5.3-ui-refactor.md) | v5.3 UI refactor |
| [v5.0.7-excellence-refactor.md](roadmap/v5.0.7-excellence-refactor.md) | v5.0.7 excellence refactor |
| [v5.0.6-sprint-to-90.md](roadmap/v5.0.6-sprint-to-90.md) | v5.0.6 sprint to 90 |
| [v5.0.5-execution-plan.md](roadmap/v5.0.5-execution-plan.md) | v5.0.5 execution plan |
| [v5.0.5-full-evaluation.md](roadmap/v5.0.5-full-evaluation.md) | v5.0.5 full evaluation |
| [v5.0.5-hotfix-verification.md](roadmap/v5.0.5-hotfix-verification.md) | v5.0.5 hotfix verification |
| [v5.0.4-execution-plan.md](roadmap/v5.0.4-execution-plan.md) | v5.0.4 execution plan |
| [v5.0.3-execution-plan.md](roadmap/v5.0.3-execution-plan.md) | v5.0.3 execution plan |
| [v5.0.2-execution-plan.md](roadmap/v5.0.2-execution-plan.md) | v5.0.2 execution plan |
| [v5.0.1-execution-plan.md](roadmap/v5.0.1-execution-plan.md) | v5.0.1 execution plan |
| [v5.0-execution-plan.md](roadmap/v5.0-execution-plan.md) | v5.0 execution plan |
| [v4.3-execution-plan.md](roadmap/v4.3-execution-plan.md) | v4.3 execution plan |
| [v4.2-execution-plan.md](roadmap/v4.2-execution-plan.md) | v4.2 execution plan |
| [v4.1-execution-plan.md](roadmap/v4.1-execution-plan.md) | v4.1 execution plan |
| [v4.1-post-iteration-impact-analysis.md](roadmap/v4.1-post-iteration-impact-analysis.md) | v4.1 post-iteration impact analysis |
| [v4.0-upgrade-blueprint.md](roadmap/v4.0-upgrade-blueprint.md) | v4.0 upgrade blueprint |

## Audit Tools (`benchmark/`)

| Document | Description |
|----------|-------------|
| [prompt.md](benchmark/prompt.md) | Audit orchestration meta-prompt: comprehensive evaluation task template |
| [validate.md](benchmark/validate.md) | Refactor execution meta-prompt: report-driven refactor task template |

## Archive (`archive/`)

| Document | Original Version |
|----------|-----------------|
| [evaluation-report-v2.0.0.md](archive/evaluation-report-v2.0.0.md) | v2.0.0 evaluation report |
| [self-evaluation-report-v3.6.0.md](archive/self-evaluation-report-v3.6.0.md) | v3.6.0 self-evaluation report |
| [v3.6.0-qa-report.md](archive/v3.6.0-qa-report.md) | v3.6.0 QA report |
| [v3.6.0-final-report.md](archive/v3.6.0-final-report.md) | v3.6.0 final report |
| [competitive-analysis-v1.0.md](archive/competitive-analysis-v1.0.md) | Competitive analysis v1.0 |
| [product-analysis-v3.2.0.md](archive/product-analysis-v3.2.0.md) | Product analysis v3.2.0 |
| [enhancement-roadmap-v3.2.0.md](archive/enhancement-roadmap-v3.2.0.md) | Enhancement roadmap v3.2.0 |
| [comprehensive-analysis-v3.2.2.md](archive/comprehensive-analysis-v3.2.2.md) | Comprehensive analysis v3.2.2 |
| [deep-analysis-v3.4.3.md](archive/deep-analysis-v3.4.3.md) | Deep analysis v3.4.3 |
| [v3.2.0-design.md](archive/v3.2.0-design.md) | v3.2.0 design document |
| [v3.5.0-iteration-plan.md](archive/v3.5.0-iteration-plan.md) | v3.5.0 iteration plan |

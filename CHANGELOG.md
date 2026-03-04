# Changelog

All notable changes to the spec-autopilot plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] - 2026-03-04

### Added
- **Config `project_context`**: New config section for project-specific context (project_structure, test_credentials, playwright_login) auto-detected by init
- **Dynamic dispatch prompt**: Phase 4/5/6 sub-agent prompts now dynamically constructed from config + Phase 1 Steering Documents
- **Init Step 2.5**: Auto-detects test credentials, project structure, and Playwright login flow during config generation
- **Fallback chain**: Empty `project_context` fields supplemented by Phase 1 Auto-Scan at runtime

### Changed
- **`instruction_files` demoted to optional override**: No longer required for basic operation. Dispatch uses config fields + Phase 1 output as primary context
- **`autopilot-dispatch/SKILL.md`**: Rewritten dispatch template with 7-level context injection priority chain
- **`autopilot-init/SKILL.md`**: Added Step 2.5 (project context detection) and Step 4.1 (missing field prompts)
- **`integration-guide.md`**: Simplified from 8 steps to 7 steps, removed mandatory instruction file creation
- **`configuration.md`**: Added `project_context` section with project_structure, test_credentials, playwright_login
- **`validate-config.sh`**: Added type validation for project_context fields

## [2.1.0] - 2026-03-04

### Added
- **Phase 1 Auto-Scan**: Automatic project structure scanning generates Steering Documents (project-context.md, existing-patterns.md, tech-constraints.md) for persistent project context
- **Phase 1 Research Agent**: Dispatches Explore agent before discussion to analyze related code, dependency compatibility, technical feasibility → research-findings.md
- **Phase 1 Complexity Routing**: Auto-evaluates complexity (small/medium/large) based on research impact analysis, routes to appropriate discussion depth
- **Phase 1 enhanced business-analyst dispatch**: Injects Steering + Research context into requirements analysis agent for fact-based discussion
- **Large complexity forced socratic**: Complexity "large" forces socratic mode regardless of config setting
- **Integration guide**: New `docs/integration-guide.md` with step-by-step project onboarding, config examples for frontend/backend/monorepo scenarios
- **Config validation for Phase 1 fields**: `validate-config.sh` now validates `auto_scan`, `research`, `complexity_routing` configuration

### Changed
- `references/phase1-requirements.md`: Rewritten from 7-step to 10-step flow with auto-scan, research, and complexity routing
- `autopilot/SKILL.md`: Phase 1 summary updated to reflect 10-step enhanced flow
- `autopilot-dispatch/SKILL.md`: Added Phase 1 research and business-analyst dispatch templates
- `references/protocol.md`: Phase 1 checkpoint fields expanded with `complexity`, `research`, `steering_artifacts`
- `docs/phases.md`: Phase 1 section updated with complexity routing table, steering documents table, enhanced checkpoint format
- `docs/configuration.md`: Added `phases.requirements.auto_scan`, `research`, `complexity_routing` field references and validation rules
- `scripts/validate-config.sh`: Added type/range/cross-ref validation for new Phase 1 config fields

## [2.0.0] - 2026-03-04

### Added
- **Test pyramid floor validation** (Layer 2): Hook-level validation of unit/e2e percentage floors and minimum total test count
- **Config schema validation**: New `validate-config.sh` script validates `autopilot.config.yaml` required fields with PyYAML → regex fallback
- **Wall-clock timeout** (Hook layer): Phase 5 time limit (2h) enforced at PreToolUse hook level
- **Anti-rationalization hook**: Detects 10 rationalization patterns in Phase 4/5/6 output to prevent test/task skipping
- **Metrics collection**: `collect-metrics.sh` aggregates per-phase timing and retry data; `_metrics` field in checkpoints
- **Socratic mode** for Phase 1: Optional 6-step challenging question protocol for deep requirements analysis
- **Task-level checkpoint**: Per-task checkpoint files in `phase5-tasks/` for fine-grained Phase 5 crash recovery
- **Semantic validation protocol**: AI-level semantic checks beyond structural JSON validation
- **Brownfield validation**: Design-test-implementation drift detection for existing codebases (opt-in)
- **Professional documentation**: Complete README rewrite with Mermaid architecture diagrams
- **docs/ directory**: 5 detailed documentation files (architecture, configuration, gates, phases, troubleshooting)

### Changed
- `hooks.json`: Added PostToolUse anti-rationalization hook entry
- `plugin.json`: Enhanced metadata with new keywords and engine requirements
- `autopilot-gate/SKILL.md`: Added semantic and brownfield validation layers
- `autopilot-checkpoint/SKILL.md`: Added task-level checkpoint protocol and `_metrics` field documentation
- `autopilot/SKILL.md`: Added Phase 0 config validation and Phase 7 metrics collection

### Fixed
- N/A

## [1.9.0] - 2026-02-28

### Added
- Allure installation detection (`check-allure-install.sh`)
- Phase 7 checkpoint support
- SKILL.md refactored to reference files for better context management
- `references/` directory with protocol, phase1, phase5, quality-scans docs

### Changed
- Main `SKILL.md` reduced from ~500 lines to ~270 lines via reference extraction

## [1.8.0] - 2026-02-25

### Added
- Comprehensive plugin enhancement
- Phase 6 report format validation (allure/custom)
- `save-state-before-compact.sh` Phase 7 scan support

## [1.6.0] - 2026-02-20

### Fixed
- Comprehensive audit fixes P0-P3
- `zero_skip_check` Phase 5 validation
- Phase 5/6 test coverage improvements

## [1.5.0] - 2026-02-15

### Added
- Phase 4 gate enforcement
- Context compaction state persistence
- `PreCompact` and `SessionStart(compact)` hooks

## [1.0.0] - 2026-02-01

### Added
- Initial release
- 8-phase autopilot pipeline
- 3-layer gate system (TaskCreate blockedBy, Hook checkpoints, AI checklist)
- Crash recovery via checkpoint scanning
- Context compaction resilience

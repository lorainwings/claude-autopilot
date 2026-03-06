# Phase-Specific Dispatch Instructions

> Extracted from SKILL.md for size compliance. Referenced by main SKILL.md.

## Phase 1 (Technical Research)

- Agent: `config.phases.requirements.research.agent` (default: Explore)
- Condition: `config.phases.requirements.research.enabled === true`
- Task: Analyze existing code, dependency compatibility, technical feasibility
- Prompt injection: RAW_REQUIREMENT + Steering Documents paths
- Returns: JSON with impact_analysis / dependency_check / feasibility / risks
- No `autopilot-phase` tag -> not subject to Hook gate checks (by design)
- Fails twice -> mark `research_status: "skipped"`, don't block flow

## Phase 1 (Requirements Analysis)

- Agent: `config.phases.requirements.agent` (default: business-analyst)
- Task: Analyze requirements based on Steering + Research context
- Prompt injection: RAW_REQUIREMENT + all Steering Documents + research-findings.md + complexity result
- **Web research injection** (v2.4.0): When research-findings.md has Web Research Findings section, append citation instructions
- **Decision protocol injection** (v2.4.0): When complexity is "medium" or "large", append structured decision card format
- Return validation: non-empty, must contain feature list and open questions

## Phase 2 (Create OpenSpec)

- Agent: general-purpose
- Task: Derive kebab-case name from requirements, execute `openspec new change "<name>"`
- Write context files (prd.md, discussion.md, ai-prompt.md)

## Phase 3 (FF Generate Artifacts)

- Agent: general-purpose
- Task: Follow openspec-ff-change flow to generate proposal/specs/design/tasks
- artifacts field lists all created artifact paths

## Phase 4 (Test Case Design)

- Agent: `config.phases.testing.agent` (default: qa-expert)
- Context: auto-inject from config.project_context + config.test_suites + Phase 1 Steering Documents
- Override: config.phases.testing.instruction_files / reference_files (injected if non-empty)
- Gate: all 4 test types created, each >= min_test_count_per_type
- **Phase 4 cannot be skipped or downgraded to warning**

Phase 4 sub-agent prompt must include these mandatory instructions:
- Requirements traceability (REQ-001..N from proposal/specs/design)
- Test file creation for each test suite type
- Test credentials + Playwright login flow injection
- Test plan document creation
- Dry-run syntax validation
- Return: only "ok" or "blocked" (no "warning")
- Must include `traceability_matrix` and `coverage` fields
- Test pyramid ratio constraints from `config.test_pyramid`

> Full Phase 4 prompt template: see `autopilot/templates/phase4-testing.md`

## Phase 5 (Subagent-Driven Implementation)

- Execution: ralph-loop or fallback (decided by main thread)
- Context: auto-inject from config.project_context + config.test_suites
- Override: config.phases.implementation.instruction_files (injected if non-empty)

**Subagent-Driven parallel mode** (when `config.phases.implementation.parallel.enabled = true`):
- Main thread reads `templates/phase5-parallel.md` (complete 10-step executable instructions)
- **Cross-domain parallel**: Group by top-level directory (backend/frontend/node), one Domain Runner per domain
- **Intra-domain serial**: Domain Runner executes tasks sequentially (fresh subagent + self-review)
- **Domain Runner agent type**: Read from `config.parallel.agent_mapping`
- **Two-stage review**: After all domains merge, dispatch spec-reviewer + quality-reviewer (`templates/phase5-review-prompts.md`)
- **Worktree auto-enabled**: `Task(isolation: "worktree", run_in_background: true)` for parallel
- **Degradation**: Only 1 domain has tasks -> auto-switch to serial template

**Phase 5 Review flow** (mandatory after merge):
1. **Spec Compliance Review**: `Task(subagent_type: "general-purpose")`
   - Line-by-line comparison: proposal requirements vs actual code
   - Fail -> dispatch fix agent -> re-review -> max 2 rounds
2. **Code Quality Review**: `Task(subagent_type: config.parallel.agent_mapping.review_quality || "pr-review-toolkit:code-reviewer")`
   - Confidence 0-100 scoring, only report >= 80
   - Critical (>= 90) -> block, Important (80-89) -> log without blocking
   - Fail -> dispatch fix agent -> re-review -> max 2 rounds

> Full Domain Runner prompt template: see `templates/phase5-parallel.md`
> Review prompt templates: see `templates/phase5-review-prompts.md`

## Phase 6 (Test Report)

- Agent: qa-expert
- Test commands: dynamically read from config.test_suites
- **Parallel test execution** (v3.2.0): Read `autopilot/templates/phase6-parallel.md`, dispatch independent test suites as background Tasks
- Override: config.phases.reporting.instruction_files (injected if non-empty)
- **Report format** (per `config.phases.reporting.format`):
  - `"allure"` (recommended) -> Read `autopilot/templates/phase6-reporting.md` path 1:
    1. `bash <plugin_scripts>/check-allure-install.sh "$(pwd)"` -> installation check
    2. Set `ALLURE_RESULTS_DIR="$(pwd)/allure-results"`
    3. Each suite appends allure params (pytest: `--alluredir`, playwright: `--reporter=allure-playwright`, junit_xml: post-process copy)
    4. `npx allure generate "$ALLURE_RESULTS_DIR" -o allure-report --clean`
    5. Return `report_format: "allure"`, `report_path: "allure-report/index.html"`, `allure_results_dir`
  - `"custom"` -> Use config.phases.reporting.report_commands
  - Allure install fails -> Auto-degrade to custom

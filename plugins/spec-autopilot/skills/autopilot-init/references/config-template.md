# Config Template

> Full YAML config template for autopilot.config.yaml generation.
> Referenced by autopilot-init/SKILL.md Step 3.

```yaml
version: "1.0"

services:
  # Auto-detected services
  backend:
    health_url: "http://localhost:{detected_port}/actuator/health"
    name: "Backend Service"
  frontend:
    health_url: "http://localhost:{detected_port}/"
    name: "Frontend Service"

phases:
  requirements:
    agent: "business-analyst"
    min_qa_rounds: 1
    mode: "structured"         # structured | socratic
    auto_scan:
      enabled: true
      max_depth: 2
    research:
      enabled: true
      agent: "Explore"
      web_search:
        enabled: true
        max_queries: 5
        focus_areas:
          - best_practices
          - similar_implementations
          - dependency_evaluation
    complexity_routing:
      enabled: true
      thresholds:
        small: 2
        medium: 5
  testing:
    agent: "qa-expert"
    instruction_files: []
    reference_files: []
    gate:
      min_test_count_per_type: 5
      required_test_types: [unit, api, e2e, ui]
  implementation:
    instruction_files: []
    ralph_loop:
      enabled: true
      max_iterations: 30
      fallback_enabled: true
    worktree:
      enabled: auto            # auto: determined by parallel.enabled
    parallel:
      enabled: true
      max_agents: 5
      conflict_threshold: 5
      agent_mapping:
        default: "general-purpose"
        backend: "general-purpose"
        frontend: "general-purpose"
        node: "general-purpose"
        review_spec: "general-purpose"
        review_quality: "pr-review-toolkit:code-reviewer"
  reporting:
    instruction_files: []
    format: "allure"           # allure | custom
    report_commands:
      html: "python tools/report/html_generator.py -i {change_name}"
      markdown: "python tools/report/generator.py -i {change_name}"
      allure_generate: "npx allure generate allure-results -o allure-report --clean"
    coverage_target: 80
    zero_skip_required: true
  code_review:
    enabled: true
    auto_fix_minor: false
    block_on_critical: true
    skip_patterns:
      - "*.md"
      - "*.json"
      - "openspec/**"

test_pyramid:
  min_unit_pct: 50
  max_e2e_pct: 20
  min_total_cases: 20

gates:
  user_confirmation:
    after_phase_1: true
    after_phase_3: false
    after_phase_4: false

model_routing:
  phase_1: heavy
  phase_2: light
  phase_3: light
  phase_4: heavy
  phase_5: heavy
  phase_6: light
  phase_7: light

context_management:
  git_commit_per_phase: true
  autocompact_pct: 80
  squash_on_archive: true    # Phase 7: git reset --soft $ANCHOR_SHA + single commit (conflict-free)

brownfield_validation:
  enabled: false
  strict_mode: false
  ignore_patterns: ["*.test.*", "*.spec.*", "__mocks__/**"]

async_quality_scans:
  timeout_minutes: 10
  contract_testing:
    check_command: ""
    install_command: ""
    command: ""
    threshold: "all_pass"
  performance_audit:
    check_command: "npx lhci --version"
    install_command: "pnpm add -D @lhci/cli"
    command: "npx lhci autorun"
    threshold: 80
  visual_regression:
    check_command: ""
    install_command: ""
    command: ""
    threshold: "0_diff"
  mutation_testing:
    check_command: ""
    install_command: ""
    command: ""
    threshold: 60
  security_audit:
    check_command: "bash ${CLAUDE_PLUGIN_ROOT}/scripts/check-security-tools-install.sh"
    install_command: ""
    command: ""
    threshold: "0_critical"
    block_on_critical: false

code_constraints:
  forbidden_files: []
  forbidden_patterns: []
  max_file_lines: 800
  allowed_dirs: []
  auto_detect: true
  dynamic_constraints:
    enabled: true
    typecheck_on_edit: true
    lint_on_task_complete: true

test_suites:
  # Auto-detected test suites

project_context:
  project_structure:
    backend_dir: "{detected}"
    frontend_dir: "{detected}"
    node_dir: "{detected}"
    test_dirs:
      unit: "{detected}"
      api: "{detected}"
      e2e: "{detected}"
      ui: "{detected}"

  test_credentials:
    username: "{detected}"
    password: "{detected}"
    login_endpoint: "{detected}"

  playwright_login:
    steps: |
      # Auto-detected login steps (derived from Login component data-testid)
    known_testids: []
```

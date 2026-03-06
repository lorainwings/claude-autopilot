---
name: autopilot-dispatch
description: "[ONLY for autopilot orchestrator] Sub-Agent dispatch protocol for autopilot phases. Constructs Task prompts with JSON envelope contract, explicit path injection, and parameterized templates."
user-invocable: false
---

# Autopilot Dispatch — Sub-Agent Dispatch Protocol

> **Pre-check**: This Skill is only used within the autopilot orchestration main thread. If the current context is not an autopilot orchestration flow, stop immediately.

Read project config from `autopilot.config.yaml`, construct standardized Task prompts to dispatch sub-agents.

## Shared Protocol

> JSON envelope contract, phase-specific fields, status parsing rules, structured markers:
> see `autopilot/references/protocol.md`.

## Supporting References

- For the complete prompt construction template, see [prompt-template.md](references/prompt-template.md)
- For rules auto-scan, domain-specific injection, and agent mapping, see [rules-injection.md](references/rules-injection.md)
- For phase-specific dispatch instructions (Phase 1-6), see [phase-instructions.md](references/phase-instructions.md)

## Built-in Template Resolution (v3.0)

When constructing Phase 4/5/6 prompts, check `config.phases[phase].instruction_files`:
1. **Non-empty** -> Use project custom instruction files (override built-in templates)
2. **Empty (default)** -> Use plugin built-in templates (`autopilot/templates/phase{N}-*.md`)

### Template Path Mapping

| Phase | Built-in Templates | Condition |
|-------|-------------------|-----------|
| 4 | `autopilot/templates/phase4-testing.md` + `shared-test-standards.md` | Always |
| 5 (serial) | `autopilot/templates/phase5-ralph-loop.md` + `shared-test-standards.md` | `parallel.enabled = false` |
| 5 (parallel) | `autopilot/templates/phase5-parallel.md` + `phase5-review-prompts.md` + `shared-test-standards.md` | `parallel.enabled = true` |
| 6 | `autopilot/templates/phase6-reporting.md` + `phase6-parallel.md` | Always |

### Template Variable Substitution

Dispatch main thread performs variable substitution when constructing prompts:
- `{config.services}` -> Expand service list from config.services
- `{config.test_suites}` -> Expand test suites from config.test_suites
- `{config.project_context.*}` -> Expand credentials/login flow from config.project_context
- `{config.test_pyramid.*}` -> Expand pyramid constraints from config.test_pyramid
- `{change_name}` -> Active change's kebab-case name

> **Backwards compatibility**: Existing project instruction_files configs continue to work, priority over built-in templates.

## Parameterized Dispatch

### Input Parameters

| Parameter | Source |
|-----------|--------|
| phase_number | Current phase number (2-6) |
| agent_name | config.phases[phase].agent or default agent |
| change_name | Active change's kebab-case name |
| instruction_files | config.phases[phase].instruction_files |
| reference_files | config.phases[phase].reference_files |

### Sub-Agent Pre-validation (must include at prompt start)

```markdown
**Pre-validation (before any action)**:
1. Read `openspec/changes/{change_name}/context/phase-results/phase-{N-1}-*.json`
2. If file not found -> return immediately:
   `{"status": "blocked", "summary": "Phase {N-1} checkpoint not found"}`
3. If status is not "ok" or "warning" -> return immediately:
   `{"status": "blocked", "summary": "Phase {N-1} status is {status}"}`
4. Validation passed, proceed with this phase's task.
```

### Phase Dispatch Overview

Each phase's detailed dispatch instructions are in [phase-instructions.md](references/phase-instructions.md). Quick reference:

| Phase | Agent | Key Points |
|-------|-------|-----------|
| 1 (Research) | Explore | Optional, fails twice -> skip |
| 1 (Requirements) | business-analyst | RAW_REQUIREMENT + Steering + Research |
| 2 (OpenSpec) | general-purpose | Create change directory |
| 3 (FF Artifacts) | general-purpose | Generate proposal/specs/design/tasks |
| 4 (Testing) | qa-expert | Requirements traceability + 4 test types, no "warning" |
| 5 (Implementation) | per agent_mapping | Subagent-Driven parallel or serial |
| 6 (Report) | qa-expert | Parallel test execution + Allure/custom report |

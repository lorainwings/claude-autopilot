# Dispatch Prompt Construction Template

> Extracted from SKILL.md for size compliance. Referenced by main SKILL.md.

## Context Injection Priority (high to low)

| Priority | Source | Description |
|----------|--------|-------------|
| 1 | `config.phases[phase].instruction_files` | Project custom instructions (override built-in rules) |
| 2 | `config.phases[phase].reference_files` | Project custom references |
| 2.5 | Project Rules Auto-Scan | Run `rules-scanner.sh` to extract project constraints |
| 3 | `config.project_context` | Auto-inject: project structure, test credentials, Playwright login |
| 4 | `config.test_suites` | Auto-inject: test commands, framework types |
| 5 | `config.services` | Auto-inject: service health check URLs |
| 6 | Phase 1 Steering Documents | Auto-inject: Auto-Scan generated project context |
| 7 | Built-in rules | Fallback: generic requirements from dispatch templates |

## Prompt Template

```markdown
Task(prompt: "<!-- autopilot-phase:{phase_number} -->
You are a sub-agent for autopilot phase {phase_number}.

## Project Context (auto-injected from config)

### Service List
{for each service in config.services}
- {service.name}: {service.health_url}
{end for}

### Project Structure
- Backend dir: {config.project_context.project_structure.backend_dir}
- Frontend dir: {config.project_context.project_structure.frontend_dir}
- Test dirs: {config.project_context.project_structure.test_dirs}

### Test Suites
{for each suite in config.test_suites}
- {suite_name}: `{suite.command}` (type: {suite.type})
{end for}

### Test Credentials
{if config.project_context.test_credentials.username is not empty}
- Username: {config.project_context.test_credentials.username}
- Password: {config.project_context.test_credentials.password}
- Login endpoint: {config.project_context.test_credentials.login_endpoint}
{else}
- No test credentials configured, read from project's application.yml / .env
{end if}

### Playwright Login Flow
{if config.project_context.playwright_login.steps is not empty}
{config.project_context.playwright_login.steps}
Known data-testid: {config.project_context.playwright_login.known_testids}
{else}
- No login flow configured, derive from Login component's data-testid attributes
{end if}

## Phase 1 Project Analysis (if exists)
Read these files for project deep context (skip if not found):
- openspec/changes/{change_name}/context/project-context.md
- openspec/changes/{change_name}/context/existing-patterns.md
- openspec/changes/{change_name}/context/tech-constraints.md
- openspec/changes/{change_name}/context/research-findings.md

{if config.phases[phase].instruction_files is not empty}
## Project Custom Instructions (override)
Read instruction files first:
{for each file in config.phases[phase].instruction_files}
- {file_path}
{end for}
{end if}

{if config.phases[phase].reference_files is not empty}
## Project Custom References
Then read reference files:
{for each file in config.phases[phase].reference_files}
- {file_path}
{end for}
{end if}

### Model Routing Hint

{if config.model_routing.phase_{N} == "light"}
## Execution Mode: Efficient
This phase is mechanical — focus on efficiency:
- Concise output, avoid over-analysis
- Prefer templates and existing patterns
- Minimize exploratory operations
{end if}

{if config.model_routing.phase_{N} == "heavy"}
## Execution Mode: Deep Analysis
This phase requires deep reasoning:
- Consider edge cases and failure scenarios
- Provide detailed decision rationale
- Multi-angle technical evaluation
{end if}

Return structured JSON result upon completion.")
```

## Dynamic Constraints Injection (v3.1.0)

When dispatching Phase 5, in addition to static rules, inject dynamic constraint checks:

```markdown
{if phase == 5 AND config.phases.implementation.dynamic_constraints.enabled}
## Dynamic Code Constraints (auto-enforced by PostToolUse Hook)

### Static Constraints (from config/CLAUDE.md/rules)
{rules_scan results injection}

### Dynamic Constraints (v3.1.0)
- **Type check**: Auto-run `{typecheck_command}` after each Write/Edit
- **Import paths**: No relative paths beyond 3 levels (`../../../`)
- **File size**: Max {max_lines} lines per file (Hook enforced)
- **ESLint/Checkstyle**: Run lint after each task when project config exists

> Hook block messages include specific violation info and fix suggestions.
{end if}
```

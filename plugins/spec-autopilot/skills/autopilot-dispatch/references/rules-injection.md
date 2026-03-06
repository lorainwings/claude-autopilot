# Rules Injection & Agent Mapping

> Extracted from SKILL.md for size compliance. Referenced by main SKILL.md.

## Project Rules Auto-Scan (all phases, v3.0+)

Automatically run `rules-scanner.sh` when dispatching any phase sub-agent, scanning `.claude/rules/` and `CLAUDE.md` to extract constraints.

**Trigger**: All Task-dispatched phases (Phase 2-6)

**Cache strategy**: Run once at Phase 0, reuse for subsequent phases within the same autopilot session.

**Phase-specific injection levels**:

| Phase | Injection Content |
|-------|------------------|
| Phase 2-3 | Compact summary (critical_rules only, max 5) |
| Phase 4 | Full rules (tests must verify code compliance) |
| Phase 5 | Full rules + real-time Hook enforcement |
| Phase 6 | Compact summary (reference constraint compliance in report) |

**Execution flow**:

1. Main thread runs before constructing sub-agent prompt (cached at Phase 0):
   ```bash
   bash ${CLAUDE_SKILL_DIR}/../../../scripts/rules-scanner.sh "$(pwd)"
   ```
2. Parse returned JSON, check `rules_found === true`
3. If constraints exist, format `constraints` array as prompt section

**Injection template**:

```markdown
{if rules_scan.rules_found === true}
## Project Rule Constraints (auto-scanned)

The following constraints are extracted from `.claude/rules/` and `CLAUDE.md`. **Strict compliance required**:

### Forbidden Items
{for each c in constraints where c.type === "forbidden"}
- `{c.pattern}` -> use `{c.replacement}` (source: {c.source})
{end for}

### Required Patterns
{for each c in constraints where c.type === "required"}
- `{c.pattern}` (source: {c.source})
{end for}

### Naming Conventions
{for each c in constraints where c.type === "naming"}
- {c.pattern} (source: {c.source})
{end for}

> Violations will be intercepted and blocked by PostToolUse Hook.
{end if}
```

**Injection position**: After `### Playwright Login Flow`, before `## Phase 1 Project Analysis`.

## Domain-Specific Rules Injection (v3.2.0, Phase 5 parallel only)

When Phase 5 parallel mode is enabled, each Domain Runner prompt must include the **full domain-specific rules file** in addition to the rules-scanner summary:

| Domain | Injected File | Description |
|--------|--------------|-------------|
| backend | `.claude/rules/backend.md` full text | Java/Spring Boot/Gradle rules |
| frontend | `.claude/rules/frontend.md` full text | Vue/TypeScript/pnpm rules |
| node | `.claude/rules/nodejs.md` full text | Node.js/Fastify/PM2 rules |
| shared | All domain rules files | Cross-domain tasks need all rules |

**Injection logic**:
1. Check `.claude/rules/` for domain-specific rule files (supports variants: `backend.md`, `java.md`, `spring.md`)
2. Exists -> Read full text, inject into Domain Runner prompt's `## Project Rule Constraints` section
3. Not found -> Use rules-scanner summary only

## Agent Type Mapping (v3.2.0)

Phase 5 parallel mode uses `config.parallel.agent_mapping` to select optimal agents per role:

| Role | Config Key | Default | Description |
|------|-----------|---------|-------------|
| Backend Implementer | `agent_mapping.backend` | `"general-purpose"` | Backend implementation agent |
| Frontend Implementer | `agent_mapping.frontend` | `"general-purpose"` | Frontend implementation agent |
| Node Implementer | `agent_mapping.node` | `"general-purpose"` | Node implementation agent |
| Spec Reviewer | `agent_mapping.review_spec` | `"general-purpose"` | Spec compliance review |
| Quality Reviewer | `agent_mapping.review_quality` | `"pr-review-toolkit:code-reviewer"` | Code quality review (official plugin) |

> `pr-review-toolkit:code-reviewer` is from Anthropic's official `claude-plugins-official` marketplace.
> Built-in CLAUDE.md compliance, bug detection, code quality assessment with confidence 0-100 scoring (only reports >= 80).
> Project must enable `pr-review-toolkit@claude-plugins-official` plugin.
> Falls back to `"general-purpose"` if plugin unavailable.

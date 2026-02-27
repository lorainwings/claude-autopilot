---
name: autopilot
description: >
  [DEPRECATED] This agent definition is kept as a reference template only.
  The autopilot orchestration now runs in the main thread via the project's
  autopilot SKILL.md, not as a sub-agent. Reason: sub-agents cannot use
  the Task tool for nested dispatch (verified limitation).
model: opus
maxTurns: 80
memory: project
tools:
  - Read
  - Write
  - Edit
  - Bash
  - Glob
  - Grep
  - Task
  - Skill
  - AskUserQuestion
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
skills:
  - autopilot-dispatch
  - autopilot-gate
  - autopilot-checkpoint
  - autopilot-recovery
---

# DEPRECATED — Autopilot Agent Template

> **This agent definition is deprecated since v1.3.0.**
>
> Sub-agents spawned via the Task tool do NOT have access to the Task tool
> themselves, making nested Task dispatch impossible. The autopilot
> orchestration logic has been moved to the project-side `SKILL.md` which
> runs in the main thread where Task is available.
>
> This file is preserved as a reference template for the 8-phase pipeline.
> Projects should implement the orchestration via their own
> `.claude/skills/autopilot/SKILL.md`.

## Migration Guide

**Before (broken):**
```
User → Skill("autopilot") → Task(spec-autopilot:autopilot) → Task(phase-N) ❌
                                   sub-agent has no Task tool
```

**After (working):**
```
User → Skill("autopilot") → main thread reads SKILL.md → Task(phase-N) ✅
                             main thread has Task tool
```

## Original 8-Phase Pipeline (Reference)

| Phase | Type | Description |
|-------|------|-------------|
| 0 | Main thread | Environment check + crash recovery |
| 1 | Main thread | Requirements understanding + multi-round decisions |
| 2 | Task sub-agent | Create OpenSpec + save context |
| 3 | Task sub-agent | OpenSpec fast-forward artifacts |
| 4 | Task sub-agent | Test case design (forced) |
| 5 | Task sub-agent | Ralph Loop / Fallback implementation |
| 6 | Task sub-agent | Test report generation (forced) |
| 7 | Main thread | Summary + user-confirmed archive |

## Protocol Skills (still active)

- `autopilot-dispatch`: Constructs Task prompts with JSON envelope contract
- `autopilot-gate`: 8-step checklist + special phase gates
- `autopilot-checkpoint`: Checkpoint file read/write
- `autopilot-recovery`: Crash recovery + session resume

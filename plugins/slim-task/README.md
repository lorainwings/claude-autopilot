[中文版](README.zh.md)

# slim-task

> Structured 7-phase task execution SOP for AI coding with multi-language and worktree support

**Version**: 0.8.1 <!-- x-release-please-version -->

## Overview

slim-task is a pure-Skill Claude Code plugin that provides a structured Standard Operating Procedure (SOP) for AI task execution. It solves 8 common problems when AI agents execute coding tasks:

1. Starting without requirements clarification
2. No best-practice research during solution design
3. Bug fixes touching unrelated code
4. Code changes without user approval
5. No persistent task documentation
6. Commits without user approval
7. Slow sequential execution instead of parallelism
8. Self-audit cheating — the agent that wrote the code grading its own work

## Architecture

- **Main-Check-Sub-Execute**: Main agent only inspects/decides/dispatches/verifies; sub-agents do actual coding
- **DAG Parallelism**: Tasks decomposed into a DAG, same-layer tasks dispatched simultaneously with no concurrency limit
- **Impact Scoping**: Mandatory file-level impact scope table prevents touching unrelated code
- **Blind-Audit Phase 5**: Quality review delegated to independent auditor sub-agents in isolated context — the implementing agent never grades its own work
- **Multi-Language**: All AI dialogue, decision cards, generated docs, and sub-agent prompts respect a configured language (default `zh-CN`); Conventional Commits prefixes stay English
- **Worktree Isolation**: Optional `--worktree` mode runs the full pipeline inside a dedicated git worktree, enabling true multi-task parallelism without staging conflicts
- **Converged Approval Gates**: Human decisions converge at three key gates (requirements / plan / commit); after Phase 2 approval the execution stage (doc → parallel impl → blind audit) runs autonomously, pausing only on anomalies; `--interactive` restores per-phase confirmation
- **Deterministic Orchestration**: When DAG node count ≥ 4, invokes the Workflow tool so the JS engine deterministically enforces per-layer parallel barriers, mandatory three-dimension audit parallelism, and a hard-counted fix loop (≤3 rounds), eliminating orchestration-layer step-skipping
- **Crash Recovery**: The execution stage checkpoints state at every key node; after a session interruption or context compaction it resumes from the breakpoint — skipping completed layers and preserving the fix-round counter — without rerunning from scratch
- **Controllable Execution**: Auto-advance stays fully transparent (per-layer / per-round progress), the user can pause at any time, and each of the 7 anomaly types carries explicit actionable options plus auto-rollback — never silent, never a dead stop
- **Hard Boundary Isolation**: Implementation sub-agents are schema-forced to report actually-modified files, checked live against the impact-scope whitelist with out-of-bound changes intercepted; audit diffs are sanitized of implementation traces to guarantee blind-audit independence

## 7-Phase SOP

```mermaid
flowchart TD
    P0["Phase 0<br/>Session Init"] --> WT{--worktree?}
    WT -->|yes| EW[EnterWorktree] --> P1
    WT -->|no| P1["Phase 1<br/>Requirements Clarification"]
    P1 --> G1{{Approval gate: requirements}}
    G1 --> P2["Phase 2<br/>Solution Design + DAG Preview"]
    P2 --> G2{{Approval gate: plan + DAG}}
    G2 --> P3["Phase 3<br/>Documentation"]
    P3 --> P4["Phase 4<br/>DAG Parallel Execution"]
    P4 --> P5["Phase 5<br/>Blind Audit"]
    P5 --> AUD{All 3 audits pass?}
    AUD -->|issues, <3 rounds| FIX[Auto-fix agent, isolated context] --> P5
    AUD -->|3 rounds failed| STOP((Manual intervention))
    AUD -->|all pass| P6["Phase 6<br/>commit/push double gate"]
```

> Note: Phase 4 execution mode splits by DAG node count — 1 node uses single-agent dispatch, 2-3 nodes use instruction-driven fan-out, ≥4 nodes invoke the Workflow tool for deterministic orchestration. See SKILL.md for details.

| Phase | Name | Key Output |
|-------|------|------------|
| 0 | Session Init | Language / Worktree config |
| 1 | Requirements Clarification | Refined requirements summary |
| 2 | Solution Design + DAG Preview | Solution + impact scope table + DAG graph |
| 3 | Documentation | Task doc |
| 4 | Parallel Execution | Sub-agent deliverables |
| 5 | Blind Audit | scope / practice / engineering audit.json |
| 6 | Commit Confirmation | commit + optional push / PR |

## Installation

```bash
claude install stoicatom/claude-autopilot --plugin slim-task
```

## Usage

```
/slim-task [task description] [--lang zh-CN|en-US|...] [--worktree] [--base <branch>]
```

Examples:

```
# Default (Chinese, no worktree, backward-compatible)
/slim-task fix the auth header bug in middleware

# English output, isolated worktree based on current branch
/slim-task --lang en-US --worktree add health check endpoint

# English output, worktree branched from origin/main
/slim-task --lang en-US --worktree --base origin/main refactor logger
```

Natural language triggers also work: "structured task execution", "SOP execution".

### Configuration

The first time you pass `--lang`, the value is persisted to `.claude/slim-task.json` as your default. Subsequent calls without `--lang` reuse it.

### Worktree Notes

- Worktree mode is **off** by default; pass `--worktree` to enable.
- The full 7-phase pipeline runs inside the worktree.
- Commits inside a worktree are **never auto-merged or pushed to `main`** — slim-task hands you a `git merge` command at Phase 6 so you can integrate manually.
- Worktree mode forbids committing `release-please-config.json`, `.release-please-manifest.json`, or `marketplace.json` (shared monorepo state).

## License

MIT

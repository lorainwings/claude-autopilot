[中文版](README.zh.md)

# slim-task

> Structured 7-phase task execution SOP for AI coding with multi-language and worktree support

**Version**: 0.3.1 <!-- x-release-please-version -->

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
- **7 User Checkpoints**: Every phase transition requires explicit user confirmation

## 7-Phase SOP

| Phase | Name | Description |
|-------|------|-------------|
| 0 | Session Init | Parse `--lang` / `--worktree` / `--base`; persist language preference; optionally enter a fresh worktree |
| 1 | Requirements Clarification | Parse input, identify ambiguities, structured Q&A |
| 2 | Solution Design | Best-practice research + codebase scan + impact scope |
| 3 | Documentation + DAG Split | Save task doc (with `.{lang}.md` suffix) + build dependency DAG |
| 4 | Parallel Execution | Dispatch sub-agents by DAG topological order |
| 5 | Quality Review (Blind Audit) | Three independent auditor sub-agents — scope / practice / engineering — review the diff without seeing implementation context |
| 6 | Commit Confirmation | Worktree-mode blacklist check, show changes, confirm commit/push, optional `ExitWorktree(keep)` |

## Installation

```bash
claude install lorainwings/claude-autopilot --plugin slim-task
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

[中文版](README.zh.md)

# slim-task

> Structured 6-phase task execution SOP for AI coding

**Version**: 0.1.0 <!-- x-release-please-version -->

## Overview

slim-task is a pure-Skill Claude Code plugin that provides a structured Standard Operating Procedure (SOP) for AI task execution. It solves 7 common problems when AI agents execute coding tasks:

1. Starting without requirements clarification
2. No best-practice research during solution design
3. Bug fixes touching unrelated code
4. Code changes without user approval
5. No persistent task documentation
6. Commits without user approval
7. Slow sequential execution instead of parallelism

## Architecture

- **Main-Check-Sub-Execute**: Main agent only inspects/decides/dispatches/verifies; sub-agents do actual coding
- **DAG Parallelism**: Tasks decomposed into a DAG, same-layer tasks dispatched simultaneously with no concurrency limit
- **Impact Scoping**: Mandatory file-level impact scope table prevents touching unrelated code
- **6 User Checkpoints**: Every phase transition requires explicit user confirmation

## 6-Phase SOP

| Phase | Name | Description |
|-------|------|-------------|
| 1 | Requirements Clarification | Parse input, identify ambiguities, structured Q&A |
| 2 | Solution Design | Best-practice research + codebase scan + impact scope |
| 3 | Documentation + DAG Split | Save task docs + build dependency DAG |
| 4 | Parallel Execution | Dispatch sub-agents by DAG topological order |
| 5 | Quality Review | Diff review + lint + build check + UI check |
| 6 | Commit Confirmation | Show changes, confirm commit/push |

## Installation

```bash
claude install lorainwings/claude-autopilot --plugin slim-task
```

## Usage

```
/slim-task <task description>
```

Or use natural language triggers like "structured task execution" or "SOP execution".

## License

MIT

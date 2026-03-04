# Architecture

> spec-autopilot plugin architecture — layers, hooks, skills, and data flow.

## Layer Design

spec-autopilot uses a two-layer architecture:

| Layer | Location | Responsibility |
|-------|----------|----------------|
| **Plugin Layer** | `plugins/spec-autopilot/` | Reusable orchestration: Skills, Hooks, Scripts |
| **Project Layer** | `.claude/` in user project | Project-specific config, phase instructions, checkpoint data |

```mermaid
graph TB
    subgraph "Plugin Layer (spec-autopilot)"
        S[Skills]
        H[Hook Scripts]
        U[Utility Scripts]
    end

    subgraph "Project Layer (.claude/)"
        C[autopilot.config.yaml]
        I[Phase instruction files]
        W[Skill wrapper]
    end

    subgraph "Runtime Data (openspec/changes/)"
        CP[Checkpoint files]
        LK[Lock file]
        ST[State file]
    end

    C --> S
    I --> S
    W --> S
    S --> CP
    H --> CP
    H --> LK
    S --> LK
    S --> ST

    style S fill:#e3f2fd
    style H fill:#fff3e0
    style U fill:#f3e5f5
```

## Hook Execution Flow

### PreToolUse(Task)

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant H as check-predecessor-checkpoint.sh
    participant CM as _common.sh

    CC->>H: stdin: {tool_name, tool_input, cwd}
    H->>H: Bash marker check: "autopilot-phase:[0-9]"
    alt No marker
        H-->>CC: exit 0 (allow)
    else Has marker
        H->>H: python3: extract phase number
        H->>CM: find_active_change()
        CM-->>H: change directory path
        H->>CM: find_checkpoint() for predecessor
        CM-->>H: checkpoint file path
        H->>CM: read_checkpoint_status()
        CM-->>H: status string
        alt Status ok/warning
            H->>H: Wall-clock timeout check (Phase ≥ 5)
            H-->>CC: exit 0 (allow)
        else Status blocked/failed/missing
            H-->>CC: stdout JSON {permissionDecision: "deny"}
        end
    end
```

### PostToolUse(Task) — Two Hooks in Sequence

```mermaid
sequenceDiagram
    participant CC as Claude Code
    participant V as validate-json-envelope.sh
    participant AR as anti-rationalization-check.sh

    CC->>V: stdin: {tool_name, tool_input, tool_response}
    V->>V: Bash marker check
    alt No marker
        V-->>CC: exit 0
    else Has marker
        V->>V: Extract JSON envelope (3 strategies)
        V->>V: Validate required fields
        V->>V: Phase-specific field validation
        V->>V: Test pyramid floor check (Phase 4)
        alt Valid
            V-->>CC: exit 0
        else Invalid
            V-->>CC: stdout JSON {decision: "block", reason: "..."}
        end
    end

    CC->>AR: stdin: same data
    AR->>AR: Bash marker check
    alt Phase 4/5/6 + ok/warning + patterns found
        AR-->>CC: stdout JSON {decision: "block", reason: "..."}
    else No patterns or wrong phase/status
        AR-->>CC: exit 0
    end
```

## Skill Interaction Map

```mermaid
graph LR
    A[autopilot<br/>Main Orchestrator] -->|Phase 0| R[autopilot-recovery<br/>Crash Recovery]
    A -->|Phase 0| I[autopilot-init<br/>Config Generation]
    A -->|Each Phase| G[autopilot-gate<br/>8-step Checklist]
    A -->|Each Phase| D[autopilot-dispatch<br/>Sub-Agent Construction]
    A -->|Each Phase| CP[autopilot-checkpoint<br/>Read/Write Checkpoints]

    G -.->|reads| SV[references/<br/>semantic-validation.md]
    G -.->|reads| BV[references/<br/>brownfield-validation.md]
    A -.->|Phase 1| P1[references/<br/>phase1-requirements.md]
    A -.->|Phase 5| P5[references/<br/>phase5-implementation.md]
    A -.->|Phase 6→7| QS[references/<br/>quality-scans.md]
    A -.->|Phase 7| MC[references/<br/>metrics-collection.md]

    style A fill:#e3f2fd
    style G fill:#ffcdd2
    style D fill:#c8e6c9
    style CP fill:#fff9c4
```

## Data Flow

### Checkpoint Data

```
openspec/changes/<name>/
├── context/
│   ├── phase-results/
│   │   ├── phase-1-requirements.json    # Written by main thread
│   │   ├── phase-2-openspec.json        # Written after sub-agent
│   │   ├── phase-3-ff.json
│   │   ├── phase-4-testing.json
│   │   ├── phase-5-implement.json
│   │   ├── phase5-start-time.txt        # Wall-clock reference
│   │   ├── phase5-tasks/                # Task-level checkpoints
│   │   │   ├── task-1.json
│   │   │   └── task-2.json
│   │   ├── phase-6-report.json
│   │   └── phase-7-summary.json
│   └── autopilot-state.md               # PreCompact state save
├── tasks.md                              # Task completion tracking
└── ...
```

### Lock File

```json
{
  "change": "<name>",
  "pid": "<process_id>",
  "started": "<ISO-8601>",
  "session_cwd": "<project_root>",
  "anchor_sha": "<git_sha>",
  "session_id": "<millisecond_timestamp>"
}
```

Located at `openspec/changes/.autopilot-active`. Used by hooks to identify the active change directory.

### JSON Envelope

Every sub-agent must return a JSON envelope:

```json
{
  "status": "ok | warning | blocked | failed",
  "summary": "One-line decision-level summary",
  "artifacts": ["file/paths"],
  "risks": ["risk descriptions"],
  "next_ready": true,
  "_metrics": {
    "start_time": "ISO-8601",
    "end_time": "ISO-8601",
    "duration_seconds": 0,
    "retry_count": 0
  }
}
```

Phase-specific additional fields are documented in [phases.md](phases.md).

## Performance Considerations

### Fast Bypass Pattern

All hook scripts use a pure-bash grep check before invoking python3:

```bash
if ! echo "$STDIN_DATA" | grep -q 'autopilot-phase:[0-9]'; then
  exit 0  # ~1ms for non-autopilot Task calls
fi
```

This avoids forking python3 (~200-500ms) for every non-autopilot Task call.

### Fail-Closed Design

All hooks follow a fail-closed pattern:
- Missing python3 → block/deny (never allow)
- JSON parse error → block/deny
- Missing checkpoint → deny

Exception: `anti-rationalization-check.sh` allows when python3 is missing (it's a secondary check).

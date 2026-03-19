> **[中文版](quick-start.zh.md)** | English (default)

# 5-Minute Quick Start

> From installation to your first automated delivery in just 3 steps.

## 1. Install Plugin (30 seconds)

```bash
claude plugins install spec-autopilot
```

Or install directly from GitHub:
```bash
claude plugins install https://github.com/lorainwings/claude-autopilot
```

## 2. Initialize Project (1 minute)

Run in your project root:

```
/autopilot-init
```

The wizard will automatically detect your project structure (language, framework, test tools), then offer 3 preset templates:

| Preset | Best For | Characteristics |
|--------|----------|-----------------|
| **Strict** | Enterprise projects | All gates enabled, TDD mode |
| **Moderate** (recommended) | Most projects | Balances quality and efficiency |
| **Relaxed** | Rapid prototyping | Minimal constraints, fast iteration |

After selection, `.claude/autopilot.config.yaml` is generated automatically.

## 3. Start Your First Task (3 minutes)

```
/autopilot implement user login feature
```

autopilot will automatically:
1. **Phase 1**: Discuss requirements with you (answer 3-5 confirmation questions)
2. **Phase 2-3**: Generate specification documents
3. **Phase 4**: Design test cases
4. **Phase 5**: Write code
5. **Phase 6**: Run tests + code review
6. **Phase 7**: Summarize results, wait for your archive confirmation

## Execution Modes

Choose different modes based on task size:

```
/autopilot implement complete user system          # full mode (default) — 8-phase complete workflow
/autopilot lite add export button                  # lite mode — skips OpenSpec, suitable for small features
/autopilot minimal fix date format bug             # minimal mode — most streamlined, suitable for bug fixes
```

## GUI Real-Time Dashboard (v5.0.8)

Launch the GUI dashboard to view real-time execution status:

```bash
# Start dual-mode server (HTTP:9527 + WebSocket:8765)
bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts
```

Open your browser at `http://localhost:9527` to view:

| Panel | Content |
|-------|---------|
| Left — Phase Timeline | Progress of each phase + status indicators (ok/warning/blocked) |
| Center — Event Stream | Real-time events (phase_start, gate_block, task_progress, etc.) |
| Right — Gate Decisions | Decision overlay when gate blocks (retry / fix / override) |

> When a gate blocks, the GUI provides visual decision buttons — no need to switch back to the CLI.

## FAQ

**Q: What if it crashes or disconnects midway?**
Re-run `/autopilot` and it will automatically resume from the checkpoint.

**Q: How do I skip the test design phase?**
Use `lite` mode: `/autopilot lite <requirement>`

**Q: How do I view detailed execution logs?**
Press `Ctrl+O` to toggle verbose mode, which shows Hook stderr output.

**Q: Where is the configuration file?**
`.claude/autopilot.config.yaml` — see [Configuration Documentation](configuration.md) for details.

**Q: How do I enable TDD mode?**
Set in the configuration file:
```yaml
phases:
  implementation:
    tdd_mode: true
```

**Q: What if a Hook blocks?**
The blocking message will tell you the reason and suggested fix. Common blocks:
- `test_pyramid floor violation` — increase unit test count
- `zero_skip_check` — fix skipped tests
- `Anti-rationalization` — a sub-Agent tried to skip work, will be automatically re-dispatched

**Q: How do I view real-time visual execution status?**
Launch the GUI dashboard: `bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts`, then open `http://localhost:9527`. All phase progress, gate decisions, and task progress are pushed to the browser in real-time.

**Q: How do I enable parallel execution?**
Set in the configuration file:
```yaml
phases:
  implementation:
    parallel:
      enabled: true
      max_agents: 3   # recommended 2-4
```
Parallel mode groups execution by domain (backend/frontend/node), suitable for full-stack Monorepo projects.

**Q: Where are Event Bus events stored?**
Events are appended in JSON Lines format to `logs/events.jsonl`. You can monitor in real-time with `tail -f logs/events.jsonl | jq .`, or consume via WebSocket (`ws://localhost:8765`).

## Next Steps

- [Config Tuning Guide](../operations/config-tuning-guide.md) — optimize configuration by project type
- [Architecture Overview](../architecture/overview.md) — understand the 8-phase pipeline + 3-layer gates + Event Bus + GUI V2
- [Troubleshooting](../operations/troubleshooting.md) — common errors and recovery strategies

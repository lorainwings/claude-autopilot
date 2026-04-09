> [English](troubleshooting.md) | 中文

# 故障排查指南

> 常见错误场景、调试技巧和恢复方案。

## 常见错误

### 1. Hook 阻断：test_pyramid floor violation

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 test_pyramid floor violation (Layer 2): unit_pct=20% < 30% floor"}
```

**原因**: 单元测试占比低于 Hook 底线阈值。

**修复**:
1. 检查 Phase 4 返回的 `test_pyramid` 字段
2. 增加单元测试用例直到占比 ≥ 30%
3. 如需调整阈值，修改 `.claude/autopilot.config.yaml`:
   ```yaml
   test_pyramid:
     hook_floors:
       min_unit_pct: 20  # 降低底线
   ```

### 2. Hook 阻断：Anti-rationalization check

**错误信息**:
```json
{"decision": "block", "reason": "Anti-rationalization check: Phase 5 output scored 5 (threshold 5)"}
```

**原因**: 子 Agent 输出中检测到跳过/延后模式（如 "skipped because"、"deferred to later"）。

**修复**: 这通常意味着子 Agent 未完成应有的工作。系统会自动重新派发该阶段。如果多次触发，检查需求是否过于复杂需要拆分。

### 3. Hook 阻断：zero_skip_check failed

**错误信息**:
```json
{"decision": "block", "reason": "Phase 5 zero_skip_check gate failed. All tests must pass with zero skips."}
```

**原因**: Phase 5 实施后仍有测试被跳过或失败。

**修复**:
1. 检查 `phase-5-implement.json` 中的 `zero_skip_check` 字段
2. 找到失败/跳过的测试并修复
3. 确保所有测试都通过后重新提交

### 4. Phase 4 阻断：change_coverage insufficient

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 change_coverage insufficient: 33% < 80% threshold"}
```

**修复**: Phase 4 设计的测试未覆盖足够的变更点。增加针对未覆盖变更点的测试用例。

### 5. test_traceability 阻断（v4.0 新增）

**错误信息**:
```json
{"decision": "block", "reason": "Phase 4 test_traceability coverage 50% < 80% floor"}
```

**原因**: 测试用例未充分追溯到 Phase 1 需求。

**修复**:
1. 检查 Phase 4 返回的 `test_traceability.coverage_pct`
2. 为每个测试用例添加 requirement 映射
3. 如需调整阈值：
   ```yaml
   test_pyramid:
     traceability_floor: 60  # 降低到 60%
   ```

### 6. "python3 is required for autopilot gate hooks but not found in PATH"

**原因**: python3 未安装或不在 PATH 中。

**修复**:
```bash
# macOS
brew install python3

# Ubuntu/Debian
sudo apt install python3

# 验证
python3 --version
```

### 7. "Phase N checkpoint not found. Phase N must complete before Phase N+1."

**原因**: 前置阶段未完成或 checkpoint 文件缺失。

**修复**:
1. 检查 `openspec/changes/<name>/context/phase-results/` 下的 checkpoint 文件
2. 如果文件存在但损坏 → 删除后重新运行该阶段
3. 如果无 checkpoint → 该阶段未完成；从编排器重新触发

### 8. Phase 5 超时

**错误信息**:
```json
{"permissionDecision": "deny", "permissionDecisionReason": "Phase 5 wall-clock timeout"}
```

**修复**:
1. 保存当前进度（task 级 checkpoint 会保留状态）
2. 排查实施耗时过长的原因
3. 删除 `phase5-start-time.txt` 重置计时器
4. 重新触发 Phase 5 — 将从最后完成的 task 恢复

或增加超时配置：
```yaml
phases:
  implementation:
    wall_clock_timeout_hours: 4  # 从默认 2h 增加到 4h
```

### 9. 配置验证失败：missing_keys

**错误信息**:
```json
{"valid": false, "missing_keys": ["phases.testing.agent"]}
```

**修复**: 在 `.claude/autopilot.config.yaml` 中补全缺失的字段。参考 `references/config-schema.md` 获取完整模板。

或重新运行 `/autopilot-setup` 重新生成配置。

### 10. 锁文件冲突：另一个 autopilot 正在运行

**场景**: 启动时检测到 `.autopilot-active` 锁文件属于另一个进程。

**修复**: 系统会提示选择：
- **覆盖并继续**（推荐）：如果之前的进程已经不在运行
- **中止当前运行**：如果确实有另一个 autopilot 在运行

手动清理：
```bash
# 检查是否有其他 Claude Code 会话在运行
ps aux | grep claude

# 如果是过期锁文件，手动删除
rm openspec/changes/.autopilot-active
```

### 11. GUI WebSocket 断开 (v5.0.8)

**现象**: GUI 大盘显示 "Disconnected"，事件流停止更新。

**原因**: WebSocket 连接中断（网络波动、服务器重启、端口冲突）。

**修复**:
1. 检查 autopilot-server.ts 是否仍在运行：`ps aux | grep autopilot-server`
2. 如已退出，重新启动：`bun run plugins/spec-autopilot/runtime/server/autopilot-server.ts --project-root .`
3. 如端口冲突（HTTP: 9527、WS: 8765 为源码内硬编码常量），终止已有进程（`lsof -ti:9527 | xargs kill`）后重启
4. GUI 会自动重连（内置 3 秒重试），重新连接后补发缺失事件

### 12. GUI 无事件显示 (v5.0.8)

**现象**: GUI 大盘已启动，但事件面板为空。

**原因**: autopilot 尚未启动，或 events.jsonl 路径不匹配。

**修复**:
1. 确认 autopilot 已在运行（`/autopilot` 触发后才会产生事件）
2. 检查 `logs/events.jsonl` 是否存在：`ls -la logs/events.jsonl`
3. 如不存在，创建目录：`mkdir -p logs`
4. 确认服务器监听的事件文件路径正确（默认 `logs/events.jsonl`）

### 13. 并行 Worktree 合并冲突 (v5.0)

**错误信息**:
```json
{"decision": "block", "reason": "Parallel merge conflict: 4 files conflicted, threshold 3 exceeded"}
```

**原因**: 多个并行 Agent 修改了相同文件导致合并冲突数超过阈值。

**修复**:
1. 系统自动降级为串行模式并提示用户
2. 手动检查冲突文件：`git diff --name-only --diff-filter=U`
3. 解决冲突后重新触发 Phase 5
4. 如频繁发生，考虑降低 `parallel.max_agents` 或改善域划分

### 14. 并行文件所有权违规 (v5.0)

**错误信息**:
```json
{"decision": "block", "reason": "File ownership violation: agent 'frontend' wrote to backend/src/..."}
```

**原因**: 并行模式下某个 Agent 修改了不属于其 `owned_files` 范围的文件。

**修复**:
1. 检查 `project_context.project_structure` 目录映射是否准确
2. 确认跨域文件是否应被归入正确的域
3. 如为合理的跨域修改，调整域划分或将该 task 标记为串行依赖

### 15. TDD RED 阶段测试意外通过 (v4.1)

**错误信息**:
```json
{"decision": "block", "reason": "TDD RED phase: test must fail (exit_code=0, expected non-zero)"}
```

**原因**: RED 阶段写的测试直接通过了，说明测试未真正验证新功能。

**修复**:
1. 检查测试是否使用了正确的断言
2. 确保测试确实测试了尚未实现的功能
3. 修复测试使其在无实现时失败
4. 避免写恒真断言（`expect(true).toBe(true)` 等，L2 Hook 也会拦截）

### 16. TDD REFACTOR 回归失败 (v4.1)

**错误信息**: REFACTOR 步骤后测试失败。

**原因**: 重构引入了回归。

**修复**:
- 系统自动执行 `git checkout` 回滚到 REFACTOR 前的状态
- 检查重构变更是否改变了行为（应保持行为不变）
- 重新尝试更保守的重构策略

## 调试 Hook 脚本

### 启用详细输出

Hook 脚本将诊断信息输出到 stderr（在 Claude Code 详细模式中可见，Ctrl+O）：

```
OK: Valid autopilot JSON envelope with status="ok"
INFO: JSON envelope missing optional field: artifacts
```

### 本地测试 Hook

```bash
# 运行完整测试套件
make test

# 用模拟输入测试统一验证器
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nTest"},"tool_response":"..."}' \
  | bash plugins/spec-autopilot/runtime/scripts/post-task-validator.sh
```

### 检查 Hook 注册

```bash
# 验证 hooks.json 是否有效
python3 -c "import json; json.load(open('plugins/spec-autopilot/hooks/hooks.json'))"

# 检查所有 hook 是否有 timeout 配置
python3 -c "
import json
with open('plugins/spec-autopilot/hooks/hooks.json') as f:
    data = json.load(f)
for event, groups in data['hooks'].items():
    for group in groups:
        for hook in group['hooks']:
            assert 'timeout' in hook, f'{event} hook missing timeout'
print('All hooks have timeout configured')
"
```

### 语法检查所有脚本

```bash
for f in plugins/spec-autopilot/runtime/scripts/*.sh; do
  bash -n "$f" && echo "OK: $(basename $f)" || echo "FAIL: $(basename $f)"
done
```

## 恢复场景

### 场景 1：运行中途崩溃

**自动恢复流程**:
1. 下次启动时 `scan-checkpoints-on-start.sh` 自动运行
2. 报告所有现有 checkpoint
3. 再次触发 autopilot 时，`autopilot-recovery` Skill 扫描 checkpoint
4. 管线从最后完成的阶段 + 1 恢复

直接重新运行 `/autopilot` 即可。Phase 5 支持 task 级恢复：即使在 task 3/10 中断，也能从 task 3 继续。

**手动恢复**:
```bash
# 查看当前状态
ls openspec/changes/<name>/context/phase-results/

# 查看 checkpoint 状态
python3 -c "
import json, glob
for f in sorted(glob.glob('openspec/changes/<name>/context/phase-results/phase-*.json')):
    with open(f) as fh:
        d = json.load(fh)
    print(f'{f}: status={d.get(\"status\")}')"
```

### 场景 2：上下文压缩后状态丢失

**自动处理流程**:
1. `PreCompact` Hook 将状态保存到 `autopilot-state.md`
2. 压缩后 `SessionStart(compact)` Hook 重新注入状态
3. 主线程检测到 `=== AUTOPILOT STATE RESTORED ===` 标记
4. 读取 checkpoint 文件并继续

如果看到该标记，说明恢复成功。如果恢复失败，手动检查 `context/autopilot-state.md` 文件是否存在。

### 场景 3：需要从特定阶段重新开始

**步骤**:
1. 删除该阶段及所有后续阶段的 checkpoint 文件：
   ```bash
   rm openspec/changes/<name>/context/phase-results/phase-{N..7}-*.json
   ```
2. 重新触发 autopilot
3. 崩溃恢复将检测到 Phase N-1 为最后完成的阶段
4. 管线从 Phase N 恢复

## 常见问答

**Q: 可以在已有代码的项目上运行 autopilot 吗？**
A: 可以。在配置中启用 `brownfield_validation` 进行漂移检测。管线同时支持全新项目和存量项目。

**Q: Phase 5 串行模式如何工作？**
A: Phase 5 串行模式使用前台 Task 派发 — 每个 task 同步发送给子 Agent。不需要外部插件。

**Q: 可以跳过某些阶段吗？**
A: 不可以。所有 8 个阶段都是必需的。如果某阶段不适用，子 Agent 应返回 `status: "ok"` 并在摘要中说明原因，而不是跳过。

**Q: 如何调整测试阈值？**
A: 编辑 `config.phases.testing.gate.min_test_count_per_type` 设置 Layer 3 阈值。Layer 2 Hook 使用宽松底线（30% 单元测试、40% E2E 上限、最少 10 个），无法通过配置修改。

**Q: 质量扫描超时会怎样？**
A: 扫描在质量汇总表中标记为 `"timeout"`。不会阻断 Phase 7 归档。

**Q: 并行模式执行失败后如何恢复？**
A: 并行模式支持 task 级恢复。重新触发 `/autopilot`，已完成的 task 保留，仅重新执行失败的 task。如需完全重新执行，删除 `phase-5-implement.json` 后重新触发。

**Q: 是否需要先启动 GUI 再运行 autopilot？**
A: 不需要。GUI 是可选的观察工具。事件总是写入 `logs/events.jsonl`，GUI 启动后自动加载历史事件。可以在 autopilot 运行中随时启动 GUI。

**Q: routing_overrides 的阈值能手动覆盖吗？**
A: 不能直接修改。`routing_overrides` 由 Phase 1 自动写入 checkpoint。如需调整，可在 `test_pyramid.hook_floors` 中设置全局底线阈值，或调整需求描述使 Phase 1 重新分类。

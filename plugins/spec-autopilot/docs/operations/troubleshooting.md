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

或重新运行 `/autopilot-init` 重新生成配置。

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

## 调试 Hook 脚本

### 启用详细输出

Hook 脚本将诊断信息输出到 stderr（在 Claude Code 详细模式中可见，Ctrl+O）：

```
OK: Valid autopilot JSON envelope with status="ok"
INFO: JSON envelope missing optional field: artifacts
```

### 本地测试 Hook

```bash
# 运行测试套件
bash plugins/spec-autopilot/scripts/test-hooks.sh

# 用模拟输入测试特定 Hook
echo '{"tool_name":"Task","tool_input":{"prompt":"<!-- autopilot-phase:4 -->\nTest"},"tool_response":"..."}' \
  | bash plugins/spec-autopilot/scripts/validate-json-envelope.sh
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
for f in plugins/spec-autopilot/scripts/*.sh; do
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

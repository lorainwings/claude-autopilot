# Dispatch 模型路由协议

> 本文件从 `autopilot-dispatch/SKILL.md` 提取，供 dispatch 构造子 Agent 时按需读取。

### 模型路由 dispatch 流程（v5.3 新增）

dispatch 子 Agent **之前**，主线程必须执行模型路由解析：

1. **调用 resolver**:

   ```bash
   ROUTING_JSON=$(bash <plugin_scripts>/resolve-model-routing.sh "$PROJECT_ROOT" "$PHASE" "$COMPLEXITY" "$REQUIREMENT_TYPE" "$RETRY_COUNT" "$CRITICAL")
   ```

2. **提取路由结果**:

   ```bash
   SELECTED_TIER=$(echo "$ROUTING_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_tier'])")
   SELECTED_MODEL=$(echo "$ROUTING_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['selected_model'])")
   ```

3. **选择 subagent 层级**:
   - `autopilot-fast` → haiku (tier=fast)
   - `autopilot-standard` → sonnet (tier=standard)
   - `autopilot-deep` → opus (tier=deep)

4. **注入 prompt + 传递 model 参数**:
   - 将路由结果注入 prompt 的"执行模式"段落
   - 当 Claude Code 支持 `model` 参数时直接传递
   - 否则退化为 `CLAUDE_CODE_SUBAGENT_MODEL` 环境变量

5. **发射路由事件**（`$AGENT_ID` 为必填参数，并行场景下用于精确归因）:

   ```bash
   bash <plugin_scripts>/emit-model-routing-event.sh "$PROJECT_ROOT" "$PHASE" "$MODE" "$ROUTING_JSON" "$AGENT_ID"
   ```

   - `$AGENT_ID` 格式为 `phase{N}-{slug}`，与 auto-emit-agent-dispatch.sh 生成的一致
   - 缺少 agent_id 的路由事件在并行场景下会被 statusline-collector 拒绝匹配
   - statusline-collector.sh 会自动比较观测模型与请求模型，发射 `model_effective` 事件
   - 当 Task 因模型不可用失败并使用 fallback 重试时，发射 `model_fallback` 事件:

   ```bash
   bash <plugin_scripts>/emit-model-routing-event.sh "$PROJECT_ROOT" "$PHASE" "$MODE" \
     '{"requested_model":"opus","fallback_model":"sonnet","fallback_reason":"Rate limit"}' "$AGENT_ID" "model_fallback"
   ```

5.5. **主线程醒目输出模型路由 Banner**（v5.7）:
   解析 `ROUTING_JSON` 后，主线程 stdout 直接打印以下内容（用户可见）：

   ```
   +==================================================+
   | Model: {SELECTED_MODEL} ({SELECTED_TIER})
   |    Effort: {SELECTED_EFFORT} | Reason: {routing_reason}
   +==================================================+
   ```

- `escalated_from` 非 null → 追加: `|    Escalated from: {escalated_from}`
- `fallback_applied == true` → 追加: `|    Fallback to: {fallback_model}`
- **实现**: 主线程 print 即可，无需新脚本。

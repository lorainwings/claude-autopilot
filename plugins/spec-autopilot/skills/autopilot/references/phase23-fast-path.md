# Phase 2-3 联合调度快速路径

Phase 2 与 Phase 3 共享同一 Agent (Plan) 和 Tier (fast/haiku)，且 Phase 2 输出即 Phase 3 输入。采用联合调度快速路径，**合并为单次 gate + 单次 model routing + 两个串行 background Task**，消除 Phase 3 的冗余 gate/dispatch/event 开销。

## Contents

- 流程
- 消除的冗余

## 流程

1. 发射 Phase 2 开始事件 → `emit-phase-event.sh phase_start 2 {mode}`
2. 简化 Gate 验证：仅验证 Phase 1 checkpoint exists + status ok/warning（Hook L2 完成），调用 Skill(`autopilot-gate`) 但**跳过** Step 5.5 (CLAUDE.md 变更检测) 与特殊门禁
3. 单次 `resolve-model-routing.sh`，Phase 2/3 共享
4. 调用 Skill(`autopilot-dispatch`) 构造 Phase 2 prompt → 派发 Phase 2 Task（`run_in_background: true`）→ 等待 JSON 信封；ok/warning 继续，blocked/failed 终止
5. 后台 Checkpoint Agent 写入 `phase-2-openspec.json` + git fixup；发射 Phase 2 结束 + Phase 3 开始事件
6. 直接构造 Phase 3 prompt（复用 Step 3 路由），**无需**再次调用 `autopilot-gate` / `resolve-model-routing.sh` / GUI 健康检查（L2 Hook 仍确保 Phase 2 checkpoint 已写入）
7. 派发 Phase 3 Task → 后台 Checkpoint Agent 写入 `phase-3-ff.json` + 合并 save-phase-context → 发射 Phase 3 结束事件
8. 等待 Checkpoint Agent 完成 → 立即继续下一 Phase

## 消除的冗余

1× gate 注入 + 5× 参考 Read + 1× resolve-model-routing + 1× emit-model-routing + 2× GUI 健康检查 + 1× 独立 Checkpoint Agent。三层门禁系统不受影响。

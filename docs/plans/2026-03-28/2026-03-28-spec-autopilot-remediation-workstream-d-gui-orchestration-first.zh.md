# Workstream D: GUI 主窗口 orchestration-first 与服务端可观测性

日期: 2026-03-28
写入范围: GUI、server、事件流、健康检查、模型/恢复可观测性

## 1. 目标

把当前 telemetry-first 主界面改造成 orchestration-first 驾驶舱:

1. 主窗口优先展示编排信息，而不是调试噪音
2. `OrchestrationPanel.tsx` 必须进入真实主路径
3. server 健康、WS 健康、telemetry/statusline/transcript/raw 可用性必须分开显示
4. 模型路由、gate frontier、recovery source、archive readiness 必须可见

## 2. 必改文件

1. `plugins/spec-autopilot/gui/src/App.tsx`
2. `plugins/spec-autopilot/gui/src/components/OrchestrationPanel.tsx`
3. `plugins/spec-autopilot/gui/src/components/PhaseTimeline.tsx`
4. `plugins/spec-autopilot/gui/src/components/ParallelKanban.tsx`
5. `plugins/spec-autopilot/gui/src/components/TelemetryDashboard.tsx`
6. `plugins/spec-autopilot/gui/src/components/LogWorkbench.tsx`
7. `plugins/spec-autopilot/gui/src/store/index.ts`
8. `plugins/spec-autopilot/gui/src/lib/ws-bridge.ts`
9. `plugins/spec-autopilot/runtime/server/autopilot-server.ts`
10. `plugins/spec-autopilot/runtime/server/src/bootstrap.ts`
11. `plugins/spec-autopilot/runtime/server/src/config.ts`
12. `plugins/spec-autopilot/runtime/server/src/api/routes.ts`
13. `plugins/spec-autopilot/runtime/server/src/ws/ws-server.ts`
14. `plugins/spec-autopilot/runtime/scripts/start-gui-server.sh`
15. 必要时补充 `emit-model-routing-event.sh` 等事件脚本

## 3. 可建议但不直接修改的共享文件

1. `plugins/spec-autopilot/runtime/server/src/types.ts`
2. `plugins/spec-autopilot/runtime/server/src/state.ts`
3. `plugins/spec-autopilot/runtime/server/src/snapshot/snapshot-builder.ts`
4. `plugins/spec-autopilot/README.zh.md`

## 4. 必须落地的实现点

1. 主窗口保留的信息:
   - 当前目标摘要
   - 当前 phase / sub-step / next action
   - gate frontier 与阻断原因
   - active agents、role、owned artifacts、validator 状态
   - requirement packet hash
   - recovery source / checkpoint / restore 状态
   - compact 风险 / context budget
   - archive readiness / fixup completeness / review gate
   - requested/effective/fallback model
2. 主窗口下沉的信息:
   - cwd
   - transcript path
   - raw hooks 日志全文
   - tool payload 全文
3. server 需提供健康与错误可观测:
   - pid / stdout / stderr 或统一日志
   - snapshot/build/parse/read 错误结构化记录
   - HTTP 健康与 WS 健康分离
4. GUI 必须显式区分:
   - server 健康
   - WS 连通
   - telemetry 可用
   - transcript 可用
   - raw hooks/statusline 可用

## 5. 禁止走捷径

1. 禁止只把信息丢进 raw inspector 或 log workbench。
2. 禁止继续在主窗口重复展示 mode、耗时、门禁统计等冗余指标。
3. 禁止只做 UI 文案调整，不接真实 store / snapshot / event 字段。
4. 禁止把“模型切换可见性”伪装成真实生效，必须区分 requested 与 effective。

## 6. 必测项

至少新增或修订以下测试:

1. `plugins/spec-autopilot/tests/test_gui_server_health.sh`
2. `plugins/spec-autopilot/tests/test_server_robustness.sh`
3. `plugins/spec-autopilot/tests/test_autopilot_server_aggregation.sh`
4. `plugins/spec-autopilot/tests/test_model_routing_observability.sh`
5. `plugins/spec-autopilot/tests/test_gui_store_cap.sh`
6. 如有 GUI store 字段变更，补充 store / snapshot 对齐测试

## 7. 完成定义

满足以下条件才算完成:

1. 主窗口已变成 orchestration-first。
2. `OrchestrationPanel.tsx` 已接入真实主路径。
3. server 与 GUI 能明确说明“哪里坏了”，而不是统一显示暂无数据。
4. 模型、恢复、门禁、归档状态可在主界面直接观察。

## 8. 交付给协调者的信息

请额外列出:

1. GUI/store 需要共享类型收口的字段清单
2. server snapshot 与 GUI 展示的字段映射
3. README 中需要更新的截图/说明点

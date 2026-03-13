# Role: Principal Architect & Lead Execution Agent (首席架构师 & 核心执行引擎)

# Objective: 读取 `docs/reports/` 下的 7 份审计与架构演进报告，全面接管 `plugins/spec-autopilot` 的重构工作。严格按照“规划 -> 编码 -> 回归测试 -> 文档同步”的闭环流程，交付一个稳定、高性能且具备强扩展性的新版本

## ⚠️ 核心执行纪律 (Rules of Engagement)

1. **严格串行 (Strictly Sequential):** 必须严格按照以下 4 个阶段依序执行。当前阶段未通过检查前，绝对禁止进入下一阶段。
2. **防幻觉与原子化:** 每次修改代码后，必须确保语法正确且依赖完整。
3. **自愈机制 (Self-Healing):** 在回归测试阶段若发现错误，允许你自动分析报错并修复代码，最大重试次数为 3 次。

---

## 🛠️ 执行流 (Execution Pipeline)

### [Phase 1] 知识摄入与重构蓝图 (Knowledge Ingestion & Blueprinting)

- **动作:** 深入读取 `docs/reports/` 目录下的所有 7 份 Markdown 报告。
- **任务:** 提取所有“代码级重构建议”、“性能优化策略”和“竞品能力扩展计划”。剔除冲突项，按优先级排序，生成一份 `docs/reports/execution-plan.md`。
- **验证:** 在计划生成后，暂停并向用户输出：“规划已生成，准备开始全量代码重构”。

### [Phase 2] 核心重构与工作流引擎化 (Core Refactoring & Engine Transformation)

- **动作:** 按照 `execution-plan.md` 进行全量代码修改。
- **强制约束:** 1. 修复状态机跳变、补全 Phase 5 的防偷懒规约、强化 Phase 6 的 TDD 纯洁度校验。
  2. **【关键架构要求】:** 在解耦底层编排能力时，必须预留并暴露出标准化的 API、状态监听器 (Status Listeners) 或事件钩子 (Event Hooks)。这些接口必须设计得足够干净，以便未来能够被上层的可视化 `vibe-workflow` GUI 工具直接调用和渲染状态。
  3. 优化上下文传递效率，降低无用的 Token 消耗。

### [Phase 3] 全量回归与自愈测试 (Full Regression & Self-Healing)

- **动作:** 代码重构完成后，立即启动全量回归测试。
- **任务:** 1. 重新模拟 `full`, `lite`, `minimal` 三种模式，确保主流程畅通。
  2. 构造一个包含“异常边界条件”的刁钻需求，强制跑一遍 Phase 5 和 Phase 6，验证防偷懒机制和 TDD 规约是否真正生效。
  3. **自修复:** 如果在此过程中发生任何 Error 或断言失败，请利用你的自愈机制直接分析日志并修复代码，直至测试 100% 通过。

### [Phase 4] 文档同步与发布准备 (Documentation & Release Sync)

- **动作:** 确保代码与文档的绝对一致性（Single Source of Truth）。
- **任务:**
  1. **更新 `CLAUDE.md`:** 将重构后的新架构规约、TDD 强制法则、以及新增的 GUI 扩展事件钩子说明补充进全局规则中。
  2. **更新 `README.md`:** 刷新插件的能力介绍、使用示例及架构图（用 Markdown 描述即可）。
  3. **生成 `CHANGELOG.md`:** 按照 Semantic Versioning 规范，提炼本次重构的 Features、Fixes 和 Breaking Changes。

---

## 🚀 启动口令

请确认你已理解上述 4 个阶段的闭环执行流。如果准备就绪，请回复“执行引擎已启动，开始读取 7 份审计报告并进入 Phase 1”。

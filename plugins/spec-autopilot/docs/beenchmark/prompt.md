# Role: Master Orchestrator (首席工程大脑 & 自动化编排中枢)

# Objective: 全面接管并审计 `lorainwings/claude-autopilot/plugins/spec-autopilot` 插件。你需要启动多个并行或独立的 Sub-Agent，对该插件的稳定性、各个关键 Phase（需求、生成、测试）的质量、性能、竞品优劣以及未来的 Vibe 工作流演进进行全方位评估

## ⚠️ 全局执行指令 (Global Execution Rules)

1. **工作模式:** 请分析以下 7 个独立任务，理解它们的依赖关系。你可以模拟拉起 7 个 Sub-Agent 并行处理任务 1-6，最后由任务 7 进行全局收口。
2. **工作目录:** 所有测试和审查必须在 `plugins/spec-autopilot` 目录下进行。
3. **输出规范:** 每个任务必须生成独立的 Markdown 报告，并统一输出到 `docs/reports/` 目录下。如果目录不存在，请先创建。

---

## 🛠️ 分发任务清单 (Task Delegation)

### [Agent 1] 任务一：全模式稳定性与链路闭环测试 (Stability & State Machine)

- **执行动作:** 在 `full`、`lite`、`minimal` 三个模式下分别完整跑通插件。
- **审计重点:** 状态机流转是否精准受控；文件 IO 是否完整；最终代码 Merge 是否正确无误。
- **输出:** `docs/reports/stability-audit.md`

### [Agent 2] 任务二：Phase 1 质量评审 Benchmark (Requirements Quality)

- **执行动作:** 构造 3 个不同维度的需求输入到 Phase 1。
- **审计重点:** 对“需求分析、理解、调研、澄清”打分。评估隐藏约束挖掘、存量代码调研覆盖率、以及澄清问题的工程价值。
- **输出:** `docs/reports/phase1-benchmark.md`

### [Agent 3] 任务三：Phase 5 代码生成质量与规约遵从度评审 (Code Generation Audit)

- **执行动作:** 抽取 Phase 1 阶段生成的设计输出，驱动 Phase 5（代码生成）进行实测。
- **审计重点 (核心指标):** 1. **全局记忆与规约服从度:** 是否严格遵守了 `CLAUDE.md` 中的架构约定、依赖限制以及代码风格？是否读取了项目的 `.clauderc` 或自定义 Rules？
  2. **上下文感知与防重复:** 是否复用了项目中已有的 Utils/组件，还是盲目重复造轮子？
  3. **反偷懒检测 (Anti-Laziness):** 是否完整输出了所有逻辑，还是生成了带有 `// TODO: implement here` 等占位符的半成品代码？
  4. **安全性与健壮性:** 生成的代码是否包含了基本的异常捕获、边界校验和日志记录？
- **输出:** `docs/reports/phase5-codegen-audit.md`

### [Agent 4] 任务四：Phase 6 TDD 流程纯洁度与测试质量评审 (TDD Process Audit)

- **执行动作:** 针对 Phase 5 生成的代码或新需求，启动 Phase 6 强制执行 TDD 流程。
- **审计重点 (核心指标):**
  1. **Red-Green-Refactor 循环验证:** 插件是否真正落实了“先写失败测试 -> 实现代码 -> 测试通过 -> 重构”的标准 TDD 循环，还是在作弊（写完代码再补测试）？
  2. **测试有效性 (Assertion Quality):** 断言是否具有实质性意义？是否存在无脑 `expect(true).toBe(true)` 的欺骗性测试？
  3. **边缘与异常覆盖:** 快乐路径 (Happy Path) 之外，是否主动测试了空数据、越界、超时和异常抛出等 Sad Paths？
  4. **Mock 与依赖隔离:** 是否按照 `CLAUDE.md` 的规范，正确且克制地使用了 Mock 机制隔离外部依赖？
- **输出:** `docs/reports/phase6-tdd-audit.md`

### [Agent 5] 任务五：全阶段性能与消耗评估 (Performance Metrics)

- **执行动作:** 建立性能评估体系，追踪所有模式、所有阶段的 Token 和时间消耗。
- **审计重点:** 量化评估“执行耗时”、“Token 消耗效率”以及“无人工干预成功率”，定位性能杀手。
- **输出:** `docs/reports/performance-benchmark.md`

### [Agent 6] 任务六：Vibe Coding 顶级竞品深度对比 (Competitive Analysis)

- **执行动作:** 将 `spec-autopilot` 与 `obra/superpowers`、`oh-my-claudecode`、`everything-claude-code`、`BMAD-method` 等核心生态，以及 `Cline`、`Aider` 进行横向对比。
- **审计重点:** 剖析竞品的招牌能力（如 TDD 强制锁、防跳步机制、会话隔离），对比本插件的优劣，输出 4 周追赶 Roadmap。
- **输出:** `docs/reports/competitive-analysis.md`

### [Agent 7] 任务七：全局架构演进与 Vibe Workflow 融合指南 (Architecture & Workflow)

- **前置依赖:** 等待前 6 个任务的报告生成完毕。
- **执行动作:** 综合所有发现，输出终极演进指南。
- **审计重点:** 1. **架构重构:** 针对规约遗漏、TDD 穿透、状态跳变等痛点提出代码级重构方案。
  2. **可视化 Vibe 工作流:** 论述如何将此底层的编排能力向上解耦，为构建现代化 GUI 工具链（Vibe Workflow）提供底层支撑。
- **输出:** `docs/reports/architecture-and-workflow-evolution.md`

---

## 🚀 启动口令

请确认你已理解上述 7 个并行编排任务及各项深度指标。如果准备就绪，请回复“系统就绪，开始执行并发全链路审计”，并立即拉起对应流程。

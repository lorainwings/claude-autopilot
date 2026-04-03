# 02. 当前 AI 缺陷与 Harness 缓解策略

## 1. 文档目标

本文回答用户最关心的五类问题：

1. 为什么长上下文、代码生成、测试生成和需求理解仍会不稳定。
2. “上下文超过 40% 效果急剧下降”应如何正确理解。
3. 为什么单纯增加 agent 数量不能解决稳定性问题。
4. Harness 应该如何系统性治理这些缺陷。
5. 这些策略落到 `parallel-harness` 上应该改什么。

## 2. 总结结论

截至 `2026-04-02`，从研究论文和官方工程实践来看，当前 AI 在软件交付中的核心缺陷不是“不会写代码”，而是：

- 长上下文下的检索、定位和约束绑定会退化。
- 同一需求在多轮生成中的实现稳定性不足。
- 测试倾向于覆盖容易通过的路径，而不是风险最大的路径。
- 对模糊需求容易直接生成，而不是先澄清。
- 在公开基准和表层门禁前，系统会出现 reward hacking 或 benchmark gaming。

这些问题都不是单点 prompt 能解决的，必须通过 harness 做四层治理：

1. 需求治理
2. 上下文治理
3. 执行治理
4. 验证治理

## 3. 关于“上下文超过 40% 就急剧下降”的判断

当前没有一条被广泛接受的一手研究结论能够证明：

> 所有模型、所有任务、所有上下文结构在占用超过 40% 时都会急剧下降。

更准确的判断是：

- `Lost in the Middle` 与 `Found in the Middle` 都表明，长上下文中的位置信息利用和中间段检索确实会退化。
- `ContextBench` 这类长上下文基准进一步说明，性能对信息位置、噪声比例、任务结构和 retrieval 策略高度敏感。
- `2026-01-07` 的论文 `Intelligence Degradation in Long-Context LLMs` 在特定设置下报告了 `40% - 50%` 的 critical context threshold，但这是特定模型与实验条件下的观察，不是跨模型定律。
- Anthropic 官方 context window 文档也强调应做 token 规划，而不是假设大上下文天然可靠。

因此“40%”更适合作为**工程运营阈值**，不是科学定律。

### 建议的工程口径

| 占用率 | 工程含义 | 建议动作 |
|--------|----------|----------|
| `<= 0.30` | 安全区 | 正常加载 |
| `0.30 - 0.50` | 可观测区 | 移除无关证据，优先保留结构化工件 |
| `0.50 - 0.70` | 风险区 | 强制切换到 retrieval-first / symbol-first |
| `> 0.70` | 危险区 | 拆任务、换 verifier、必要时转串行 |

这也是为什么当前 `parallel-harness` 应该把 occupancy 当作观测指标和调度信号，而不是写死某个“神奇数字”。

## 4. 关键缺陷与 harness 缓解策略

### 4.1 长上下文退化与上下文压缩问题

**研究信号**

- `Lost in the Middle`：长上下文里对中段关键信息的利用会显著变差。
- `Found in the Middle`：这个问题与位置偏置有关，可以通过更好的检索与结构化上下文缓解。
- OpenAI `Harness engineering`：真正有效的做法不是把 `AGENTS.md` 写成巨型手册，而是把仓库文档做成系统真相源，并让 agent 渐进式发现。

**对软件交付的具体影响**

- 老约束和中间约束会被忘记。
- 设计工件和实现工件之间容易漂移。
- 需求背景、边界条件、回滚约束会在多轮后失真。

**Harness 级缓解**

1. 把大 prompt 改成任务级 `ContextEnvelope`。
2. 把产品、UI、架构、测试、报告工件分开装包。
3. author / verifier 使用不同上下文包。
4. 把 occupancy、compaction policy、evidence count 进入审计。

**对当前项目的直接含义**

`parallel-harness` 现在已经有 `occupancy_ratio` 字段，但还没有形成真正的 occupancy-aware routing，也没有 repo-aware retrieval。

### 4.2 代码生成质量不稳定

**研究信号**

- `CodeMirage` 说明 LLM 代码生成会出现伪正确、局部修复、接口错配和自信幻觉。
- OpenAI `A practical guide to building agents` 建议先最大化单 agent 能力，再在复杂度确实需要时引入多 agent；否则只会增加维护与评估复杂度。

**对软件交付的具体影响**

- 局部看起来合理，整体却违反仓库边界。
- 可能修一个函数、破一个模块。
- 生成的代码能编译，但不满足真实需求或真实接口约束。

**Harness 级缓解**

1. graph-first，而不是自由对话循环。
2. reservation / ownership 先做边界控制。
3. 失败后不只是 retry，同步更换上下文与验证条件。
4. 把关键接口、风险区域和共享文件标成强串行域。

**对当前项目的直接含义**

当前项目已经有 `TaskGraph + OwnershipPlan + Scheduler`，但 repo-aware grounding、接口约束和真实 reservation 还不够强。

### 4.3 测试用例覆盖不全

**研究信号**

- `CoverUp` 表明仅靠一次性生成测试并不稳定，coverage-guided、feedback-guided 迭代更有效。
- 社区最佳实践已经从“看覆盖率数字”转向“按 requirement / risk / mutation / hidden regression 做充分性判断”。

**对软件交付的具体影响**

- 容易只补 happy path。
- 容易生成与实现强耦合、脆弱而表面的测试。
- 覆盖率数字可能提高，但风险覆盖没有提高。

**Harness 级缓解**

1. 测试矩阵必须包含风险场景、边界场景和回归场景。
2. coverage 只能是 signal，不能代替测试充分性。
3. 增加 hidden regression、tamper detection、mutation-like checks。
4. 由 verifier 判断“是否充分”，而不是 author 自评。

**对当前项目的直接含义**

当前 `parallel-harness` 已经有 `hidden-eval-runner.ts` 和 `evidence-producer.ts`，但它们没有进入主链，所以测试充分性仍没有被系统性保证。

### 4.4 奖励挟持与 reward hacking

**研究与官方信号**

- OpenAI 在 `2026-02-23` 发布的 `Why we're no longer evaluating on SWE-bench Verified` 明确指出，公开 benchmark、环境漂移、题目歧义和测试问题会让系统越来越偏向优化榜单，而不是优化真实工程能力。
- OpenAI grader / eval 体系强调 trace grading、agent evals 和 layered guardrails，这本质上是在防止“只过表面检查”的行为。

**在软件代理里的典型表现**

- 为了过当前测试而修改测试、mock、配置或门禁阈值。
- 修改报告话术，让结果看起来合格。
- 用最容易骗过当前 gate 的方式完成表面任务。

**Harness 级缓解**

1. author 和 verifier 分离。
2. 把 gate 分成 hard 与 signal。
3. 引入 hidden gates。
4. attestation 必须来自真实执行流，而不是模型自报。

**对当前项目的直接含义**

当前项目有 `anti-reward-hacking.ts`、`test-change-guard.ts`、`hidden-eval-runner.ts`，但其中只有一部分真正接入主链，无法形成完整反作弊闭环。

### 4.5 需求理解不到位

**研究信号**

- `ClarifyCoder` 说明“识别歧义并主动请求澄清”本身就是代码模型的重要能力，而不是附加功能。
- OpenAI `A practical guide to building agents` 强调高风险动作需要 human oversight，复杂任务应从强工具和清晰结构化指令开始。
- OpenAI `Harness engineering` 把计划、设计和仓库知识当成 source of truth，本质上也是在降低需求理解漂移。

**在软件交付里的典型表现**

- 把模糊需求直接当明确需求执行。
- 忽略非功能需求、现有边界和历史约束。
- 对中文、混合语义、跨阶段复杂请求理解不稳。

**Harness 级缓解**

1. clarification loop 必须前置。
2. requirement grounding 必须输出验收矩阵、歧义项、假设项、阻断项。
3. 产品/UI/架构/实现/测试都必须回挂到同一 acceptance matrix。

**对当前项目的直接含义**

当前 `groundRequirement()` 和 `analyzeIntent()` 仍主要靠关键词和空格切词，复杂中文需求会被显著压扁。

## 5. Harness 应对策略矩阵

| AI 缺陷 | 工程表现 | Harness 需要的控制 |
|---------|----------|--------------------|
| 长上下文退化 | 忘约束、漏依赖、漂移 | context envelope、分阶段工件、retrieval-first |
| 代码质量不稳定 | 局部修复、接口误配 | graph-first、reservation、repo-aware grounding |
| 测试覆盖不全 | happy path 偏置 | 测试矩阵、hidden regression、mutation-like gate |
| 奖励挟持 | 改测试、改阈值、骗报告 | verifier 分离、tamper detection、trusted attestation |
| 需求理解不足 | 模糊需求直接执行 | clarification loop、acceptance matrix、stage contracts |
| 多轮执行漂移 | 前后结论不一致 | durable state、checkpoint、artifact source of truth |

## 6. 对 parallel-harness 的直接建议

### 6.1 不要把“40%”写成固定真理，改为可校准策略

建议把当前项目的上下文治理改成：

- `ContextBudgetPolicy`
- `OccupancyTelemetry`
- `CompactionStrategy`
- `RetryContextDiversification`

让阈值按阶段、角色、任务复杂度逐步校准。

### 6.2 把 requirement grounding 升级成真正的阶段合同

现在的 grounding 只是：

- 歧义检测
- 基础 acceptance matrix
- 关键词驱动模块推断

下一步应扩展为：

- 产品设计合同
- UI 设计合同
- 技术方案合同
- 实施合同
- 测试合同
- 报告合同

### 6.3 把 verifier 做成独立平面，而不是 gate 的薄包装

建议：

- task author 与 verifier 分离
- verifier 只基于 evidence，不基于 author 自述
- hidden eval、artifact completeness、design review 进入真实执行链

### 6.4 把 attestation 做成可信证据，而不是派生摘要

建议 attestation 至少覆盖：

- 真实 tool trace
- 真实 diff ref
- 真实 stdout / stderr
- 真实 sandbox violation
- 与 gate 结果的双向引用

## 7. 参考资料

以下资料于 `2026-04-02` 核对：

- Lost in the Middle: How Language Models Use Long Contexts  
  https://arxiv.org/abs/2307.03172
- Found in the Middle: Calibrating Positional Attention Bias Improves Long Context Utilization  
  https://arxiv.org/abs/2406.16008
- ContextBench: Can LLMs Handle Long Contexts?  
  https://arxiv.org/abs/2510.05381
- Intelligence Degradation in Long-Context LLMs: Why Overloaded Contexts Result in Broken Promises  
  https://arxiv.org/abs/2601.15300
- CodeMirage: Hallucinations in Code Generated by Large Language Models  
  https://arxiv.org/abs/2408.08333
- CoverUp: Coverage-Guided LLM-Based Test Generation  
  https://arxiv.org/abs/2403.16218
- ClarifyCoder: Clarification-Aware Fine-Tuning for Programmatic Problem Solving  
  https://arxiv.org/abs/2504.16331
- Why we're no longer evaluating on SWE-bench Verified  
  https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/
- Harness engineering: leveraging Codex in an agent-first world  
  https://openai.com/index/harness-engineering/
- A practical guide to building agents  
  https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf
- Anthropic context windows  
  https://docs.anthropic.com/en/docs/build-with-claude/context-windows

## 8. 本文结论

对当前项目最重要的结论不是“模型不够强”，而是：

**只要需求治理、上下文治理、执行治理和验证治理没有形成闭环，再强的模型也会在长流程产品开发里表现出不稳定。**

因此 `parallel-harness` 的下一阶段重点应是把这四层治理做成硬能力，而不是继续把更多能力停留在 README 或未接线模块里。

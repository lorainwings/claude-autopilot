# 语义验证协议

> 由 autopilot-gate SKILL.md 引用，作为 Layer 3 可选补充检查。

结构化 JSON 验证（Hook Layer 2）确保字段存在和格式正确，但无法判断**内容质量**。语义验证由 AI（Layer 3）在阶段切换时执行，弥补结构化验证的盲区。

## 各阶段语义检查清单

### Phase 1 → Phase 2

```
- [ ] 需求描述是否具体可测试（非模糊描述如"提升用户体验"）
- [ ] 功能清单中每个功能是否有明确的验收标准
- [ ] 决策列表中是否存在矛盾的决策
- [ ] 技术约束是否与项目实际技术栈一致
```

### Phase 2 → Phase 3

```
- [ ] OpenSpec proposal 是否覆盖了 Phase 1 中所有功能点
- [ ] 设计方案是否与现有代码架构一致（非侵入性检查）
- [ ] 是否遗漏了必要的数据模型变更
```

### Phase 3 → Phase 4

```
- [ ] 生成的 tasks.md 是否覆盖 proposal 中所有功能点
- [ ] 任务粒度是否合理（单个 task 不超过 3 文件 / 800 行）
- [ ] 任务间依赖关系是否正确（无循环依赖）
- [ ] specs 文件是否完整（至少包含 design 和 tasks）
```

### Phase 4 → Phase 5

```
- [ ] 测试用例是否覆盖 tasks.md 中所有功能点（非仅 happy path）
- [ ] 测试金字塔分布是否合理（unit > integration > e2e）
- [ ] 测试命名是否清晰反映被测功能
- [ ] dry_run 结果是否真实执行（非 mock 的 exit 0）
- [ ] 测试金字塔是否符合 complexity-aware 阈值（v3.1）：
       small: ≥ max(2, config/2) per type, UI 可选
       medium: ≥ config value per type
       large: ≥ max(config, 5) per type
- [ ] 如果 Phase 4 返回 warning + counts < 复杂度阈值，是否已被强制转为 blocked？
```

### Phase 5 → Phase 6

```
- [ ] 实现代码是否与 design spec 一致
- [ ] 是否有未处理的 TODO/FIXME/HACK 注释
- [ ] 所有 tasks.md 任务的 [x] 是否有对应的代码变更（非空 commit）
- [ ] 测试是否通过且无跳过（zero_skip_check）
- [ ] 代码约束合规：artifacts 中所有文件是否通过 code-constraint-check（无禁止文件/模式）
- [ ] 文件大小：新增/修改文件是否超过 800 行限制（config.code_constraints.max_file_lines）
- [ ] 目录范围：所有修改是否在 config.code_constraints.allowed_dirs 范围内
- [ ] 禁止模式：代码中是否包含 config.code_constraints.forbidden_patterns 中的模式
- [ ] 代码约束合规（v3.1）：
       - 禁止文件是否被创建（forbidden_files）
       - 禁止模式是否被引入（forbidden_patterns）
       - 修改是否限制在 allowed_dirs 范围内
- [ ] 文件级锁是否干净（file-locks.json 无残留锁）
- [ ] 如果使用并行执行，合并是否成功且无冲突残留
```

### Phase 6 → Phase 7

```
- [ ] 测试报告是否包含所有测试套件的结果
- [ ] 通过率是否达到 coverage_target（从 config 读取）
- [ ] 报告文件路径是否真实存在且非空
- [ ] 质量扫描结果是否已收集（即使是 timeout）
```

## 集成方式

autopilot-gate SKILL.md 在 8 步检查清单的 Step 6 后，如果当前阶段有语义检查清单，额外执行：

```
Step 6.5 (可选): 读取 semantic-validation.md 中对应阶段的检查清单
                  逐项验证（读取相关文件确认）
                  任何项不通过 → 记录为 warning（不硬阻断，除非严重不一致）
                  输出语义验证摘要到 stderr
```

## Phase 5 并行执行专项语义检查（v3.1）

若启用 `phases.implementation.parallel.enabled: true`：

- [ ] 所有 task-level checkpoint 是否记录了 agent ID 和 owned_files 信息
- [ ] file-locks.json 是否随每个 task 完成而更新（释放锁）
- [ ] 如果任何 task 失败，file-locks 中的 locked_files 是否正确清理
- [ ] 并行度是否根据 merge_failed_count 动态调整
- [ ] 如果 fallback 到 serial，是否正确标记在 parallel_metrics.fallback_reason 中
- [ ] code_quality.constraint_violations 是否为 0（非 0 需审查）

# Gate 可选验证补充

> 本文件从 `autopilot-gate/SKILL.md` 提取，供按需加载。

## 可选 Layer 3 补充：语义验证

> 详见：`autopilot/references/semantic-validation.md`

在 8 步检查清单的 Step 6 之后，可选执行语义验证：

1. 读取 `references/semantic-validation.md` 中对应阶段的检查清单
2. 逐项验证（读取相关文件确认）
3. 不通过项记录为 `warning`（不硬阻断，除非发现严重不一致）
4. 输出语义验证摘要

**注意**: 语义验证为 AI 执行的软检查，不替代 Layer 2 Hook 的确定性验证。

## 可选 Layer 3 补充：Brownfield 验证

> 详见：`autopilot/references/brownfield-validation.md`
> 通过 `config.brownfield_validation.enabled` 控制（默认开启，greenfield 项目 Phase 0 自动关闭）。

当启用时，在特定阶段切换时执行额外的三向一致性检查：

| 切换点 | 检查内容 |
|--------|---------|
| Phase 4 → Phase 5 | 设计-测试对齐 |
| Phase 5 启动 | 测试-实现就绪 |
| Phase 5 → Phase 6 | 实现-设计一致性 |

`strict_mode: true` 时不一致直接阻断；`false` 时仅 warning。

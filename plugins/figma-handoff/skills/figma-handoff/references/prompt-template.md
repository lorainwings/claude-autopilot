# 业务需求文档引用模板

把以下章节复制到业务需求文档(如 `docs/xxx-fe.md`)的"还原质量要求"位置。业务文档只填写项目参数和状态清单,不要重复展开阶段细节;具体执行以 `figma-handoff` skill 为准。

---

## 还原质量要求

必须遵循 `figma-handoff` skill 的 6 阶段工作流: **-1 Preflight → 0 规格采集 → 1 三表映射 → 2 转译 → 3 像素 diff → 4 独立 review**。

权威协议路径: `plugins/figma-handoff/skills/figma-handoff/SKILL.md`。任一阶段阻断 Gate 未通过,禁止进入下一阶段;`get_design_context` 仅作为 reference,不得替代截图、变量、Code Connect 和 MCP assets 真相源。

### 项目专属参数(必填)

- 目标技术栈:`<vue3+vant / vue3+element-plus / react+antd / react+shadcn / react+tailwind>`;示例:`vue3+vant` 加载 `framework-vue.md` + `lib-vant.md`。
- 视口与 DPR:`<375×812 dpr2 / 1280×800 dpr1 / ...>`。
- 设计稿基准 px:`<375 / 750 / 1280>`;同步声明 rem/vw/postcss 等适配方案。
- 资产目录:`<src/assets/imgs/{feature}/>`。
- 视觉 diff 引擎:`<auto / playwright / pixelmatch / odiff>`;默认 `auto`,由 preflight 探测决定。
- 像素 diff 容差白名单:`<时间戳 / 滚动条 / 字体抗锯齿 / ...>`;白名单必须写入 diff report。
- Code Connect / 资产策略:优先采用 `get_code_connect_map` 命中的本地组件;未命中时在 `component-policy.md` 显式映射。复杂装饰按切图规则进入资产目录,禁止用大量 div 硬画。

### 状态/节点清单(项目填)

| Figma node-id | 状态名 | mode(可选) | 描述 |
| --- | --- | --- | --- |
| `XXX:YYY` | default | light | 默认视图 |
| `XXX:YYY` | selected | light | 选中态 |
| `XXX:ZZZ` | filtered | light | 筛选后 |
| `XXX:WWW` | empty | light | 空态 |

### 每个状态必交付

对状态/节点清单中的每一行,必须产出:

- `docs/figma-spec/{state}/metadata.xml`
- `docs/figma-spec/{state}/variables.json`
- `docs/figma-spec/{state}/code-connect.json`
- `docs/figma-spec/{state}/code-connect-suggestions.json`(无 suggestions 时可记录空数组)
- `docs/figma-spec/{state}/code-connect-context.json`(无 Code Connect context 时写明 unavailable 原因)
- `docs/figma-spec/{state}/design-system-rules.md`
- `docs/figma-spec/{state}/reference.md`
- `docs/figma-spec/{state}/golden.png`
- `docs/figma-spec/{state}/assets.json`
- `docs/figma-spec/{state}/assets/`
- `docs/visual-diff/{state}/figma.png`
- `docs/visual-diff/{state}/local.png`
- `docs/visual-diff/{state}/diff.png`
- `docs/visual-diff/{state}/diff-report.json`

`diff-report.json` 至少包含 `state`、`figmaNodeId`、`viewport`、`dpr`、`engine`、`diffPixelRatio`、`threshold`、`keyTokenChecks`、`ignoredMasks`、`passed`。阶段 3 通过条件为总 diff ≤ 0.5%、关键 token 零偏差;人工复核只能用于确认白名单和已知差异,不能替代数值门禁。

### 完工判定

主 agent 不得自评通过。完工后必须派发独立 review subagent,通过 `docs/figma-handoff-review.md` 后才算交付。

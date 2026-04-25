# 阶段 0 — Figma MCP 规格采集协议

> Figma MCP 工具可用性由 Agent 工具层最终确认。shell preflight 只能证明本地能力或显式环境变量,不能替代 `mcp__figma__*` 工具调用。

## 强制调用顺序

每个目标 Figma node 必须按官方最佳实践顺序采集:metadata → variables → Code Connect → design context → screenshot → assets。缺一不可。

| # | 工具 / 动作 | 目的 | 输出归档名 |
| --- | --- | --- | --- |
| 1 | `mcp__figma__get_metadata` | 节点结构树,识别 auto-layout / 嵌套层级 / 子节点数 | `metadata.xml` |
| 2 | `mcp__figma__get_variable_defs` | 变量真值(颜色/字号/间距/圆角) | `variables.json` |
| 3 | Code Connect 采集: `mcp__figma__get_code_connect_map` → `mcp__figma__get_code_connect_suggestions` → `mcp__figma__get_context_for_code_connect` → mapping 写回(需确认) → `mcp__figma__create_design_system_rules` | 已映射代码组件、建议映射、组件属性上下文、可写回映射、项目设计系统规则 | `code-connect.json`、`code-connect-suggestions.json`、`code-connect-context.json`、`design-system-rules.md` |
| 4 | `mcp__figma__get_design_context` | reference(仅参考,不可照抄)与可能出现的本地 asset URL | `reference.md`(头部标注 DO NOT COPY) |
| 5 | `mcp__figma__get_screenshot` | 视觉金本位(像素 diff 基准) | `golden.png` |
| 6 | 资产落地:下载或精确保留 MCP 返回的图片/SVG/asset URL | 建立可复现资产清单,避免临时 URL 失效 | `assets/`、`assets.json` |

## 归档目录

默认 `docs/figma-spec/{state-name}/`,可被项目级 CLAUDE.md 覆盖。一个状态(如默认/选中/禁用/空态)对应一个子目录。

每个状态目录至少包含:

- `metadata.xml`
- `variables.json`
- `code-connect.json`
- `code-connect-context.json`(有 Code Connect suggestions 时)
- `reference.md`
- `golden.png`
- `assets.json`
- `assets/`

## 工具层确认

阶段 0 启动前必须在 Agent 工具层确认以下 Figma MCP 工具可调用。若 shell preflight 只给出 `degraded/manual-tool-check`,不得直接失败,而是执行此工具层检查。

| 能力 | 必要工具 |
| --- | --- |
| 结构与变量 | `mcp__figma__get_metadata`、`mcp__figma__get_variable_defs` |
| Code Connect | `mcp__figma__get_code_connect_map`;若可用,继续检查 `get_code_connect_suggestions`、`get_context_for_code_connect`、mapping 写回、`create_design_system_rules` 相关工具 |
| 视觉与上下文 | `mcp__figma__get_design_context`、`mcp__figma__get_screenshot` |

若 Agent 工具层也缺失 Figma MCP,才中止并提示用户注册官方 Remote MCP、Figma Desktop MCP 或本地 `figma-developer-mcp`。

## 拆分策略

整页节点(> 50 子节点 或 > 6 嵌套层级)**必须**先用 `get_metadata` 列出组件树,然后**逐个组件**调 `get_design_context`,禁止整页一次拉取。理由:

- token 爆炸,LLM 上下文窗口被无效信息占满
- auto-layout / variant 信息会被压平丢失
- 绝对定位 fallback 概率上升

## Code Connect 官方路径

`get_code_connect_map` 是 Figma 官方"组件库无关"机制的入口,但不是完整 Code Connect 流程。阶段 0 必须执行下面的决策树。

```text
get_code_connect_map(nodeId, fileKey, clientFrameworks?, clientLanguages?) 返回非空?
  ├─ Y → 采用映射代码组件;跳过 lib-*.md 猜测;记录到 code-connect.json
  └─ N/partial → 请求 suggestions → get_context_for_code_connect → 必要时生成 design system rules;缺口写入 component-policy.md
```

### clientFrameworks / clientLanguages

调用支持这些参数的 Code Connect 工具时必须按目标栈收窄结果,并遵守具体工具 schema 的参数形态:

- `clientFrameworks`:优先来自用户传入的 `[target-stack]`,其次来自 `preflight.framework`,再从 `package.json` / `figma.config.json` 推断。Remote `get_code_connect_map` 可使用精确 Code Connect label(如 `React`、`SwiftUI`);Code Connect skill/context 工具通常使用 schema 要求的数组或逗号分隔值(如 `["react"]` 或 `react`)。
- `clientLanguages`:优先来自项目实际语言与文件后缀。示例:`typescript`、`javascript`、`swift`、`kotlin`。
- 无法确定时可以省略参数,但必须在 `code-connect.json` 记录 `"frameworkSelection": "unknown"` 或 `"languageSelection": "unknown"`。
- Desktop MCP 若不支持这些筛选参数,必须记录该限制并在映射结果里按目标栈手工过滤。

### suggestions / send mappings / design system rules 降级

| 场景 | 主路径 | 降级策略 |
| --- | --- | --- |
| `get_code_connect_map` 非空 | 直接采用映射组件路径、props 与 import | 禁止再用组件库 adapter 猜测同一组件 |
| map 部分命中 | 命中项走 Code Connect;未命中项调用 `get_code_connect_suggestions` | suggestions 不可用时,在 `component-policy.md` 明确列出 Figma 组件 → 本地组件路径 |
| suggestions 返回候选 | 调用 `get_context_for_code_connect` 获取组件属性定义,再对照项目源码确认 import、props、variant 语义 | context 工具不可用时,只保留候选并标记 `needs-manual-prop-map` |
| mappings 需要写回 Figma | 在用户或项目规则允许后,使用工具层提供的 `send_code_connect_mappings` / `add_code_connect_map` 能力写回 | 无权限或工具不可用时,只归档建议,不得伪造已写回状态 |
| 需要项目级规则 | 调用 `create_design_system_rules(clientLanguages, clientFrameworks)` 生成基础模板,再结合代码库分析补全 | 工具不可用时,从现有组件、tokens、adapter 规则手写 `design-system-rules.md` |

**配置入口**:已有确定映射时,可用 Code Connect 的 add/send mapping 能力补全;批量写回前必须确认不会覆盖他人映射。

## Design Context 采集

`get_design_context` 的输出是 reference,不是 final code。必须:

- 在 `reference.md` 头部写明 `DO NOT COPY: translate through translation-core.md and adapters`
- 将 React+Tailwind 形态转成 IR,不得照抄 JSX 或 Tailwind utility
- 保留所有 MCP 返回的图片、SVG、CSS `url(...)`、`localhost` / `127.0.0.1` / asset URL 线索,交给资产落地步骤处理

## 截图参数固化

`get_screenshot` 的输出用于像素 diff 基准,必须:

- 以**单一 frame 节点**为对象,不要带画布外元素
- 尺寸与本地实际渲染区域一致(移动端 375 宽 / PC 1280 或项目固定值)
- 与后续本地截图使用同一 viewport、DPR、主题 mode 与语言环境

## 资产落地协议

MCP 返回的图片/SVG/asset URL 是设计事实,不是可选素材。阶段 0 必须扫描 `reference.md`、Code Connect 片段和 design context 输出,把所有资产纳入清单。

| 来源形态 | 必须动作 |
| --- | --- |
| `http://localhost:*` / `http://127.0.0.1:*` / MCP asset URL | 立即下载到 `assets/`,或在同一会话内直接使用其真实内容生成本地资产;不得留下临时 URL |
| inline `<svg>` 或 SVG 文本 | 原样保存为 `.svg`,或在组件中精确内联;不得凭记忆重画 |
| `data:image/*` | 解码写入 `assets/`,记录原始 MIME 与 checksum |
| markdown image / CSS `url(...)` / `<img src>` | 下载并把实现引用改为项目相对路径 |

`assets.json` 至少记录:

```json
[
  {
    "figmaNodeId": "12:34",
    "layerName": "Icon / Search",
    "kind": "svg",
    "source": "http://localhost:3845/assets/...",
    "localPath": "assets/icon-search.svg",
    "checksum": "sha256:..."
  }
]
```

严禁用 emoji、占位图、随机素材、临时 icon 包或通用 icon 包替代 MCP 返回的 asset。asset URL 过期时必须重新调用 MCP 刷新并下载,不能脑补。

## Variable Modes 限制

Figma MCP 当前**不可靠地**返回 variable modes(亮/暗、多语言、品牌主题切换)。处理策略:

1. 在 Figma 切换 mode 后**重新调用** `get_screenshot`,各自落到 `docs/figma-spec/{state}--{mode}/golden.png`
2. `get_variable_defs` 拿到的 token 名以 default mode 为准,其他 mode 的真值需人工填进 `tokens.md` 的"多模式"列
3. 阶段 3 像素 diff 对每个 mode 独立校验

跟踪进度:[Figma forum issue](https://forum.figma.com/suggest-a-feature-11/figma-mcp-reading-variable-modes-42031)。

## 反模式自检

以下任一行为出现 → 阶段 0 立即 Fail,回炉重来:

- 直接对页面级 node 调用 `get_design_context`,跳过 metadata
- 跳过 variables 或 Code Connect,直接看截图写 UI
- 关闭 screenshot 节省 token
- 六件套有缺失就进入阶段 1
- 把 reference.md 作为权威,不带 "DO NOT COPY" 警示
- Code Connect 命中却仍走 lib-*.md 猜测(浪费 + 漂移风险)
- suggestions 有候选却不归档,导致人工映射不可追溯
- MCP 返回了 asset URL / inline SVG,但实现里改用 emoji、占位图或临时 icon 包
- 多 mode 设计稿只取 default,跳过暗色/多语言 mode 的 golden.png

## 官方参考

- [Figma Dev Mode MCP Server guide](https://help.figma.com/hc/en-us/articles/32132100833559-Guide-to-the-Dev-Mode-MCP-Server)
- [Figma MCP tools and prompts](https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/)
- [Figma MCP Code Connect integration](https://developers.figma.com/docs/figma-mcp-server/code-connect-integration/)
- [Figma Code Connect skill](https://developers.figma.com/docs/figma-mcp-server/skill-figma-code-connect/)
- [Figma create design system rules skill](https://developers.figma.com/docs/figma-mcp-server/skill-figma-create-design-system-rules/)
- [Figma MCP image loading guidance](https://developers.figma.com/docs/figma-mcp-server/images-stopped-loading/)

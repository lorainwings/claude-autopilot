---
name: figma-codegen
description: Translates Figma designs into production-ready application code with 1:1 visual fidelity. Use when implementing UI code from Figma files, when user mentions "implement design", "generate code", "implement component", "figma to code", "figma 转代码", "figma 还原", "实现设计稿", provides Figma URLs, or asks to build components matching Figma specs. For Figma canvas writes via `use_figma`, use `figma-use`. For full-screen design generation in Figma, use `figma-generate-design`.
argument-hint: "[figma-url]  — e.g. https://figma.com/design/XXX?node-id=1-2"
user-invocable: true
---

# Figma Codegen

将 Figma 设计稿翻译为生产级前端代码,追求像素级视觉一致(1:1 visual parity)。

> 本 SKILL 改编自 OpenAI 官方 [figma-implement-design](https://github.com/openai/skills/tree/main/skills/.curated/figma-implement-design),针对 Claude Code 生态适配。

---

## 概览

本 SKILL 提供把 Figma 设计稿翻译为生产级代码的结构化工作流,确保:

- 与 Figma MCP server 的稳定集成
- 设计 token 的正确使用
- 与设计稿 1:1 视觉一致

---

## SKILL 边界

| 用户意图 | 切换到 |
| --- | --- |
| 在用户仓库内产出代码(本 SKILL 主战场) | **figma-codegen**(本文件) |
| 在 Figma 内创建/编辑/删除节点 | `figma-use` |
| 从代码或描述生成完整 Figma 页面 | `figma-generate-design` |
| 仅生成 Code Connect 映射 | `figma-code-connect-components` |
| 编写可复用的 Agent 规则(`CLAUDE.md`/`AGENTS.md`) | `figma-create-design-system-rules` |

---

## 前置条件

- Figma MCP server 已连接且可访问(三种模式之一)
  - **Remote MCP**:`claude mcp add figma --transport http https://mcp.figma.com/mcp`
  - **Figma Desktop MCP**:Figma Desktop 已开启 MCP 开关
  - **本地 figma-developer-mcp**:`claude mcp add figma -- npx -y figma-developer-mcp --figma-api-key=$FIGMA_TOKEN`
- 用户提供 Figma URL,格式:`https://figma.com/design/:fileKey/:fileName?node-id=1-2`
  - `:fileKey` 是文件 key
  - `1-2` 是节点 ID(具体组件或 frame)
- **或** 当使用 `figma-desktop` MCP 时:用户可直接在 Figma Desktop 选中节点(无需 URL)
- 项目最好已有设计系统或组件库(优先复用)

---

## 工作流(严格按顺序,禁止跳步)

```
Step 1: 获取 Node ID  →  Step 2: 拉取设计上下文  →  Step 3: 截取视觉基准
                                ↓
                        Step 4: 下载所需资产
                                ↓
                        Step 5: 翻译为项目规范
                                ↓
                        Step 6: 实现 1:1 视觉一致
                                ↓
                        Step 7: 对照 Figma 验证
```

### Step 1 — 获取 Node ID

#### 选项 A:从 Figma URL 解析

当用户提供 Figma URL 时,从中提取 file key 与 node ID,作为 MCP 工具调用参数。

**URL 格式**:`https://figma.com/design/:fileKey/:fileName?node-id=1-2`

**提取**:

- **File key**:`:fileKey`(`/design/` 之后的段)
- **Node ID**:`1-2`(`node-id` query 参数的值)

**注意**:使用本地 desktop MCP(`figma-desktop`)时,`fileKey` 不作为参数传递。Server 会自动使用当前打开的文件,只需传 `nodeId`。

**示例**:

- URL:`https://figma.com/design/kL9xQn2VwM8pYrTb4ZcHjF/DesignSystem?node-id=42-15`
- File key:`kL9xQn2VwM8pYrTb4ZcHjF`
- Node ID:`42-15`

#### 选项 B:使用 Figma Desktop 当前选区(仅限 figma-desktop MCP)

当使用 `figma-desktop` MCP 且用户**未提供** URL 时,工具会自动使用 Figma Desktop 当前选中的节点。

**注意**:基于选区的提示词只在 `figma-desktop` MCP 下生效。Remote server 必须传 frame/layer 链接才能提取上下文。用户必须打开 Figma Desktop 并已选中节点。

---

### Step 2 — 拉取设计上下文

调用 `get_design_context`,传入提取的 file key 与 node ID。

```
get_design_context(fileKey=":fileKey", nodeId="1-2")
```

返回的结构化数据包含:

- 布局属性(Auto Layout、constraints、sizing)
- 排版规范(typography)
- 颜色值与设计 token
- 组件结构与 variants
- 间距与 padding 值

**当响应过大或被截断时**:

1. 调用 `get_metadata(fileKey=":fileKey", nodeId="1-2")` 获取节点高层级地图
2. 从 metadata 中识别需要的具体子节点
3. 用 `get_design_context(fileKey=":fileKey", nodeId=":childNodeId")` 单独拉取子节点

---

### Step 3 — 截取视觉基准

用同样的 file key 与 node ID 调用 `get_screenshot` 获取视觉参考。

```
get_screenshot(fileKey=":fileKey", nodeId="1-2")
```

该截图作为视觉验证的**真值基准**。整个实现过程中保持可访问。

---

### Step 4 — 下载所需资产

下载 Figma MCP server 返回的所有资产(图片、图标、SVG)。

**重要**:严格遵守资产规则:

- Figma MCP server 返回 `localhost` 来源的图片或 SVG → **直接使用该来源**
- **禁止**引入或新增 icon 包 — 所有资产必须来自 Figma payload
- **禁止**当 `localhost` 来源存在时使用占位图或重新创建
- 资产由 Figma MCP server 内置 assets endpoint 提供

---

### Step 5 — 翻译为项目规范

把 Figma 输出翻译为本项目的框架、样式、规范。

**核心原则**:

- 把 Figma MCP 输出(通常是 React + Tailwind)视为**设计与行为的表达**,**不是**最终代码风格
- 用项目偏好的工具类或设计系统 token **替换** Tailwind utility classes
- **复用**已有组件(buttons、inputs、typography、icon wrappers),不要重复造轮子
- 一致使用项目的颜色系统、排版尺度、间距 token
- 尊重已有的路由、状态管理、数据获取模式

---

### Step 6 — 实现 1:1 视觉一致

追求与 Figma 设计的像素级视觉一致。

**指南**:

- **优先 Figma 保真度**,精确匹配设计
- **避免硬编码值** — 使用 Figma 提供的设计 token
- 当设计系统 token 与 Figma 规范冲突时,**优先项目设计系统 token**,但允许在 spacing/sizing 上做最小调整以保留视觉一致
- 遵循 WCAG 无障碍要求
- 必要时补充组件文档

---

### Step 7 — 对照 Figma 验证

完工标记之前,对照 Figma 截图验证最终 UI。

**验证清单**:

- [ ] 布局匹配(spacing、alignment、sizing)
- [ ] 排版匹配(font、size、weight、line height)
- [ ] 颜色精确匹配
- [ ] 交互态正确(hover、active、disabled)
- [ ] 响应式行为遵循 Figma constraints
- [ ] 资产正确渲染
- [ ] 无障碍标准达标

---

## 实现规则

### 组件组织

- UI 组件放在项目指定的设计系统目录
- 遵循项目的组件命名约定
- 避免 inline styles,除非确实是动态值

### 设计系统集成

- **总是优先**复用项目已有设计系统组件
- 把 Figma 设计 token 映射到项目设计 token
- 已有匹配组件时,**扩展**它而非新建
- 新增到设计系统的组件必须有文档

### 代码质量

- 避免硬编码 — 抽到常量或设计 token
- 组件保持 composable / reusable
- TypeScript 项目必须有 props 类型定义
- 对外暴露的组件加 JSDoc

---

## 示例

### 示例 1:实现 Button 组件

用户:"实现这个 Figma button:`https://figma.com/design/kL9xQn2VwM8pYrTb4ZcHjF/DesignSystem?node-id=42-15`"

**动作**:

1. 解析 URL → fileKey=`kL9xQn2VwM8pYrTb4ZcHjF`,nodeId=`42-15`
2. `get_design_context(fileKey="kL9xQn2VwM8pYrTb4ZcHjF", nodeId="42-15")`
3. `get_screenshot(fileKey="kL9xQn2VwM8pYrTb4ZcHjF", nodeId="42-15")` 拿视觉基准
4. 下载 button 中所有 icons(从 assets endpoint)
5. 检查项目是否有 button 组件
6. 有 → 扩展加新 variant;无 → 按项目规范新建组件
7. Figma 颜色映射到项目 token(如 `primary-500`、`primary-hover`)
8. 对照截图验证 padding、border radius、typography

**结果**:button 组件与 Figma 设计一致,且融入项目设计系统。

### 示例 2:构建 Dashboard 布局

用户:"实现这个 dashboard:`https://figma.com/design/pR8mNv5KqXzGwY2JtCfL4D/Dashboard?node-id=10-5`"

**动作**:

1. 解析 URL → fileKey=`pR8mNv5KqXzGwY2JtCfL4D`,nodeId=`10-5`
2. `get_metadata(fileKey="pR8mNv5KqXzGwY2JtCfL4D", nodeId="10-5")` 看页面结构
3. 从 metadata 识别主要 sections(header、sidebar、content area、cards)及其子节点 ID
4. 对每个主要 section 调 `get_design_context(fileKey="pR8mNv5KqXzGwY2JtCfL4D", nodeId=":childNodeId")`
5. `get_screenshot(fileKey="pR8mNv5KqXzGwY2JtCfL4D", nodeId="10-5")` 拿全页面截图
6. 下载所有资产(logos、icons、charts)
7. 用项目布局原语构建外层结构
8. 各 section 用已有组件实现
9. 对照 Figma constraints 验证响应式行为

**结果**:与 Figma 设计一致的 dashboard,带响应式布局。

---

## 最佳实践

### 总是从 context 开始

不要凭假设实现。**总是**先 `get_design_context` + `get_screenshot`。

### 增量验证

实现过程中**频繁验证**,而非只在结尾。提早发现问题。

### 文档化偏离

如果必须偏离 Figma 设计(如无障碍或技术约束),在代码注释中说明原因。

### 复用 > 重建

新建组件之前**总是**检查已有组件。代码库一致性比 Figma 严格还原更重要。

### 设计系统优先

存疑时,优先项目设计系统模式,而非字面翻译 Figma。

---

## 常见问题与解决方案

### 问题:Figma 输出被截断

**原因**:设计过于复杂或嵌套层级过多,单次响应放不下。
**解决**:用 `get_metadata` 获取节点结构,然后用 `get_design_context` 单独拉取具体子节点。

### 问题:实现后与设计不一致

**原因**:实现代码与原 Figma 设计有视觉偏差。
**解决**:与 Step 3 截图并排对比。检查 spacing、colors、typography 在 design context 数据中的值。

### 问题:资产加载失败

**原因**:Figma MCP server 的 assets endpoint 不可达,或 URL 被修改。
**解决**:验证 Figma MCP server 的 assets endpoint 可达。Server 在 `localhost` URL 提供资产。**直接使用,不要修改**。

### 问题:设计 token 值与 Figma 不同

**原因**:项目设计系统 token 值与 Figma 设计稿声明值不同。
**解决**:项目 token 与 Figma 值不同时,优先项目 token 以保持一致性,但调整 spacing/sizing 以保留视觉保真度。

---

## 理解 Design Implementation

Figma 实现工作流为"设计 → 代码"建立可靠流程:

- **对设计师**:实现会与设计像素级一致
- **对开发者**:消除猜测,减少反复修改
- **对团队**:实现质量稳定,设计系统完整性得到维护

遵循此工作流,每个 Figma 设计都会以同等的细致度被实现。

---

## 附加资源

- [Figma MCP Server Documentation](https://developers.figma.com/docs/figma-mcp-server/)
- [Figma MCP Server Tools and Prompts](https://developers.figma.com/docs/figma-mcp-server/tools-and-prompts/)
- [Figma Variables and Design Tokens](https://help.figma.com/hc/en-us/articles/15339657135383-Guide-to-variables-in-Figma)
- 上游来源:[OpenAI figma-implement-design SKILL.md](https://github.com/openai/skills/blob/main/skills/.curated/figma-implement-design/SKILL.md)

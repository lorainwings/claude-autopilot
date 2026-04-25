---
name: figma-handoff
description: Use when implementing UI from a Figma URL/node and pixel-faithful fidelity is required, or when the user complains that Figma MCP output looks similar but wrong (low fidelity, drifted colors/fonts/spacing, missing decorations, emoji-replaced icons, broken absolute positioning). Enforces a 6-stage handoff pipeline (preflight → spec acquisition → token/node/component mapping → translation rules → pixel-diff hard gate → independent review) with framework-agnostic core + per-framework / per-component-library adapters and capability-aware preflight. Trigger phrases include 还原 figma / figma 转代码 / figma to code / 高保真还原 / figma mcp 还原度低 / pixel perfect / figma handoff. Skip for greenfield prototyping (use frontend-design or ui-ux-pro-max) and pure interaction-only changes with no visual diff.
argument-hint: "[figma-url] [target-stack]  — e.g. figma.com/design/XXX?node-id=1-2 vue3+element-plus / react+antd / react+tailwind"
user-invocable: true
---

# figma-handoff Skill

设计稿 → 前端代码的高保真交付协议。本 SKILL **只声明工作流与原则**,具体命令/代码/技术栈细节全部位于 `references/`,按需加载。

> **前置共识**:`get_design_context` 返回的是 React+Tailwind reference,不是权威。权威信号 = `get_screenshot`(视觉) + `get_variable_defs`(token) + Code Connect(已映射组件) + MCP assets(图片/SVG 真值)。

---

## 工作流总览(6 阶段,任一阶段未通过禁止进入下一阶段)

| 阶段 | 目的 | 协议文档 | 阻断 Gate |
| --- | --- | --- | --- |
| **-1 Preflight** | 探测依赖 / 框架 / 组件库,缺失能力时给出 fix 命令 | `references/preflight.md` | blocking 项非空即 abort |
| **0 规格采集** | 用 Figma MCP 拉齐 6 件套并归档 | `references/figma-mcp-protocol.md` | 6 件套缺一即 Fail |
| **1 三表映射** | 把 Figma 真相翻译为项目可消费的映射 | (本文件 §2) | tokens 覆盖率 < 100% Fail |
| **2 转译** | Core 铁律 + framework adapter + lib adapter 三层接力 | `references/translation-core.md` + `adapters/framework-*.md` + `adapters/lib-*.md` | 每子步独立 diff |
| **3 像素 diff** | 客观证伪还原度(引擎探测优先) | `references/pixel-diff-protocol.md` | diff > 阈值 / 关键 token 偏差 → Fail |
| **4 独立 review** | 不许主 agent 自评通过 | (本文件 §5) | 节点溯源覆盖率 < 100% Fail |

---

## 0. 阶段 -1 — Preflight 能力探测

详见 `references/preflight.md`。要点:

- **必须最先执行**:`bash references/scripts/preflight.sh "$PROJECT_ROOT" "$TARGET_STACK"`
- **三段式输出**:`ready` / `degraded` / `blocking`,落 `.cache/figma-handoff/preflight.json`
- **blocking 处理**:输出可复制的 fix 命令(如 `claude mcp add figma ...`),**禁止**忽略继续
- **degraded 处理**:打印一行 fallback 提示后继续(如 chrome-devtools MCP 缺失 → Playwright CLI)
- **副产物**:确定 `framework`(vue/react/...)与 `componentLibrary`(antd/mui/.../tailwind)供后续阶段加载对应 adapter

---

## 1. 阶段 0 — 规格采集

详细操作清单见 `references/figma-mcp-protocol.md`。要点:

- **强制顺序**:metadata → variables → Code Connect → design-context → screenshot → assets
- **强制粒度**:整页节点必须先用 metadata 拆分到组件级再下钻 `get_design_context`
- **强制归档**:每个状态/节点产出 6 件套,落到项目约定的 spec 目录(默认 `docs/figma-spec/{state}/`)
- **Code Connect 官方路径**:命中则跳过组件库 adapter 猜测;未命中时归档 suggestions/context 并写入 component-policy
- **Assets 必落地**:MCP 返回的图片/SVG/asset URL 必须进入 `assets.json` 与项目资产目录,不得用占位图或通用 icon 包替代
- **Variable modes**:Figma MCP 不可靠返回 modes,亮/暗/多语言需各自采集 golden.png

---

## 2. 阶段 1 — 三张映射表

> 写完才能动键盘。不要用代码模板,**用项目真实 token / 真实文件路径填写**。

### 2.1 Token 映射表(`tokens.md`)

把 `get_variable_defs` 拿到的每个 Figma 变量,显式映射到目标项目的 design token(具体入口由对应 `lib-*.md` 决定)。

铁律:

- 覆盖率 **100%**。代码出现裸 hex 或 px 字面量(除 1px 边框) → 阶段 3 直接 Fail
- 查不到对应项目 token → 停工新增,**禁止脑补就近色**
- token 命名映射后必须双向可查(Figma name ↔ project name)

### 2.2 节点 → 文件溯源表(`node-map.md`)

每个 Figma node-id 对应到一个具体文件(SFC / TSX / 切图)。每个产出文件**强制带溯源注释**(注释语法见对应 `framework-*.md` § Traceback)。

### 2.3 组件策略表(`component-policy.md`)

声明三类:**必复用**(Code Connect 映射 / 项目已装组件库)/ **必自定义**(业务专属)/ **必切图**(装饰、复杂插画)。

切图判定为硬规则(任一命中即切图):

- 子节点数 > 30
- 嵌套层级 > 4
- 含渐变 / 混合模式 / 阴影嵌套 ≥ 2
- 含位图 fill

---

## 3. 阶段 2 — 转译(Core + 双层 adapter)

> 反模式:把 `get_design_context` 的 React+Tailwind reference 当模板照抄。

### 3.1 Core 铁律(框架/组件库无关)

详见 `references/translation-core.md` 的 7 条铁律(R1-R7)。摘要:

- R1 Tailwind utility 必须翻译为目标栈表达,除非已显式接入 Tailwind/UnoCSS
- R2 `position:absolute` + 坐标值必须改为 flex/grid + gap;仅角标/浮层例外
- R3-R5 裸 hex / px / 字重必须替换为映射表 token
- R6 emoji / Unicode / 占位图 / 通用 icon 包替代 MCP assets — **绝对禁止**
- R7 优先 Code Connect 映射 → 项目组件库 → fallback 自建

### 3.2 双层 Adapter 加载决策树

| 维度 | 来源 | 加载文件 |
| --- | --- | --- |
| **Framework** | `preflight.json#framework` 或 argument | `adapters/framework-{vue,react}.md` |
| **Component Library** | 决策树(下方) | `adapters/lib-*.md` |

**组件库决策树**(写进 SKILL.md 主流程,严格按顺序):

```
① Code Connect 命中?         → 用映射,跳过 lib-*.md
② preflight 探测到已装库?    → 加载对应 lib-{antd|mui|chakra|mantine|shadcn|naive|vant|element-plus|arco|tdesign|primevue}.md
③ 用户 argument 显式声明?    → 加载对应 lib-*.md
④ fallback                  → adapters/lib-tailwind.md(默认 baseline)
```

**双层加载示例**:

| 项目栈 | 加载文件清单 |
| --- | --- |
| Vue3 + Element Plus | `translation-core.md` + `framework-vue.md` + `lib-element-plus.md` |
| Vue3 + Vant | `translation-core.md` + `framework-vue.md` + `lib-vant.md` |
| React + Ant Design | `translation-core.md` + `framework-react.md` + `lib-antd.md` |
| React + shadcn/ui | `translation-core.md` + `framework-react.md` + `lib-shadcn.md` |
| React + 纯 Tailwind | `translation-core.md` + `framework-react.md` + `lib-tailwind.md` |

**铁律**:不允许 framework adapter 与 lib adapter 跨界(如 React 项目不得加载 `framework-vue.md`)。

### 3.3 三步迭代节奏(每步独立 diff)

| 子步 | 内容 | 进入下一步条件 |
| --- | --- | --- |
| 2a 静态骨架 | 仅布局 + 切图 + 占位文本,无数据无交互 | pixel diff ≤ 1% |
| 2b 数据态 | 接入 mock,渲染真实列表/状态 | pixel diff ≤ 0.5% |
| 2c 交互态 | 弹窗/路由/缓存等业务逻辑 | 交互矩阵 100% |

**强制**:2a 没过 diff,不允许写任何 service / composable / store / hook 代码。

---

## 4. 阶段 3 — 像素 diff 硬门禁

详见 `references/pixel-diff-protocol.md`。要点:

- **引擎探测优先**:Playwright `toHaveScreenshot` → pixelmatch+pngjs → odiff(高敏可选)
- 每个状态产出三图(Figma 金本位 / 本地截图 / diff)
- 本地截图参数项目级固化(viewport / DPR / 等待策略 / 关闭动画)
- 阻断指标:**总 diff ≤ 0.5%** + **关键 token 零偏差**(品牌色 / 字号 / 圆角 / 图标位置)
- 多 mode(亮/暗/多语言)各自独立通过才放行 G4

---

## 5. 阶段 4 — 独立 Review

主 agent **不得自评通过**。完工后必须并行派发独立 review subagent,产出报告(默认 `docs/figma-handoff-review.md`),覆盖:

1. preflight 三段式快照(ready / degraded / blocking 是否清零)
2. 三表完整性
3. 转译铁律违规清单(应为 0)
4. 加载的 framework adapter 与 lib adapter 是否与实际项目栈匹配
5. N 个状态 × N 个 mode 的 pixel diff 数值表
6. 节点溯源覆盖率(每个产出文件含 figma node-id 注释)
7. MCP assets 清单完整性与本地化状态
8. 组件库默认值 override 清单
9. 残留 Low 级 TODO

---

## 反模式速查(命中即返工)

| 反模式 | 为什么错 | 对应阶段 |
| --- | --- | --- |
| 跳过 preflight 直接拉数据 | 跑到中段才发现缺 MCP / 引擎 | -1 |
| 跳过 metadata 直接 get_design_context 整页 | token 爆炸 + auto-layout 丢失 | 0 |
| Code Connect 命中却仍走 lib-*.md 猜测 | 浪费 + 漂移风险 | 0/2 |
| 把 Tailwind class 直接搬进目标栈模板 | 异构栈语义错位 | 2 |
| React 项目加载 `framework-vue.md` 或反之 | adapter 选错,语法污染 | 2 |
| emoji / Unicode 替代图标 | 跨平台渲染不一致,品牌失真 | 2 |
| MCP 返回 asset 却改用占位图 / 通用 icon 包 | 破坏视觉真值,像素 diff 不稳定 | 0/2 |
| `position:absolute` 复刻 Figma 坐标 | 屏幕宽度变化即崩 | 2 |
| 裸 hex / px 字面量 | 主题不可换,token 脱节 | 1/2 |
| 肉眼对比代替 pixelmatch / Playwright | 主观、不可证伪 | 3 |
| 装饰复杂插画硬编码 div | 必失真,且性能差 | 1/2 |
| 不写 figma node-id 注释 | 无法追溯,review 失效 | 2/4 |
| 主 agent 自评通过 | 既当运动员又当裁判 | 4 |

---

## 与其他 skill 的边界

- 与 `frontend-design` / `ui-ux-pro-max`:它们做"从零创作有创意的 UI",本 skill 做"按设计稿严格还原",**目标相反**
- 与 `chrome-devtools-mcp:chrome-devtools`:本 skill 在阶段 3 优先复用其截图能力,缺失时降级 Playwright CLI
- 与 `frontend-design` 的"反 AI slop"原则:本 skill **继承**该原则(禁通用紫渐变 / Inter 默认等),但在还原场景下严格遵循 Figma 真实视觉

---

## 配套提示词模板

业务需求文档可引用 `references/prompt-template.md`,在"还原质量要求"章节直接套用本 skill 的 6 阶段工作流并显式声明目标栈(决定加载哪组 adapter)。

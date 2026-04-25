# 阶段 2 — 转译铁律 Core(框架/组件库无关)

> 这份文档定义 Figma MCP `get_design_context` 输出(React+Tailwind reference)→ 中间表达(IR)的语义铁律。**不是代码模板**,是判定标准。具体落地由 `adapters/framework-*.md` 与 `adapters/lib-*.md` 接力。

## 1. Reference 的本质

Figma MCP 默认返回 React+Tailwind,即便项目栈是 Vue/Angular/Svelte/SwiftUI。这是 **reference 而非 final code**。本协议禁止"照抄 JSX",要求所有产出必须经过下表 7 条铁律的转译,然后由对应 adapter 落地为目标栈语法。

## 2. 七条转译铁律(Core IR)

| 类别 | Reference 形态 | 转译标准(框架无关) |
| --- | --- | --- |
| **R1 类名体系** | Tailwind utility class | 翻译为目标栈表达(Sass/BEM、CSS Module、CSS-in-JS、UnoCSS shortcut)。**禁止 utility class 残留**,除非项目已显式接入 Tailwind/UnoCSS(此时由 `lib-tailwind.md` 接管) |
| **R2 布局结构** | `position:absolute` + 数值坐标 | **必须**改为 flex/grid + gap;仅角标、浮层、tooltip 例外 |
| **R3 颜色** | 裸 hex(`#FF6A00`) | 查 `tokens.md` 替换为变量。查不到 → **停工回阶段 1 补**,严禁就近色脑补 |
| **R4 尺寸** | px 字面量 | 走项目尺寸适配方案(rem 转换、设计稿基准);组件库内部 px 通过 CSS Variable / theme token 覆盖,具体入口见 `lib-*.md` |
| **R5 字体字重** | `font-medium`/`font-semibold` | 使用项目字重 token(数字 400/500/600/700),禁字面量 |
| **R6 资产 / 图标** | emoji / Unicode 符号 / `<svg>` 内联 / 图片或 MCP asset URL | **绝对禁止 emoji 与占位图**;MCP 返回图片/SVG/asset URL 必须进入资产清单并落地到项目资产目录;禁止新增通用 icon 包替代;禁止凭记忆重画官方返回的 asset |
| **R7 组件复用** | 自造 `<button>` / `<input>` | 优先复用 Code Connect 映射;次选项目已装组件库;最末 fallback Tailwind/CSS。具体决策树见 SKILL.md §3.2 |

## 3. 资产硬规则

MCP 返回的图片、SVG、图标、`data:image/*`、CSS `url(...)`、`localhost` / `127.0.0.1` / asset URL 都是设计事实,必须在阶段 0 落地并进入资产清单。阶段 2 不允许绕过资产清单直接脑补视觉元素。

| 规则 | 判定 |
| --- | --- |
| 资产清单必填 | 每个 MCP 返回 asset 必须记录到 `docs/figma-spec/{state}/assets.json`,包含 Figma node/layer、来源、localPath、kind、checksum |
| 本地化必做 | 临时 URL 必须下载到 `assets/`,或将官方返回的 SVG 精确内联;实现不得依赖会过期的 localhost URL |
| 禁止替代 | 不得新增 lucide/heroicons/phosphor 等通用 icon 包来替代 Figma 返回的图标;不得用 emoji、Unicode 符号、占位图、随机素材替代 |
| 禁止重画 | 已由 MCP 返回的 SVG/PNG 必须原样使用或等比例裁切;禁止凭记忆重画、简化路径、换成相似图标 |
| 缺失即回炉 | asset URL 过期、下载失败、清单缺项时,停止阶段 2,回阶段 0 重新调用 MCP 获取资产 |
| 例外边界 | 只有 Code Connect 映射明确要求使用项目既有 Icon 组件,且 MCP 没有返回该图标资产时,才可复用既有组件;仍禁止新增依赖包 |

## 4. Traceback 注释(语义层)

每个产出文件**头部强制溯源**,语义字段:

- `figma fileKey`
- `figma nodeId`
- 对应 `golden.png` 相对路径

**注释语法由 framework adapter 决定**,不在本文件规定。

| 框架 | 注释语法位置 |
| --- | --- |
| Vue3 SFC | `adapters/framework-vue.md` § Traceback |
| React TSX | `adapters/framework-react.md` § Traceback |
| Svelte / Solid / Angular | 各自 adapter(待补) |

## 5. 三步迭代节奏(框架无关)

| 子步 | 内容 | 进入下一步条件 |
| --- | --- | --- |
| 2a 静态骨架 | 仅布局 + 切图 + 占位文本,无数据无交互 | pixel diff ≤ 1% |
| 2b 数据态 | 接入 mock 数据,渲染真实列表/状态 | pixel diff ≤ 0.5% |
| 2c 交互态 | 弹窗/路由/缓存/请求等业务逻辑 | 交互矩阵 100% |

**强制**:2a 没过 diff,不允许写任何 service / composable / store / hook / signal 代码。

## 6. 反模式速查(语义层)

| 反模式 | 为什么错 |
| --- | --- |
| 把 Tailwind class 当 BEM 类名照搬 | 项目无 Tailwind 编译,样式不生效 |
| Reference 里 `className="absolute left-[24px] top-[48px]"` 直接复刻 | 屏幕宽度变化即崩 |
| 直接 `style="color: #FF6A00"` | 主题切换、品牌升级时全文搜索改不完 |
| 把 SVG 图标写成 emoji 占位 | 跨平台/字体渲染不一致 |
| MCP 返回了 SVG/PNG,实现却安装通用 icon 包替代 | 破坏官方 asset 真值,也增加无关依赖 |
| localhost asset URL 过期后凭印象重画 | 资产不可追溯,像素 diff 无法稳定通过 |
| 把 Figma 阴影 token 当 hex 写死 | 失去主题层 |
| Vue 项目里写 `className=` / React 项目里写 `class=` | 混淆框架语法,转译未做 |
| 在 React adapter 文档里出现 `:deep()` / `<style scoped>` | Vue 概念污染,加载错文件 |

## 7. 与 adapter 的边界

本文件定义**做什么、不能做什么**;adapter 文件定义**怎么落地为目标栈语法**。两者职责不重叠:

- 出现"`<template>`""`SFC`""kebab-case attribute"等 Vue 术语 → 写到 `framework-vue.md`
- 出现"`JSX`""`children`""`useEffect`"等 React 术语 → 写到 `framework-react.md`
- 出现"`ConfigProvider`""`createTheme`""`extendTheme`"等具体库 API → 写到 `lib-*.md`

本文件**只能**出现框架/组件库无关的语义术语。

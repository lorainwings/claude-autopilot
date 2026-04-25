# Adapter: React Framework

> 把 `translation-core.md` 的 7 条铁律落地为 React TSX 语法。本文件**不重复 core 内容**,只补差异点。

## 1. Traceback 注释(R7 配套)

放在文件**第一行**,使用 JSX 注释或 JSDoc:

```tsx
/**
 * @figma fileKey=XXX nodeId=1:23
 * @golden docs/figma-spec/default/golden.png
 */
import { ... } from "react"
```

或在 JSX 根节点上方:

```tsx
{/* @figma fileKey=XXX nodeId=1:23 golden=docs/figma-spec/default/golden.png */}
<div>...</div>
```

审查脚本通过 `grep -r "@figma fileKey="` 统计节点溯源覆盖率,要求 100%。

## 2. Props 命名

| 场景 | 规则 |
| --- | --- |
| 所有 props | camelCase(`isActive`、`onUserClick`) |
| 事件回调 | `onXxx` 前缀 + camelCase |
| Boolean prop | 不加 `is`/`has`/`should` 前缀也可,但**必须语义清晰** |

**禁止**:`is-active`、`user-name` 等 kebab-case attribute(那是 Vue 的)。

## 3. 子节点 / Children

Reference 中的 `children` 直接保留为 React 标准 children:

| 场景 | 落地 |
| --- | --- |
| 单一插槽 | `children: ReactNode` |
| 多插槽 | 拆为多个 props:`header?: ReactNode`、`footer?: ReactNode` |
| 控制反转 | render prop:`renderItem: (x) => ReactNode` |

**禁止**用 `<template #header>` 等 Vue 概念。

## 4. 样式方案

按项目栈选择(由 `lib-*.md` 决定):

| 方案 | 落地 |
| --- | --- |
| **CSS Modules** | `import styles from './Foo.module.css'` + `className={styles.foo}` |
| **Tailwind / UnoCSS** | utility class 保留,由 `lib-tailwind.md` 接管 |
| **CSS-in-JS** | styled-components / emotion / vanilla-extract / linaria |
| **shadcn/ui 模式** | Tailwind + CSS variables + `cn()` 工具函数 |

**铁律**:**禁止**使用 Vue `:deep()` / `<style scoped>` 概念。穿透组件库样式优先走对应 `lib-*.md` 的 ThemeProvider / CSS Variable;真要覆盖用 CSS Module 的 `:global()` 或 `!important`(后者最末手段)。

## 5. 状态 / 副作用

| 概念 | 落地 |
| --- | --- |
| 组件状态 | `useState` / `useReducer` |
| 副作用 | `useEffect` / `useLayoutEffect` |
| 派生值 | `useMemo`(慎用,React 19 之后 React Compiler 接管) |
| 引用稳定 | `useCallback` |
| Context | `createContext` + `useContext` |
| 数据请求 | TanStack Query / SWR / RSC |

**React 19 / Next.js 15 注意**:Server Component 默认无 hooks,交互组件必须 `"use client"`。

## 6. 文件命名 / 组织

| 类型 | 命名 |
| --- | --- |
| 组件文件 | PascalCase(`UserCard.tsx`),配套 `index.ts` 导出 |
| Hook | `useXxx.ts`(camelCase + 前缀 use) |
| 工具函数 | camelCase(`formatPrice.ts`) |
| 类型 | `types.ts` 或就近声明 |

## 7. 反模式速查

| 反模式 | 正解 |
| --- | --- |
| 把 Vue `<template #header>` 写成 React | 多 prop 拆分或 render prop |
| Props 用 kebab-case | 一律 camelCase |
| 滥用 `:deep()` 概念 | CSS Module `:global()` 或主题 token |
| forwardRef 漏写但需要传 ref | React 19 后函数组件可直接接 ref;旧版必须 forwardRef |
| Server Component 里用 `useState` | 标记 `"use client"` 或重构 |
| `index.tsx` 同名文件超过 200 行 | 拆分子组件,保持单一职责 |

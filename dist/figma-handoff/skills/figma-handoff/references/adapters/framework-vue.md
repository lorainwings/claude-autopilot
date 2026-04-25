# Adapter: Vue 3 Framework

> 把 `translation-core.md` 的 7 条铁律落地为 Vue 3 SFC 语法。本文件**不重复 core 内容**,只补差异点。

## 1. Traceback 注释(R7 配套)

放在 `<template>` **之前**,使用 HTML 注释:

```vue
<!-- @figma fileKey=XXX nodeId=1:23 golden=docs/figma-spec/default/golden.png -->
<template>
  ...
</template>
```

审查脚本通过 `grep -r "@figma fileKey="` 统计节点溯源覆盖率,要求 100%。

## 2. Props / Attribute 命名

| 场景 | 规则 |
| --- | --- |
| `<template>` 中绑定属性 | kebab-case(`is-active`、`v-model:user-name`) |
| `<script setup>` 中声明 | camelCase(`defineProps<{ isActive: boolean }>()`) |
| 自定义事件 | kebab-case 触发 + camelCase 声明(`@user-click="..."`,`emits: ['userClick']`) |

## 3. 子节点 / Slot

Reference 中的 `children` 必须翻译为命名 slot:

| Reference 形态 | Vue 落地 |
| --- | --- |
| `<Card>{children}</Card>` | `<Card><template #default>...</template></Card>` 或简写 |
| `<Modal header={...} footer={...}>` | 命名 slot:`<template #header>` / `<template #footer>` |

**禁止**用 props 传 VNode,违反 Vue 单向数据流。

## 4. 样式作用域

| 场景 | 推荐 |
| --- | --- |
| 组件局部样式 | `<style scoped lang="scss">` |
| 穿透组件库内部 | `:deep(.van-button) { ... }` 仅作为最后手段;**优先**通过 `lib-*.md` 提供的 CSS Variable / ConfigProvider 修改 |
| 全局 token | `<style>` 不带 scoped,或写到 `src/styles/tokens.scss` |
| CSS Module | `<style module>` + `:class="$style.foo"`(适合大型项目) |

**铁律**:`:deep()` 用得多 = adapter 选择错了。检查是否应该改用主题入口。

## 5. 状态 / 副作用

| Reference 概念 | Vue 3 落地 |
| --- | --- |
| `useState` | `ref` / `reactive` |
| `useEffect` | `watch` / `watchEffect` / `onMounted` |
| `useMemo` | `computed` |
| `useCallback` | 一般无需,直接函数声明 |
| Context | `provide` / `inject` 或 Pinia store |

## 6. 文件命名 / 组织

| 类型 | 命名 |
| --- | --- |
| 单文件组件 | PascalCase 文件名(`UserCard.vue`),小写多词(`user-card.vue` 仅在 kebab-case 项目中接受) |
| Composable | `useXxx.ts`(camelCase + 前缀 use) |
| Store(Pinia) | `useXxxStore.ts` |

## 7. 反模式速查

| 反模式 | 正解 |
| --- | --- |
| 把 React `children` 直接写成 `<slot>` 不命名 | 命名 slot 显式声明 |
| 散落 `:deep()` 覆盖组件库样式 | 改 CSS Variable / ConfigProvider |
| `<style>` 不加 scoped 又不走 module | 样式污染全局 |
| props 用 PascalCase / 事件用 onUserClick | 违反 Vue 命名约定 |
| 在 SFC 里写 React 风格 `useState` | 用 `ref` |

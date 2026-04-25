# Adapter: Naive UI(Vue 3,PC 端)

## 1. Token 入口

`<n-config-provider :theme-overrides="...">`。

```vue
<script setup lang="ts">
import { darkTheme, type GlobalThemeOverrides } from 'naive-ui'

const themeOverrides: GlobalThemeOverrides = {
  common: {
    primaryColor: '#FF6A00',
    primaryColorHover: '#E65A00',
    borderRadius: '8px',
    fontFamily: 'PingFang SC, ...',
  },
  Button: {
    heightMedium: '36px',
    borderRadiusMedium: '8px',
  },
}
</script>

<template>
  <n-config-provider :theme="darkTheme" :theme-overrides="themeOverrides">
    <slot />
  </n-config-provider>
</template>
```

## 2. 已知默认值落差

| 组件 | Naive 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `n-button` 圆角 | 3px | 4 / 8 / round | `Button.borderRadiusMedium` |
| `n-button` 高度 | small=28 medium=34 large=40 | Figma 多 36 | `Button.heightMedium` |
| `n-input` 边框色 | `#0001` | 设计稿可能更深 | `Input.border` |
| `n-modal` 遮罩 | `rgba(0,0,0,0.5)` | 同 | `Modal.color` |
| 主题色 | 绿(#18a058) | 品牌色 | `common.primaryColor`(及 hover/pressed/suppl 四档) |

## 3. 暗色优先

Naive 的卖点是 darkTheme 一等公民,**禁止**通过 `.dark` 类名硬切。统一走 `:theme="isDark ? darkTheme : null"`。

## 4. 样式落地

| 场景 | 推荐 |
| --- | --- |
| 全局主题 | `themeOverrides` |
| 单组件实例 | `:theme-overrides` 在组件上传 |
| 局部覆盖 | `<style scoped>` + `:deep(.n-button)`(最末手段) |

## 5. 组件复用映射

| Figma 类型 | Naive 组件 |
| --- | --- |
| 按钮 | `n-button` + `type/secondary/tertiary/quaternary` |
| 输入 | `n-input` / `n-input-number` |
| 对话框 | `n-modal` / `n-drawer` |
| 表格 | `n-data-table` |
| 通知 | `useNotification()` / `useMessage()` |

## 6. 反模式

| 反模式 | 正解 |
| --- | --- |
| 用 `.n-button { ... }` 全局污染 | 走 `themeOverrides` |
| 散用 `:deep()` | 同上 |
| 主题色只改 `primaryColor` 不改 hover/pressed/suppl | 四档全配 |

# Adapter: PrimeVue(Vue 3,PC 端)

## 1. Token 入口

PrimeVue v4+ 引入 `definePreset` + `<PrimeVue :pt="...">` 机制(基于设计 token 的"无 CSS"主题系统)。

```ts
import PrimeVue from 'primevue/config'
import Aura from '@primevue/themes/aura'
import { definePreset } from '@primevue/themes'

const Brand = definePreset(Aura, {
  semantic: {
    primary: {
      50: '#FFF1E8', 500: '#FF6A00', 950: '#3A1A00',
    },
    borderRadius: { md: '8px' },
  },
})

app.use(PrimeVue, { theme: { preset: Brand, options: { darkModeSelector: '.dark' } } })
```

## 2. 已知默认值落差

| 组件 | PrimeVue 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `Button` 圆角 | 6px | 4 / 8 / round | `borderRadius.md` |
| `Button` 高度 | 36px | 项目多自定义 | preset 中改 token |
| 主题色 | 各 preset 不同 | 品牌色 | `semantic.primary.500` + 全色阶 |

## 3. PassThrough(pt)机制

PrimeVue v4 的杀手锏:用 `pt` 在不写 CSS 的前提下覆盖任意子节点 class:

```vue
<Button :pt="{ root: { class: 'rounded-lg h-9' } }" />
```

适合在 Tailwind 项目里精细控制,**不要**与 SCSS 覆盖混用。

## 4. 反模式

| 反模式 | 正解 |
| --- | --- |
| 仍用 v3 SCSS 主题 | 升 v4 token preset |
| pt + 全局 SCSS 双轨 | 选一种 |

## 5. 组件映射(简表)

| Figma | PrimeVue |
| --- | --- |
| 按钮 | `Button` |
| 输入 | `InputText` / `InputNumber` |
| 对话框 | `Dialog` / `Drawer` |
| 表格 | `DataTable` |

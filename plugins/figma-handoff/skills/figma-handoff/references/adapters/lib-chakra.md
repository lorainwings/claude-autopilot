# Adapter: Chakra UI(React)

## 1. Token 入口

`extendTheme` + `<ChakraProvider>`(v2)/ `defineConfig` + `<Provider>`(v3)。

### v2 写法

```tsx
import { ChakraProvider, extendTheme } from '@chakra-ui/react'

const theme = extendTheme({
  colors: {
    brand: { 500: '#FF6A00', 600: '#E65A00' },
  },
  fonts: { heading: 'PingFang SC', body: 'PingFang SC' },
  radii: { md: '8px' },
  components: {
    Button: {
      baseStyle: { borderRadius: 'md' },
      sizes: { md: { h: '36px' } },
    },
  },
})

<ChakraProvider theme={theme}><App /></ChakraProvider>
```

### v3 写法

```tsx
import { defineConfig, createSystem, defaultConfig } from '@chakra-ui/react'

const config = defineConfig({
  theme: {
    tokens: {
      colors: { brand: { value: '#FF6A00' } },
      radii: { md: { value: '8px' } },
    },
  },
})
const system = createSystem(defaultConfig, config)
```

## 2. 已知默认值落差

| 组件 | Chakra 默认 | Figma 习惯值 | Override |
| --- | --- | --- | --- |
| `Button` 圆角 | 6px(md) | 4 / 8 / round | `radii.md` 或 `components.Button.baseStyle.borderRadius` |
| `Button` 高度 | sm/md/lg = 32/40/48 | Figma 多 36 | `components.Button.sizes.md.h` |
| `Input` 高度 | 同 Button | 同上 | `components.Input.sizes.md.field.h` |
| `Modal` 遮罩 | `blackAlpha.600` | 项目可能更深/浅 | `components.Modal.baseStyle.overlay.bg` |
| 主题色 | teal | 品牌色 | `colors.brand.500` 然后组件 `colorScheme="brand"` |

## 3. 样式落地

Chakra 有四种样式入口,优先级:

1. `theme` 对象(全局) — **首选**
2. 组件 prop(`<Button colorScheme="brand" size="md" />`)
3. `sx={{...}}` 就近覆盖
4. CSS Module(最末手段)

## 4. 组件复用映射

| Figma 类型 | Chakra 组件 |
| --- | --- |
| 按钮 | `Button` + `colorScheme` + `variant` |
| 输入 | `Input` / `Textarea` / `NumberInput` |
| 对话框 | `Modal` / `Drawer` |
| 表格 | `Table` |
| 通知 | `useToast` |

## 5. 反模式

| 反模式 | 正解 |
| --- | --- |
| 用 `style={{...}}` 覆盖 Chakra 主题色 | 走 `theme.colors` + `colorScheme` |
| 主题色硬编码到具体组件 | 全部走 token |
| v2/v3 API 混用 | 锁定单一版本,迁移一次到位 |

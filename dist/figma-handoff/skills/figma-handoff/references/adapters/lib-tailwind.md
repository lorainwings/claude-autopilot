# Adapter: Tailwind / UnoCSS(默认 fallback,无组件库场景)

> 当项目未装任何组件库,或显式选择"原子化 CSS only"路径时使用。**所有其他 lib-*.md 都可降级到本文件**。

## 1. 何时用本 adapter

- `package.json` deps 不含任何已知组件库
- 项目显式声明 `react+tailwind` / `vue3+unocss` 等
- shadcn/ui 项目(本质是 Tailwind + CSS variables + headless 原语,优先加载 `lib-shadcn.md`)

## 2. Token 入口

唯一入口:`tailwind.config.{js,ts}` 的 `theme.extend`。把 `tokens.md` 中的 Figma 变量 1:1 写入:

```js
// tailwind.config.ts
export default {
  theme: {
    extend: {
      colors: {
        brand: {
          DEFAULT: 'var(--brand)',         // 用 CSS variable 留主题切换余地
          50: 'var(--brand-50)',
          // ...
        },
      },
      fontSize: {
        // Figma 字号 token, 全部走 var()
      },
      borderRadius: {},
      spacing: {},
    },
  },
}
```

CSS variable 主题源放在 `src/styles/tokens.css`:

```css
:root { --brand: #FF6A00; --brand-50: #FFF1E8; }
[data-theme="dark"] { --brand: #FF8533; }
```

## 3. 类名残留是否允许

**仅在本 adapter 下,允许 utility class 直接出现在产物中**(R1 例外)。其他 adapter 一律禁止。

## 4. 反模式

| 反模式 | 正解 |
| --- | --- |
| 在 `tailwind.config` 里写硬编码 hex | 全部走 CSS variable |
| 一份配置同时维护 Tailwind 颜色 + Sass 变量双轨 | 单一真相 → CSS variable |
| 在 SFC 里写 `class="bg-[#FF6A00]"` 任意值 | 加进 `tailwind.config` 命名 token |
| 用 `@apply` 把 utility 翻译成 BEM | 既然选了 Tailwind,就不要绕回去 |

## 5. 与框架 adapter 的协同

- React + Tailwind:`className="bg-brand text-white"`
- Vue3 + Tailwind / UnoCSS:`class="bg-brand text-white"`(注意 Vue 里是 `class`,不是 `className`)

UnoCSS 同理,只是 `unocss.config.ts` 替代 `tailwind.config.ts`,API 高度兼容。

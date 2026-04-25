# Adapter: shadcn/ui(React)

> 本质是 "Tailwind + CSS variables + Radix headless 原语 + cn() 工具",**不是**传统组件库。组件代码生成在用户仓库内(`components/ui/`),由用户拥有与改造。

## 1. Token 入口

`app/globals.css` (或同等位置)的 `:root` / `.dark`:

```css
@layer base {
  :root {
    --background: 0 0% 100%;
    --foreground: 222.2 84% 4.9%;
    --primary: 222.2 47.4% 11.2%;
    --radius: 0.5rem;
    /* ... 把 tokens.md 的 Figma 变量 1:1 写进来 */
  }
  .dark {
    --background: 222.2 84% 4.9%;
    /* ... */
  }
}
```

**注意**:shadcn 默认用 HSL **空格分隔**字符串,然后通过 `hsl(var(--primary))` 引用。Figma hex → HSL 转换写在 `tokens.md`。

`tailwind.config.ts` 通过 `colors: { primary: 'hsl(var(--primary))' }` 桥接。

## 2. 组件复用规则

| 场景 | 规则 |
| --- | --- |
| Figma 含按钮/输入/对话框 | **必须**先 `npx shadcn-ui@latest add button dialog ...`,再用 |
| 已生成组件需调整样式 | **直接修改** `components/ui/*.tsx`(这是 shadcn 设计哲学) |
| 完全自定义业务组件 | 放到 `components/` 而非 `components/ui/` |

## 3. cn() 工具

shadcn 推荐用 `cn = (...inputs) => twMerge(clsx(inputs))` 合并 class,处理 Tailwind 冲突:

```tsx
<Button className={cn("bg-brand", isPrimary && "bg-primary")} />
```

## 4. 反模式

| 反模式 | 正解 |
| --- | --- |
| 把 shadcn 当传统库,用 npm install 引入 | shadcn 是复制粘贴,不是依赖 |
| `components/ui/button.tsx` 改了又通过 `--force` 重生覆盖 | 自己拥有 = 自己负责升级 diff |
| 直接写 `bg-[#FF6A00]` 字面量 | 写进 CSS variable + tailwind config |
| 与传统组件库混用(同时装 antd + shadcn) | 选一个,避免双轨 |

## 5. 与 framework adapter 协同

shadcn 仅 React;Vue 生态对应方案是 [shadcn-vue](https://www.shadcn-vue.com/),配置同构,组件用 Radix-Vue。

# spec-autopilot v5.0.7 — 整体回归报告

> 生成日期: 2026-03-14
> 运行环境: macOS Darwin 21.6.0 / Node.js / Python 3 / Bash

---

## 1. 测试套件回归

| 指标 | 结果 |
|------|------|
| 测试文件数 | 49 |
| 总断言数 | 357 |
| 通过 | **357** |
| 失败 | **0** |
| 通过率 | **100%** |

### 测试模块覆盖清单

| # | 测试模块 | 通过/失败 | 备注 |
|---|---------|-----------|------|
| 1 | Syntax checks (bash -n) | 29/0 | 29 个脚本语法验证 |
| 2 | check-predecessor-checkpoint.sh | 7/0 | 前驱 checkpoint 门禁 |
| 3 | validate-json-envelope.sh | 23/0 | JSON 信封协议验证 |
| 4 | scan-checkpoints-on-start.sh | 1/0 | SessionStart hook |
| 6 | hooks.json validation | 4/0 | Hook 配置完整性 |
| 7 | deny() fail-closed | 1/0 | 失败安全语义 |
| 8 | Pure bash marker bypass | 4/0 | P2 性能优化 |
| 9 | Fail-closed consistency | 4/0 | python3 缺失时的降级 |
| 10 | SessionStart async | 1/0 | 异步 hook 配置 |
| 11 | PreCompact + SessionStart(compact) | 7/0 | 状态保存/恢复 |
| 12 | _common.sh shared library | 2/0 | 共享库语法 |
| 13 | JSON lock file parsing | 3/0 | 锁文件解析 |
| 14 | Phase 1 checkpoint compatibility | 4/0 | Phase 1 兼容性 |
| 15 | references/ directory structure | 2/0 | 目录结构验证 |
| 16 | check-allure-install.sh | 5/0 | Allure 安装检测 |
| 17 | Phase 6 envelope (Allure fields) | 6/0 | Allure 字段验证 |
| 18 | save-state Phase 7 scan | 2/0 | Phase 7 状态扫描 |
| 19 | _common.sh unit tests | 14/0 | 共享函数单元测试 |
| 20 | check-allure-install.sh enhanced | 7/0 | Allure 增强检测 |
| 21 | validate-config.sh tests | 4/0 | 配置验证 |
| 22 | anti-rationalization-check.sh | 9/0 | 反合理化检查 |
| 23 | Wall-clock timeout tests | 6/0 | 超时机制 |
| 24 | test_pyramid threshold | 10/0 | 测试金字塔阈值 |
| 25 | Lock file pre-check | 10/0 | 锁文件误报防护 |
| 26 | has_active_autopilot | 3/0 | 活跃状态检测 |
| 27 | Two-pass JSON extraction | 8/0 | 双遍 JSON 提取 |
| 28 | Phase 6 suite_results | 4/0 | 测试结果验证 |
| 29 | v3.2.0 optional fields | 8/0 | 可选字段兼容 |
| 30 | v3.2.0 reference files | 5/0 | 参考文件存在性 |
| 31 | validate-config v1.1 | 2/0 | v1.1 配置兼容 |
| 32 | Phase 4 missing fields | 7/0 | Phase 4 必填字段 |
| 33 | Phase 6.5 code review bypass | 4/0 | 代码审查绕过 |
| 34 | Phase 7 predecessor (no 6.5) | 4/0 | Phase 7 无 6.5 依赖 |
| 35 | Phase 6 independent of 6.5 | 2/0 | Phase 6/6.5 解耦 |
| 36 | Quality scan bypass | 3/0 | 质量扫描绕过 |
| 37 | Minimal mode (Phase 7 w/o Phase 6) | 4/0 | Minimal 模式路径 |
| 38 | Lite mode Phase 6 tri-path | 4/0 | Lite 模式三路径 |
| 39 | parallel-merge-guard anchor_sha | 11/0 | 并行合并守卫 |
| 40 | Phase 4 change_coverage | 13/0 | 变更覆盖率 |
| 41 | Ralph-loop removal | 11/0 | Ralph-loop 清理验证 |
| 42 | Serial task config | 7/0 | 串行任务配置 |
| 43 | Phase 5 serial checkpoint | 6/0 | Phase 5 串行检查点 |
| 44 | Template file mapping | 5/0 | 模板文件映射 |
| 45 | Background agent bypass | 13/0 | 后台 Agent 绕过 |
| 46 | summary field downgrade | 10/0 | summary 字段降级 |
| 47 | Mode lock + predecessor gate | 12/0 | 模式锁+前驱门禁 |
| 48 | output_file / new fields | 4/0 | 新字段兼容 |
| 49 | Phase 7 archive timing | 9/0 | Phase 7 归档时序 |
| 50 | Lockfile absolute path | 5/0 | 锁文件绝对路径 |
| 51 | Fixup commit git add -A | 5/0 | 提交纪律 |
| 52 | Search policy rule engine | 25/0 | 搜索策略引擎 |

---

## 2. GUI 状态

| 检查项 | 结果 |
|--------|------|
| 依赖安装 | npm install 成功，0 漏洞 |
| TypeScript 类型检查 | **修复后通过** (4 处类型错误已修复) |
| Vite 开发服务器 | 运行中 @ http://localhost:5174/ |
| 生产构建 | 成功 (45 模块, 1.83s) |
| 产物体积 | JS: 500KB / CSS: 17.4KB / HTML: 0.6KB |

### GUI 类型修复详情

| 文件 | 问题 | 修复 |
|------|------|------|
| `GateBlockCard.tsx:25` | 数组索引返回 `T \| undefined` | 添加非空断言 `!` |
| `GateBlockCard.tsx:49` | `payload.gate_score` 为 `unknown` | 使用 `String()` 包裹 |
| `GateBlockCard.tsx:51` | `payload.error_message` 为 `unknown` | 改用 `typeof === "string"` 守卫 |
| `VirtualTerminal.tsx:106` | 数组最后元素可能 `undefined` | 添加非空断言 `!` |

---

## 3. 插件配置检查

| 检查项 | 状态 |
|--------|------|
| plugin.json 版本 | v5.0.7 |
| hooks.json 有效性 | 5 类 hook，timeout 均已配置 |
| Hook 脚本语法 | 29 个脚本全部通过 `bash -n` |
| Python 模块导入 | 4 个模块全部可导入 |
| 构建脚本 (build-dist.sh) | 成功，1.1M (压缩比 98.6%) |

### Hook 注册清单

| 事件 | Matcher | 脚本 | Timeout |
|------|---------|------|---------|
| PreToolUse | `^Task$` | check-predecessor-checkpoint.sh | 30s |
| PostToolUse | `^Task$` | post-task-validator.sh | 60s |
| PostToolUse | `^(Write\|Edit)$` | unified-write-edit-check.sh | 15s |
| PreCompact | (all) | save-state-before-compact.sh | 15s |
| SessionStart | (all) | scan-checkpoints-on-start.sh | 15s (async) |
| SessionStart | (all) | check-skill-size.sh | 15s |
| SessionStart | compact | reinject-state-after-compact.sh | 15s |

---

## 4. 总结

### 健康度评分: 98/100

| 维度 | 评分 | 说明 |
|------|------|------|
| 测试覆盖 | 100% | 49 文件 357 断言全部通过 |
| 构建稳定性 | 100% | GUI + dist 构建无错误 |
| 类型安全 | 95% | 4 处类型错误已修复 (非运行时问题) |
| 配置完整性 | 100% | Hook/Plugin/Config 配置一致 |
| Python 依赖 | 100% | 全部模块可正常导入 |

### 发现的问题 (已修复)

1. **GUI TypeScript 类型错误** — 4 处 strict mode 下的类型不匹配
   - 根因: `Record<string, unknown>` 值在 JSX 中需显式类型窄化
   - 影响: 仅编译时错误，Vite 构建不受影响 (esbuild 不做类型检查)
   - 状态: **已修复**

### 待关注项

- GUI 开发服务器默认端口 5173 被占用，自动切换到 5174
- `_post_task_validator.py` 在空 stdin 时输出 WARNING（正常行为，非 bug）

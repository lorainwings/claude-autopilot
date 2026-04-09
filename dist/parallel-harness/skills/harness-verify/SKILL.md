---
name: harness-verify
description: "Verification phase protocol for parallel engineering orchestrator. Runs multi-gate quality checks (test, lint, type, security, policy, coverage), verifies file ownership compliance, synthesizes gate conclusions with blocking/non-blocking classification.\n\n并行工程验证阶段协议。运行多维度门禁检查（测试、Lint、类型、安全、策略、覆盖率），验证文件所有权合规，综合门禁结论并分类为阻断/非阻断。"
user-invocable: false
---

# Harness Verify -- 验证阶段协议

> 版本: v1.5.0 (GA)
> 本协议由主编排器 (`/harness`) 在验证阶段调用。

你是 parallel-harness 平台的验证编排器。你的职责是独立验证所有任务输出的质量，综合门禁结论，输出通过或阻断决策。

## 输入

你会收到：
- 所有任务的执行结果（修改的文件列表、Agent 输出摘要）
- 任务的 allowed_paths 和 acceptance_criteria
- 项目配置（测试命令、lint 配置等）

## 执行步骤

### Step 1: 检测项目工具链

自动检测项目使用的工具：

```
Glob("package.json")          → 检查 scripts 中的 test/lint 命令
Glob("tsconfig.json")         → TypeScript 项目
Glob(".eslintrc*")            → ESLint 配置
Glob("biome.json")            → Biome 配置
Glob("jest.config*")          → Jest 配置
Glob("vitest.config*")        → Vitest 配置
```

确定可用的验证命令。

### Step 2: 运行门禁检查

按优先级执行以下门禁：

#### Gate 1: test (阻断)

运行项目测试：

```bash
# 根据检测到的工具链选择
bun test                      # Bun 项目
npm test                      # npm 项目
pnpm test                     # pnpm 项目
npx jest                      # Jest
npx vitest run                # Vitest
```

- 全部通过 → PASS
- 任何测试失败 → BLOCK

#### Gate 2: lint_type (阻断)

运行类型检查和 lint：

```bash
# TypeScript 类型检查
bunx tsc --noEmit             # 或 npx tsc --noEmit

# Lint
bunx eslint . --quiet         # 或 npx eslint . --quiet
npx biome check .             # Biome
```

- 无错误 → PASS
- 有类型错误或 lint error → BLOCK（warnings 不阻断）

#### Gate 3: security (阻断)

检查敏感文件模式：

```
Grep("\\.env$")               → .env 文件被修改
Grep("credentials")           → credentials 文件
Grep("password.*=.*['\"]")    → 硬编码密码
Grep("api[_-]?key.*=.*['\"]") → 硬编码 API key
Grep("\\.pem$|\\.key$")       → 证书/密钥文件
```

仅检查本次修改的文件。

- 无敏感文件被修改 → PASS
- 检测到敏感内容 → BLOCK

#### Gate 4: policy / ownership (阻断)

验证文件所有权合规：

对每个任务，检查实际修改的文件是否在 `allowed_paths` 范围内：

```bash
# 通过 git diff 获取实际修改的文件
git diff --name-only HEAD~1   # 或根据实际提交范围
```

- 所有修改在允许范围内 → PASS
- 存在越权修改 → BLOCK

#### Gate 5: review (非阻断)

代码审查检查：

- 修改文件数是否过多（> 20 个文件 → 警告）
- 源码修改是否有对应测试变更
- 修改摘要是否过短

#### Gate 6: coverage (非阻断)

如果项目有覆盖率配置：

```bash
bun test --coverage           # 或其他覆盖率命令
```

- 覆盖率未下降 → PASS
- 覆盖率下降 → WARN（不阻断）

### Step 3: 综合门禁结论

汇总所有门禁结果：

```
门禁结论:
  阻断性门禁:
    - test:      PASS / BLOCK
    - lint_type: PASS / BLOCK
    - security:  PASS / BLOCK
    - policy:    PASS / BLOCK
  
  非阻断性门禁:
    - review:    PASS / WARN
    - coverage:  PASS / WARN

  总结论: PASS (全部阻断性门禁通过) / BLOCK (至少一个阻断性门禁失败)
```

### Step 4: 处理阻断

如果存在阻断性问题：

1. **分析失败原因**
   - 读取测试失败输出，定位问题
   - 检查类型错误的具体位置

2. **生成修复建议**
   ```
   阻断问题:
     - test: 2 个测试失败
       - test/user.test.ts:42 — expected 'logout' to be defined
       - test/auth.test.ts:15 — timeout
     
     修复建议:
       - 在 UserService 中实现 logout 方法
       - 检查 auth.test.ts 的异步处理
   ```

3. **返回阻断信息给主编排器**
   - 主编排器决定是否派发修复 Agent
   - 修复后重新运行验证

## 输出格式

```
## 验证报告

### 门禁结果

| 门禁 | 级别 | 结果 | 详情 |
|------|------|------|------|
| test | 阻断 | PASS | 42 tests passed |
| lint_type | 阻断 | PASS | No errors |
| security | 阻断 | PASS | No sensitive files modified |
| policy | 阻断 | PASS | All modifications within allowed_paths |
| review | 信号 | WARN | 15 files modified, consider splitting |
| coverage | 信号 | PASS | Coverage: 85% (no change) |

### 总结论
**PASS** — 所有阻断性门禁通过

### 问题列表
- [WARN] review: 修改了 15 个文件，建议考虑拆分

### 建议
- 考虑为新增代码添加更多测试用例
```

## 约束

- 验证器不能修改任何代码文件
- 验证器独立于执行 Agent
- 每个任务至少经过 test + lint_type + security + policy 四项检查
- 阻断必须给出可操作的修复建议
- 如果项目没有测试命令，test gate 标记为 SKIP（非 PASS）
- 安全检查仅针对本次修改的文件，不扫描全仓

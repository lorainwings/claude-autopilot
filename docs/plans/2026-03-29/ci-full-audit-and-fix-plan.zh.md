# CI/CD 全流程审计与修复方案

> 生成时间: 2026-03-29
> 适用范围: lorainwings/claude-autopilot monorepo 全部 CI workflow
> 用途: 直接喂给 Claude Code / Codex 执行修复

---

## 目录

1. [CI 全流程协作分析](#一ci-全流程协作分析)
2. [发现的问题清单](#二发现的问题清单22-项)
3. [开源社区最佳实践对标](#三开源社区最佳实践对标)
4. [可执行修复方案](#四可执行修复方案)
5. [执行顺序](#五执行顺序)
6. [验证清单](#六验证清单)

---

## 一、CI 全流程协作分析

### 1.1 Workflow 清单

| Workflow | 文件 | 触发条件 | 职责 |
|----------|------|---------|------|
| release-please | `.github/workflows/release-please.yml` | push to main（无 paths 过滤） | 自动版本管理 + post-release 更新 |
| test-spec-autopilot | `.github/workflows/test-spec-autopilot.yml` | push/PR to main + paths 过滤 | SA 测试、lint、构建验证 |
| test-parallel-harness | `.github/workflows/test-parallel-harness.yml` | push/PR to main + paths 过滤 | PH 测试、lint、构建验证 |

### 1.2 场景 1：直接推送到 main

```
git push origin main (修改 plugins/parallel-harness/)
  │
  ├── [触发] release-please.yml — 分析 conventional commits → 创建/更新 Release PR
  │     └─ releases_created == false → post-release 不执行
  │
  ├── [触发] test-parallel-harness.yml — paths 匹配
  │     └─ should-run → release-discipline → ph-typecheck/ph-test/ph-lint → ph-build
  │
  └── [不触发] test-spec-autopilot.yml — paths 不匹配
```

### 1.3 场景 2：PR 合并到 main

```
阶段 A — PR 创建/更新:
  ├── [触发] test-parallel-harness.yml (on.pull_request)
  └── [不触发] release-please.yml (仅 push to main)

阶段 B — PR 合并:
  ├── [触发] release-please.yml → 创建/更新 Release PR
  ├── [触发] test-parallel-harness.yml (on.push)
  └── [触发] test-spec-autopilot.yml (如 paths 匹配)
```

### 1.4 场景 3：release-please 全流程（最复杂）

```
阶段 1: feat/fix commit 合入 main
  └─ release-please 创建 Release PR（bump version + CHANGELOG）

阶段 2: Release PR 触发 CI（bot bypass 跳过大部分检查）

阶段 3: Release PR 合并到 main
  ├─ release-please 创建 GitHub Release + Git Tag
  └─ post-release job 执行:
       1. 构建 dist（条件触发，按插件）
       2. 更新 README badge/标题版本
       3. 更新根 README 版本表
       4. 更新 marketplace.json 版本
       5. commit + push "chore: post-release update dist + README versions"

阶段 4: post-release commit 推到 main
  ├─ release-please.yml 触发但 releases_created=false → 无操作
  ├─ test-parallel-harness.yml → should-run 检测 bot commit → skip=true ✓
  └─ test-spec-autopilot.yml → ⚠️ 缺少 should-run gate → 完整 CI 执行（浪费资源）
```

### 1.5 Bot Commit 绕过机制

| 组件 | 绕过方式 | 覆盖范围 |
|------|---------|---------|
| test-parallel-harness | `should-run` job 前置 gate | 全部后续 job |
| test-spec-autopilot | `build-dist` 内联检测 | **仅** dist staleness 检查 |
| check-release-discipline.sh | 脚本内部 bypass | 仅 discipline 检查 |
| pre-commit hook | 分支名检测 `release-please--*` | 全部 pre-commit |

### 1.6 关键不对称

| 维度 | test-parallel-harness | test-spec-autopilot |
|------|----------------------|---------------------|
| Bot bypass gate | ✅ `should-run` job | ❌ 缺失 |
| build-dist needs 链 | ✅ `needs: [typecheck, test, lint]` | ❌ 并行独立 |
| `.githooks/**` paths | ✅ 包含 | ❌ 缺失 |
| Bot 检测逻辑 | AND（author && message） | release-discipline 中 OR |

---

## 二、发现的问题清单（22 项）

### Critical（2 项）

| ID | 问题 | 影响 |
|----|------|------|
| **C1** | 三个 workflow 均缺少 `concurrency` group 配置 | 同一 PR 多次推送并行运行浪费资源；post-release push 与 test workflow 竞态 |
| **C2** | `build-dist.sh` 中 `\|\| true` 吞掉测试失败 | 若 `bun test` 输出格式变化，`FAIL_COUNT` grep 失效，测试失败被静默忽略 |

### High（8 项）

| ID | 问题 | 影响 |
|----|------|------|
| **H1** | `test-spec-autopilot.yml` 缺少整体 bot commit bypass（`should-run` job） | release-please/post-release commit 触发完整 CI 浪费资源 |
| **H2** | `test-spec-autopilot.yml` 的 `build-dist` 缺少 `needs` 依赖链 | 测试失败时构建仍执行，语义不正确 |
| **H3** | `test-spec-autopilot.yml` paths 缺少 `.githooks/**` | pre-commit hook 变更不触发 SA 测试 |
| **H4** | bot 检测条件在不同位置使用 AND vs OR 逻辑不一致 | 某些 bot commit 在一处被跳过另一处不被跳过 |
| **H5** | `marketplace.json` 不在 release-please `extra-files` 中 | Release PR 中版本不同步，依赖 post-release 延迟更新；若 post-release 失败则永久不同步 |
| **H6** | README/CLAUDE.md 中 `x-release-please-version` 标记与 post-release sed 双重更新 | 冗余/误导，README 中的标记无实际效果（不在 extra-files 中） |
| **H7** | post-release push 与 test workflow 的竞态窗口 | release merge commit 触发 CI 与 post-release push 触发 CI 并行运行 |
| **H8** | post-release 使用 `git add -A` 过于宽泛 | 可能意外提交临时文件 |

### Medium（9 项）

| ID | 问题 | 影响 |
|----|------|------|
| **M1** | 根目录 `Makefile` 变更不触发任何 test workflow | Makefile target 修改后 CI 不验证 |
| **M2** | `actions/checkout` 版本不一致（v4 vs v5） | 潜在行为差异 |
| **M3** | 所有 job 缺少 `timeout-minutes` | 步骤挂起消耗 6 小时 CI 额度 |
| **M4** | 未启用 Bun 依赖缓存 | 每次 CI 从网络下载依赖 |
| **M5** | PH dist staleness 检查缺少内层 bot bypass 纵深防御 | 若 should-run 遗漏新 bot 模式则无安全网 |
| **M6** | `separate-pull-requests: false` 导致两插件共享 Release PR | 无法独立控制发版节奏 |
| **M7** | pre-commit 对两插件 dist 重建触发条件不对称 | SA 修改 README 触发无效 dist 重建 |
| **M8** | `CLAUDE.md` 中 `x-release-please-version` 标记与 `(GA)` 文本兼容性风险 | Generic updater 可能无法正确解析 |
| **M9** | 两个 test workflow 缺少 `permissions` 声明 | 使用默认权限，不符合最小权限原则 |

### Low（3 项）

| ID | 问题 | 影响 |
|----|------|------|
| **L1** | pre-commit diff 基于工作树而非暂存区 | dist 可能包含未暂存变更 |
| **L2** | pre-commit 缺少 PH 版本一致性检查 | 本地可 commit 版本不一致代码 |
| **L3** | `workflow_dispatch` 触发时 base ref 回退逻辑边界情况 | 只有一个初始 commit 时 fallback 失败 |

---

## 三、开源社区最佳实践对标

| 维度 | 社区最佳实践 | 当前项目状态 | 差距 |
|------|------------|------------|------|
| 并发控制 | `concurrency` + `cancel-in-progress` | ❌ 未配置 | Critical |
| Job 超时 | 每个 job 设置 `timeout-minutes` | ❌ 未设置 | Medium |
| 权限声明 | `permissions: contents: read` | ❌ 未声明 | Medium |
| 依赖缓存 | `setup-bun` 的 `cache: true` | ❌ 未启用 | Medium |
| Bot bypass | 统一前置 gate job | ⚠️ 仅 PH 有 | High |
| Build needs 链 | 构建依赖 lint+test+typecheck | ⚠️ 仅 PH 有 | High |
| release-please tag | `include-component-in-tag: true` | ❌ 未配置 | Medium |
| 独立 Release PR | `separate-pull-requests: true` | ❌ 共享 PR | Medium |
| `exclude-paths` | 防跨插件误触发 | ❌ 未配置 | Medium |
| `git add` 精确化 | 显式指定文件 | ❌ 使用 `git add -A` | High |
| Dist 管理 | CI artifact / 不 git tracked | ⚠️ git tracked + freshness 检查 | 可接受（插件市场要求） |

---

## 四、可执行修复方案

> **说明**: 以下每个修复项精确到文件路径和代码变更。可直接作为 Claude Code / Codex prompt 执行。

---

### 修复 1: 添加 concurrency 控制 [C1]

**文件**: `.github/workflows/test-parallel-harness.yml`

在 `on:` 块之后、`jobs:` 之前添加:
```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
```

**文件**: `.github/workflows/test-spec-autopilot.yml`

同上，在 `on:` 块之后、`jobs:` 之前添加相同配置。

**文件**: `.github/workflows/release-please.yml`

```yaml
concurrency:
  group: release-please
  cancel-in-progress: false
```

**理由**: PR 分支上取消旧运行节省资源；main 分支保持所有运行完成；release-please 不取消进行中的发版。

---

### 修复 2: 添加 timeout-minutes [M3]

**文件**: `.github/workflows/test-parallel-harness.yml`

为每个 job 添加 `timeout-minutes`:
- `should-run`: 5
- `release-discipline`: 10
- `ph-typecheck`: 10
- `ph-test`: 15
- `ph-lint`: 10
- `ph-build`: 15

**文件**: `.github/workflows/test-spec-autopilot.yml`

- `release-discipline`: 10
- `test-hooks`: 20
- `lint`: 10
- `typecheck`: 10
- `build-dist`: 15

**文件**: `.github/workflows/release-please.yml`

- `release-please`: 10
- `post-release`: 20

---

### 修复 3: 添加 permissions 声明 [M9]

**文件**: `.github/workflows/test-parallel-harness.yml` 和 `.github/workflows/test-spec-autopilot.yml`

在 `on:` 块之后添加:
```yaml
permissions:
  contents: read
```

---

### 修复 4: 统一 actions/checkout 版本 [M2]

**文件**: `.github/workflows/release-please.yml`

将所有 `actions/checkout@v4` 改为 `actions/checkout@v5`。

---

### 修复 5: 为 test-spec-autopilot 添加 bot bypass [H1]

**文件**: `.github/workflows/test-spec-autopilot.yml`

在 `jobs:` 之后、第一个现有 job 之前添加 `should-run` job:

```yaml
  # ── bot commit bypass ─────────────────────────────────────────────
  should-run:
    name: Check if CI should run
    runs-on: ubuntu-latest
    timeout-minutes: 5
    outputs:
      skip: ${{ steps.check.outputs.skip }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 2

      - name: Detect bot commits
        id: check
        run: |
          AUTHOR=$(git log -1 --format='%an')
          MSG=$(git log -1 --format='%s')
          if [[ "$AUTHOR" == *"github-actions"* ]] && \
             { [[ "$MSG" =~ ^chore:\ release\ main ]] || \
               [[ "$MSG" =~ ^chore\(main\):\ release ]] || \
               [[ "$MSG" =~ ^chore:\ post-release ]]; }; then
            echo "skip=true" >> "$GITHUB_OUTPUT"
            echo "ℹ️  Bot commit detected ($MSG) — skipping CI"
          else
            echo "skip=false" >> "$GITHUB_OUTPUT"
          fi
```

然后为所有现有 job 添加依赖:
```yaml
  release-discipline:
    needs: [should-run]
    if: needs.should-run.outputs.skip != 'true'
    ...

  test-hooks:
    needs: [should-run]
    if: needs.should-run.outputs.skip != 'true'
    ...

  lint:
    needs: [should-run]
    if: needs.should-run.outputs.skip != 'true'
    ...

  typecheck:
    needs: [should-run]
    if: needs.should-run.outputs.skip != 'true'
    ...

  build-dist:
    needs: [should-run, test-hooks, lint, typecheck]
    if: needs.should-run.outputs.skip != 'true'
    ...
```

---

### 修复 6: 为 test-spec-autopilot 的 build-dist 添加 needs 链 [H2]

**文件**: `.github/workflows/test-spec-autopilot.yml`

```diff
   build-dist:
     name: spec-autopilot / Build & Verify dist
     runs-on: ubuntu-latest
+    needs: [should-run, test-hooks, lint, typecheck]
+    if: needs.should-run.outputs.skip != 'true'
     steps:
```

**理由**: 构建只在 lint/typecheck/test 全部通过后执行，与 PH 保持一致。

---

### 修复 7: 为 test-spec-autopilot paths 添加 `.githooks/**` [H3]

**文件**: `.github/workflows/test-spec-autopilot.yml`

在 push 和 pull_request 的 paths 列表中添加:
```yaml
      - '.githooks/**'
```

---

### 修复 8: 启用 Bun 依赖缓存 [M4]

**文件**: `.github/workflows/test-parallel-harness.yml`

所有 `oven-sh/setup-bun@v2` 步骤添加:
```yaml
      - uses: oven-sh/setup-bun@v2
        with:
          cache: true
          cache-dependency-path: plugins/parallel-harness/bun.lock
```

**文件**: `.github/workflows/test-spec-autopilot.yml`

```yaml
      - uses: oven-sh/setup-bun@v2
        with:
          cache: true
          cache-dependency-path: |
            plugins/spec-autopilot/gui/bun.lock
            plugins/spec-autopilot/runtime/server/bun.lock
```

**文件**: `.github/workflows/release-please.yml`

```yaml
      - uses: oven-sh/setup-bun@v2
        with:
          cache: true
```

---

### 修复 9: 为 PH dist staleness 添加 bot bypass 安全网 [M5]

**文件**: `.github/workflows/test-parallel-harness.yml`

在 "Check dist not stale" step 开头添加:
```bash
          # 额外的 bot commit 安全网（与 should-run 互为冗余保护）
          HEAD_MSG=$(git log -1 --format='%s')
          HEAD_AUTHOR=$(git log -1 --format='%an')
          if echo "$HEAD_MSG" | grep -qE '^chore(\(main\))?: (release|post-release)'; then
            echo "ℹ️  release-please / post-release commit — skipping dist staleness check"
            exit 0
          fi
          if echo "$HEAD_AUTHOR" | grep -q 'github-actions'; then
            echo "ℹ️  bot commit — skipping dist staleness check"
            exit 0
          fi
```

---

### 修复 10: 精确化 post-release 的 `git add` [H8]

**文件**: `.github/workflows/release-please.yml`

```diff
-          git add -A
+          git add \
+            dist/ \
+            plugins/spec-autopilot/README.md plugins/spec-autopilot/README.zh.md \
+            plugins/parallel-harness/README.md plugins/parallel-harness/README.zh.md \
+            plugins/parallel-harness/CLAUDE.md \
+            README.md README.zh.md \
+            .claude-plugin/marketplace.json
```

---

### 修复 11: release-please 配置优化 [M6, M8]

**文件**: `release-please-config.json`

```diff
 {
   "$schema": "https://raw.githubusercontent.com/googleapis/release-please/main/schemas/config.json",
   "bootstrap-sha": "fcd3ee68e0e3f78f3a96b540c4c62138f7e5f5df",
-  "separate-pull-requests": false,
+  "separate-pull-requests": true,
+  "include-component-in-tag": true,
   "changelog-sections": [
```

为每个包添加 `exclude-paths`:
```diff
     "plugins/spec-autopilot": {
       "release-type": "simple",
       "component": "spec-autopilot",
+      "exclude-paths": ["plugins/parallel-harness"],
       "extra-files": [
```

```diff
     "plugins/parallel-harness": {
       "release-type": "simple",
       "component": "parallel-harness",
+      "exclude-paths": ["plugins/spec-autopilot"],
       "extra-files": [
```

**注意**: `include-component-in-tag` 会改变 tag 格式（从 `v1.1.1` 变为 `parallel-harness-v1.1.1`）。需要检查是否有代码依赖旧 tag 格式。`separate-pull-requests: true` 需要验证 post-release job 是否需要适配（因为可能分两个 release event 触发）。

---

### 修复 12: post-release commit message 包含版本信息 [建议]

**文件**: `.github/workflows/release-please.yml`

```diff
-            git commit -m "chore: post-release update dist + README versions"
+            COMMIT_MSG="chore: post-release update dist + README versions"
+            SA_VER="${{ needs.release-please.outputs.sa_version }}"
+            PH_VER="${{ needs.release-please.outputs.ph_version }}"
+            [ -n "$SA_VER" ] && COMMIT_MSG="$COMMIT_MSG [spec-autopilot@$SA_VER]"
+            [ -n "$PH_VER" ] && COMMIT_MSG="$COMMIT_MSG [parallel-harness@$PH_VER]"
+            git commit -m "$COMMIT_MSG"
```

---

### 修复 13: post-release push 添加重试机制 [建议]

**文件**: `.github/workflows/release-please.yml`

```diff
-            git push
+            # 带重试的 push（处理并发冲突）
+            for i in 1 2 3; do
+              if git push; then
+                echo "✅ Push succeeded"
+                break
+              fi
+              if [ $i -eq 3 ]; then
+                echo "❌ Push failed after 3 attempts"
+                exit 1
+              fi
+              echo "⚠️  Push failed (attempt $i/3), rebasing..."
+              git pull --rebase
+            done
```

---

### 修复 14: 统一 bot 检测逻辑 [H4]

**问题**: `check-release-discipline.sh` 使用 OR 逻辑（author OR message），`should-run` 使用 AND 逻辑（author AND message）。

**建议**: 统一为 AND 逻辑更安全（同时匹配 author 和 message，避免误跳过人工提交）。但需要确保所有 bot commit 的 author 和 message 都在已知列表中。

**文件**: `scripts/check-release-discipline.sh`

将第 38-48 行的 OR bypass 改为 AND:
```diff
-  if [[ "$HEAD_AUTHOR" == *"github-actions"* ]] || \
-     [[ "$HEAD_MESSAGE" == "chore(main): release"* ]] || \
-     [[ "$HEAD_MESSAGE" == "chore: release main"* ]] || \
-     [[ "$HEAD_MESSAGE" == "chore: post-release"* ]]; then
+  if [[ "$HEAD_AUTHOR" == *"github-actions"* ]] && \
+     { [[ "$HEAD_MESSAGE" == "chore(main): release"* ]] || \
+       [[ "$HEAD_MESSAGE" == "chore: release main"* ]] || \
+       [[ "$HEAD_MESSAGE" == "chore: post-release"* ]]; }; then
```

---

### 修复 15: 清理无效的 `x-release-please-version` 标记 [H6]

**问题**: README.md 文件中的 `<!-- x-release-please-version -->` 注释不在 release-please extra-files 中，不会被自动更新，属于误导。

**文件**:
- `plugins/parallel-harness/README.md` — 移除标记（版本由 post-release sed 更新）
- `plugins/parallel-harness/README.zh.md` — 同上
- `plugins/spec-autopilot/README.md` — 同上（如存在）
- `plugins/spec-autopilot/README.zh.md` — 同上（如存在）

**保留**: `plugins/parallel-harness/CLAUDE.md` 中的标记（因为 CLAUDE.md 在 extra-files 中）。

---

## 五、执行顺序

### 阶段 1: 基础设施（低风险，立即省资源）

| 序号 | 修复项 | 涉及文件 | 风险 |
|------|--------|---------|------|
| 1 | 修复 1: concurrency 控制 | 三个 workflow | 极低 |
| 2 | 修复 2: timeout-minutes | 三个 workflow | 极低 |
| 3 | 修复 3: permissions 声明 | 两个 test workflow | 极低 |
| 4 | 修复 4: checkout 版本统一 | release-please.yml | 极低 |

### 阶段 2: CI 逻辑修复（中等风险，核心改进）

| 序号 | 修复项 | 涉及文件 | 风险 |
|------|--------|---------|------|
| 5 | 修复 5: SA bot bypass | test-spec-autopilot.yml | 低 |
| 6 | 修复 6: SA build-dist needs 链 | test-spec-autopilot.yml | 低 |
| 7 | 修复 7: SA paths + .githooks | test-spec-autopilot.yml | 极低 |
| 8 | 修复 8: Bun 缓存 | 三个 workflow | 低 |
| 9 | 修复 9: PH dist bot bypass | test-parallel-harness.yml | 极低 |
| 10 | 修复 14: 统一 bot 检测逻辑 | check-release-discipline.sh | 低 |

### 阶段 3: release-please 配置（需谨慎验证）

| 序号 | 修复项 | 涉及文件 | 风险 |
|------|--------|---------|------|
| 11 | 修复 11: RP 配置优化 | release-please-config.json | **中**（tag 格式变更） |
| 12 | 修复 15: 清理无效标记 | README.md/README.zh.md | 低 |

### 阶段 4: post-release 优化（低优先级）

| 序号 | 修复项 | 涉及文件 | 风险 |
|------|--------|---------|------|
| 13 | 修复 10: git add 精确化 | release-please.yml | 低 |
| 14 | 修复 12: commit message 版本信息 | release-please.yml | 极低 |
| 15 | 修复 13: push 重试机制 | release-please.yml | 极低 |

---

## 六、验证清单

### 阶段 1 验证

- [ ] 在 PR 上连续推送两次 → 旧 CI 运行被取消
- [ ] Actions 页面确认每个 job 显示 timeout 设置
- [ ] Actions 页面确认 test workflow 使用 read-only 权限
- [ ] 所有 workflow 中 actions/checkout 版本一致

### 阶段 2 验证

- [ ] 模拟 bot commit 推送到 main → SA workflow 被 should-run 跳过
- [ ] 故意让 SA lint 失败 → build-dist 不运行
- [ ] 修改 `.githooks/pre-commit` → SA workflow 触发
- [ ] 连续触发两次 CI → 第二次的 `bun install` 显示 cache hit
- [ ] PH post-release commit → dist stale check 显示 bypass 信息
- [ ] 验证 check-release-discipline.sh 在 bot commit 时正确跳过

### 阶段 3 验证

- [ ] 合入 main 后检查 release-please PR 的 tag 名是否包含 component 前缀
- [ ] 同时有两插件变更时是否生成两个独立 Release PR
- [ ] README 中无 x-release-please-version 注释（CLAUDE.md 保留）

### 阶段 4 验证

- [ ] 触发 post-release → commit 只包含预期文件
- [ ] post-release commit message 包含版本号
- [ ] 模拟 push 冲突 → 重试机制正常工作

---

## 附录 A: 涉及的文件路径

```
.github/workflows/release-please.yml
.github/workflows/test-spec-autopilot.yml
.github/workflows/test-parallel-harness.yml
release-please-config.json
scripts/check-release-discipline.sh
plugins/parallel-harness/README.md
plugins/parallel-harness/README.zh.md
plugins/spec-autopilot/README.md (如存在标记)
plugins/spec-autopilot/README.zh.md (如存在标记)
```

## 附录 B: 给 AI Agent 的执行指令

```
请按照 docs/plans/2026-03-29/ci-full-audit-and-fix-plan.zh.md 中的修复方案，
按"执行顺序"章节的阶段依次执行。

规则:
1. 每个修复项完成后运行 `make ph-test` 和 `make ph-lint` 确认无回归
2. 阶段 1-2 可以合为一个 commit
3. 阶段 3（release-please 配置）单独一个 commit
4. 阶段 4（post-release 优化）单独一个 commit
5. 每个 commit 使用 conventional commits 格式: `ci(workflow): <描述>`
6. 修改 release-please-config.json 时需要特别注意 include-component-in-tag 对已有 tag 的影响
7. 不要修改 dist/ 下任何文件
8. 不要修改版本号
```

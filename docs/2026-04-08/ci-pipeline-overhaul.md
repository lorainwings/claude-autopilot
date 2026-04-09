# CI 流水线彻底修复技术方案

> 日期: 2026-04-08
> 范围: 全仓库 CI / pre-commit / build / release 链路
> 目标: 彻底消除三大 BUG 的结构性根因，使本地 → CI → Release 全链路语义一致

---

## 目录

1. [现状架构全景](#1-现状架构全景)
2. [BUG 复现与根因深度分析](#2-bug-复现与根因深度分析)
3. [开源社区竞品对标](#3-开源社区竞品对标)
4. [彻底修复方案](#4-彻底修复方案)
5. [逐文件改动清单](#5-逐文件改动清单)
6. [迁移策略与验证矩阵](#6-迁移策略与验证矩阵)

---

## 1. 现状架构全景

### 1.1 仓库结构

```
claude-autopilot/                  (monorepo root)
├── plugins/
│   ├── spec-autopilot/            (shell + Python + React GUI 插件)
│   ├── parallel-harness/          (TypeScript 插件)
│   └── daily-report/              (纯文件复制插件)
├── dist/                          (git-tracked 发布产物)
│   ├── spec-autopilot/
│   ├── parallel-harness/
│   └── daily-report/
├── scripts/                       (共享 CI 脚本)
├── .githooks/                     (本地 git hooks)
├── .github/workflows/             (CI 定义)
│   ├── ci.yml                     (主 CI — PR / push / merge_group)
│   ├── ci-sweep.yml               (每周全量扫描)
│   └── release-please.yml         (自动发版 + post-release 回写)
└── Makefile                       (构建编排入口)
```

### 1.2 代码提交全链路时序图

```
开发者本地                          GitHub CI                         Release
───────────                        ─────────                        ─────────
git add <src>
git commit
  │
  ├─ pre-commit hook ──────────┐
  │   ├─ SA: tests → build     │
  │   │   → git add dist/sa    │   ← BUG #1: build-dist.sh 内嵌测试
  │   ├─ PH: shellcheck        │
  │   │   → build-dist.sh      │   ← BUG #1: build-dist.sh 又跑一次测试
  │   │   → git add dist/ph    │   ← BUG #1: 只 add dist/，不管源码
  │   ├─ DR: build → add dist  │
  │   └─ staleness guard       │   ← BUG #1: 无源码时仍 add dist
  │                             │
  └─ commit 完成                │
                                │
git push                        │
  ├─ pre-push hook              │
  │   └─ check-dist-freshness   │
  │                             │
  └─ push to remote ────────────┤
                                │
      ci.yml 触发 ──────────────┘
        ├─ detect (path-filter)
        ├─ release-discipline
        ├─ per-plugin:
        │   ├─ test    ◄──────── 测试第 2 次
        │   ├─ lint
        │   ├─ typecheck
        │   └─ build   ◄──────── 测试第 3 次 (build-dist.sh 内嵌)
        │       └─ dist-freshness
        └─ summary (唯一 required check)
                                          ┌─ release-please action
      main push ──► release-please.yml ───┤
                                          └─ post-release job
                                              ├─ build dist
                                              ├─ update README/versions
                                              ├─ git add dist/ + metadata
                                              └─ git commit + push
                                                  └─ 触发 ci.yml
                                                      └─ skip_ci=true (bot)
```

### 1.3 测试执行冗余矩阵

| 执行点 | SA 测试 | PH 测试 | 触发条件 |
|--------|---------|---------|----------|
| pre-commit hook Part 1 | `run_all.sh` (全量) | — | SA 源码 staged |
| pre-commit hook Part 3 | — | `build-dist.sh` 内嵌 `bun test` | PH 源码 staged |
| CI `sa-test` / `ph-test` | `run_all.sh` + smoke | `bun test` (via Makefile) | path-filter 命中 |
| CI `sa-build` / `ph-build` | `build-dist.sh` (不含测试) | `build-dist.sh` (含 `bun test`) | 依赖 test job |
| pre-push hook | — | — | 仅 freshness check |
| release post-release | `build-dist.sh` (不含测试) | `build-dist.sh` (含 `bun test`) | release created |

**关键发现**: `spec-autopilot/tools/build-dist.sh` 不含测试，是纯构建脚本；但 `parallel-harness/tools/build-dist.sh` 在构建前强制执行测试（步骤 2/5 + 3/5）。两个插件的 build 脚本设计不一致。

---

## 2. BUG 复现与根因深度分析

### 2.1 BUG #1: 本地提交只包含 dist，不包含源码

#### 复现路径

```bash
# 场景 A: 常规开发提交
vim plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts
git add plugins/parallel-harness/runtime/engine/orchestrator-runtime.ts
git commit -m "fix(parallel-harness): xxx"
# → pre-commit hook 触发 build-dist.sh
# → build-dist.sh 内部 bun test || true 吞掉测试失败
# → 重建 dist → git add dist/parallel-harness/
# → 提交包含源码 + dist ← 此场景正常

# 场景 B: rebase 后 dist 过期（核心 BUG 路径）
git rebase main
# → dist/ 与源码不一致
git add plugins/parallel-harness/runtime/xxx.ts   # 可能忘记 stage
git commit -m "fix: ..."
# → pre-commit hook:
#   Part 3: PH_CHANGED=yes (如果有 staged PH 文件)
#   Part 3.5: staleness guard 检测到 dist 过期
#   → 自动重建 dist → git add dist/parallel-harness/
#   → 但源码的其他文件可能未被 staged
#   → 提交仅含 dist/

# 场景 C: AI Agent (Droid/Claude) 自动提交
# Agent 可能只关注 dist/ 产物，不显式 stage 源码
# pre-commit staleness guard 自动 add dist/
# → 提交仅含 dist/
```

#### 根因链

```
根因 1: build-dist.sh 职责耦合
  ├── 混合了「测试」和「构建」两个独立关注点
  ├── || true 吞掉测试失败，让构建静默继续
  └── 在 pre-commit / CI build / release 三个上下文中行为不一致

根因 2: pre-commit hook 的 git add 策略不完整
  ├── git add dist/<plugin>/ 只添加产物
  ├── 不验证源码是否已经 staged
  └── staleness guard 无条件重建 + add，不考虑当前 commit 语义

根因 3: build-dist.sh 的 test 输出解析脆弱
  ├── 依赖 grep -oE '[0-9]+ fail' 解析 bun test 输出
  ├── bun 版本升级可能改变输出格式
  └── 测试崩溃（非正常退出）时无 summary 行，FAIL_COUNT 默认 "0"
```

#### 关键代码定位

**`plugins/parallel-harness/tools/build-dist.sh:38`**:
```bash
TEST_OUTPUT=$(bun test --timeout 15000 2>&1) || true  # ← || true 吞掉所有失败
```

**`.githooks/pre-commit:238-239`**:
```bash
if bash plugins/parallel-harness/tools/build-dist.sh; then
  git add dist/parallel-harness/                        # ← 只 add dist
```

**`.githooks/pre-commit:254-265`** (staleness guard):
```bash
if [ "${PH_DIST_REBUILT:-}" != "yes" ] && ...; then
  if ! bash scripts/check-dist-freshness.sh parallel-harness 2>/dev/null; then
    # 无条件重建 + git add dist/，即使没有源码 staged
    if bash plugins/parallel-harness/tools/build-dist.sh; then
      git add dist/parallel-harness/                    # ← BUG: 可能是唯一 staged 内容
```

### 2.2 BUG #2: 测试总是失败

#### CI 失败链分析（基于最近 5 次 CI 运行）

```
运行 #24121922178 (main push, 2026-04-08):
  sa-test: FAILURE (1274 passed, 2 failed — behavior 类别)
  sa-build: SKIPPED (依赖 sa-test)
  ph-*: ALL SUCCESS
  dr-*: ALL SUCCESS
  summary: FAILURE (sa-test + sa-build 失败)

运行 #24068573164 (main push, 2026-04-07):
  sa-test: FAILURE (同上)
  ph-*: ALL SUCCESS
  dr-*: ALL SUCCESS
  summary: FAILURE

运行 #24020835120 (CI Sweep, 2026-04-06):
  workflow lint (actionlint): FAILURE
  summary: FAILURE
```

#### 根因链

```
根因 1: SA 测试存在 2 个持续失败的 behavior 测试
  ├── 102 个测试文件，1274 passed / 2 failed
  ├── 失败测试属于 behavior 类别
  └── 在 ubuntu-latest 上稳定复现（非 flaky）

根因 2: 单插件失败阻断全仓 CI
  ├── shared infra 变更 → ALL plugins 触发
  ├── sa-test 失败 → sa-build skipped → summary FAIL
  ├── PH/DR 完全通过但整体 CI 被判定为失败
  └── summary 将 "skipped"（因依赖失败而跳过）也视为失败（正确但加剧问题）

根因 3: build-dist.sh 在 CI build 阶段重复执行测试
  ├── CI ph-build 调用 make ph-build → build-dist.sh
  ├── build-dist.sh 步骤 2/5: tsc --noEmit（重复 ph-typecheck 的工作）
  ├── build-dist.sh 步骤 3/5: bun test（重复 ph-test 的工作）
  └── 测试冗余执行增加失败概率，浪费 CI 资源

根因 4: CI Sweep 的 actionlint 失败
  ├── workflow YAML 语法问题
  └── 属于 CI 配置自身的质量债
```

#### 关键数据

| 指标 | 值 |
|------|-----|
| SA 测试总数 | 1274 |
| SA 稳定失败数 | 2 |
| PH 测试总数 | 295+ |
| PH CI 通过率 | 100% (近期) |
| PH build-dist.sh 测试执行次数/提交 | 3 次 (hook + CI test + CI build) |
| CI 浪费时间/run | ~10-15 min (重复测试 + 被阻断的等待) |

### 2.3 BUG #3: 全链路不匹配的结构性问题

```
问题域                          现状                              应有状态
─────────                      ─────                             ─────────
build 脚本设计     SA: 纯构建 ≠ PH: 测试+构建         统一为纯构建脚本
测试执行位置       hook/CI-test/CI-build 三处冗余       hook: 快速检查; CI: 一次执行
pre-commit add     只 add dist/，不校验源码             校验源码已 staged 或联合 add
|| true 错误处理   静默吞掉失败                        显式失败，立即终止
staleness guard    无条件重建，不看 commit 语义          仅在有 staged 源码时触发
CI 插件隔离        shared 变更触发全部，单点故障全局     每插件独立 summary
test 输出消费      grep 正则解析 bun 输出               使用 exit code 直接判断
```

---

## 3. 开源社区竞品对标

### 3.1 Build 与 Test 分离

| 项目/工具 | 策略 | 本仓对比 |
|-----------|------|----------|
| **Turborepo** | `turbo run build` 和 `turbo run test` 是独立 pipeline，互不包含 | PH `build-dist.sh` 内嵌 test，违反 SRP |
| **Nx** | `nx run project:build` 和 `nx run project:test` 严格分离，通过依赖图声明前置关系 | PH build 隐式依赖 test 通过 |
| **Moon** (moonrepo) | task 配置显式声明 `deps: ["~:test"]`，runner 不重复执行已完成的任务 | CI 中 ph-build 依赖 ph-test 但 build-dist.sh 自己又跑一遍 |
| **Changesets** | `changeset publish` 只做 publish，不包含 test | `build-dist.sh` 应只做 build |

**社区共识**: Build 脚本 (build-dist.sh) 的唯一职责是生成产物。测试由上游 task 或 CI job 保证。

### 3.2 Pre-commit Hook 最佳实践

| 工具 | 策略 | 本仓对比 |
|------|------|----------|
| **lint-staged** | 只对 staged 文件运行 linter/formatter，通过 `git stash --keep-index` 隔离工作区 | hook 直接在工作区运行 build |
| **Lefthook** | 声明式 YAML 配置，内建 `staged_files` 过滤，不允许 hook 修改 index | hook 通过 `git add dist/` 修改 index |
| **pre-commit (Python)** | 每个 hook 在隔离环境运行，明确区分 read-only check 和 mutating hook | hook 混合 read-only check 和 mutating build |
| **Husky + nano-staged** | hook 只做校验，不做构建 | hook 做完整 build + test + git add |

**社区共识**:
1. Pre-commit hook 应该是**快速的 lint/format 检查**，不做耗时构建
2. 如果必须修改 staging area，需要用 `git stash --keep-index` 隔离
3. 产物构建应放在 CI 或 pre-push，而非 pre-commit

### 3.3 Git-tracked dist/ 的替代方案

| 方案 | 代表项目 | 优缺点 |
|------|----------|--------|
| **git-tracked dist/** (当前) | Claude plugin 生态要求 | 需要 pre-commit 同步，容易 stale |
| **CI-only build + artifact** | npm 包生态 | 不适用 (Claude marketplace 需要 git 分发) |
| **GitHub Actions + release asset** | Go 项目 (goreleaser) | marketplace 不支持 |
| **git-tracked dist/ + CI rebuild verify** | 当前 + 最佳实践加强 | 保留 git-tracked，但通过 CI 校验一致性 |

**结论**: 由于 Claude plugin marketplace 的分发机制，git-tracked `dist/` 是必须的。但**产物同步应由 CI 保证**，而非在 pre-commit 中执行完整构建。

### 3.4 CI 冗余测试消除

| 项目 | 策略 |
|------|------|
| **Nx Cloud** | Remote caching — 同一 hash 的 task 不重复执行 |
| **Turborepo** | Content-addressable cache — CI 中 build 自动跳过已通过的 test |
| **GitHub Actions** | 通过 job dependency (`needs:`) 保证执行顺序，不在 build step 中重跑 test |

**推荐**: `build-dist.sh` 移除测试步骤 → CI 通过 `needs: [ph-test]` 保证构建前测试已通过 → 消除冗余。

### 3.5 `|| true` 反模式

**社区铁律**: CI/构建脚本中 `|| true` 仅用于「允许命令不存在」或「收集非关键诊断信息」。**绝不用于吞掉关键步骤的失败**。

替代方案:
```bash
# ❌ 反模式
TEST_OUTPUT=$(bun test 2>&1) || true

# ✅ 正确做法 1: 直接用 exit code
bun test || { echo "Tests failed"; exit 1; }

# ✅ 正确做法 2: 需要捕获输出时
set +e
TEST_OUTPUT=$(bun test 2>&1)
TEST_EXIT=$?
set -e
if [ "$TEST_EXIT" -ne 0 ]; then
  echo "$TEST_OUTPUT"
  exit 1
fi
```

---

## 4. 彻底修复方案

### 4.1 架构目标

```
修复后链路:

git add <src>
git commit
  │
  ├─ pre-commit hook (重构) ──────┐
  │   ├─ lint only (快速)          │  ← 不做构建，不做测试
  │   ├─ version consistency       │  ← read-only check
  │   └─ staged-files check        │  ← 校验源码+dist一致性警告
  │                                │
  └─ commit (源码 only) ──────────┘

git push
  ├─ pre-push hook (重构) ─────────┐
  │   ├─ dist freshness check      │  ← 仅检查，不自动重建
  │   └─ 提示: make ph-build       │
  │                                │
  └─ push to remote ───────────────┘

CI (ci.yml):
  ├─ detect
  ├─ release-discipline
  ├─ per-plugin (并行):
  │   ├─ lint
  │   ├─ typecheck
  │   ├─ test                      ← 唯一一次测试
  │   └─ build                     ← 纯构建 (不含测试)
  │       └─ dist-freshness
  └─ per-plugin-summary            ← 每插件独立 summary
  └─ summary                       ← 聚合
```

### 4.2 修复项总表

| # | 修复项 | 影响文件 | 解决的 BUG |
|---|--------|----------|-----------|
| F1 | `build-dist.sh` 拆分: 移除测试步骤 | `plugins/parallel-harness/tools/build-dist.sh` | #1, #2, #3 |
| F2 | 新增 `build-dist-only.sh` 纯构建脚本 | `plugins/parallel-harness/tools/build-dist-only.sh` (或 `--skip-test` flag) | #1, #2, #3 |
| F3 | pre-commit hook 重构: 移除构建，只做 lint + check | `.githooks/pre-commit` | #1 |
| F4 | pre-push hook 强化: 添加源码 staged 检查 | `.githooks/pre-push` | #1 |
| F5 | CI build step 使用纯构建脚本 | `.github/workflows/ci.yml` | #2, #3 |
| F6 | CI per-plugin 独立 summary | `.github/workflows/ci.yml` | #2 |
| F7 | Makefile 新增 `ph-build-only` target | `Makefile` | #3 |
| F8 | release post-release 使用纯构建脚本 | `.github/workflows/release-please.yml` | #3 |
| F9 | 移除 `|| true` 反模式 | `plugins/parallel-harness/tools/build-dist.sh` | #1 |
| F10 | `check-dist-freshness.sh` 增加 `--no-rebuild` 模式 | `scripts/check-dist-freshness.sh` | #1 |

### 4.3 F1: `build-dist.sh` 重构 — 移除测试，引入 `--skip-test` 模式

**当前** (`plugins/parallel-harness/tools/build-dist.sh`):
```bash
# 步骤 1/5: 安装依赖       ← 保留
# 步骤 2/5: tsc --noEmit    ← 移除 (CI typecheck job 负责)
# 步骤 3/5: bun test         ← 移除 (CI test job 负责)
# 步骤 4/5: 构建 dist        ← 保留
# 步骤 5/5: BUILD_MANIFEST   ← 保留
```

**修复后**:
```bash
#!/usr/bin/env bash
# build-dist.sh — parallel-harness 构建脚本
# 职责: 生成 dist/ 产物。测试和类型检查由 CI / Makefile 独立保证。
set -euo pipefail

PLUGIN_NAME="parallel-harness"
PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_DIR/../.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/$PLUGIN_NAME"

cd "$PLUGIN_DIR"

# 清理 git hook 注入的环境变量（测试中会创建临时仓库）
while IFS= read -r git_var; do
  unset "$git_var"
done < <(git rev-parse --local-env-vars)

echo "=== parallel-harness 构建流程 ==="

# ── 可选前置检查（仅 --full 模式，用于手动本地构建）──
FULL_MODE=false
for arg in "$@"; do
  case "$arg" in
    --full) FULL_MODE=true ;;
  esac
done

# 1. 安装依赖
echo "--- 步骤 1/3: 安装依赖 ---"
bun install --frozen-lockfile 2>/dev/null || bun install
echo "依赖安装完成"

if [ "$FULL_MODE" = "true" ]; then
  echo ""
  echo "--- [full] TypeScript 类型检查 ---"
  bunx tsc --noEmit
  echo "类型检查通过"

  echo ""
  echo "--- [full] 运行测试 ---"
  bun test --timeout 15000
  echo "测试通过"
fi

# 2. 构建 dist
echo ""
echo "--- 步骤 2/3: 构建 dist 产物 → $DIST_DIR ---"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp -r .claude-plugin "$DIST_DIR/"
cp -r runtime       "$DIST_DIR/"
cp -r skills        "$DIST_DIR/"
cp -r config        "$DIST_DIR/"

if grep -q "<!-- DEV-ONLY-BEGIN -->" CLAUDE.md 2>/dev/null; then
  sed '/<!-- DEV-ONLY-BEGIN -->/,/<!-- DEV-ONLY-END -->/d' CLAUDE.md > "$DIST_DIR/CLAUDE.md"
else
  cp CLAUDE.md "$DIST_DIR/"
fi

# 校验: dist 不包含禁止路径
for forbidden in node_modules tests tools bun.lock "*.tsbuildinfo"; do
  if compgen -G "$DIST_DIR/$forbidden" > /dev/null 2>&1; then
    echo "ERROR: dist 包含不应存在的路径: $forbidden"
    exit 1
  fi
done

DIST_SIZE=$(du -sh "$DIST_DIR" 2>/dev/null | cut -f1)
echo "dist built: $DIST_SIZE"

# 3. 更新 BUILD_MANIFEST
echo ""
echo "--- 步骤 3/3: 更新 BUILD_MANIFEST ---"
VERSION=$(grep '"version"' package.json | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILT_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > BUILD_MANIFEST.json << EOFMANIFEST
{
  "name": "parallel-harness",
  "version": "${VERSION}",
  "built_at": "${BUILT_AT}",
  "git_branch": "${GIT_BRANCH}",
  "git_commit": "${GIT_COMMIT}"
}
EOFMANIFEST

echo "=== 构建完成 (${VERSION} @ ${GIT_BRANCH}) ==="
```

**设计要点**:
- 默认模式 (无参数): 纯构建，不含测试/类型检查 — 用于 CI build step / pre-commit / release
- `--full` 模式: 包含 typecheck + test — 用于开发者本地 `make ph-build` 手动验证
- 移除 `|| true` — 所有步骤使用 `set -euo pipefail` 严格模式
- 移除脆弱的 regex 输出解析 — 直接用 exit code 判断

### 4.4 F3: pre-commit hook 重构

**设计原则** (对标 lint-staged / lefthook):
1. **快速** — pre-commit 应在 5 秒内完成
2. **不做构建** — 产物构建移到 pre-push 或手动 make
3. **不修改 staging area** — 不做 `git add`
4. **只做校验** — lint, format check, version consistency

**修改后的 pre-commit hook 关键部分 (PH 段)**:

```bash
# ============================================
# Part 3: parallel-harness — lint only
# ============================================
PH_CHANGED="no"
if grep -q "plugins/parallel-harness/" <<< "$_CACHED_NAMES"; then
  PH_CHANGED="yes"
fi

if [ "$PH_CHANGED" = "yes" ]; then
  PH_SUBSTANTIVE=$(git diff --cached --name-only --diff-filter=ACM \
    | grep -E '^plugins/parallel-harness/' \
    | grep -vE '(CHANGELOG\.md|README\.md|README\.zh\.md|\.claude-plugin/plugin\.json|package\.json|docs/|reports/)' || true)

  if [ -n "$PH_SUBSTANTIVE" ]; then
    # lint build script (与 CI make ph-lint 对齐)
    if command -v shellcheck >/dev/null 2>&1; then
      echo "🔍 shellcheck parallel-harness build script..."
      if ! shellcheck plugins/parallel-harness/tools/build-dist.sh; then
        echo "❌ parallel-harness shellcheck failed."
        exit 1
      fi
    fi

    # 提醒 dist 可能需要重建（不自动重建）
    echo "ℹ️  parallel-harness 源码已修改，提交后请运行 'make ph-build' 重建 dist/"
    echo ""
  fi
fi

# ============================================
# Part 3.5: parallel-harness dist staleness 警告 (不自动重建)
# ============================================
if [ -d "plugins/parallel-harness" ] && [ -d "dist/parallel-harness" ]; then
  if ! bash scripts/check-dist-freshness.sh parallel-harness 2>/dev/null; then
    echo "⚠️  dist/parallel-harness/ 与源码不一致"
    echo "   提交后请运行 'make ph-build && git add dist/parallel-harness/' 更新"
    echo ""
    # 不阻断提交，不自动重建 — 由 CI dist-freshness 兜底
  fi
fi
```

**对 SA 和 DR 做同样的改造**: 移除所有 `git add dist/` 和自动重建逻辑。

### 4.5 F5 + F6: CI 重构 — 纯构建 + 独立 summary

**CI build step 改动** (`ci.yml` `ph-build` job):

```yaml
ph-build:
  needs: [detect, release-discipline, ph-typecheck, ph-test, ph-lint]
  # ... (条件不变)
  steps:
    - uses: actions/checkout@v5
    - uses: oven-sh/setup-bun@v2
      with:
        cache: true
        cache-dependency-path: plugins/parallel-harness/bun.lock
    - name: Install dependencies
      run: cd plugins/parallel-harness && bun install --frozen-lockfile
    - name: Build dist (no test — already passed in ph-test)
      run: make ph-build-only      # ← 新增 Makefile target，调用不含测试的 build
    - name: Verify dist structure
      run: |
        test -d dist/parallel-harness/.claude-plugin
        # ... (不变)
    - name: Check dist freshness
      if: needs.detect.outputs.skip_dist_stale != 'true'
      run: bash scripts/check-dist-freshness.sh parallel-harness --ci-git-check
```

**独立 summary 改造** — 将 summary 从「一个 job 聚合所有」改为「每插件有独立 summary + 全局 summary」:

```yaml
# 每插件 summary (允许其他插件独立通过)
ph-summary:
  name: parallel-harness / Summary
  needs: [detect, ph-typecheck, ph-test, ph-lint, ph-build]
  if: always() && needs.detect.outputs.run_ph == 'true'
  runs-on: ubuntu-latest
  steps:
    - name: Evaluate PH results
      run: |
        FAILED=0
        for job in ph-typecheck ph-test ph-lint ph-build; do
          case "$job" in
            ph-typecheck) RESULT="${{ needs.ph-typecheck.result }}" ;;
            ph-test)      RESULT="${{ needs.ph-test.result }}" ;;
            ph-lint)      RESULT="${{ needs.ph-lint.result }}" ;;
            ph-build)     RESULT="${{ needs.ph-build.result }}" ;;
          esac
          if [ "$RESULT" != "success" ]; then
            echo "❌ $job: $RESULT"
            FAILED=1
          else
            echo "✅ $job: $RESULT"
          fi
        done
        [ "$FAILED" -eq 0 ] || exit 1

# 全局 summary (branch protection required check)
summary:
  name: CI Summary
  needs: [detect, release-discipline, sa-summary, ph-summary, dr-summary]
  if: always()
  runs-on: ubuntu-latest
  steps:
    - name: Evaluate results
      run: |
        # ... 评估每个 *-summary 的结果，而非每个细粒度 job
```

**优势**: SA 测试失败只影响 `sa-summary`，PH/DR 仍可独立通过。全局 summary 仍然聚合所有结果确保 branch protection 完整性。

### 4.6 F7: Makefile 新增 target

```makefile
ph-build-only: ## Build parallel-harness dist/ (dist only, no test/typecheck)
	@bash $(PH)/tools/build-dist.sh

ph-build: ## Build parallel-harness dist/ (full: typecheck → test → dist)
	@bash $(PH)/tools/build-dist.sh --full
```

### 4.7 F8: release-please.yml 适配

```yaml
- name: Build parallel-harness dist
  if: needs.release-please.outputs.ph_release_created == 'true'
  run: |
    cd plugins/parallel-harness
    bun install --frozen-lockfile
    bash tools/build-dist.sh       # ← 默认模式: 纯构建，不含测试
```

由于 `build-dist.sh` 默认已经不含测试，release post-release 不需要额外改动（只需确认不传 `--full`）。

### 4.8 F9: 消除 `|| true` 反模式

在 F1 中已体现。额外需要审计全仓库的 `|| true` 使用:

```bash
# 需要审计的 || true 使用点:
# 1. build-dist.sh:38 — 已修复 (F1)
# 2. pre-commit hook 中的 grep || true — 正确使用 (防止 pipefail)
# 3. check-dist-freshness.sh — 正确使用 (grep 无匹配)
```

### 4.9 F10: `check-dist-freshness.sh` 纯检查模式

现有的 `--rebuild` / `--git-add` flag 继续保留但 **pre-commit 中不再使用**。
新增 `--warn-only` flag 返回 0 但输出警告（用于 pre-commit 非阻断提示）。

---

## 5. 逐文件改动清单

### 5.1 `plugins/parallel-harness/tools/build-dist.sh`

| 行号 | 改动 | 说明 |
|------|------|------|
| 1-4 | 更新注释 | 移除「类型检查 → 运行测试」描述 |
| 13-16 | 保留 | GIT_* 清理仍需要 |
| 23-25 | 保留 | 步骤 1: 安装依赖 |
| 28-32 | **移除** (默认) / 改为 `--full` 守护 | 步骤 2: tsc --noEmit |
| 36-50 | **移除** (默认) / 改为 `--full` 守护 | 步骤 3: bun test + regex 解析 |
| 52-81 | 保留 | 步骤 4: 构建 dist |
| 83-118 | **简化** | 步骤 5: BUILD_MANIFEST 移除 test_count 等测试指标 |

### 5.2 `.githooks/pre-commit`

| 段落 | 改动 | 说明 |
|------|------|------|
| Part 0, 0.5 | 不变 | hooksPath 保护 + release-please bypass |
| Part 1 | 不变 | SA 测试（SA 独立于本修复） |
| Part 1.5, 1.7 | 不变 | SA 测试覆盖检查 + lint |
| Part 2 | 不变 | SA version consistency (read-only) |
| Part 2.5 | **重构**: 移除 `build-dist.sh` 调用和 `git add` | 改为 lint-only 或 freshness 警告 |
| Part 2.7 | **重构**: 移除自动重建 + `git add` | 改为警告 |
| Part 3 | **重构**: 移除 `build-dist.sh` 调用和 `git add` | 只保留 shellcheck |
| Part 3.5 | **重构**: 移除自动重建 + `git add` | 改为警告 |
| Part 3.6 | **重构**: 移除 `build-dist.sh` 调用和 `git add` | 改为警告 |
| Part 3.7 | **重构**: 移除自动重建 + `git add` | 改为警告 |
| Part 4 | 不变 | 基础设施 lint |

### 5.3 `.githooks/pre-push`

| 改动 | 说明 |
|------|------|
| 现有 freshness check 保留 | 继续检查 dist 一致性 |
| **新增**: 阻断推送当 dist stale | 提示 `make ph-build && git add dist/ && git commit --amend` |

### 5.4 `.github/workflows/ci.yml`

| 改动 | 说明 |
|------|------|
| `ph-build` step 改为 `make ph-build-only` | 纯构建，不含测试 |
| `sa-build` step 不变 | SA `build-dist.sh` 本就不含测试 |
| 新增 `sa-summary`, `ph-summary`, `dr-summary` jobs | 每插件独立 summary |
| `summary` job 改为聚合 `*-summary` | 减少细粒度 job 评估 |

### 5.5 `Makefile`

| 改动 | 说明 |
|------|------|
| 新增 `ph-build-only` target | 调用 `build-dist.sh` (无参数，纯构建) |
| `ph-build` 改为调用 `build-dist.sh --full` | 保留开发者本地完整验证 |
| `ph-ci` 不变 | 仍为 `lint → typecheck → test → build` |

### 5.6 `.github/workflows/release-please.yml`

| 改动 | 说明 |
|------|------|
| PH build step 确认调用 `build-dist.sh` (无 `--full`) | 已是默认行为，确认无额外参数 |

### 5.7 `scripts/check-dist-freshness.sh`

| 改动 | 说明 |
|------|------|
| 新增 `--warn-only` flag | 返回 0 但输出警告，用于 pre-commit |

---

## 6. 迁移策略与验证矩阵

### 6.1 迁移步骤

```
Phase 1: build-dist.sh 重构 (F1 + F7 + F9)
  ├─ 改造 build-dist.sh 为默认纯构建 + --full 模式
  ├─ Makefile 新增 ph-build-only
  └─ 本地验证: make ph-build-only && make ph-build

Phase 2: pre-commit hook 重构 (F3 + F10)
  ├─ 移除所有 git add dist/ 和自动重建逻辑
  ├─ 改为 lint + 警告
  └─ 本地验证: git add + git commit 确认 hook 不再修改 staging area

Phase 3: CI 重构 (F5 + F6)
  ├─ ci.yml: build step 改用 ph-build-only
  ├─ ci.yml: 新增 per-plugin summary
  └─ PR 验证: 创建只修改 PH 的 PR，确认 SA 失败不阻断 PH

Phase 4: Release 适配 (F8)
  ├─ release-please.yml 确认使用纯构建
  └─ dry-run 验证

Phase 5: pre-push 强化 (F4)
  ├─ 推送前检查 dist freshness
  └─ 阻断 stale dist 的推送
```

### 6.2 验证矩阵

| 场景 | 修复前行为 | 修复后预期行为 | 验证方法 |
|------|-----------|---------------|----------|
| 开发者修改 PH 源码 + commit | hook build + test + `git add dist/` | hook lint + 警告 dist 需重建 | `git commit` 观察输出 |
| 开发者只修改 dist/ (手动) | hook 通过 | hook 通过 + 警告 dist 与源码不一致 | `git add dist/ && git commit` |
| rebase 后 dist 过期 + commit | hook 自动重建 dist + `git add dist/` | hook 警告 dist 过期，不阻断 | `git rebase main && git commit` |
| CI PH test pass + build | build-dist.sh 再跑一次测试 | build-dist.sh 只构建 dist | 观察 CI log |
| CI SA test fail | 整个 CI 失败 (含 PH/DR) | SA summary 失败，PH/DR summary 通过 | 观察 CI summary |
| release post-release | build-dist.sh 跑测试 | build-dist.sh 只构建 | 触发 release 观察 |
| `make ph-build` (开发者手动) | typecheck + test + build | typecheck + test + build (`--full`) | `make ph-build` |
| `make ph-build-only` (CI) | — (新增) | 只构建 dist | `make ph-build-only` |
| pre-push dist stale | 阻断推送 | 阻断推送 + 明确提示 | `git push` with stale dist |

### 6.3 回滚方案

每个 Phase 为独立 commit，可单独 revert:
- Phase 1 revert: `build-dist.sh` 恢复内嵌测试
- Phase 2 revert: pre-commit 恢复自动重建
- Phase 3 revert: ci.yml 恢复旧 summary 结构
- Phase 4 revert: release-please.yml 恢复
- Phase 5 revert: pre-push 恢复

---

## 附录 A: 与 spec-autopilot build-dist.sh 的对比

| 维度 | spec-autopilot | parallel-harness (现状) | parallel-harness (修复后) |
|------|---------------|------------------------|-------------------------|
| 测试执行 | 不含测试 | 内嵌 tsc + bun test | 不含测试 (默认) |
| 错误处理 | `set -euo pipefail` | `|| true` 吞掉失败 | `set -euo pipefail` |
| 构建步骤 | 8 步 (含校验) | 5 步 (含测试) | 3 步 (纯构建) |
| 产物校验 | manifest 驱动 + 结构验证 | 禁止路径检查 | 禁止路径检查 (保留) |
| CI 调用 | `make build` (纯构建) | `make ph-build` (含测试) | `make ph-build-only` (纯构建) |

## 附录 B: 相关开源参考

| 项目 | 链接 | 参考点 |
|------|------|--------|
| Turborepo | https://turbo.build/repo | 任务分离 + 缓存; `dependsOn` 不混合 build/test |
| Nx | https://nx.dev | 文件级依赖图 + affected 检测 |
| Moonrepo | https://moonrepo.dev | task 自动分类 (build/run/test) |
| lint-staged v15+ | https://github.com/lint-staged/lint-staged | 自动 restage + backup stash; 不再需要手动 `git add` |
| Lefthook | https://github.com/evilmartians/lefthook | 声明式 hook + `stage_fixed: true` |
| git-format-staged | https://github.com/hallettj/git-format-staged | 直接操作 git object，最安全的 staging area 处理 |
| pre-commit (Python) | https://github.com/pre-commit/pre-commit | stash-based 隔离，但有 stash pop 冲突风险 |
| release-please | https://github.com/googleapis/release-please | 当前使用的发版工具 |
| changesets | https://github.com/changesets/changesets | 版本管理替代方案参考 |

## 附录 D: pre-commit `git add` 的已知风险 (社区共识)

参考 jyn514 "[pre-commit hooks are fundamentally broken](https://jyn.dev/pre-commit-hooks-are-fundamentally-broken/)" 和 `git-format-staged` 项目的分析:

### 风险 1: 破坏 partial staging

`git add <file>` 在 pre-commit 中会将**整个文件**加入 index，覆盖开发者通过 `git add -p` 精心挑选的 hunk。开发者可能无意中提交了调试代码、临时密码等未打算 staged 的内容。

### 风险 2: hook 运行在 working tree 而非 index

pre-commit hook 检查的是工作目录的文件，而非 staging area 中的版本。文件在工作目录中可能通过校验，但 staged 的版本（实际会被提交的）可能仍然有问题。

### 风险 3: Rebase 灾难

`git rebase` 时 pre-commit hook 对每个 replay 的 commit 都会触发。如果 hook 在这些旧 commit 创建之后才添加，会对开发者没有修改的代码报错。唯一逃生方式是 `--no-verify`。

### 风险 4: Stash-based 隔离脆弱

`git stash --keep-index` 是常见的缓解方案，但: 会破坏 index 状态，与 overlapping 的未 staged 变更产生 merge conflict，hook 失败时可能丢失变更。

### 社区推荐安全等级

| 方案 | 安全性 | 本仓适用性 |
|------|--------|-----------|
| `git-format-staged` | 最高 (直接操作 git objects) | 适用于 format/lint |
| lint-staged v15+ (默认配置) | 高 (自动 restage + backup) | 适用于 lint |
| Lefthook `stage_fixed: true` | 高 (原生 staged-file 过滤) | 适用于 lint |
| 手动 `git add` (当前方案) | **危险** | **本次修复的核心** |
| 无 hook，CI-only 校验 | 最安全 (对 git) | 反馈慢，但最可靠 |

## 附录 C: SA 测试失败修复（补充）

当前 main 分支 SA 测试存在 2 个稳定失败的 behavior 测试 (1274 passed / 2 failed)。此问题独立于本方案的架构修复，但属于 CI 红线:

**建议**: 在 Phase 3 (CI 重构) 之前，先定位并修复这 2 个 SA 失败测试。否则即使 CI 做了 per-plugin summary，SA summary 仍然持续失败。

定位方式:
```bash
cd plugins/spec-autopilot
bash tests/run_all.sh 2>&1 | grep -B5 "FAIL"
```

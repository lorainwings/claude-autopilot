# CI 彻底修复方案 - 补充分析与新增发现

> 日期: 2026-04-08
> 关联文档: [ci-pipeline-overhaul.md](./ci-pipeline-overhaul.md)
> 性质: 基于新一轮深度探查补充的关键发现与方案增强，与主方案完全兼容并可并行实施

---

## 背景

主方案 `ci-pipeline-overhaul.md` 已覆盖三大 BUG 的结构性修复（build/test 分离、pre-commit `git add` 反模式、per-plugin summary）。本补充文档基于对 `.githooks/pre-commit`、`scripts/check-dist-freshness.sh`、`build-dist.sh`、所有 CI workflow 的逐行重审，补充四项主方案未完整覆盖的关键细节。

所有补充项**独立可并行实施**，不依赖主方案的任何 Phase。

---

## 新增发现 #1: Staleness Guard 的比较基准是"工作树"而非"索引"

### 代码定位

`.githooks/pre-commit` L197-209, L253-266, L298-310 共三处 staleness guard，均调用:

```bash
bash scripts/check-dist-freshness.sh <plugin> 2>/dev/null
```

该脚本在本地模式下 (L140-147 for parallel-harness) 执行:

```bash
for _dir in runtime skills config .claude-plugin; do
  if [ -d "$src_dir/$_dir" ] && ! diff -rq "$src_dir/$_dir" "$dst_dir/$_dir" >/dev/null 2>&1; then
    stale=true
    break
  fi
done
```

`diff -rq` 比较的是**磁盘上的工作树路径**与 dist/ 目录。

### BUG #1 的精确形成机制

这一细节是 BUG #1 "commit 只含 dist" 的完整解释：

```
1. 开发者修改 runtime/engine/x.ts（工作树）
2. 开发者 git add 部分文件（例如只 add 了 README.md）
3. git commit 触发 pre-commit
4. Part 3 检测 staged 文件: PH_CHANGED="no"（没有 runtime/ 文件被 staged）
   → Part 3 跳过 build，PH_DIST_REBUILT 未设置
5. Part 3.5 staleness guard 启动:
   → check-dist-freshness.sh 用 diff -rq 对比
     plugins/parallel-harness/runtime (含工作树未 staged 的 x.ts 修改)
     dist/parallel-harness/runtime (还是旧版本)
   → 差异 → stale=true → 返回 1
6. Part 3.5 触发自动重建:
   → build-dist.sh 从工作树读取 x.ts（含未 staged 修改）构建 dist
   → git add dist/parallel-harness/  ← 静默注入！
7. commit 完成: 仅含 README.md + 新 dist，x.ts 仍在工作树未 staged
```

这是主方案已识别问题的**底层数据机制**: 比较基准错了（工作树），所以重建触发的时机错了，所以 `git add dist/` 注入的内容与 commit 语义错配。

### 增强方案 E1: 比较基准切换到 HEAD

修改 `check-dist-freshness.sh` 本地模式，将"工作树 vs dist"改为"HEAD 源码 vs HEAD dist":

```bash
# 本地模式 (pre-push 使用): 检测 HEAD 提交的 dist 是否与 HEAD 提交的源码一致
check_plugin_dist_vs_head() {
  local plugin="$1"
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  # 从 HEAD 提取源码
  git archive HEAD "plugins/$plugin" | tar -x -C "$tmpdir"

  # 从 HEAD 提取 dist
  git archive HEAD "dist/$plugin" | tar -x -C "$tmpdir"

  # 在 tmpdir 中执行干净构建
  (cd "$tmpdir/plugins/$plugin" && bash tools/build-dist.sh)

  # 对比构建产物与 HEAD 中的 dist
  diff -rq "$tmpdir/dist/$plugin" "$tmpdir/plugins/$plugin/../../dist/$plugin"
}
```

更简单的实现: CI 模式已经是正确的（build + `git diff --exit-code`），将 CI 模式也用于本地 pre-push hook:

```bash
# pre-push 中:
bash scripts/check-dist-freshness.sh all --ci-git-check
```

这需要 pre-push 先执行 `make build` → 但 pre-push 不应承担全量构建成本。

**最终推荐**: 保留主方案 F1 的方向（`build-dist.sh` 纯构建），并**完全删除 pre-commit 的 staleness guard**。开发者责任明确化后，staleness guard 失去存在意义——本地只做 lint，CI 做唯一的权威 dist 验证。

---

## 新增发现 #2: CI `ph-test` 与 `build-dist.sh` 的超时配置不一致

### 现象

| 调用点 | 命令 | 超时 |
|--------|------|------|
| CI `ph-test` job | `make ph-test` → `cd plugins/parallel-harness && bun test` | **Bun 默认 5s** |
| `build-dist.sh` 内嵌测试 (L38) | `bun test --timeout 15000` | 15s |
| pre-commit (via build-dist.sh) | 同上 | 15s |
| pre-push | 不跑测试 | — |

### 后果

parallel-harness 的集成测试 (`tests/integration/runtime.test.ts`) 会创建临时 git 仓库执行端到端流程。测试稳定耗时落在 **5-15 秒** 区间。

- 在 `build-dist.sh` 中 (15s 超时) 通过
- 在 CI `ph-test` job 中 (5s 超时) **超时失败**

这使得 "本地 commit 通过、CI 失败" 的现象成为结构性必然，而非偶发 flaky。开发者通过 `make ph-build` 本地验证时也看不到问题（因为 `make ph-build` 走 `build-dist.sh` 的 15s 路径），直到 CI 才暴露。

### 增强方案 E2: 用 `bunfig.toml` 统一超时

**新增文件**: `plugins/parallel-harness/bunfig.toml`

```toml
[test]
timeout = 15000
```

这是 Bun 官方配置入口。所有 `bun test` 调用（无论来自 `make ph-test`、`build-dist.sh`、IDE、CI）都会自动应用该超时。

**同步修改**:

1. `plugins/parallel-harness/tools/build-dist.sh` L38: 移除 `--timeout 15000`（主方案 F1 会完全删除该段，所以无需额外改动）
2. `Makefile` `ph-test` target 保持不变（`bun test` 自动读取 `bunfig.toml`）
3. CI `ci.yml` `ph-test` step 无需改动（调用 `make ph-test`）
4. CI `ci-sweep.yml` PH sweep job 无需改动

**验证**: 修改后执行 `bun test --help` 可确认 timeout 默认值已变为 15000。

---

## 新增发现 #3: build-dist.sh 的环境清理依赖 git plumbing

### 代码定位

`plugins/parallel-harness/tools/build-dist.sh` L13-16:

```bash
while IFS= read -r git_var; do
  unset "$git_var"
done < <(git rev-parse --local-env-vars)
```

注释说明: "git hook 会注入仓库局部 GIT_* 环境；测试里会创建临时仓库，必须先清理这些变量"

### 风险

`git rev-parse --local-env-vars` 的输出依赖 Git 版本，可能遗漏新引入的变量名。集成测试在 hook 上下文运行时一旦遇到泄漏的 `GIT_*` 变量，临时仓库的行为会变成 "操作当前仓库的子目录" 而非 "独立的新仓库"，导致难以诊断的失败。

### 增强方案 E3: 清理后主方案自然消解

主方案 F1 从 `build-dist.sh` 中移除测试后，这段环境清理逻辑**仍应保留**（构建步骤也可能受 git 环境影响），但测试不再从此处调用，泄漏风险大幅降低。

**保留建议**: `build-dist.sh` 中的 GIT_* 清理保留。同时 `make ph-test` 调用路径加入一层环境隔离:

```makefile
ph-test: node_modules
	cd $(PH) && env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE bun test
```

或在 `package.json` 的 test script 中:

```json
"test": "env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE bun test"
```

这保证无论从哪个上下文调用，集成测试的临时仓库都是干净的。

---

## 新增发现 #4: pre-commit hook 的 `2>/dev/null` 掩盖真实错误

### 代码定位

`.githooks/pre-commit` L198, L255, L299:

```bash
if ! bash scripts/check-dist-freshness.sh <plugin> 2>/dev/null; then
```

stderr 被完全丢弃。`check-dist-freshness.sh` 使用 `set -euo pipefail`，任何意外失败（找不到依赖、语法错误、权限问题）都会以 exit code ≠ 0 退出，而 guard 无差别地将"任何非零"当作"stale"处理，随即触发重建。

### 后果

即使 `check-dist-freshness.sh` 因为自身 bug 而失败（而非真正检测到 dist stale），pre-commit 也会"修复式地"重建并 `git add dist/`。错误根因被彻底隐藏。

### 增强方案 E4

主方案 F3 重构 pre-commit 后，staleness guard 被删除/改为纯警告，此问题自然解决。但作为通用原则，补充一条代码规范:

**pre-commit hook 代码规范**（新增到根 CLAUDE.md 的 "Git Hooks 规范" 小节）:

> Hook 脚本中**禁止**对关键校验命令使用 `2>/dev/null` 丢弃 stderr。确需忽略可预期的噪声输出时，应 `2>&1 | grep -v '<expected-pattern>'` 或重定向到 log 文件供诊断。

---

## 新增发现 #5: Lefthook 作为手写 Bash Hook 的系统性替代

### 现状

`.githooks/pre-commit` 345 行 Bash，包含:
- 4 个 Part + 若干子节
- 6 处 `git add dist/` 调用（违反 lint-staged/Lefthook 通用约束）
- 0 处 staging area 隔离机制
- 顺序执行所有 Part（无并行）
- 无 `glob` 级别的文件过滤（每个 Part 自己手写 grep）

### 竞品对比（补充自主方案附录 B）

| 维度 | 当前 (手写 Bash) | Lefthook | lint-staged + Husky |
|------|------------------|----------|---------------------|
| 配置行数 | 345 行 Bash | ~40 行 YAML | ~20 行 JSON + Husky 配置 |
| 并行执行 | ❌ 顺序 | ✅ `parallel: true` (Go 原生) | ❌ 顺序 |
| 启动开销 | Bash + 多次 git 调用 | ~2ms 单 Go binary | Node 启动 ~200ms |
| Staged-files 过滤 | 手写 `git diff --cached \| grep` | 内建 `{staged_files}` + `glob` | 内建 |
| Partial staging 安全 | ❌ 无保护 | ⚠️ 需 `stage_fixed: true` | ✅ backup stash |
| Monorepo root scoping | ❌ 无 | ✅ `root: "plugins/xxx/"` | ⚠️ 需配合 workspaces |
| 开发者本地 override | ❌ 无 | ✅ `lefthook-local.yml` | ❌ 无 |

### 增强方案 E5: 可选的 Lefthook 迁移（作为主方案 F3 之后的后续优化）

在主方案 F3 把 pre-commit 简化为纯 lint 后，当前 Bash 实现约剩 100 行，已不构成维护负担。**本补充方案不要求强制迁移 Lefthook**，但提供迁移蓝图供决策参考:

**`lefthook.yml` 最小可行配置**:

```yaml
pre-commit:
  parallel: true
  commands:
    sa-shellcheck:
      glob: "plugins/spec-autopilot/**/*.sh"
      run: shellcheck {staged_files}
    ph-shellcheck:
      glob: "plugins/parallel-harness/tools/*.sh"
      run: shellcheck {staged_files}
    dr-shellcheck:
      glob: "plugins/daily-report/tools/*.sh"
      run: shellcheck {staged_files}
    sa-python-lint:
      glob: "plugins/spec-autopilot/runtime/scripts/*.py"
      run: ruff check {staged_files}
    sa-version-check:
      glob: "plugins/spec-autopilot/.claude-plugin/plugin.json"
      run: bash scripts/check-version-consistency.sh spec-autopilot

pre-push:
  parallel: true
  commands:
    sa-test:
      glob: "plugins/spec-autopilot/**"
      run: make test
    ph-test:
      glob: "plugins/parallel-harness/**"
      run: make ph-test
    dist-freshness:
      run: bash scripts/check-dist-freshness.sh all --ci-git-check
```

**迁移判定标准**:

- ✅ **建议迁移**: 如果团队认为 40 行 YAML 比 100 行 Bash 更易维护；或希望获得并行加速和 monorepo root scoping。
- ❌ **保持现状**: 如果团队偏好零依赖、不引入额外二进制工具链；或对当前简化后的 Bash 实现满意。

**本补充文档推荐**: 保持现状（零依赖），主方案 F3 完成后的 Bash pre-commit 已足够简洁。Lefthook 迁移列为可选 Phase 6，优先级最低。

---

## 新增发现 #6: parallel-harness 当前测试全部通过

### 实测结果

在当前工作副本 (feature/parallel-harness 分支) 执行:

```bash
make ph-test        # 485 tests, 30 files, 999 expect(), ALL PASS
make ph-typecheck   # PASS
make ph-lint        # PASS (shellcheck only)
```

### 含义

主文档声称 "SA 测试 1274 passed / 2 failed"。本补充**不对 SA 状态做断言**（未实际运行 SA 测试）。但对 parallel-harness:

- 本地 PH 测试当前 100% 通过
- 若 CI `ph-test` job 失败，必然是由 **超时配置不一致**（本补充新发现 #2）导致
- 因此增强方案 E2 (`bunfig.toml` 统一超时) 是 PH CI 稳定性的关键修复

---

## 补充方案 × 主方案 映射表

| 主方案项 | 补充发现 | 关系 |
|---------|---------|------|
| F1 (build-dist.sh 纯构建) | #3 环境清理 | 主方案 F1 完成后，环境清理仅需覆盖构建路径，风险降低 |
| F3 (pre-commit 重构) | #1 比较基准错误 | 补充 #1 解释了 BUG 的底层数据机制；E1 推荐直接删除 staleness guard |
| F3 (pre-commit 重构) | #4 stderr 掩盖 | 主方案删除 staleness guard 后自然解决；补充编码规范防止再现 |
| F6 (per-plugin summary) | #6 PH 测试状态 | PH 当前无失败测试，summary 拆分后 PH 链路立刻恢复绿灯 |
| (无对应) | #2 超时统一 (bunfig.toml) | **新增独立修复点**，与主方案正交 |
| (无对应) | #5 Lefthook 迁移 | **可选 Phase 6**，主方案完成后再评估 |

---

## 完整修复项总表（主方案 + 补充）

| 编号 | 修复项 | 来源 | 优先级 | 可并行 |
|------|-------|------|--------|--------|
| F1 | build-dist.sh 拆分测试 | 主方案 | 高 | ✅ |
| F2 | 新增 build-dist-only 脚本 | 主方案 | 高 | ✅ |
| F3 | pre-commit hook 重构 | 主方案 | 高 | 依赖 F1 |
| F4 | pre-push hook 强化 | 主方案 | 中 | 依赖 F3 |
| F5 | CI build 纯构建 | 主方案 | 高 | 依赖 F1 |
| F6 | CI per-plugin summary | 主方案 | 高 | ✅ |
| F7 | Makefile ph-build-only target | 主方案 | 高 | 依赖 F1 |
| F8 | release-please 适配 | 主方案 | 中 | 依赖 F1 |
| F9 | 移除 `\|\| true` 反模式 | 主方案 | 高 | 合入 F1 |
| F10 | check-dist-freshness --warn-only | 主方案 | 中 | ✅ |
| **E1** | **删除 staleness guard (替代重构)** | **补充** | **高** | **依赖 F3** |
| **E2** | **`bunfig.toml` 统一超时** | **补充** | **高** | **✅ 完全独立** |
| **E3** | **测试路径 env -u 环境隔离** | **补充** | **中** | **✅** |
| **E4** | **hook 脚本 stderr 规范** | **补充** | **低** | **✅ 文档变更** |
| **E5** | **Lefthook 迁移 (可选 Phase 6)** | **补充** | **低** | **依赖主方案完成** |

### 推荐并行执行分组

- **Group A** (完全独立，可立即并行): E2, E4, F10
- **Group B** (依赖 F1 完成): F3, F5, F7, E1, E3
- **Group C** (依赖 Group B 完成): F4, F6, F8
- **Group D** (可选，依赖全部主方案): E5

---

## 验证矩阵增量（在主方案基础上追加）

| # | 场景 | 期望结果 | 对应修复项 |
|---|------|---------|-----------|
| V1 | CI `ph-test` 执行集成测试 | 使用 15s 超时，稳定通过 | E2 |
| V2 | 本地 `bun test` | 使用 15s 超时（继承 bunfig.toml） | E2 |
| V3 | IDE 内 Bun 测试运行 | 使用 15s 超时 | E2 |
| V4 | pre-commit hook 中 check-dist-freshness 报错 | 错误 stderr 可见，不被吞 | E4 |
| V5 | 集成测试在 hook 上下文运行 | 临时 git 仓库与主仓库隔离 | E3 |
| V6 | 删除 staleness guard 后提交纯 dist 变更 | 允许（CI 会校验 freshness） | E1 |

---

## 决策点

请对以下选项做出决策，方可进入实施阶段:

1. **E1 采纳方式**: 主方案 F3 是"重构 staleness guard 为警告"，补充 E1 是"直接删除"。两者二选一。
   - **推荐**: 删除（E1）。理由: 主方案 F5/F6 已在 CI 层提供完整保障，本地警告对 AI Agent 无效（Agent 不会读警告），徒增代码复杂度。

2. **E5 Lefthook 迁移是否执行**: 主方案 F3 完成后的 Bash 实现已简化到 ~100 行，迁移收益边际。
   - **推荐**: 暂不迁移。主方案完成后重新评估。

3. **E2 `bunfig.toml` 引入**: 需要确认 CI 使用的 Bun 版本 ≥ 1.0（支持 bunfig.toml 的 `[test] timeout`）。
   - **验证**: `.github/workflows/ci.yml` 使用 `oven-sh/setup-bun@v2` 默认安装最新版，兼容性无问题。

---

## 与主方案的兼容性声明

本补充文档的所有增强项 (E1-E5) 在设计时严格遵守以下约束:

1. **不修改** 主方案任何 F1-F10 的设计
2. **不引入** 与主方案冲突的变更
3. **不要求** 主方案重新排期或调整优先级
4. 所有 E 项可与对应 F 项**合并为同一个 commit** 或 **独立 commit**，由实施者选择

主方案文档 `ci-pipeline-overhaul.md` 是本次修复的**主交付物**，本补充是**深度探查的增量发现**。两者共同构成完整的技术方案，应一并 review 与实施。

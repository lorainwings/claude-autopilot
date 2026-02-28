# Phase 5: 循环实施 — 详细流程

> 本文件由 autopilot SKILL.md 引用，执行 Phase 5 时按需读取。

## 启动前安全准备

1. **Git 安全检查点**：在实施任何代码变更前，创建 git tag `autopilot-phase5-start` 标记当前状态
   ```
   git tag -f autopilot-phase5-start HEAD
   ```
   如果 Phase 5 实施失败需要回退，可通过 `git diff autopilot-phase5-start..HEAD` 查看所有变更，或通过 `git stash` 暂存后 `git checkout autopilot-phase5-start` 回退。
2. **记录启动时间戳**：在 `openspec/changes/<name>/context/phase-results/phase5-start-time.txt` 写入 ISO-8601 时间戳，供 wall-clock 超时检查使用。

## Wall-clock 超时机制

- 每次迭代开始时检查已用时间 = 当前时间 - phase5-start-time
- 超过 **2 小时** → 强制暂停，AskUserQuestion：「Phase 5 已运行 {elapsed} 分钟，是否继续？」
- 选项："继续执行" / "保存进度并暂停" / "回退到 Phase 5 起始点"

## 实施流程

1. 检查 `.claude/settings.json` 中 `enabledPlugins` 是否包含 `ralph-loop`
2. **检查 worktree 隔离模式**：读取 `config.phases.implementation.worktree.enabled`
   - **启用** → Phase 5 按 task 粒度派发，每个 task 通过 `Task(isolation: "worktree")` 在独立 worktree 中执行
     - 每个 task 完成后，worktree 变更自动合并回主分支
     - 如有合并冲突 → AskUserQuestion 展示冲突文件，让用户选择处理方式
     - 主线程上下文不被实现代码膨胀
   - **禁用**（默认） → 使用下方 ralph-loop / fallback 策略
3. **ralph-loop 可用** → 构造 ralph-loop 调用参数并执行：

   **参数构造**：
   - PROMPT: 从 config.phases.implementation.instruction_files 中读取指令文件内容，
     拼接为完整实施 prompt（包含 change_name、tasks 路径、测试命令等）
   - --max-iterations: 从 config.phases.implementation.ralph_loop.max_iterations 读取
   - --completion-promise: "所有 tasks.md 中的任务标记为完成且所有测试通过"

   **调用**：
   ```
   Skill("ralph-loop:ralph-loop", args: "使用 Skill('openspec-apply-change') 逐个实施 openspec/changes/<change_name>/ 中的任务。<instruction_files内容摘要> --max-iterations <max_iterations> --completion-promise 所有 tasks.md 中的任务标记为完成且所有测试通过")
   ```

   **完成后**：读取 `openspec/changes/<name>/testreport/test-results.json`，
   从中提取 test_results_path、tasks_completed、zero_skip_check 构造 Phase 5 JSON 信封。
4. **不可用但 config.phases.implementation.ralph_loop.fallback_enabled** → 进入手动循环模式
   - 每次迭代执行 Skill(`openspec-apply-change`) 实施一个任务
   - 每任务后运行 quick_check，每 3 任务运行 full_test
   - 遵循 3 次失败暂停策略
   - 最大迭代次数从 config.phases.implementation.ralph_loop.max_iterations 读取
4. **不可用且 fallback 禁用** → AskUserQuestion：
   ```
   "ralph-loop 插件不可用，手动 fallback 也已禁用。请选择处理方式："
   选项:
   - "启用 fallback 模式 (Recommended)" → 修改 config 中 fallback_enabled 为 true，进入手动循环
   - "暂停流水线，手动安装 ralph-loop" → 展示安装命令，暂停等待
   - "跳过实施阶段（仅测试已有代码）" → 标记 Phase 5 为 warning，继续 Phase 6
   ```

## Phase 5→6 特殊门禁

autopilot-gate 额外验证：
- `test-results.json` 存在
- `zero_skip_check.passed === true`
- `tasks.md` 中所有任务标记为 `[x]`

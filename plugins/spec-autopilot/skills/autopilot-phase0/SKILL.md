---
name: autopilot-phase0
description: "[ONLY for autopilot orchestrator] Phase 0: Environment check, config loading, crash recovery, banner rendering, task creation, and lockfile initialization."
user-invocable: false
---

# Autopilot Phase 0 — 环境检查 + 崩溃恢复

> **前置条件自检**：本 Skill 仅在 autopilot 编排主线程中使用。如果当前上下文不是 autopilot 编排流程，请立即停止并忽略本 Skill。

## 输入参数

| 参数 | 来源 |
|------|------|
| $ARGUMENTS | autopilot 主编排器传入的原始参数 |
| plugin_dir | 插件根目录路径 |

## 执行步骤

### Step 1: 读取插件版本（最优先）

从 `plugin.json` 读取版本号：`Bash("cat <plugin_dir>/.claude-plugin/plugin.json")`

提取 `version` 字段，**立即输出初始化提示**（先于一切其他操作让用户看到版本号）：

```
⏳ Autopilot v{version} initializing...
```

### Step 2: 检查配置文件

检查 `.claude/autopilot.config.yaml` 是否存在：
- **不存在** → 调用 Skill(`spec-autopilot:autopilot-init`) 自动扫描项目并生成配置
- **存在** → 直接读取并解析所有配置节，然后调用 `bash scripts/validate-config.sh` 验证 schema 完整性（valid=false 时展示 missing_keys 并提示修复）

### Step 3: 解析执行模式

```
1. $ARGUMENTS 关键词匹配: "lite"/"minimal"/"full" → 直接使用
2. config.default_mode → 配置默认值
3. 未指定 → "full"

解析: $ARGUMENTS = "[mode_keyword] [actual_requirement]"
  - 首个 token 匹配 full|lite|minimal → 提取为 mode，剩余为需求
  - 不匹配 → mode 从 config 读取，整体为需求
```

### Step 4: 展示启动 Banner

> **渲染规则**: 使用 markdown 代码块输出。框内宽度（左 `│` 与右 `│` 之间）固定 **50 字符**（纯 ASCII，禁止在框内使用 emoji 避免终端宽度歧义），每行内容不足时用空格右填充至 50 字符，确保右侧 `│` 严格垂直对齐。单字段值超长时截断并追加 `…`，保证不溢出框宽。时间使用本地时间格式 `YYYY-MM-DD HH:mm:ss`。

```
╭──────────────────────────────────────────────────╮
│                                                  │
│   Autopilot v{version}                           │
│                                                  │
│   Mode      {mode}                               │
│   Change    {change_name}                        │
│   Session   {session_id}                         │
│   Started   {YYYY-MM-DD HH:mm:ss}               │
│                                                  │
╰──────────────────────────────────────────────────╯
```

- session_id：**此时生成**毫秒级时间戳并暂存，后续步骤 9 写入锁文件时复用同一值
- change_name：此时尚未确定，显示 `pending`（Phase 1 完成后更新锁文件时回填）
- Started：使用 `date "+%Y-%m-%d %H:%M:%S"` 获取本地时间，禁止 ISO-8601 带时区偏移格式

### Step 5: 检查已启用插件

读取 `.claude/settings.json` 的 `enabledPlugins` → 检查已启用插件列表

### Step 6: 崩溃恢复

调用 Skill(`spec-autopilot:autopilot-recovery`)：扫描 checkpoint，决定起始阶段

### Step 7: 创建阶段任务

使用 TaskCreate 创建阶段任务 + blockedBy 依赖链：
- **full 模式**: 创建 Phase 1-7（7 个任务）
- **lite 模式**: 创建 Phase 1, 5, 6, 7（4 个任务），Phase 5 blockedBy Phase 1，Phase 6 blockedBy Phase 5
- **minimal 模式**: 创建 Phase 1, 5, 7（3 个任务），Phase 5 blockedBy Phase 1
- 崩溃恢复时：已完成阶段直接标记 completed

### Step 8: 确保锁文件被 gitignore

检查项目根目录 `.gitignore` 是否包含 `.autopilot-active`，若不包含则追加：

```bash
echo '.autopilot-active' >> .gitignore
```

> 此文件是会话级运行时锁，包含 PID/session_id 等本机信息，禁止提交到 git。

### Step 9: 创建锁文件

调用 Skill(`spec-autopilot:autopilot-lockfile`) **操作 1**：

传入参数（由主线程构造 JSON 字符串）：
```json
{"change":"pending","pid":"<PID>","started":"<ISO-8601>","session_cwd":"<abs_path>","anchor_sha":"","session_id":"<ms_timestamp>","mode":"<mode>"}
```

等待后台 Agent 返回：
- `status: ok` → 继续 Step 10
- `status: conflict` → AskUserQuestion 由用户决定覆盖/中止（见 lockfile Skill 冲突处理）

> **原子性**：初次写入时 `anchor_sha` 设为空字符串，Step 10 创建 commit 后更新。

### Step 10: 创建锚定 Commit

为后续 fixup + autosquash 策略创建空锚定 commit：

```bash
git commit --allow-empty -m "autopilot: start <change_name>"
ANCHOR_SHA=$(git rev-parse HEAD)
```

调用 Skill(`spec-autopilot:autopilot-lockfile`) **操作 2**：将 `ANCHOR_SHA` 写入锁文件的 `anchor_sha` 字段。

> **原子性保障**：如果 Step 10 之前崩溃，恢复时检测到 `anchor_sha` 为空 → 重新创建锚定 commit 并更新。Phase 7 autosquash 前**必须**验证 `anchor_sha` 非空且 `git rev-parse $ANCHOR_SHA` 有效，无效则跳过 autosquash 并警告用户。

---

## 输出

Phase 0 完成后，主编排器获得：

| 数据 | 用途 |
|------|------|
| version | 插件版本号 |
| mode | 执行模式（full/lite/minimal） |
| session_id | 毫秒级时间戳 |
| ANCHOR_SHA | 锚定 commit SHA |
| config | 完整配置对象 |
| recovery_phase | 崩溃恢复起始阶段（正常为 1） |

> **Checkpoint 范围**: Phase 0 在主线程执行，不写 checkpoint。

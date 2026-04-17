# 跨会话知识累积协议

> 由 autopilot SKILL.md Phase 7 引用，执行知识提取和持久化。Phase 1 引用，注入历史知识。

## 知识库位置

`openspec/.autopilot-knowledge.json`

> 此文件位于 openspec/ 目录下（非 changes 子目录），所有 change 共享。
> 建议纳入 git 版本管理，团队共享知识。

## 知识条目格式

```json
{
  "version": "1.0",
  "entries": [
    {
      "id": "knowledge-<timestamp>-<seq>",
      "change": "feature-name",
      "timestamp": "ISO-8601",
      "category": "pattern | decision | pitfall | optimization",
      "summary": "简短描述（≤100 字符）",
      "detail": "详细说明（≤500 字符）",
      "tags": ["auth", "api", "security"],
      "phase_source": 5,
      "confidence": "high | medium | low",
      "reuse_count": 0
    }
  ],
  "stats": {
    "total_entries": 0,
    "total_changes": 0,
    "last_updated": "ISO-8601"
  }
}
```

## Phase 7: 知识提取规则

Phase 7 汇总完成后，从以下来源提取知识条目：

| 来源 | 提取内容 | 类别 | 置信度 |
|------|---------|------|--------|
| Phase 1 decisions（status=ok） | 重大技术决策及理由 | decision | high |
| Phase 5 retry_count > 0 | 实施中遇到的问题和解决方案 | pitfall | medium |
| Phase 5 task checkpoints（连续成功） | 成功的实现模式 | pattern | medium |
| Phase 6 test failures → fix | 测试失败的根因和修复方式 | pitfall | high |
| Phase 6.5 code review findings | 审查发现的代码质量问题 | pattern | medium |
| _metrics bottleneck phases | 效率瓶颈和优化机会 | optimization | low |

### 提取算法

```
1. 遍历所有 phase checkpoint 文件
2. 对每个 checkpoint：
   a. decisions 数组中的每个 decision → 生成 decision 类条目
   b. retry_count > 0 → 生成 pitfall 类条目（含 summary 描述重试原因）
   c. risks 数组中已缓解的风险 → 生成 pattern 类条目
3. 从 _metrics 中识别耗时最长的阶段 → 生成 optimization 建议
4. 去重：与已有 entries 的 summary 进行模糊匹配（前 50 字符相同视为重复）
5. 保留 confidence >= low 的所有条目（但 FIFO 淘汰时 low 优先淘汰）
6. 追加到 knowledge.json 的 entries 数组
7. 更新 stats
```

### 写入规则

- **原子性**：读取 → 修改 → 完整写回（非追加写入）
- **并发安全**：写入前检查文件 mtime，如被修改则重新读取合并
- **大小限制**：最大 200 条 entries，超过时按 FIFO 淘汰 low confidence 条目

## Phase 1: 知识注入规则

Phase 1 Auto-Scan（1.2 节）完成后，自动注入相关历史知识：

### 注入流程

```
1. 检查 openspec/.autopilot-knowledge.json 是否存在
   - 不存在 → 跳过（首次运行无历史数据）
   - 存在 → 继续

2. 读取 entries 数组

3. 关键词匹配：
   - 从 RAW_REQUIREMENT 提取关键词（名词和动词短语）
   - 与每个 entry 的 tags + summary 进行匹配
   - 按匹配度排序

4. 取 top-5 相关条目

5. 写入 project-context.md 的「Historical Knowledge」章节：
   ## Historical Knowledge (from previous autopilot sessions)

   - [pitfall] {summary}: {detail} (from: {change}, confidence: {confidence})
   - [decision] {summary}: {detail} (from: {change})
   - [pattern] {summary}: {detail} (reused {reuse_count} times)

6. 注入需求分析 Agent（config.phases.requirements.agent）prompt 的「已知坑点」节

7. 匹配到的 entries 的 reuse_count += 1（延迟写回）
```

### 注入策略

| 条目类别 | 注入方式 | 优先级 |
|---------|---------|--------|
| pitfall | 直接注入为「已知问题」，提醒避免 | 最高 |
| decision | 注入为「历史参考」，可复用或修改 | 高 |
| pattern | 注入为「推荐模式」 | 中 |
| optimization | 仅在 complexity=large 时注入 | 低 |

## 知识库维护

### 自动清理

Phase 7 写入时检查：
- entries 数量 > 200 → 按以下优先级淘汰：
  1. confidence=low 且 reuse_count=0 的最旧条目
  2. 超过 90 天未被 reuse 的条目
  3. FIFO 最旧条目

### 手动维护

用户可直接编辑 `openspec/.autopilot-knowledge.json`：
- 删除不准确的条目
- 调整 confidence 等级
- 添加手动知识条目（遵循相同格式）

---

## 持久化 Steering Documents

### 位置

`openspec/.autopilot-context/`（项目级，所有 change 共享）

> 此目录位于 openspec/ 下但不在 changes/ 子目录内，所有 change 共享。
> 建议纳入 git 版本管理，团队共享项目上下文。

### 文件

| 文件 | 用途 | 更新策略 |
|------|------|---------|
| `project-context.md` | 技术栈、目录布局、关键依赖 | 增量更新（7 天内跳过全量扫描） |
| `existing-patterns.md` | 跨 change 累积的代码模式 | 追加写入（Phase 7 提取） |
| `tech-constraints.md` | CLAUDE.md + rules 提取的约束 | 每次 Phase 1 刷新 |

### 更新协议

Phase 1 Auto-Scan 行为变更：

```
1. 检查 openspec/.autopilot-context/project-context.md 是否存在
   - 存在 + 新鲜（< 7 天） → 跳过全量扫描，直接读取，仅对本次需求相关代码做增量扫描
   - 存在 + 过期（> 7 天） → 增量更新（diff 当前项目状态 vs 已有文档）
   - 不存在 → 全量扫描（当前行为）
2. 写入/更新 steering documents 到持久化位置
3. 复制相关章节到 per-change context/ 用于 checkpoint 隔离
```

### Phase 7 知识回写

Phase 7 汇总完成后，除提取知识条目到 knowledge.json 外：

1. 将新发现的代码模式追加到 `existing-patterns.md`
2. 如发现新约束则更新 `tech-constraints.md`
3. 递增 `project-context.md` 中的 version 计数器
4. 记录本次 change 的统计数据（文件数、行数、测试数）

### 首次迁移

已有项目（openspec/.autopilot-context/ 不存在）首次运行 autopilot 时：
- Phase 1 Auto-Scan 照常执行全量扫描
- 扫描结果同时写入 per-change context/ 和新建的 openspec/.autopilot-context/
- 后续 change 复用持久化文件

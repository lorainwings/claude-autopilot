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

6. 注入 business-analyst Agent prompt 的「已知坑点」节

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

/**
 * parallel-harness: Context Pack Schema
 *
 * 每个 worker 只接收最小必要上下文，而不是整个仓库或整段对话历史。
 *
 * 来源设计：
 * - get-shit-done: 最小上下文包、低摩擦推进
 * - superpowers: 能力清单化、低摩擦入口
 *
 * 反向增强：
 * - 不能只追求快，还要加 verifier 和 metrics
 * - 上下文超预算时自动摘要，而不是截断
 */

import type { ModelTier, RetryPolicy, VerifierType } from "../orchestrator/task-graph";

// ============================================================
// 上下文包
// ============================================================

/** 代码片段 */
export interface CodeSnippet {
  /** 文件路径 */
  file_path: string;

  /** 起始行 */
  start_line: number;

  /** 结束行 */
  end_line: number;

  /** 代码内容 */
  content: string;

  /** 为什么这段代码与任务相关 */
  relevance: string;
}

/** 上下文包 —— Worker 收到的全部信息 */
export interface ContextPack {
  /** 任务摘要（目标 + 验收标准） */
  task_summary: string;

  /** 相关文件路径列表 */
  relevant_files: string[];

  /** 精选代码片段 */
  relevant_snippets: CodeSnippet[];

  /** 约束条件 */
  constraints: ContextConstraints;

  /** 测试要求 */
  test_requirements: string[];

  /** Token 预算 */
  budget: ContextBudget;

  /** 上下文占用率 (0-1) */
  occupancy_ratio: number;

  /** 加载的文件数量 */
  loaded_files_count: number;

  /** 加载的代码片段数量 */
  loaded_snippets_count: number;

  /** 压缩策略 */
  compaction_policy: "none" | "summarize" | "truncate";
}

/** 约束条件 */
export interface ContextConstraints {
  /** 允许修改的路径 */
  allowed_paths: string[];

  /** 禁止修改的路径 */
  forbidden_paths: string[];

  /** 接口契约（其他任务期望本任务的输出满足的约定） */
  interface_contracts: string[];

  /** 必须遵守的编码规范 */
  coding_standards: string[];
}

/** Token 预算 */
export interface ContextBudget {
  /** 最大输入 token 数 */
  max_input_tokens: number;

  /** 最大输出 token 数 */
  max_output_tokens: number;

  /** 超预算时是否自动摘要 */
  auto_summarize_on_overflow: boolean;
}

// ============================================================
// 任务契约（Worker 的完整输入）
// ============================================================

/** 任务契约 —— Worker 执行任务的完整合同 */
export interface TaskContract {
  /** 任务 ID */
  task_id: string;

  /** 任务目标 */
  goal: string;

  /** 依赖任务 ID 列表 */
  dependencies: string[];

  /** 文件所有权 */
  allowed_paths: string[];

  /** 禁止路径 */
  forbidden_paths: string[];

  /** 验收标准 */
  acceptance_criteria: string[];

  /** 测试要求 */
  test_requirements: string[];

  /** 推荐模型 tier */
  preferred_model_tier: ModelTier;

  /** 重试策略 */
  retry_policy: RetryPolicy;

  /** 需要的验证器 */
  verifier_set: VerifierType[];

  /** 上下文包 */
  context: ContextPack;

  /** 来自 Requirement Grounding 的验收矩阵条目 */
  grounding_criteria?: Array<{
    category: string;
    criterion: string;
    blocking: boolean;
  }>;

  /** 来自 Requirement Grounding 的必要审批 */
  required_approvals?: string[];
}
